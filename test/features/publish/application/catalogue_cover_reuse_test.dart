import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/application/site/catalogue_section_builder.dart';
import 'package:pitaka/features/publish/domain/publish_cover_ids.dart';
import 'package:pitaka/features/publish/domain/publish_cover_names.dart';
import 'package:pitaka/features/publish/domain/publish_cover_rendition.dart';
import 'package:pitaka/features/publish/domain/publish_item_keys.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';
import 'package:pitaka/features/publish/domain/site/section_merge.dart';

/// Plan D.1 tests (ADR 0020 Decisions 2–3): a COUNTING cover reader proves
/// how many covers a catalogue build really produces, across publishes that
/// feed each other's record — exactly how the hosts chain them.
///
/// The targets this pins (plan A.2): an unchanged republish produces 0
/// covers; adding one book with a cover produces 1.
void main() {
  final salt = ascii.encode('salt-1234567890');
  const remote = 'https://covers.openlibrary.org/b/id/9-L.jpg';

  late List<String> reads;
  late List<String> fetches;
  late Set<String> unreadable;

  setUp(() {
    reads = [];
    fetches = [];
    unreadable = {};
  });

  CatalogueSectionBuilder builder() => CatalogueSectionBuilder(
    covers: PublishCoverDecider(
      readLocalCover: (src) async {
        reads.add(src);
        return unreadable.contains(src) ? null : utf8.encode('JPEG:$src');
      },
      fetchRemoteCover: (url) async {
        fetches.add(url);
        return utf8.encode('JPEG:$url');
      },
    ),
    buildViewerHtml:
        ({required libraryName, required contact, required sharing}) async =>
            utf8.encode('<html></html>'),
    encodeBooksJson: encodeBooksJsonBytes,
  );

  const series = Periodical(
    id: 7,
    periodicalUid: 'uid-1',
    title: 'Chandamama',
    coverUrl: 'covers/series.jpg',
  );
  CatalogueItem book(int id, String? cover) =>
      CatalogueItem(id: id, title: 'Item $id', coverUrl: cover);
  const issue = CatalogueItem(
    id: 2,
    title: 'Chandamama — Oct 2026',
    details: IssueOf(
      periodicalUid: 'uid-1',
      volume: 249,
      issueNumber: 10,
      issueDate: 1759276800000,
    ),
  );
  final library = [book(1, 'covers/one.jpg'), issue, book(9, remote)];

  // Keys and cover names from the same fixed salt, as `namingFor` would
  // return them from one read (plan D.5).
  PublishNaming namingFor(List<CatalogueItem> items) => (
    keys: PublishKeySet.tryCreate(
      id: PublishItemKeys.keySetIdFor(salt: salt),
      keysById: {
        for (final item in items)
          item.id: PublishItemKeys.keyFor(salt: salt, itemId: item.id),
      },
    )!,
    coverNames: PublishCoverNames.tryCreate(salt)!,
  );

  Future<PublishSection> build(
    List<CatalogueItem> items,
    PublishManifest previous, {
    PublishMode mode = PublishMode.incremental,
  }) async => (await builder().build(
    books: items,
    periodicals: const [series],
    activeLoanCounts: null,
    libraryJson: null,
    gitHubPagesSite: false,
    settings: const PublishPageSettings(libraryName: 'Test Library'),
    previous: previous,
    now: 1000,
    naming: namingFor(items),
    mode: mode,
  )).toNullable()!;

  /// The record a GitHub catalogue commit of [section] leaves behind.
  PublishManifest committed(PublishManifest previous, PublishSection section) {
    final merge = mergeSection(previous: previous, section: section);
    return previous.afterCommit(
      commitSha: 'commit',
      mergedShas: merge.fileShas,
      coverUrlByBookId: section.coverUrlByKey,
      coverRendition: section.coverRendition,
      proofPath: PublishProofPath.booksJson,
      committedAt: 1000,
      wroteKeyedCatalogue: true,
    );
  }

  const start = PublishManifest(
    repo: 'me/lib',
    branch: 'main',
    headSha: 'HEAD',
  );

  Future<PublishManifest> publishedOnce() async {
    final record = committed(start, await build(library, start));
    reads.clear();
    fetches.clear();
    return record;
  }

  test('the first publish produces every cover once; a series cover is '
      'produced once for the series and its issue', () async {
    final section = await build(library, start);

    expect(reads, ['covers/one.jpg', 'covers/series.jpg']);
    expect(fetches, [remote]);
    expect(section.coverRendition, PublishCoverRendition.current);
    expect(section.coverUrlByKey, {
      '1': 'covers/one.jpg',
      '9': remote,
      'periodical:uid-1': 'covers/series.jpg',
    });
  });

  test('an unchanged republish produces 0 covers and uploads none', () async {
    final record = await publishedOnce();
    final again = await build(library, record);

    expect(reads, isEmpty);
    expect(fetches, isEmpty);
    final covers = again.files.where((f) => f.path.startsWith('covers/'));
    expect(covers, hasLength(3));
    for (final cover in covers) {
      expect(cover.upload, isFalse, reason: cover.path);
      expect(cover.bytes, isEmpty, reason: 'carried by its sha');
      expect(cover.gitSha, record.shaFor(cover.path), reason: cover.path);
    }
    expect(again.coverUrlByKey, record.coverUrlByBookId);
    // The site is byte-for-byte the same: books.json did not change either.
    expect(
      again.files.firstWhere((f) => f.path == 'books.json').upload,
      isFalse,
    );
  });

  test('adding one book with a cover produces exactly 1 cover', () async {
    final record = await publishedOnce();
    final grown = [...library, book(3, 'covers/three.jpg')];
    final section = await build(grown, record);

    expect(reads, ['covers/three.jpg']);
    expect(fetches, isEmpty);
    expect(section.coverUrlByKey['3'], 'covers/three.jpg');
  });

  test(
    'a replaced picture (new file name) is produced; the rest is not',
    () async {
      final record = await publishedOnce();
      final replaced = [book(1, 'covers/one-v2.jpg'), issue, book(9, remote)];
      await build(replaced, record);
      expect(reads, ['covers/one-v2.jpg']);
    },
  );

  test(
    'a record made with another rendition produces every cover again',
    () async {
      final record = await publishedOnce();
      final otherRecipe = PublishManifest(
        repo: record.repo,
        branch: record.branch,
        headSha: record.headSha,
        ownershipConfirmed: true,
        fileShas: record.fileShas,
        coverUrlByBookId: record.coverUrlByBookId,
        coverRendition: PublishCoverRendition.current + 1,
      );
      final section = await build(library, otherRecipe);
      expect(reads, ['covers/one.jpg', 'covers/series.jpg']);
      expect(fetches, [remote]);
      expect(section.coverRendition, PublishCoverRendition.current);
    },
  );

  test('a cover the record holds but the site lacks is produced', () async {
    final record = await publishedOnce();
    final onePath = 'covers/${PublishCoverIds.shortHashHex(salt, 1)}.jpg';
    final withoutOne = PublishManifest(
      repo: record.repo,
      branch: record.branch,
      headSha: record.headSha,
      ownershipConfirmed: true,
      fileShas: {...record.fileShas}..remove(onePath),
      coverUrlByBookId: record.coverUrlByBookId,
      coverRendition: record.coverRendition,
    );
    await build(library, withoutOne);
    expect(reads, ['covers/one.jpg']);
  });

  test('a COMPLETE snapshot produces every cover even over a full record '
      '(CV4)', () async {
    final record = await publishedOnce();
    await build(library, record, mode: PublishMode.complete);
    expect(reads, ['covers/one.jpg', 'covers/series.jpg']);
    expect(fetches, [remote]);
  });

  test('a removed book leaves the record; its cover file is deleted', () async {
    final record = await publishedOnce();
    final section = await build([issue, book(9, remote)], record);
    final merge = mergeSection(previous: record, section: section);

    expect(section.coverUrlByKey.containsKey('1'), isFalse);
    expect(merge.deletePaths, [
      'covers/${PublishCoverIds.shortHashHex(salt, 1)}.jpg',
    ]);
    expect(reads, isEmpty);
  });

  test('a cover that falls back to an older file under an unknown rendition '
      'is not vouched for, so the next publish tries it again', () async {
    // A record from before ADR 0020: it holds book 1's file, rendition
    // unknown. This time the file cannot be read (for example, a worker
    // isolate could not start), so the old file is kept.
    final onePath = 'covers/${PublishCoverIds.shortHashHex(salt, 1)}.jpg';
    final previous = PublishManifest(
      repo: 'me/lib',
      branch: 'main',
      headSha: 'HEAD',
      ownershipConfirmed: true,
      fileShas: {onePath: 'OLD-UNKNOWN-RENDITION'},
      coverUrlByBookId: const {'1': 'covers/one.jpg'},
    );
    unreadable.add('covers/one.jpg');
    final first = await build([book(1, 'covers/one.jpg')], previous);
    expect(
      first.files.firstWhere((f) => f.path == onePath).gitSha,
      'OLD-UNKNOWN-RENDITION',
    );
    expect(first.coverUrlByKey.containsKey('1'), isFalse);

    final record = committed(previous, first);
    expect(record.coverRendition, PublishCoverRendition.current);
    unreadable.clear();
    reads.clear();
    final second = await build([book(1, 'covers/one.jpg')], record);
    expect(reads, ['covers/one.jpg'], reason: 'tried again, not frozen');
    expect(second.coverUrlByKey['1'], 'covers/one.jpg');
  });

  test('cover sources are recorded trimmed, so a padded reference still '
      'matches next time', () async {
    final padded = [book(1, '  covers/one.jpg  ')];
    final first = await build(padded, start);
    expect(first.coverUrlByKey['1'], 'covers/one.jpg');
    final record = committed(start, first);
    reads.clear();
    await build(padded, record);
    expect(reads, isEmpty);
  });
}
