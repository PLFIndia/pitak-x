/// What the worker last saw at one library — the reference point every
/// later diff compares against (PLAN.md §1 "Baseline").
///
/// Null vs empty (beginner note): a site whose `events.json` the worker has
/// never read authoritatively has NO baseline (`null`). A site that was read
/// and had zero posters has an EMPTY baseline. They behave differently: a
/// first read never notifies (decision 5), while a poster appearing after an
/// empty baseline is a real addition.
library;

import 'package:pitaka/features/network/domain/events_watch/poster_digest.dart';
import 'package:pitaka/features/network/domain/events_watch/watch_settings_token.dart';
import 'package:pitaka/features/network/domain/published_event_poster_resolver.dart';

/// One poster as remembered in a baseline: its reference and digest only.
/// No caption is stored — the digest covers it, and keeping text out of the
/// state file minimizes what the file reveals.
final class BaselinePoster {
  /// Creates a remembered poster. Use [validate] for stored input.
  const BaselinePoster({required this.imageRef, required this.digest});

  /// Same-site `posters/<leaf>` reference.
  final String imageRef;

  /// [PosterDigest] over `(imageRef, caption)`.
  final String digest;

  /// Strict gate for stored input.
  static BaselinePoster? validate({
    required Object? imageRef,
    required Object? digest,
  }) {
    if (imageRef is! String ||
        PublishedEventPosterResolver.sanitizeReference(imageRef) != imageRef) {
      return null;
    }
    if (!PosterDigest.isValid(digest)) return null;
    return BaselinePoster(imageRef: imageRef, digest: digest! as String);
  }

  /// Field-by-field equality (repo convention).
  bool sameAs(BaselinePoster other) =>
      other.imageRef == imageRef && other.digest == digest;
}

/// The authoritative last-seen state of one site.
final class SiteBaseline {
  /// Creates a baseline. [posters] is copied and made unmodifiable.
  SiteBaseline({
    required List<BaselinePoster> posters,
    required this.token,
    this.validator,
  }) : posters = List.unmodifiable(posters);

  /// The public contract allows at most two posters per site.
  static const int maxPosters = 2;

  /// Remembered posters in publish order (≤ [maxPosters]).
  final List<BaselinePoster> posters;

  /// Entity tag the host sent for these posters, or null. Sent back as
  /// `If-None-Match`; a `304` is only trusted when this is non-null.
  final String? validator;

  /// The settings token this baseline was established under. A baseline
  /// from a different token is NOT diffed against (quiet re-enable).
  final WatchSettingsToken token;

  /// The same posters re-tagged to [token] (after a validated `304` or a
  /// `404` under a new token), optionally replacing the validator.
  SiteBaseline retagged(WatchSettingsToken token, {String? validator}) =>
      SiteBaseline(posters: posters, token: token, validator: validator);

  /// The poster remembered under [imageRef], or null.
  BaselinePoster? posterAt(String imageRef) {
    for (final poster in posters) {
      if (poster.imageRef == imageRef) return poster;
    }
    return null;
  }

  /// Field-by-field equality (repo convention).
  bool sameAs(SiteBaseline other) {
    if (other.posters.length != posters.length) return false;
    for (var i = 0; i < posters.length; i++) {
      if (!posters[i].sameAs(other.posters[i])) return false;
    }
    return other.validator == validator && other.token.sameAs(token);
  }
}
