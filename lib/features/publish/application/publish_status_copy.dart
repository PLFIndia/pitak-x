/// The one place a finished publish becomes a sentence (application copy; R9).
///
/// Why a shared function (beginner note): two different screens report a
/// publish, and a result has three outcomes that must not be confused —
/// verified live, pushed but not yet visible, and pushed but NOT recorded on
/// this phone. Writing those conditionals twice is how one screen ends up
/// claiming a commit that the phone never saved. Both screens read them here.
library;

import 'package:pitaka/features/publish/application/publish_events_use_case.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/domain/github_error_messages.dart';

/// The connection tab's status line for a successful CATALOGUE publish.
String cataloguePublishStatusMessage(PublishSuccess result) {
  if (!result.localStateSaved) {
    // The commit landed: the site IS updated. What failed is this phone's own
    // record of it, which the next publish reconciles from the remote tree.
    return gitHubPublishRecordUnsavedMessage;
  }
  return (result.pagesLive ?? false)
      ? 'Published! Your site is live.'
      : 'Published! The commit is pushed — the site can take a minute to '
            'update.';
}

/// The events screen's message for a successful EVENTS publish.
String eventsPublishStatusMessage(PublishEventsSuccess result) {
  if (!result.localStateSaved) return gitHubPublishRecordUnsavedMessage;
  return 'Published! Your events page is at ${result.eventsUrl}';
}
