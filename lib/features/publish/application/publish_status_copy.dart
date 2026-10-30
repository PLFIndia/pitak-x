/// The one place a finished publish becomes a sentence (application copy; R9).
library;

import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// The connection card's status line for a successful CATALOGUE publish.
String cataloguePublishStatusMessage(
  PublishSuccess result, {
  PublishHost? host,
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
        : 'Published! Your site is live.';
  } else {
    message = cloudflare
        ? 'Deployed, but the site is not reachable yet. Retry verification.'
        : 'Published! The commit is pushed — the site can take a minute to '
              'update.';
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
  } else {
    message = cloudflare
        ? 'Deployed, but the events page is not reachable yet. Retry '
              'verification.'
        : 'Published! The events commit is pushed — the page can take a minute '
              'to update.';
  }
  return _withCleanup(message, result);
}

String _withCleanup(String message, PublishSuccess result) =>
    result.temporaryCleanupFailed
    ? '$message ${CloudflareErrorMessages.temporaryCleanup}'
    : message;
