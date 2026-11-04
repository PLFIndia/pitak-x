import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/site/complete_snapshot_verifier.dart';
import 'package:pitaka/features/publish/application/site/moved_site_verifier.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';
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

    test('an empty file (.nojekyll, plan SP5) is proven by an empty body '
        'and not by its absence', () async {
      final empty = PublishFile(
        path: '.nojekyll',
        bytes: const [],
        gitSha: GitBlobSha.of(const []),
        upload: true,
      );
      Future<bool> verify(FakeStructuredReader reader) =>
          CompleteSnapshotVerifier(
            reader: reader,
            sleep: (_) async {},
            attempts: 1,
          ).verify(
            siteUrl: moveGitHubTarget.siteUrl,
            files: [empty],
            revision: 7,
          );

      expect(
        await verify(FakeStructuredReader()..body('.nojekyll', [])),
        isTrue,
      );
      expect(
        await verify(FakeStructuredReader()..absent('.nojekyll')),
        isFalse,
      );
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

    // S11 J.7 regression (2026-10-29): GitHub Pages needed 81 s to publish a
    // move commit, past the old 12 × 5 s budget, so the move failed and every
    // retry re-committed (restarting the build). GitHub documents that a
    // Pages build "can take up to 10 minutes".
    group('GitHub Pages budget', () {
      test('covers the documented 10 minutes', () {
        const verifier = CompleteSnapshotVerifier.gitHubPages(
          reader: _NeverReader(),
          sleep: _noSleep,
        );
        final budget = verifier.interval * verifier.attempts;
        expect(budget, greaterThanOrEqualTo(const Duration(minutes: 10)));
        expect(verifier.interval, const Duration(seconds: 10));
      });

      test('a build that lands after 81 s still verifies the move', () async {
        // Unreadable (the Pages 404 before the build) for 9 rounds, i.e. the
        // first 90 s, then the real bytes.
        final reader = _FlakyReader(
          first: const PublishedSiteReadUnreadable(),
          failingRounds: 9,
        );
        final waited = <Duration>[];
        final verifier = CompleteSnapshotVerifier.gitHubPages(
          reader: reader,
          sleep: (delay) async => waited.add(delay),
        );

        final verified = await verifier.verify(
          siteUrl: moveGitHubTarget.siteUrl,
          files: [file('index.html', '<html>one</html>')],
          revision: 7,
        );

        expect(verified, isTrue);
        expect(reader.calls, hasLength(10));
        expect(
          waited.fold(Duration.zero, (sum, delay) => sum + delay),
          const Duration(seconds: 100),
        );
      });

      // Review finding 5: one operation deadline and at most four reads in
      // flight, so a complete move proof cannot outlive `attempts × interval`
      // or take the whole budget for a single round of covers.
      test(
        '1,000 covers are all checked, four at a time, in two rounds',
        () async {
          final files = [
            for (var i = 0; i < 1000; i++) file('covers/$i.jpg', 'cover-$i'),
          ];
          final reader = FakeStructuredReader(); // every read is unreadable
          final verifier = CompleteSnapshotVerifier(
            reader: reader,
            sleep: (_) async {},
            attempts: 2,
          );

          final verified = await verifier.verify(
            siteUrl: moveGitHubTarget.siteUrl,
            files: files,
            revision: 7,
          );

          expect(verified, isFalse);
          expect(
            reader.calls,
            hasLength(2000),
            reason: 'every path, per round',
          );
          final perRound = <String, int>{};
          for (final call in reader.calls) {
            perRound.update(call.$2, (n) => n + 1, ifAbsent: () => 1);
          }
          expect(perRound, hasLength(1000));
          expect(perRound.values.every((n) => n == 2), isTrue);
        },
      );

      test('no more than four reads are in flight at once', () async {
        final bodies = {
          for (var i = 0; i < 6; i++) 'covers/$i.jpg': utf8.encode('cover-$i'),
        };
        final files = [
          for (final entry in bodies.entries)
            PublishFile(
              path: entry.key,
              bytes: entry.value,
              gitSha: GitBlobSha.of(entry.value),
              upload: true,
            ),
        ];
        final reader = _HoldingReader(bodies);
        final verifier = CompleteSnapshotVerifier(
          reader: reader,
          sleep: (_) async {},
          attempts: 1,
        );

        final result = verifier.verify(
          siteUrl: moveGitHubTarget.siteUrl,
          files: files,
          revision: 7,
        );
        await pumpEventQueue();
        expect(reader.started, hasLength(4), reason: 'the first batch');

        // Answer the first batch, which lets the remaining two start.
        reader.releaseAll();
        await pumpEventQueue();
        expect(reader.started, hasLength(6));
        reader.releaseAll();

        expect(await result, isTrue);
        expect(reader.maxActive, 4);
      });

      test('a fake clock proves no read starts after the deadline', () async {
        var now = 0;
        final reader = _ClockRecordingReader(() => now);
        final verifier = CompleteSnapshotVerifier(
          reader: reader,
          sleep: (delay) async => now += delay.inMilliseconds,
          attempts: 3,
          interval: const Duration(seconds: 10),
          clock: () => now,
        );

        final verified = await verifier.verify(
          siteUrl: moveGitHubTarget.siteUrl,
          files: [file('index.html', '<html>one</html>')],
          revision: 7,
        );

        expect(verified, isFalse);
        // Two rounds started at t=10 s and t=20 s; the third sleep reached
        // the 30 s deadline, so that round begins no read.
        expect(now, 30000);
        expect(reader.started, [10000, 20000]);
      });

      test('a sleep is capped by the time left, and in-flight reads still '
          'count', () async {
        var now = 0;
        final bodies = {
          for (var i = 0; i < 2; i++) 'covers/$i.jpg': utf8.encode('cover-$i'),
        };
        final files = [
          for (final entry in bodies.entries)
            PublishFile(
              path: entry.key,
              bytes: entry.value,
              gitSha: GitBlobSha.of(entry.value),
              upload: true,
            ),
        ];
        final held = <Completer<void>>[];
        final reader = _LateAnswerReader(
          bodies,
          onRead: () {
            held.add(Completer<void>());
            return held.last.future;
          },
        );
        final waited = <Duration>[];
        final verifier = CompleteSnapshotVerifier(
          reader: reader,
          sleep: (delay) async {
            waited.add(delay);
            now += delay.inMilliseconds;
          },
          attempts: 2,
          interval: const Duration(seconds: 10),
          clock: () => now,
        );

        final result = verifier.verify(
          siteUrl: moveGitHubTarget.siteUrl,
          files: files,
          revision: 7,
        );
        await pumpEventQueue();
        expect(held, hasLength(2));
        // Time passes beyond the 20 s deadline while the reads are open.
        now = 25000;
        for (final gate in held) {
          gate.complete();
        }

        expect(await result, isTrue, reason: 'the open batch was awaited');
        expect(waited, [const Duration(seconds: 10)]);
      });

      test('still fails closed when the build never appears', () async {
        final waited = <Duration>[];
        final verifier = CompleteSnapshotVerifier.gitHubPages(
          reader: const _NeverReader(),
          sleep: (delay) async => waited.add(delay),
        );

        final verified = await verifier.verify(
          siteUrl: moveGitHubTarget.siteUrl,
          files: [file('index.html', '<html>one</html>')],
          revision: 7,
        );

        expect(verified, isFalse);
        expect(waited, hasLength(CompleteSnapshotVerifier.gitHubPagesAttempts));
      });
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

    // Regression (handoff §12, 2026-10-31): the probe used a 1-byte cap, and
    // the real reader refuses an over-cap body, so a live 24 KiB catalogue
    // root was reported as "not answering".
    group('rootServesContent with the real cap behaviour', () {
      MovedSiteVerifier verifierFor(FakeStructuredReader reader) =>
          MovedSiteVerifier(
            reader: reader,
            markerCodec: codec,
            validateMovedHtml: (_) async => true,
            sleep: (_) async {},
            attempts: 1,
          );
      final pending = movePending(oldTarget: moveCloudflareTarget);

      test('a real-size live root answers', () async {
        final reader = CapHonoringStructuredReader()
          ..body('', List<int>.filled(24 * 1024, 0x61));
        expect(
          await verifierFor(reader).rootServesContent(pending, revision: 1),
          isTrue,
        );
        expect(reader.calls.single.$3, MovedSiteVerifier.rootProbeMaxBytes);
      });

      test('a real 404 is gone; an over-cap body is unproven', () async {
        final gone = CapHonoringStructuredReader()..absent('');
        expect(
          await verifierFor(gone).rootServesContent(pending, revision: 1),
          isFalse,
        );
        final huge = CapHonoringStructuredReader()
          ..body(
            '',
            List<int>.filled(MovedSiteVerifier.rootProbeMaxBytes + 1, 0),
          );
        expect(
          await verifierFor(huge).rootServesContent(pending, revision: 1),
          isNull,
        );
      });
    });

    test('the default (Cloudflare) budget is 60 s', () {
      const verifier = MovedSiteVerifier(
        reader: _NeverReader(),
        markerCodec: codec,
        validateMovedHtml: _neverMoved,
        sleep: _noSleep,
      );
      expect(
        verifier.interval * verifier.attempts,
        const Duration(seconds: 60),
      );
    });

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
      'L17: a GitHub source waits for a build that lands after 81 s',
      () async {
        // GitHub Pages serves the OLD site while it builds, so the moved page
        // is unreadable until the build lands. The source retirement must wait
        // as long as a GitHub destination does (fix-plan L17).
        final pending = movePending(
          oldTarget: moveGitHubTarget,
          indexHtml: page,
        );
        final reader = _LateMovedReader(
          page: page,
          readyAfter: const Duration(seconds: 81),
        );
        final verifier = MovedSiteVerifier.gitHubPages(
          reader: reader,
          markerCodec: codec,
          validateMovedHtml: (_) async => true,
          sleep: (delay) async => reader.elapsed += delay,
        );

        expect(
          await verifier.verify(pending, revision: 3),
          isTrue,
          reason: 'an 81 s build must verify, not fail',
        );
        expect(reader.elapsed, const Duration(seconds: 90));
      },
    );

    test('L17: the Cloudflare budget still fails closed at 60 s', () async {
      final pending = movePending(
        oldTarget: moveCloudflareTarget,
        indexHtml: page,
      );
      final reader = _LateMovedReader(
        page: page,
        readyAfter: const Duration(seconds: 61),
      );
      final verifier = MovedSiteVerifier(
        reader: reader,
        markerCodec: codec,
        validateMovedHtml: (_) async => true,
        sleep: (delay) async => reader.elapsed += delay,
      );

      expect(await verifier.verify(pending, revision: 3), isFalse);
      expect(reader.elapsed, const Duration(seconds: 60));
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
/// Answers [first] for the first [failingRounds] reads, then the real body.
final class _FlakyReader implements PublishedSiteReadVerifier {
  _FlakyReader({required this.first, this.failingRounds = 1});

  final PublishedSiteReadOutcome first;
  final int failingRounds;
  final List<(String, String, int, String?)> calls = [];

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    calls.add((siteUrl, path, maxBytes, cacheBuster));
    if (calls.length <= failingRounds) return first;
    return PublishedSiteReadBody(utf8.encode('<html>one</html>'));
  }
}

/// Records the injected clock at every read it answers (all unreadable).
final class _ClockRecordingReader implements PublishedSiteReadVerifier {
  _ClockRecordingReader(this.clock);

  final int Function() clock;
  final List<int> started = [];

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    started.add(clock());
    return const PublishedSiteReadUnreadable();
  }
}

/// Holds every read open until the test releases it, counting how many are
/// in flight at once.
final class _HoldingReader implements PublishedSiteReadVerifier {
  _HoldingReader(this.bodies);

  final Map<String, List<int>> bodies;
  final List<String> started = [];
  final Map<String, Completer<void>> _gates = {};
  int active = 0;
  int maxActive = 0;

  void releaseAll() {
    for (final gate in _gates.values) {
      if (!gate.isCompleted) gate.complete();
    }
  }

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    started.add(path);
    active++;
    if (active > maxActive) maxActive = active;
    final gate = _gates.putIfAbsent(path, Completer<void>.new);
    try {
      await gate.future;
    } finally {
      active--;
    }
    final body = bodies[path];
    return body == null
        ? const PublishedSiteReadUnreadable()
        : PublishedSiteReadBody(body);
  }
}

/// Answers the real bytes only after the test releases each read.
final class _LateAnswerReader implements PublishedSiteReadVerifier {
  _LateAnswerReader(this.bodies, {required this.onRead});

  final Map<String, List<int>> bodies;
  final Future<void> Function() onRead;

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    await onRead();
    final body = bodies[path];
    return body == null
        ? const PublishedSiteReadUnreadable()
        : PublishedSiteReadBody(body);
  }
}

/// A host whose new build never appears (GitHub Pages 404 forever).
final class _NeverReader implements PublishedSiteReadVerifier {
  const _NeverReader();

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async => const PublishedSiteReadUnreadable();
}

Future<void> _noSleep(Duration _) async {}

Future<bool> _neverMoved(PendingMove _) async => false;

/// A moved page that appears only after [readyAfter] of simulated time.
final class _LateMovedReader implements PublishedSiteReadVerifier {
  _LateMovedReader({required this.page, required this.readyAfter});

  final List<int> page;
  final Duration readyAfter;
  Duration elapsed = Duration.zero;

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    if (elapsed < readyAfter) return const PublishedSiteReadUnreadable();
    return path.isEmpty
        ? PublishedSiteReadBody(page)
        : const PublishedSiteReadAbsent();
  }
}
