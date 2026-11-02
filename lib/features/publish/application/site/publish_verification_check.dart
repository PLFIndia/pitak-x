/// The pre-publish verification of an unconfirmed publication (application
/// layer; Cloudflare plan F.4 step 2 / deviation 48, ADR 0019 Decision 10).
///
/// The situation it exists for (beginner note): a publish can land on the host
/// and still never be confirmed — the phone lost signal, the CDN was slow, the
/// app was killed. The record then says `deployed`: "the host accepted it, I
/// never saw it served". The next publish must not simply build on that.
///
/// What it does: if the record is `deployed` AND it describes the head we are
/// about to build on, read the file that proves that commit (its
/// [PublishProofPath]) and compare it with what this phone recorded:
///  - most proofs are a FILE: its content hash must equal the recorded one.
///    The bytes of the earlier publish are not kept, but their git blob sha
///    is, so one fetch answers "is the live site still what I published?";
///  - the proof of an availability REMOVAL is an ABSENCE: the file must
///    answer an exact HTTP 404. That is why this check reads through the
///    structured [PublishedSiteReadVerifier], which tells a real 404 apart
///    from "could not read".
///
/// The proof comes from the record, not from the caller: an events commit is
/// proven by `events.json` even when the catalogue publish runs the check
/// (plan A.1 item 8 — before ADR 0019 it read `books.json`, which an events
/// commit never changes, and could "prove" the wrong commit).
///
/// The three answers lead to three different behaviours, and that distinction
/// is the point (deviation 48):
///  - `matched` — mark the record live and carry on;
///  - `contradicted` — the site serves DIFFERENT content: stop, because a new
///    publish would silently overwrite whatever changed it;
///  - `unreachable` — no answer at all: carry on, because a phone on a train
///    must not be locked out of publishing by a timeout.
///
/// The FIRST readable answer decides. That is right once the earlier commit
/// has had time to go live; seconds after a commit it is wrong, which is why
/// the deferred check polls instead (ADR 0019 Decision 10). Since plan SP1 a
/// publish returns at commit time, so the NEXT publish can start while GitHub
/// Pages is still building the last one. Inside the build window
/// ([ReadBackBudget.gitHubBuildWindow], counted from the commit time the
/// record keeps) other bytes therefore mean [PublishVerificationOutcome
/// .stillBuilding], not "contradicted". That is safe because the check only
/// runs when the branch head is still this phone's own commit: no other
/// writer committed, so building on it overwrites nobody's work.
library;

import 'package:pitaka/features/publish/application/site/read_back_budget.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// What a verification of an ALREADY-published commit found (F.4 step 2).
///
/// Four outcomes, because "could not check" and "checked and it is wrong" are
/// different facts and must lead to different behaviour (deviation 48):
///  - [matched] — the live site serves exactly the recorded proof;
///  - [contradicted] — the site answered, with DIFFERENT content: someone or
///    something changed it, so a new publish must not silently overwrite it;
///  - [unreachable] — no answer within the budget (offline, timeout, a 404
///    where a file was expected, oversize). That is not evidence of a
///    conflict, so it must not block a publish on a phone with a bad
///    connection;
///  - [stillBuilding] — the site answered with other content, but the commit
///    is younger than the Pages build window: carry on like [unreachable]
///    (plan SP1);
///  - [notApplicable] — there is nothing to verify (the record is already live,
///    or the head moved, or no content sha was recorded).
enum PublishVerificationOutcome {
  /// The live site serves the recorded content.
  matched,

  /// The live site answered with different content.
  contradicted,

  /// The live site could not be read within the budget.
  unreachable,

  /// The live site still serves other content, inside the build window of
  /// the commit (plan SP1). Not proof either way; the publish carries on.
  stillBuilding,

  /// There is nothing to verify.
  notApplicable,
}

/// Verifies an unconfirmed publication before a new one is built.
final class PublishVerificationCheck {
  /// Creates the check over the bounded, structured public reader.
  const PublishVerificationCheck({
    required PublishedSiteReadVerifier reader,
    required Future<void> Function(Duration) sleep,
    this.attempts = defaultAttempts,
    this.interval = defaultInterval,
  }) : _reader = reader,
       _sleep = sleep;

  /// Polls for the pre-publish check.
  ///
  /// Deliberately short: the earlier publish has had time, so this is a
  /// confirmation, not a wait for a build. Three tries cover a cold CDN edge
  /// without making every publish feel slow.
  static const int defaultAttempts = 3;

