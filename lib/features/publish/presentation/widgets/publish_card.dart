/// Host-neutral ordinary publish card and replacement confirmation plumbing.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/publish/application/publish_controller.dart';
import 'package:pitaka/features/publish/application/publish_result.dart';
import 'package:pitaka/features/publish/application/publish_status_copy.dart';
import 'package:pitaka/features/publish/application/site/publish_journal_reset_controller.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status_controller.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/presentation/widgets/move_site_controls.dart';
import 'package:pitaka/features/publish/presentation/widgets/pending_move_banner.dart';
import 'package:pitaka/features/publish/presentation/widgets/publish_journal_reset_dialog.dart';
import 'package:pitaka/features/publish/presentation/widgets/replace_site_dialog.dart';
import 'package:pitaka/features/publish/presentation/widgets/section_card.dart';
import 'package:pitaka/features/publish/presentation/widgets/share_library_sheet.dart';

/// Shows active-host/target truth, verified sharing, and ordinary actions.
class PublishCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const PublishCard({super.key});

  @override
  ConsumerState<PublishCard> createState() => _PublishCardState();
}

class _PublishCardState extends ConsumerState<PublishCard> {
  bool _dialogOpen = false;
  PublishReplacementSummary? _shownSummary;

  @override
  Widget build(BuildContext context) {
    ref.listen(publishControllerProvider, (_, next) {
      final result = next.valueOrNull;
      if (result is PublishReplacementRequired &&
          !identical(_shownSummary, result.summary)) {
        _shownSummary = result.summary;
        unawaited(_confirmReplacement(result.summary));
      }
    });
    final status = ref.watch(publishSiteStatusProvider);
    final publish = ref.watch(publishControllerProvider);
    return status.when(
      loading: () => const SectionCard(
        title: 'Publish',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const SectionCard(
        title: 'Publish',
        child: Text('Could not load the publishing setup.'),
      ),
      data: (site) => _buildCard(site, publish),
    );
  }

  Widget _buildCard(
    PublishSiteStatus site,
    AsyncValue<PublishResult?> publish,
  ) {
    final result = publish.valueOrNull;
    final busy = publish.isLoading;
    final review = result is PublishReplacementRequired;
    final target = site.target;
    return Column(
      children: [
        if (site.journalUnreadable)
          SectionCard(
            title: 'Publishing record',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pitak can’t read its record of where your library is '
                  'published. This can happen after installing an older '
                  'version.',
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: busy ? null : _resetJournal,
                  child: const Text('Reset publishing record'),
                ),
              ],
            ),
          ),
        SectionCard(
          title: 'Publish',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Active host: ${site.hostLabel}'),
              if (target != null) ...[
                const SizedBox(height: 8),
                SelectableText('Configured target: ${target.siteUrl}'),
                const Text('A configured target is not necessarily live yet.'),
              ] else if (site.setupMessage != null) ...[
                const SizedBox(height: 8),
                Text(site.setupMessage!),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: !site.canPublish || busy
                    ? null
                    : () {
                        if (result is PublishReplacementRequired) {
                          unawaited(_confirmReplacement(result.summary));
                        } else {
                          unawaited(_publish());
                        }
                      },
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload),
                label: Text(
                  review ? 'Review site replacement' : 'Publish catalogue now',
                ),
              ),
              if (_canRetryVerification(site, result)) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: busy ? null : _retryVerification,
                  child: const Text('Retry verification'),
                ),
              ],
              if (result case final PublishSuccess success) ...[
                const SizedBox(height: 8),
                Text(
                  cataloguePublishStatusMessage(success, host: site.activeHost),
                ),
              ] else if (result case PublishFailure(:final reason)) ...[
                const SizedBox(height: 8),
                Text('Publish failed: $reason'),
              ] else if (review) ...[
                const SizedBox(height: 8),
                const Text('Review the replacement before publishing.'),
              ],
            ],
          ),
        ),
        if (site.pendingMove case final pending?)
          PendingMoveBanner(pending: pending)
        else
          MoveSiteControls(enabled: site.canMove),
        if (site.verifiedSiteUrl case final url?)
          SectionCard(
            title: 'Your site',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(url),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _copy(url),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy link'),
                    ),
                    FilledButton.icon(
                      onPressed: () => showShareLibrarySheet(context, url: url),
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Share'),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  bool _canRetryVerification(PublishSiteStatus site, PublishResult? result) {
    if (site.activeHost != PublishHost.cloudflare) return false;
    return switch (result) {
      final PublishSuccess success =>
        success.pagesLive == null || !success.localStateSaved,
      PublishFailure(:final reason) =>
        // A contradiction needs a reviewed replacement, never another check;
        // "nothing to verify" is not a transient failure either.
        reason == CloudflareErrorMessages.siteNotChecked ||
            reason == CloudflareErrorMessages.publicationVerificationFailed,
      _ => false,
    };
  }

  Future<void> _publish() async {
    try {
      await ref.read(publishControllerProvider.notifier).publish();
    } on Object {
      // A `Failure` is not an `Exception`; catching only the latter left
      // this card's spinner on for the session (fix-plan M8).
      _snack('Something went wrong. Please try again.');
    }
  }

  Future<void> _retryVerification() async {
    try {
      await ref
          .read(publishControllerProvider.notifier)
          .publish(verificationOnly: true);
    } on Object {
      // A `Failure` is not an `Exception`; catching only the latter left
      // this card's spinner on for the session (fix-plan M8).
      _snack('Something went wrong. Please try again.');
    }
  }

  Future<void> _confirmReplacement(PublishReplacementSummary summary) async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    _shownSummary = summary;
    try {
      final confirmed = await showReplaceSiteDialog(context, summary);
      _dialogOpen = false;
      if (!mounted || !confirmed) return;
      await ref
          .read(publishControllerProvider.notifier)
          .publish(confirmation: summary);
    } on Object {
      // A `Failure` is not an `Exception`; catching only the latter left
      // this card's spinner on for the session (fix-plan M8).
      _snack('Something went wrong. Please try again.');
    } finally {
      _dialogOpen = false;
    }
  }

  Future<void> _resetJournal() async {
    if (!await showPublishJournalResetDialog(context)) return;
    if (!mounted) return;
    final result = await ref
        .read(publishJournalResetProvider.notifier)
        .resetUnreadable();
    if (!mounted) return;
    result.fold(
      (_) => _snack('The publishing record could not be reset. Try again.'),
      (_) =>
          _snack('Publishing record reset. Publish to record your site again.'),
    );
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    _snack('Link copied');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
