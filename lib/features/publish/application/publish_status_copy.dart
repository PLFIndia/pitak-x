/// The one place a finished publish becomes a sentence (application copy; R9).
library;

import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/site/deferred_publish_verification.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// A GitHub commit was accepted and its deferred check is still waiting for
/// GitHub Pages (plan SP1; the plan's words, product owner 2026-11-02).
const String gitHubGoingLiveMessage =
    'Published — going live (usually within a minute).';

/// The deferred check proved the GitHub commit served by the live site.
const String gitHubLiveMessage = 'Published! Your site is live.';

/// The commit was accepted, but no check saw it live (yet): out of budget, a
/// newer commit took over, or the check was stopped.
const String gitHubNotSeenLiveMessage =
    'Published! The commit is pushed — the site can take a minute to update.';

/// The connection card's status line for a successful CATALOGUE publish.
///
/// [goingLive] is how the GitHub commit's deferred check ended (plan SP1),
/// or null while it is still running; the card passes it so its line updates
/// itself from "going live" to "live" (product owner, 2026-11-02). It is
/// ignored for Cloudflare and for a result without a deferred check.
String cataloguePublishStatusMessage(
  PublishSuccess result, {
  PublishHost? host,
  DeferredVerificationOutcome? goingLive,
}) {
  final cloudflare = host == PublishHost.cloudflare;
  final verified = result.pagesLive ?? false;
  final String message;
  if (!result.localStateSaved) {
    message = cloudflare
        ? 'Cloudflare accepted the deployment, but this device could not save '
              'all publish state. Retry verification before publishing again.'
        : gitHubPublishRecordUnsavedMessage;
  } else if (!result.newDeployment) {
    // A deploy-free check of an earlier publication: nothing was published
    // now, so "Published!" would be a lie (fix-plan L7).
    message = cloudflare
        ? 'Verified: your live site matches this phone’s last publish.'
        : 'Verified: your live site matches this phone’s last commit.';
  } else if (verified) {
    message = cloudflare
        ? 'Published! Your site is verified live.'
        : gitHubLiveMessage;
  } else if (cloudflare) {
    message =
        'Deployed, but the site is not reachable yet. Retry verification.';
  } else if (result.verification == null) {
    message = gitHubNotSeenLiveMessage;
  } else {
    message = switch (goingLive) {
      null => gitHubGoingLiveMessage,
      DeferredVerificationOutcome.live => gitHubLiveMessage,
      // Proven, but the record or the share address could not be saved.
      DeferredVerificationOutcome.notSaved => gitHubPublishRecordUnsavedMessage,
      DeferredVerificationOutcome.notProven ||
      DeferredVerificationOutcome.superseded ||
      DeferredVerificationOutcome.cancelled => gitHubNotSeenLiveMessage,
    };
  }
  return _withCleanup(message, result);
}

/// The events screen's message for a successful EVENTS publish.
String eventsPublishStatusMessage(PublishSuccess result, {PublishHost? host}) {
  final cloudflare = host == PublishHost.cloudflare;
  final verified = result.pagesLive ?? false;
  final String message;
  if (!result.localStateSaved) {
    message = cloudflare
        ? 'Cloudflare accepted the deployment, but this device could not save '
              'all publish state. Retry verification before publishing again.'
        : gitHubPublishRecordUnsavedMessage;
  } else if (!result.newDeployment) {
    message = 'Verified: your events page is live at ${result.pagesUrl}';
  } else if (verified) {
    message = 'Published! Your events page is at ${result.pagesUrl}';
  } else if (cloudflare) {
    message =
        'Deployed, but the events page is not reachable yet. Retry '
        'verification.';
  } else if (result.verification != null) {
    // Plan SP1: one message; the deferred check finishes in the background
    // (product owner, 2026-11-02).
    message =
        'Published — your events page is going live (usually within a '
        'minute): ${result.pagesUrl}';
  } else {
    message =
        'Published! The events commit is pushed — the page can take a minute '
        'to update.';
  }
  return _withCleanup(message, result);
}

String _withCleanup(String message, PublishSuccess result) =>
    result.temporaryCleanupFailed
    ? '$message ${CloudflareErrorMessages.temporaryCleanup}'
    : message;
