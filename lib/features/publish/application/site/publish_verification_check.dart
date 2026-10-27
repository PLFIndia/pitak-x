/// The pre-publish verification of an unconfirmed publication (application
/// layer; Cloudflare plan F.4 step 2 / deviation 48).
///
/// The situation it exists for (beginner note): a publish can land on the host
/// and still never be confirmed — the phone lost signal, the CDN was slow, the
/// app was killed. The record then says `deployed`: "the host accepted it, I
/// never saw it served". The next publish must not simply build on that.
///
/// What it does: if the record is `deployed` AND it describes the head we are
/// about to build on, fetch the live anchor file and compare its content hash
/// with the one this phone recorded. The hash is the whole trick — the bytes of
/// the earlier publish are not kept, but their git blob sha is, so one fetch
/// answers "is the live site still the thing I published?".
///
/// The three answers lead to three different behaviours, and that distinction
/// is the point (deviation 48):
///  - `matched` — mark the record live and carry on;
///  - `contradicted` — the site serves DIFFERENT content: stop, because a new
///    publish would silently overwrite whatever changed it;
///  - `unreachable` — no answer at all: carry on, because a phone on a train
///    must not be locked out of publishing by a timeout.
///
/// Host-neutral on purpose: it takes the state, the anchor and the expected
/// hash as values, so the Cloudflare publish can use the same rule with its
/// marker id in place of the commit sha.
library;

import 'package:pitaka/features/publish/application/site/published_file_read_back.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

/// Verifies an unconfirmed publication before a new one is built.
final class PublishVerificationCheck {
  /// Creates the check over a bounded verifier.
  const PublishVerificationCheck({
    required PublishedSiteVerifier verifier,
    required Future<void> Function(Duration) sleep,
    this.attempts = defaultAttempts,
    this.interval = defaultInterval,
  }) : _verifier = verifier,
       _sleep = sleep;

  /// Polls for the pre-publish check.
  ///
  /// Deliberately short: the earlier publish has had time, so this is a
  /// confirmation, not a wait for a build. Three tries cover a cold CDN edge
  /// without making every publish feel slow.
  static const int defaultAttempts = 3;

  /// Pause between the pre-publish polls.
  static const Duration defaultInterval = Duration(seconds: 2);

  final PublishedSiteVerifier _verifier;
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
  Future<PublishVerificationOutcome> call({
    required PublishState? localState,
    required String? localAnchor,
    required String remoteAnchor,
    required String? expectedSha,
    required String siteUrl,
    required String anchorPath,
    required int maxBytes,
    required int revision,
  }) async {
    if (localState != PublishState.deployed) {
      return PublishVerificationOutcome.notApplicable;
    }
    if (localAnchor == null || localAnchor != remoteAnchor) {
      // Someone else moved the site on: our unconfirmed write is superseded,
      // and the new publish builds on their state.
      return PublishVerificationOutcome.notApplicable;
    }
    if (expectedSha == null || expectedSha.isEmpty) {
      return PublishVerificationOutcome.notApplicable;
    }
    return PublishedFileReadBack(
      verifier: _verifier,
      sleep: _sleep,
      attempts: attempts,
      interval: interval,
    ).untilMatchesSha(
      siteUrl: siteUrl,
      path: anchorPath,
      expectedSha: expectedSha,
      revision: revision,
      maxBytes: maxBytes,
    );
  }
}
