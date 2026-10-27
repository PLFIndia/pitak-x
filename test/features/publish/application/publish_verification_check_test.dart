import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/site/publish_verification_check.dart';
import 'package:pitaka/features/publish/application/site/published_file_read_back.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// SPECIFICATION of the pre-publish verification (Cloudflare plan F.4 step 2,
/// deviation 48 — the "Option B" rule).
///
/// The point of these tests: "could not check" and "checked and it is wrong"
/// are different facts. Only the second one may stop a publish.
class _ScriptedVerifier implements PublishedSiteVerifier {
  _ScriptedVerifier(this.answers);

  /// One answer per call; the last one repeats.
  final List<List<int>?> answers;
  int calls = 0;

  @override
  Future<List<int>?> read({
    required String siteUrl,
    required String path,
    required int maxBytes,
    String? cacheBuster,
  }) async {
    final index = calls < answers.length ? calls : answers.length - 1;
    calls++;
    return answers[index];
  }
}

void main() {
  final published = utf8.encode('{"books":[]}');
  final publishedSha = GitBlobSha.of(published);

  PublishVerificationCheck check(PublishedSiteVerifier verifier) =>
      PublishVerificationCheck(
        verifier: verifier,
        sleep: (_) async {},
        interval: Duration.zero,
      );

  Future<PublishVerificationOutcome> run(
    PublishedSiteVerifier verifier, {
    PublishState? localState = PublishState.deployed,
    String? localAnchor = 'HEAD',
    String remoteAnchor = 'HEAD',
    String? expectedSha = 'sha-books',
  }) => check(verifier).call(
    localState: localState,
    localAnchor: localAnchor,
    remoteAnchor: remoteAnchor,
    expectedSha: expectedSha,
    siteUrl: 'https://me.github.io/lib/',
    anchorPath: 'books.json',
    maxBytes: publishedCatalogueReadBackMaxBytes,
    revision: 1,
  );

  group('not applicable', () {
    test('a live record has nothing to verify', () async {
      final verifier = _ScriptedVerifier([published]);

      expect(
        await run(verifier, localState: PublishState.live),
        PublishVerificationOutcome.notApplicable,
      );
      expect(verifier.calls, 0);
    });

    test('a retired record has nothing to verify', () async {
      expect(
        await run(
          _ScriptedVerifier([published]),
          localState: PublishState.retired,
        ),
        PublishVerificationOutcome.notApplicable,
      );
    });

    test('no record at all has nothing to verify', () async {
      expect(
        await run(_ScriptedVerifier([published]), localState: null),
        PublishVerificationOutcome.notApplicable,
      );
    });

    test('a moved head means the unconfirmed write is superseded', () async {
      final verifier = _ScriptedVerifier([published]);

      expect(
        await run(verifier, localAnchor: 'OLD', remoteAnchor: 'NEW'),
        PublishVerificationOutcome.notApplicable,
      );
      expect(verifier.calls, 0);
    });

    test('a record with no anchor has nothing to verify', () async {
      expect(
        await run(_ScriptedVerifier([published]), localAnchor: null),
        PublishVerificationOutcome.notApplicable,
      );
    });

    test('no recorded sha means there is nothing to compare', () async {
      expect(
        await run(_ScriptedVerifier([published]), expectedSha: null),
        PublishVerificationOutcome.notApplicable,
      );
    });
  });

  group('the three real answers', () {
    test('matching bytes are a match', () async {
      final verifier = _ScriptedVerifier([published]);

      expect(
        await run(verifier, expectedSha: publishedSha),
        PublishVerificationOutcome.matched,
      );
      expect(verifier.calls, 1);
    });

    test('different bytes are a contradiction, not a retry', () async {
      final verifier = _ScriptedVerifier([
        utf8.encode('{"books":[1]}'),
        published, // would match, but the first answer already decided
      ]);

      expect(
        await run(verifier, expectedSha: publishedSha),
        PublishVerificationOutcome.contradicted,
      );
      expect(verifier.calls, 1);
    });

    test('no answer at all is unreachable, never a silent success', () async {
      final verifier = _ScriptedVerifier([null]);

      expect(
        await run(verifier, expectedSha: publishedSha),
        PublishVerificationOutcome.unreachable,
      );
      expect(verifier.calls, 3);
    });

    test('a later readable answer still counts', () async {
      final verifier = _ScriptedVerifier([null, published]);

      expect(
        await run(verifier, expectedSha: publishedSha),
        PublishVerificationOutcome.matched,
      );
      expect(verifier.calls, 2);
    });
  });
}