  /// Pause between the pre-publish polls.
  static const Duration defaultInterval = Duration(seconds: 2);

  final PublishedSiteReadVerifier _reader;
  final Future<void> Function(Duration) _sleep;

  /// Maximum number of polls.
  final int attempts;

  /// Pause between polls.
  final Duration interval;

  /// Runs the check.
  ///
  /// [localState] and [localAnchor] describe what THIS PHONE recorded;
  /// [remoteAnchor] is what the host reports now. The check only applies when
  /// the record is `deployed` and its anchor still matches — otherwise the
  /// unconfirmed publication has been superseded and there is nothing to
  /// verify.
  ///
  /// [proof] says which file proves that commit. [expectedSha] is the hash
  /// recorded for that file; it is ignored when the proof is an absence, and
  /// a file proof without a recorded hash has nothing to compare.
  ///
  /// [committedAt] is when that commit was accepted (null = unknown) and
  /// [now] the current time, both epoch ms on this phone's clock. Other
  /// content counts as [PublishVerificationOutcome.stillBuilding] only when
  /// `0 <= now - committedAt < gitHubBuildWindow`; an unknown time or one in
  /// the future (the clock moved back) keeps the stricter rule.
  Future<PublishVerificationOutcome> call({
    required PublishState? localState,
    required String? localAnchor,
    required String remoteAnchor,
    required PublishProofPath proof,
    required String? expectedSha,
    required String siteUrl,
    required int revision,
    required int? committedAt,
    required int now,
  }) async {
    if (localState != PublishState.deployed) {
      return PublishVerificationOutcome.notApplicable;
    }
    if (localAnchor == null || localAnchor != remoteAnchor) {
      // Someone else moved the site on: our unconfirmed write is superseded,
      // and the new publish builds on their state.
      return PublishVerificationOutcome.notApplicable;
    }
    if (!proof.expectsAbsent && (expectedSha == null || expectedSha.isEmpty)) {
      return PublishVerificationOutcome.notApplicable;
    }
    final building = isInsideBuildWindow(committedAt: committedAt, now: now);
    for (var attempt = 0; attempt < attempts; attempt++) {
      await _sleep(interval);
      final outcome = await _read(siteUrl, proof, '$revision-$attempt');
      final decided = _decide(outcome, proof: proof, expectedSha: expectedSha);
      if (decided == PublishVerificationOutcome.contradicted && building) {
        return PublishVerificationOutcome.stillBuilding;
      }
      if (decided != null) return decided;
    }
    return PublishVerificationOutcome.unreachable;
  }

  /// True while a commit accepted at [committedAt] may still be building on
  /// GitHub Pages at [now] (see [call]).
  static bool isInsideBuildWindow({
    required int? committedAt,
    required int now,
  }) {
    if (committedAt == null) return false;
    final age = now - committedAt;
    return age >= 0 && age < ReadBackBudget.gitHubBuildWindow.inMilliseconds;
  }

  /// The verdict of one read, or null for "no readable answer yet, try
  /// again".
  ///
  /// A 404 proves an expected absence. Where a FILE was expected, a 404 is
  /// not a contradiction but "not readable", exactly as before this check
  /// could tell a 404 apart: a phone must not be blocked by a site that is
  /// briefly missing a file.
  static PublishVerificationOutcome? _decide(
    PublishedSiteReadOutcome outcome, {
    required PublishProofPath proof,
    required String? expectedSha,
  }) => switch (outcome) {
    PublishedSiteReadUnreadable() => null,
    PublishedSiteReadAbsent() =>
      proof.expectsAbsent ? PublishVerificationOutcome.matched : null,
    PublishedSiteReadBody(:final bytes) =>
      !proof.expectsAbsent && GitBlobSha.of(bytes) == expectedSha
          ? PublishVerificationOutcome.matched
          : PublishVerificationOutcome.contradicted,
  };

  Future<PublishedSiteReadOutcome> _read(
    String siteUrl,
    PublishProofPath proof,
    String cacheBuster,
  ) async {
    try {
      // Origin-bound, redirect-free and capped at the proof file's own
      // reader cap (one rule for both GitHub checks).
      return await _reader.readOutcome(
        siteUrl: siteUrl,
        path: proof.path,
        maxBytes: readBackMaxBytesFor(proof),
        cacheBuster: cacheBuster,
      );
    } on Exception {
      // The port promises not to throw; a failing adapter is treated like any
      // other unreadable answer, never as proof.
      return const PublishedSiteReadUnreadable();
    }
  }
}
