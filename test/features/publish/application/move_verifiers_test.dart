import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/site/complete_snapshot_verifier.dart';
import 'package:pitaka/features/publish/application/site/moved_site_verifier.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_marker.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_publish_marker_codec.dart';

import '../support/cloudflare_s8_fakes.dart';
import '../support/move_fakes.dart';

void main() {
  group('CompleteSnapshotVerifier', () {
    PublishFile file(String path, String body) {
      final bytes = utf8.encode(body);
      return PublishFile(
        path: path,
        bytes: bytes,
        gitSha: GitBlobSha.of(bytes),
        upload: true,
      );
    }

    test('proves every body at the exact origin and every deletion', () async {
      final reader = FakeStructuredReader()
        ..body('index.html', utf8.encode('<html>one</html>'))
        ..body('books.json', utf8.encode('{"books":[]}'))
        ..absent('old.html');
      final verifier = CompleteSnapshotVerifier(
        reader: reader,
        sleep: (_) async {},
        attempts: 1,
      );

      final verified = await verifier.verify(
        siteUrl: moveGitHubTarget.siteUrl,
        files: [file('index.html', '<html>one</html>')],
        deletedPaths: const ['old.html'],
        revision: 7,
      );

      expect(verified, isTrue);
      expect(reader.calls.map((call) => call.$1).toSet(), {
        moveGitHubTarget.siteUrl,
      });
      expect(reader.calls.map((call) => call.$2).toSet(), {
        'index.html',
        'old.html',
      });
    });

    test('one mismatched byte fails the whole set', () async {
      final reader = FakeStructuredReader()
        ..body('index.html', utf8.encode('<html>other</html>'));
      final verifier = CompleteSnapshotVerifier(
        reader: reader,
        sleep: (_) async {},
        attempts: 2,
      );

      final verified = await verifier.verify(
        siteUrl: moveGitHubTarget.siteUrl,
        files: [file('index.html', '<html>one</html>')],
        revision: 7,
      );

      expect(verified, isFalse);
    });

    test('a body where absence is required is not proof', () async {
      final reader = FakeStructuredReader()
        ..body('old.html', utf8.encode('<html>still here</html>'));
      final verifier = CompleteSnapshotVerifier(
        reader: reader,
        sleep: (_) async {},
        attempts: 1,
      );

      final verified = await verifier.verify(
        siteUrl: moveGitHubTarget.siteUrl,
        files: const [],
        deletedPaths: const ['old.html'],
        revision: 7,
      );

      expect(verified, isFalse);
    });

    test('a later polling round can still prove the same set', () async {
      final reader = _FlakyReader(first: const PublishedSiteReadUnreadable());
      final verifier = CompleteSnapshotVerifier(
        reader: reader,
        sleep: (_) async {},
        attempts: 3,
      );

      final verified = await verifier.verify(
        siteUrl: moveGitHubTarget.siteUrl,
        files: [file('index.html', '<html>one</html>')],
        revision: 7,
      );

      expect(verified, isTrue);
      expect(reader.calls, hasLength(2));
    });

    test('an unreadable result is never treated as absence', () async {
      final reader = FakeStructuredReader()..unreadable('old.html');
      final verifier = CompleteSnapshotVerifier(
        reader: reader,
        sleep: (_) async {},
        attempts: 2,
      );

      final verified = await verifier.verify(
        siteUrl: moveGitHubTarget.siteUrl,
        files: const [],
        deletedPaths: const ['old.html'],
        revision: 7,
      );

      expect(verified, isFalse);
    });
  });

  group('MovedSiteVerifier', () {
    const codec = CloudflarePublishMarkerCodec();
    final page = utf8.encode('<html>moved</html>');

    test(
      'GitHub proves the exact moved root and the old books.json 404',
      () async {
        final pending = movePending(
          oldTarget: moveGitHubTarget,
          indexHtml: page,
        );
        final reader = FakeStructuredReader()
          ..body('', page)
          ..absent('books.json');
        final verifier = MovedSiteVerifier(
          reader: reader,
          markerCodec: codec,
          validateMovedHtml: (_) async => true,
          sleep: (_) async {},
          attempts: 1,
        );

        expect(await verifier.verify(pending, revision: 3), isTrue);
        expect(reader.calls.map((call) => call.$2).toSet(), {'', 'books.json'});
      },
    );

    test('Cloudflare additionally proves the exact retired marker', () async {
      final pending = movePending(oldTarget: moveCloudflareTarget);
      final marker = pending.retirement.marker!;
      final reader = FakeStructuredReader()
        ..body('', pending.retirement.indexHtml)
        ..absent('books.json')
        ..body('pitak-publish.json', codec.encode(marker));
      final verifier = MovedSiteVerifier(
        reader: reader,
        markerCodec: codec,
        validateMovedHtml: (_) async => true,
        sleep: (_) async {},
        attempts: 1,
      );

      expect(await verifier.verify(pending, revision: 3), isTrue);
    });

    test(
      'a non-retired or missing marker fails Cloudflare retirement',
      () async {
        final pending = movePending(oldTarget: moveCloudflareTarget);
        final reader = FakeStructuredReader()
          ..body('', pending.retirement.indexHtml)
          ..absent('books.json')
          ..body(
            'pitak-publish.json',
            codec.encode(
              const PublishMarker(
                publishId: moveRetiredPublishId,
                publishedAt: 1700000000000,
                state: PublishMarkerState.live,
              ),
            ),
          );
        final verifier = MovedSiteVerifier(
          reader: reader,
          markerCodec: codec,
          validateMovedHtml: (_) async => true,
          sleep: (_) async {},
          attempts: 1,
        );

        expect(await verifier.verify(pending, revision: 3), isFalse);
      },
    );

    test('a stale root or a still-present books.json fails', () async {
      final pending = movePending(oldTarget: moveGitHubTarget, indexHtml: page);
      for (final reader in <FakeStructuredReader>[
        FakeStructuredReader()
          ..body('', utf8.encode('<html>old</html>'))
          ..absent('books.json'),
        FakeStructuredReader()
          ..body('', page)
          ..body('books.json', utf8.encode('{}')),
      ]) {
        final verifier = MovedSiteVerifier(
          reader: reader,
          markerCodec: codec,
          validateMovedHtml: (_) async => true,
          sleep: (_) async {},
          attempts: 1,
        );

        expect(await verifier.verify(pending, revision: 3), isFalse);
      }
    });

    test(
      'persisted HTML that no longer validates is refused before any read',
      () async {
        final pending = movePending(oldTarget: moveGitHubTarget);
        final reader = FakeStructuredReader();
        final verifier = MovedSiteVerifier(
          reader: reader,
          markerCodec: codec,
          validateMovedHtml: (_) async => false,
          sleep: (_) async {},
          attempts: 1,
        );

        expect(await verifier.verify(pending, revision: 3), isFalse);
        expect(reader.calls, isEmpty);
      },
    );
  });
}

/// Serves an unreadable outcome once, then a body — for the grouped-polling
/// path.
final class _FlakyReader implements PublishedSiteReadVerifier {
  _FlakyReader({required this.first});

  final PublishedSiteReadOutcome first;
  final List<(String, String, int, String?)> calls = [];

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    calls.add((siteUrl, path, maxBytes, cacheBuster));
    if (calls.length == 1) return first;
    return PublishedSiteReadBody(utf8.encode('<html>one</html>'));
  }
}
