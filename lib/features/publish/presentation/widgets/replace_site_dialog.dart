/// Explicit whole-Worker replacement confirmation, copy selected by reason.
///
/// Every message says what this phone knows and what the publish will do. The
/// reason only selects copy: the WRITE is authorised by the summary's remote
/// anchor, which the use case re-checks before deploying (fix-plan N1/M10).
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';

/// Shows the reviewed facts and returns true only for explicit confirmation.
Future<bool> showReplaceSiteDialog(
  BuildContext context,
  PublishReplacementSummary summary,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(_title(summary.reason)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_message(summary)),
            if (summary.catalogueIsEmpty) ...[
              const SizedBox(height: 12),
              const Text('Your catalogue has 0 items'),
            ],
            if (summary.eventsIsEmpty) ...[
              const SizedBox(height: 12),
              const Text('Your events page will be empty'),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(_confirmLabel(summary.reason)),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

String _title(PublishReplacementReason reason) => switch (reason) {
  PublishReplacementReason.targetChanged => 'Publish to a different site?',
  PublishReplacementReason.addressChanged => 'Publish at a new address?',
  PublishReplacementReason.workerMissing => 'Recreate your site?',
  PublishReplacementReason.localBytesMissing => 'Repair your site?',
  _ => 'Replace your Cloudflare site?',
};

String _confirmLabel(PublishReplacementReason reason) => switch (reason) {
  PublishReplacementReason.targetChanged => 'Publish to the new site',
  PublishReplacementReason.addressChanged => 'Publish at the new address',
  PublishReplacementReason.workerMissing => 'Recreate and publish',
  PublishReplacementReason.localBytesMissing => 'Repair and publish',
  _ => 'Replace the site',
};

/// The body: the changed-review warning first, then the reason's own copy.
String _message(PublishReplacementSummary summary) {
  final body = _reasonMessage(summary);
  if (!summary.remoteChangedSinceReview) return body;
  return 'The Cloudflare site changed after you reviewed this. Review the '
      'replacement again.\n\n$body';
}

String _reasonMessage(PublishReplacementSummary summary) {
  final target = summary.target;
  final catalogue = '${summary.catalogueItemCount} items';
  final catalogueAndPosters =
      '($catalogue) and ${summary.posterCount} event posters';
  return switch (summary.reason) {
    PublishReplacementReason.localBytesMissing =>
      'Some files from your last publish are no longer on this phone or on '
          'Cloudflare. Publishing your whole library again repairs the site: '
          '$catalogue, ${summary.posterCount} posters.',
    PublishReplacementReason.workerMissing =>
      'The Cloudflare Worker “${target.workerName.value}” no longer exists. '
          'Publishing recreates it at ${target.siteUrl} with this phone’s '
          'catalogue $catalogueAndPosters.',
    PublishReplacementReason.addressChanged =>
      'Your workers.dev address changed from ${summary.previousSiteUrl} to '
          '${target.siteUrl}, so the old address no longer works. Publishing '
          'rebuilds this Worker’s site at the new address.',
    PublishReplacementReason.targetChanged => _targetChanged(
      summary,
      catalogueAndPosters,
    ),
    PublishReplacementReason.recordContradicted =>
      'The live Cloudflare site does not match this phone’s last publish. '
          'Publishing replaces the whole Worker with this phone’s catalogue '
          '$catalogueAndPosters.',
    PublishReplacementReason.unknownRemoteState ||
    PublishReplacementReason.retiredSite =>
      'This phone has no verified record of the current site. Publishing '
          'replaces the whole Worker with this phone’s catalogue '
          '$catalogueAndPosters. Anything only on the site — including a '
          'newer catalogue or other posters — will be removed.',
  };
}

String _targetChanged(PublishReplacementSummary summary, String counts) {
  final previous = summary.previousSiteUrl;
  final warning = summary.remoteAnchor.workerExists
      ? 'Publishing replaces everything already on '
            '${summary.target.siteUrl} with this phone’s catalogue ($counts).'
      : 'Publishing creates the Cloudflare Worker '
            '“${summary.target.workerName.value}” with this phone’s catalogue '
            '($counts).';
  return 'This library was last published from this phone to $previous. That '
      'site is not changed or deleted — it keeps showing its last version. '
      'Your share link switches to ${summary.target.siteUrl} once the new site '
      'is verified.\n\n$warning';
}
