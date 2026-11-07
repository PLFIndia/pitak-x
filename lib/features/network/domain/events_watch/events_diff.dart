/// Pure diff of a freshly fetched `events.json` against a site's baseline
/// (PLAN.md §3, "Fetch outcome" table, `200` row).
///
/// This file has no IO and no state: it takes what was observed and what
/// was remembered and says what the new baseline is and which posters
/// changed. Everything that touches files or notifications lives elsewhere
/// and calls this.
library;

import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/domain/events_watch/pending_change.dart';
import 'package:pitaka/features/network/domain/events_watch/poster_digest.dart';
import 'package:pitaka/features/network/domain/events_watch/site_baseline.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_settings_token.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';

/// One detected change, before it becomes a [PendingChange].
final class ObservedChange {
  /// Creates an observed change.
  const ObservedChange({
    required this.kind,
    required this.imageRef,
    required this.caption,
    required this.digest,
  });

  /// Added or modified.
  final PendingChangeKind kind;

  /// Poster reference.
  final String imageRef;

  /// Raw caption as published (NOT yet safety-checked).
  final String caption;

  /// Digest of `(imageRef, caption)`.
  final String digest;

  /// Converts to a pending entry for [identity] under [token], applying the
  /// caption safety rule.
  PendingChange toPending({
    required WatchedLibraryIdentity identity,
    required WatchSettingsToken token,
  }) => PendingChange(
    kind: kind,
    identity: identity,
    imageRef: imageRef,
    safeCaption: PendingChange.safeCaptionOf(caption),
    digest: digest,
    token: token,
  );
}

/// Result of diffing one authoritative `200` payload.
sealed class EventsDiffResult {
  const EventsDiffResult();
}

/// The payload cannot be diffed (partial read, duplicate reference, newer
/// schema). Nothing changes; existing pending entries are withheld.
final class EventsDiffWithheld extends EventsDiffResult {
  /// Creates the withheld result.
  const EventsDiffWithheld();
}

/// The payload is authoritative. [baseline] is the new baseline to commit;
/// [changes] is empty when this read only ESTABLISHED a baseline (first
/// sight, or a baseline from a different token).
final class EventsDiffed extends EventsDiffResult {
  /// Creates the diffed result.
  EventsDiffed({required this.baseline, required List<ObservedChange> changes})
    : changes = List.unmodifiable(changes);

  /// New authoritative baseline.
  final SiteBaseline baseline;

  /// Added/modified posters, in publish order.
  final List<ObservedChange> changes;

  /// References present in the new baseline — pending entries for any other
  /// reference at this site must be dropped (the poster disappeared).
  Set<String> get currentRefs =>
      baseline.posters.map((p) => p.imageRef).toSet();
}

/// Diffs [observed] against [baseline] under [token].
///
/// Rules (PLAN.md §3):
///  - partial read, newer schema or duplicate references → withheld;
///  - null baseline, or a baseline from another token → new baseline, no
///    changes (quiet first sight / quiet re-enable);
///  - otherwise: unknown reference → added; known reference with a different
///    digest → modified; disappearance → nothing.
EventsDiffResult diffPublishedEvents({
  required SiteBaseline? baseline,
  required PublishedEvents observed,
  required WatchSettingsToken token,
  required String? validator,
}) {
  if (observed.hasPartialRead || observed.hasNewerSchema) {
    return const EventsDiffWithheld();
  }
  if (observed.posters.length > SiteBaseline.maxPosters) {
    return const EventsDiffWithheld();
  }
  final seenRefs = <String>{};
  final current = <BaselinePoster>[];
  final captions = <String, String>{};
  for (final poster in observed.posters) {
    if (!seenRefs.add(poster.imageRef)) return const EventsDiffWithheld();
    final digest = PosterDigest.compute(
      imageRef: poster.imageRef,
      caption: poster.description,
    );
    current.add(BaselinePoster(imageRef: poster.imageRef, digest: digest));
    captions[poster.imageRef] = poster.description;
  }
  final next = SiteBaseline(
    posters: current,
    token: token,
    validator: validator,
  );

  if (baseline == null || !baseline.token.sameAs(token)) {
    return EventsDiffed(baseline: next, changes: const []);
  }

  final changes = <ObservedChange>[];
  for (final poster in current) {
    final remembered = baseline.posterAt(poster.imageRef);
    if (remembered == null) {
      changes.add(
        ObservedChange(
          kind: PendingChangeKind.added,
          imageRef: poster.imageRef,
          caption: captions[poster.imageRef]!,
          digest: poster.digest,
        ),
      );
    } else if (remembered.digest != poster.digest) {
      changes.add(
        ObservedChange(
          kind: PendingChangeKind.modified,
          imageRef: poster.imageRef,
          caption: captions[poster.imageRef]!,
          digest: poster.digest,
        ),
      );
    }
  }
  return EventsDiffed(baseline: next, changes: changes);
}
