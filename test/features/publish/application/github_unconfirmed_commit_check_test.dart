import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/github_publication_reconciler.dart';
import 'package:pitaka/features/publish/application/github_unconfirmed_commit_check.dart';
import 'package:pitaka/features/publish/application/site/publish_verification_check.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

import '../support/github_lane_fakes.dart';

/// The shared pre-check of an unconfirmed GitHub commit (ADR 0019
/// Decision 10): it picks the proof the record names, and only a match
/// writes anything.
void main() {
  final target = GitHubPublishTarget.create('me/lib')!;
  final books = utf8.encode('{"books":[]}');
  final events = utf8.encode('{"posters":[]}');

  PublishManifest unconfirmed({PublishProofPath? proof, int? committedAt}) =>
      PublishManifest(
        repo: 'me/lib',
        branch: 'main',
        headSha: 'HEAD',
        fileShas: {
          'books.json': laneSha(books),
          'events.json': laneSha(events),
        },
        proofPath: proof,
        committedAt: committedAt,
      );

  Future<(PublishVerificationOutcome, LaneMemManifest, LaneRecorder)> run({
    required PublishManifest local,
    required LaneSite? site,
    PublishProofPath legacyProof = PublishProofPath.booksJson,
    int now = 1700000000000,
  }) async {
    final manifest = LaneMemManifest(local);
    final recorder = LaneRecorder();
    final outcome =
        await GitHubUnconfirmedCommitCheck(
          reader: site,
          manifest: manifest,
          hostState: recorder,
          sleep: (_) async {},
        ).call(
          local: local,
          // The reconciled record of an unchanged branch is the same record.
          publication: ReconciledPublication(
            manifest: local,
            headSha: 'HEAD',
            knownBlobShas: const {},
          ),
          target: target,
          legacyProof: legacyProof,
          revision: 1,
          now: now,
        );
    return (outcome, manifest, recorder);
  }

  test('no reader wired: not applicable, nothing read or written', () async {
    final (outcome, manifest, recorder) = await run(
      local: unconfirmed(),
      site: null,
    );
    expect(outcome, PublishVerificationOutcome.notApplicable);
    expect(manifest.saves, isEmpty);
    expect(recorder.recorded, isEmpty);
  });

  test("the record's own proof wins over the caller's legacy file", () async {
    final site = LaneSite(
      (path, _) => path == 'events.json'
          ? laneBody(events)
          : laneBody(utf8.encode('changed')),
    );
    final (outcome, manifest, recorder) = await run(
      local: unconfirmed(proof: PublishProofPath.eventsJson),
      site: site,
    );
    expect(outcome, PublishVerificationOutcome.matched);
    expect(site.reads.single.$1, 'events.json');
    expect(manifest.current.state, PublishState.live);
    expect(recorder.recorded.single.targetId, target.targetId);
  });

  test('a record without a proof falls back to the legacy file', () async {
    final site = LaneSite((path, _) => laneBody(books));
    final (outcome, _, _) = await run(
      local: unconfirmed(),
      site: site,
      legacyProof: PublishProofPath.eventsJson,
    );
    // events.json was read (the legacy file), and it is not books' bytes.
    expect(site.reads.first.$1, 'events.json');
    expect(outcome, PublishVerificationOutcome.contradicted);
  });

  test('a contradiction writes nothing', () async {
    final (outcome, manifest, recorder) = await run(
      local: unconfirmed(proof: PublishProofPath.booksJson),
      site: LaneSite((_, _) => laneBody(utf8.encode('someone else'))),
    );
    expect(outcome, PublishVerificationOutcome.contradicted);
    expect(manifest.saves, isEmpty);
    expect(recorder.recorded, isEmpty);
  });

  test('plan SP1: other bytes while the recorded commit is still inside its '
      'Pages build window are stillBuilding and write nothing', () async {
    final (outcome, manifest, recorder) = await run(
      local: unconfirmed(
        proof: PublishProofPath.booksJson,
        committedAt: 1700000000000 - 30000,
      ),
      site: LaneSite((_, _) => laneBody(utf8.encode('previous books'))),
    );
    expect(outcome, PublishVerificationOutcome.stillBuilding);
    expect(manifest.saves, isEmpty);
    expect(recorder.recorded, isEmpty);
  });

  test(
    'plan SP1: after the window the same answer is a contradiction',
    () async {
      final (outcome, _, _) = await run(
        local: unconfirmed(
          proof: PublishProofPath.booksJson,
          committedAt:
              1700000000000 - const Duration(minutes: 10).inMilliseconds,
        ),
        site: LaneSite((_, _) => laneBody(utf8.encode('previous books'))),
      );
      expect(outcome, PublishVerificationOutcome.contradicted);
    },
  );

  test('a removal proof is matched by a 404 (no hash needed)', () async {
    final local = PublishManifest(
      repo: 'me/lib',
      branch: 'main',
      headSha: 'HEAD',
      fileShas: {'books.json': laneSha(books)},
      proofPath: PublishProofPath.availabilityJsonAbsent,
    );
    final (outcome, manifest, _) = await run(
      local: local,
      site: LaneSite((_, _) => const PublishedSiteReadAbsent()),
    );
    expect(outcome, PublishVerificationOutcome.matched);
    expect(manifest.current.state, PublishState.live);
  });
}
