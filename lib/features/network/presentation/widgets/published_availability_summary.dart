/// The availability summary of the published-catalogue viewer (network
/// presentation; ADR 0019 AV14 and Decision 4, ADR 0015 amendment).
///
/// What it says, in order:
///  - "312 of 340 available · updated 2:05 pm": how many tagged items are
///    Available, and — only when the library's `availability.json` decided
///    the tags and its time is plausible — when that file was computed;
///  - one plain sentence on where the tags come from, so the words never
///    promise a live loan;
///  - a small note when the latest availability could not be checked.
///
/// The counts and the time are decided in the domain
/// (`PublishedAvailabilityMerge`); this widget only words them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/local_time_text.dart';
import 'package:pitaka/features/network/application/published_availability_controller.dart';
import 'package:pitaka/features/network/domain/published_availability_merge.dart';

/// Shown under the summary when the tags come from the library's
/// separately updated availability file.
const String publishedAvailabilityFromFileText =
    'The library updates availability after loans and returns. It is not a '
    'live loan check.';

/// Shown under the summary when the tags come from the catalogue itself.
const String publishedAvailabilityFromCatalogueText =
    'Availability is the snapshot from publish time, not a live loan check.';

/// Shown when the availability file could not be checked and nothing saved
/// could stand in (the items show the catalogue's own tags, if any).
const String publishedAvailabilityFailedText =
    "Couldn't check the latest availability.";

/// Shown when the tags come from the device's saved copy of the file.
const String publishedAvailabilitySavedCopyText =
    "Couldn't check the latest availability; showing the last one this "
    'device saw.';

/// The summary sentence for [merged], or null when no item shows a tag.
/// [time] words an epoch-millisecond time (passed in so the wording is
/// testable without a locale).
String? publishedAvailabilitySummaryText(
  PublishedCatalogueWithAvailability merged, {
  required String Function(int millis) time,
}) {
  if (!merged.hasTags) return null;
  final counts = '${merged.availableCount} of ${merged.taggedCount} available';
  final updatedAt = merged.updatedAt;
  return updatedAt == null ? counts : '$counts · updated ${time(updatedAt)}';
}

/// The summary block for the library saved at [siteUrl].
class PublishedAvailabilitySummary extends ConsumerWidget {
  /// Creates the block.
  const PublishedAvailabilitySummary({required this.siteUrl, super.key});

  /// The family key of the viewer's providers.
  final String siteUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merged = ref
        .watch(publishedCatalogueWithAvailabilityProvider(siteUrl))
        .valueOrNull;
    final file = ref.watch(publishedAvailabilityControllerProvider(siteUrl));
    final now = ref.watch(clockProvider)();
    final style = Theme.of(context).textTheme.bodySmall;

    final summary = merged == null
        ? null
        : publishedAvailabilitySummaryText(
            merged,
            time: (millis) =>
                formatLocalMoment(context, millis, nowMillis: now),
          );
    final note = file.hasError && !file.isLoading
        ? publishedAvailabilityFailedText
        : (file.valueOrNull?.isSavedCopy ?? false)
        ? publishedAvailabilitySavedCopyText
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary != null)
          Text(summary, style: Theme.of(context).textTheme.bodyMedium),
        if (merged != null && merged.hasTags)
          Text(
            merged.usesFile
                ? publishedAvailabilityFromFileText
                : publishedAvailabilityFromCatalogueText,
            style: style,
          ),
        if (note != null) Text(note, style: style),
      ],
    );
  }
}
