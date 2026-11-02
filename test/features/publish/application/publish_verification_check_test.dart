import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/site/publish_verification_check.dart';
import 'package:pitaka/features/publish/application/site/read_back_budget.dart';
import 'package:pitaka/features/publish/domain/availability/availability_document.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// SPECIFICATION of the pre-publish verification (Cloudflare plan F.4 step 2,
/// deviation 48 — the "Option B" rule — and ADR 0019 Decision 10).
///
/// The point of these tests: "could not check" and "checked and it is wrong"
/// are different facts. Only the second one may stop a publish. Since S4 the
/// check reads the proof the record names, and an availability removal is
/// proven by an exact 404.
class _ScriptedReader implements PublishedSiteReadVerifier {
  _ScriptedReader(this.answers);

  /// One answer per call; the last one repeats.
  final List<PublishedSiteReadOutcome> answers;
  final List<(String path, int maxBytes)> calls = [];

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    final index = calls.length < answers.length
        ? calls.length
        : answers.length - 1;
    calls.add((path, maxBytes));
    return answers[index];
  }
}

class _ThrowingReader implements PublishedSiteReadVerifier {
  int calls = 0;

  @override
  Future<PublishedSiteReadOutcome> readOutcome({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    calls++;
    throw const FormatException('adapter bug');
  }
}

void main() {
  final published = utf8.encode('{"books":[]}');
  final publishedSha = GitBlobSha.of(published);
  final body = PublishedSiteReadBody(published);
  const absent = PublishedSiteReadAbsent();
  const unreadable = PublishedSiteReadUnreadable();

  PublishVerificationCheck check(PublishedSiteReadVerifier reader) =>
      PublishVerificationCheck(
        reader: reader,
        sleep: (_) async {},
        interval: Duration.zero,
      );

  Future<PublishVerificationOutcome> run(
    PublishedSiteReadVerifier reader, {
    PublishState? localState = PublishState.deployed,
    String? localAnchor = 'HEAD',
    String remoteAnchor = 'HEAD',
    PublishProofPath proof = PublishProofPath.booksJson,
    String? expectedSha = 'sha-books',
    int? committedAt,
    int now = 1700000000000,
  }) => check(reader).call(
    localState: localState,
    localAnchor: localAnchor,
    remoteAnchor: remoteAnchor,
    proof: proof,
    expectedSha: expectedSha,
    siteUrl: 'https://me.github.io/lib/',
    revision: 1,
    committedAt: committedAt,
    now: now,
  );

  group('not applicable', () {
    test('a live record has nothing to verify', () async {
      final reader = _ScriptedReader([body]);

      expect(
        await run(reader, localState: PublishState.live),
        PublishVerificationOutcome.notApplicable,
      );
      expect(reader.calls, isEmpty);
    });

    test('a retired record has nothing to verify', () async {
      expect(
        await run(_ScriptedReader([body]), localState: PublishState.retired),
        PublishVerificationOutcome.notApplicable,
      );
    });

    test('no record at all has nothing to verify', () async {
      expect(
        await run(_ScriptedReader([body]), localState: null),
        PublishVerificationOutcome.notApplicable,
      );
    });

    test('a moved head means the unconfirmed write is superseded', () async {
      final reader = _ScriptedReader([body]);

      expect(
        await run(reader, localAnchor: 'OLD', remoteAnchor: 'NEW'),
        PublishVerificationOutcome.notApplicable,
      );
      expect(reader.calls, isEmpty);
    });

    test('a record with no anchor has nothing to verify', () async {
      expect(
        await run(_ScriptedReader([body]), localAnchor: null),
        PublishVerificationOutcome.notApplicable,
      );
    });

    test('a file proof with no recorded sha has nothing to compare', () async {
      for (final sha in [null, '']) {
        final reader = _ScriptedReader([body]);
        expect(
          await run(reader, expectedSha: sha),
          PublishVerificationOutcome.notApplicable,
          reason: '$sha',
        );
        expect(reader.calls, isEmpty);
      }
    });
  });

  group('a file proof: the three real answers', () {
    test('matching bytes are a match', () async {
      final reader = _ScriptedReader([body]);

      expect(
        await run(reader, expectedSha: publishedSha),
        PublishVerificationOutcome.matched,
      );
      expect(reader.calls, hasLength(1));
    });

    test('different bytes are a contradiction, not a retry', () async {
      final reader = _ScriptedReader([
        PublishedSiteReadBody(utf8.encode('{"books":[1]}')),
        body, // would match, but the first answer already decided
      ]);

      expect(
        await run(reader, expectedSha: publishedSha),
        PublishVerificationOutcome.contradicted,
      );
      expect(reader.calls, hasLength(1));
    });

    test('no answer at all is unreachable, never a silent success', () async {
      final reader = _ScriptedReader([unreadable]);

      expect(
        await run(reader, expectedSha: publishedSha),
        PublishVerificationOutcome.unreachable,
      );
      expect(reader.calls, hasLength(PublishVerificationCheck.defaultAttempts));
    });

    test('a 404 where a file is expected is retried, not a contradiction '
        '(the behaviour before 404s could be told apart)', () async {
      final reader = _ScriptedReader([absent]);

      expect(
        await run(reader, expectedSha: publishedSha),
        PublishVerificationOutcome.unreachable,
      );
      expect(reader.calls, hasLength(PublishVerificationCheck.defaultAttempts));
    });

    test('a later readable answer still counts', () async {
      final reader = _ScriptedReader([unreadable, body]);

      expect(
        await run(reader, expectedSha: publishedSha),
        PublishVerificationOutcome.matched,
      );
      expect(reader.calls, hasLength(2));
    });

    test('an adapter that throws counts as unreadable', () async {
      final reader = _ThrowingReader();

      expect(
        await run(reader, expectedSha: publishedSha),
        PublishVerificationOutcome.unreachable,
      );
      expect(reader.calls, PublishVerificationCheck.defaultAttempts);
    });
  });

  group('ADR 0019: the record names the proof', () {
    test('each proof reads its own file with its own reader cap', () async {
      final expected = {
        PublishProofPath.booksJson: (
          'books.json',
          publishedCatalogueReadBackMaxBytes,
        ),
        PublishProofPath.eventsJson: (
          'events.json',
          publishedEventsReadBackMaxBytes,
        ),
        PublishProofPath.availabilityJson: (
          'availability.json',
          AvailabilityDocument.readerMaxBytes,
        ),
        PublishProofPath.availabilityJsonAbsent: (
          'availability.json',
          AvailabilityDocument.readerMaxBytes,
        ),
      };
      for (final MapEntry(key: proof, value: read) in expected.entries) {
        final reader = _ScriptedReader([unreadable]);
        await run(reader, proof: proof);
        expect(reader.calls.first, read, reason: proof.name);
        expect(readBackMaxBytesFor(proof), read.$2, reason: proof.name);
      }
    });

    test(
      'a removal is proven by an exact 404, without a recorded sha',
      () async {
        final reader = _ScriptedReader([absent]);

        expect(
          await run(
            reader,
            proof: PublishProofPath.availabilityJsonAbsent,
            expectedSha: null,
          ),
          PublishVerificationOutcome.matched,
        );
        expect(reader.calls, hasLength(1));
      },
    );

    test('a removal whose file is still served is a contradiction', () async {
      final reader = _ScriptedReader([body]);

      expect(
        await run(reader, proof: PublishProofPath.availabilityJsonAbsent),
        PublishVerificationOutcome.contradicted,
      );
    });

    test('a removal that cannot be read is unreachable, then a late 404 '
        'still counts', () async {
      expect(
        await run(
          _ScriptedReader([unreadable]),
          proof: PublishProofPath.availabilityJsonAbsent,
        ),
        PublishVerificationOutcome.unreachable,
      );
      expect(
        await run(
          _ScriptedReader([unreadable, absent]),
          proof: PublishProofPath.availabilityJsonAbsent,
        ),
        PublishVerificationOutcome.matched,
      );
    });
  });

  group('plan SP1: the next publish may start while Pages still builds', () {
    const now = 1700000000000;
    final window = ReadBackBudget.gitHubBuildWindow.inMilliseconds;
    final other = PublishedSiteReadBody(utf8.encode('{"books":[1]}'));

    test('the window is the documented 10 minutes of a Pages build', () {
      expect(ReadBackBudget.gitHubBuildWindow, const Duration(minutes: 10));
    });

    test(
      'other bytes inside the window are stillBuilding, decided at once',
      () async {
        for (final age in [0, 1, window - 1]) {
          final reader = _ScriptedReader([other, body]);
          expect(
            await run(
              reader,
              expectedSha: publishedSha,
              committedAt: now - age,
            ),
            PublishVerificationOutcome.stillBuilding,
            reason: 'age $age ms',
          );
          expect(reader.calls, hasLength(1), reason: 'age $age ms');
        }
      },
    );

    test('a removal still served inside the window is stillBuilding', () async {
      expect(
        await run(
          _ScriptedReader([body]),
          proof: PublishProofPath.availabilityJsonAbsent,
          committedAt: now - 1000,
        ),
        PublishVerificationOutcome.stillBuilding,
      );
    });

    test('the stricter rule holds at the window end, with no time, and for a '
        'time in the future (the clock moved back)', () async {
      for (final committedAt in <int?>[now - window, null, now + 1]) {
        expect(
          await run(
            _ScriptedReader([other]),
            expectedSha: publishedSha,
            committedAt: committedAt,
          ),
          PublishVerificationOutcome.contradicted,
          reason: '$committedAt',
        );
      }
    });

    test('inside the window a match is still a match and no answer is still '
        'unreachable', () async {
      expect(
        await run(
          _ScriptedReader([body]),
          expectedSha: publishedSha,
          committedAt: now - 1000,
        ),
        PublishVerificationOutcome.matched,
      );
      expect(
        await run(
          _ScriptedReader([unreadable]),
          expectedSha: publishedSha,
          committedAt: now - 1000,
        ),
        PublishVerificationOutcome.unreachable,
      );
    });

    test('isInsideBuildWindow is the one rule', () {
      expect(
        PublishVerificationCheck.isInsideBuildWindow(
          committedAt: now,
          now: now,
        ),
        isTrue,
      );
      expect(
        PublishVerificationCheck.isInsideBuildWindow(
          committedAt: now - window,
          now: now,
        ),
        isFalse,
      );
      expect(
        PublishVerificationCheck.isInsideBuildWindow(
          committedAt: null,
          now: now,
        ),
        isFalse,
      );
    });
  });
}
