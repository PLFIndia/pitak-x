import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_cover_names.dart';
import 'package:pitaka/features/publish/domain/publish_cover_rendition.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/previous_publication.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';

/// ADR 0020 Decision 2 (plan CV2, CV4): the cover decider reuses a cover
/// that is already online WITHOUT reading or re-encoding it, but only when
/// the record vouches for it — same source, path recorded, current
/// rendition — and never in a complete snapshot.
///
/// Every test counts the reads and fetches, because "nothing was read" is
/// the whole point of plan Phase 2 (A.2: 0 covers processed on an unchanged
/// republish, 1 after adding one book).
void main() {
  final salt = ascii.encode('salt-1234567890');
  // The names of this publish, from the one salt read (plan D.5).
  final names = PublishCoverNames.tryCreate(salt)!;
  final itemPath = 'covers/${PublishCoverIds.shortHashHex(salt, 1)}.jpg';
  final seriesPath =
      'covers/${PublishCoverIds.shortHashHexForKey(salt, 'periodical:uid-1')}.jpg';
  const local = 'covers/0b5e2f6a-local.jpg';
  const remote = 'https://covers.openlibrary.org/b/id/1-L.jpg';
  final producedBytes = utf8.encode('FRESH-RENDITION');

  late List<String> reads;
  late List<String> fetches;
  late bool readFails;

  setUp(() {
    reads = [];
    fetches = [];
    readFails = false;
  });

  PublishCoverDecider decider() => PublishCoverDecider(
    readLocalCover: (src) async {
      reads.add(src);
      return readFails ? null : producedBytes;
    },
    fetchRemoteCover: (url) async {
      fetches.add(url);
      return readFails ? null : producedBytes;
    },
  );

  /// A GitHub record holding [path] with the given cover source/rendition.
  PublishManifest record({
    String? path,
    Map<String, String> sources = const {'1': local},
    int? rendition = PublishCoverRendition.current,
  }) => PublishManifest(
    repo: 'me/lib',
    branch: 'main',
    headSha: 'HEAD',
    ownershipConfirmed: true,
    fileShas: {(path ?? itemPath): 'LIVE-SHA'},
    coverUrlByBookId: sources,
    coverRendition: rendition,
  );

  Future<CoverDecision> item(
    String? cover,
    PreviousPublication previous, {
    PublishMode mode = PublishMode.incremental,
  }) => decider().forItem(
    cover,
    itemId: 1,
    names: names,
    manifest: previous,
    mode: mode,
  );

  group('1. reuse, unread', () {
    test('a local cover already online is reused: nothing is read', () async {
      final decision = await item(local, record());

      expect(reads, isEmpty);
      expect(decision.publishPath, itemPath);
      expect(decision.bytes, isNull);
      expect(decision.reuseSha, 'LIVE-SHA');
      expect(decision.publishedCoverUrl, itemPath);
      expect(decision.source, local, reason: 'the record keeps vouching');
    });

    test(
      'a remote cover already online is reused: nothing is fetched',
      () async {
        final decision = await item(remote, record(sources: {'1': remote}));

        expect(fetches, isEmpty);
        expect(decision.reuseSha, 'LIVE-SHA');
        expect(decision.source, remote);
      },
    );

    test('a series cover follows the same rule under its own key', () async {
      final decision = await decider().forPeriodical(
        local,
        periodicalUid: 'uid-1',
        names: names,
        manifest: record(
          path: seriesPath,
          sources: {'periodical:uid-1': local},
        ),
        mode: PublishMode.incremental,
      );

      expect(reads, isEmpty);
      expect(decision.publishPath, seriesPath);
      expect(decision.reuseSha, 'LIVE-SHA');
      // The book key space is separate: a book entry for '1' would not do.
      final other = await decider().forPeriodical(
        local,
        periodicalUid: 'uid-1',
        names: names,
        manifest: record(path: seriesPath),
        mode: PublishMode.incremental,
      );
      expect(other.bytes, producedBytes);
      expect(reads, [local]);
    });

    test('surrounding spaces in the stored reference do not matter', () async {
      final decision = await item('  $local  ', record());
      expect(reads, isEmpty);
      expect(decision.source, local, reason: 'sources are stored trimmed');
    });
  });

  group('2. produced again (read or fetched)', () {
    test('a record from before ADR 0020 (no rendition) reads once', () async {
      final decision = await item(local, record(rendition: null));

      expect(reads, [local]);
      expect(decision.bytes, producedBytes);
      expect(decision.gitSha, GitBlobSha.of(producedBytes));
      expect(decision.source, local);
    });

    test('another rendition (a bumped recipe) reads again', () async {
      await item(local, record(rendition: PublishCoverRendition.current + 1));
      expect(reads, [local]);
    });

    test('a changed source (a new picture = a new file name) reads', () async {
      await item('covers/new-picture.jpg', record());
      expect(reads, ['covers/new-picture.jpg']);
    });

    test('a path the record does not hold reads', () async {
      await item(local, record(path: 'covers/elsewhere.jpg'));
      expect(reads, [local]);
    });

    test('a remote cover with an unknown rendition is fetched once', () async {
      // Plan A.6 #84: the rendition rule applies to remote covers too, so a
      // recipe change re-renders every cover (CV3).
      await item(remote, record(sources: {'1': remote}, rendition: null));
      expect(fetches, [remote]);
    });

    test(
      'a COMPLETE snapshot never reuses: it reads every cover (CV4)',
      () async {
        final decision = await item(
          local,
          record(),
          mode: PublishMode.complete,
        );
        expect(reads, [local]);
        expect(decision.bytes, producedBytes);
      },
    );

    test(
      'a Cloudflare record whose hashes this build cannot use reads',
      () async {
        final entry = CloudflareAssetEntry(
          sha: 'LIVE-SHA',
          hash: 'a' * 32,
          size: 3,
          type: CloudflareContentType.jpeg,
        );
        final trusted = CloudflareSiteManifest(
          hashScheme: CloudflareAssetHash.scheme,
          files: {itemPath: entry},
          coverUrlByBookId: const {'1': local},
          coverRendition: PublishCoverRendition.current,
        );
        await item(local, trusted);
        expect(reads, isEmpty, reason: 'trusted hashes: reused');

        final untrusted = CloudflareSiteManifest(
          hashScheme: 'an-older-formula',
          files: {itemPath: entry},
          coverUrlByBookId: const {'1': local},
          coverRendition: PublishCoverRendition.current,
        );
        await item(local, untrusted);
        expect(
          reads,
          [local],
          reason: 'an unusable hash would make the reused cover a missing file',
        );
      },
    );
  });

  group('3. fall back to the published file', () {
    test('an unreadable new picture keeps the old file, which still shows the '
        'OLD source', () async {
      readFails = true;
      final decision = await item('covers/new-picture.jpg', record());

      expect(decision.reuseSha, 'LIVE-SHA');
      expect(decision.publishedCoverUrl, itemPath);
      expect(
        decision.source,
        local,
        reason: 'recording the new source would freeze the old picture',
      );
    });

    test('under an unknown rendition no source is vouched for', () async {
      readFails = true;
      final decision = await item(local, record(rendition: null));

      expect(decision.reuseSha, 'LIVE-SHA');
      expect(decision.source, isNull, reason: 'the next publish retries');
    });

    test('a failed remote fetch keeps the old file the same way', () async {
      readFails = true;
      const changed = 'https://covers.openlibrary.org/b/id/2-L.jpg';
      final decision = await item(changed, record(sources: {'1': remote}));
      expect(fetches, [changed]);
      expect(decision.reuseSha, 'LIVE-SHA');
      expect(decision.source, remote);
    });
  });

  group('4. nothing usable', () {
    test('an unreadable local cover with nothing online is dropped', () async {
      readFails = true;
      final decision = await item(local, PublishManifest.empty);
      expect(decision.publishPath, isNull);
      expect(decision.publishedCoverUrl, isNull);
      expect(decision.source, isNull);
    });

    test('a failed remote fetch degrades to the sanitized URL', () async {
      readFails = true;
      final decision = await item(remote, PublishManifest.empty);
      expect(decision.publishPath, isNull);
      expect(decision.publishedCoverUrl, remote);
      expect(decision.source, isNull, reason: 'no file backs it');
    });

    test('no cover reference: no decision, no IO', () async {
      final decision = await item('   ', record());
      expect(decision.publishPath, isNull);
      expect(reads, isEmpty);
      expect(fetches, isEmpty);
    });
  });
}
