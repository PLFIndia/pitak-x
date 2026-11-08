/// One detected poster change that has not yet been successfully submitted
/// as a notification (PLAN.md §1 "Pending change", §4).
///
/// "Pending" is NOT notification history (beginner note): an entry exists
/// only between "the worker saw a change" and "Android accepted the
/// notification". It is removed right after a successful submission, and
/// discarded whenever the settings token changes.
library;

import 'package:pitaka/core/text/safe_display_text.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/network/domain/events_watch/poster_digest.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_settings_token.dart';
import 'package:pitaka/features/network/domain/events_watch/watched_library.dart';
import 'package:pitaka/features/network/domain/published_event_poster_resolver.dart';

/// What kind of change was observed.
enum PendingChangeKind {
  /// A reference the baseline did not have.
  added,

  /// A known reference whose digest changed (new caption).
  modified,
}

/// An immutable pending alert for one poster at one library.
final class PendingChange {
  /// Creates a pending change. Use [validate] for stored input.
  const PendingChange({
    required this.kind,
    required this.identity,
    required this.imageRef,
    required this.safeCaption,
    required this.digest,
    required this.token,
  });

  /// Added or modified.
  final PendingChangeKind kind;

  /// The saved row this alert belongs to (re-checked before showing).
  final WatchedLibraryIdentity identity;

  /// Same-site poster reference. Together with the site URL this is the
  /// key: at most one pending entry per `(siteUrl, imageRef)`.
  final String imageRef;

  /// The caption to show, or null when the caption is empty or fails the
  /// safe-display check — the notifier then uses a fixed fallback line.
  final String? safeCaption;

  /// Digest of the content this entry describes (for coalescing).
  final String digest;

  /// Settings token under which the change was detected.
  final WatchSettingsToken token;

  /// Convenience: canonical site URL.
  String get siteUrl => identity.siteUrl;

  /// Layout whitespace a publisher may legitimately type (line breaks,
  /// tabs, repeated spaces, Unicode line/paragraph separators).
  static final RegExp _layoutWhitespace = RegExp(r'[ \t\r\n\u2028\u2029]+');

  /// The one-line text to show for a caption, or null when nothing safe
  /// can be shown (the notifier then uses a fixed fallback line).
  ///
  /// Beginner note: a notification body is a single line, and
  /// `EventPoster.create` accepts multi-line descriptions, so a caption
  /// with line breaks is normal publisher input, not an attack. Runs of
  /// layout whitespace are folded into one space BEFORE the safety check;
  /// every other control, zero-width or bidi character still rejects the
  /// caption. The result is a fixed point (folding it again changes
  /// nothing), which [validate] relies on for stored captions.
  static String? safeCaptionOf(String raw) {
    final folded = raw.replaceAll(_layoutWhitespace, ' ').trim();
    if (folded.isEmpty) return null;
    if (folded.length > EventPoster.maxDescriptionLength) return null;
    if (!SafeDisplayText.isSafe(folded)) return null;
    return folded;
  }

  /// Strict gate for stored input.
  static PendingChange? validate({
    required Object? kind,
    required WatchedLibraryIdentity identity,
    required Object? imageRef,
    required Object? safeCaption,
    required Object? digest,
    required WatchSettingsToken token,
  }) {
    final parsedKind = switch (kind) {
      'added' => PendingChangeKind.added,
      'modified' => PendingChangeKind.modified,
      _ => null,
    };
    if (parsedKind == null) return null;
    if (imageRef is! String ||
        PublishedEventPosterResolver.sanitizeReference(imageRef) != imageRef) {
      return null;
    }
    if (!PosterDigest.isValid(digest)) return null;
    final String? caption;
    if (safeCaption == null) {
      caption = null;
    } else if (safeCaption is String) {
      // Re-validate: a stored caption is as untrusted as a fetched one.
      caption = safeCaptionOf(safeCaption);
      if (caption != safeCaption) return null;
    } else {
      return null;
    }
    return PendingChange(
      kind: parsedKind,
      identity: identity,
      imageRef: imageRef,
      safeCaption: caption,
      digest: digest! as String,
      token: token,
    );
  }

  /// The same entry describing newer content at the same reference. The
  /// kind is kept: an addition the user never saw stays an addition.
  PendingChange withContent({
    required String? safeCaption,
    required String digest,
  }) => PendingChange(
    kind: kind,
    identity: identity,
    imageRef: imageRef,
    safeCaption: safeCaption,
    digest: digest,
    token: token,
  );

  /// Field-by-field equality (repo convention).
  bool sameAs(PendingChange other) =>
      other.kind == kind &&
      other.identity.sameAs(identity) &&
      other.imageRef == imageRef &&
      other.safeCaption == safeCaption &&
      other.digest == digest &&
      other.token.sameAs(token);

  /// Never includes the caption or URL.
  @override
  String toString() => 'PendingChange(${kind.name}, #${identity.rowId})';
}
