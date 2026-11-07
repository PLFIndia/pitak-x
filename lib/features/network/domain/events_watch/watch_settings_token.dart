/// Identity of ONE enabled period of the background event check
/// (PLAN.md §1).
///
/// Why two parts (beginner note): the worker stores baselines and pending
/// alerts on disk, and the foreground can turn the feature off, on, or reset
/// it at any time. Every stored item carries the token it was made under, so
/// the worker can tell "this belongs to the current ON period" from "this is
/// left over from before the user turned it off".
///
///  - **epoch** goes up by one on every explicit enable/disable. Old pending
///    work with an older epoch is discarded (decision 6: quiet re-enable).
///  - **incarnation** is a fresh random UUID on first creation and on every
///    explicit *reset*. Without it, a reset back to epoch 0 and a later
///    enable to epoch 2 could collide with leftovers from a previous life
///    that also reached epoch 2. A new incarnation can never match an old
///    one, no matter the epoch.
///
/// Compare with `sameAs` — always the whole token, never the integer alone.
library;

/// Immutable `(incarnation, epoch)` pair.
final class WatchSettingsToken {
  /// Creates a token. Use [WatchSettingsToken.validate] for stored input.
  const WatchSettingsToken({required this.incarnation, required this.epoch});

  /// Random identifier of this settings lineage (a UUID v4 string).
  final String incarnation;

  /// Enable/disable counter within [incarnation]; never reused.
  final int epoch;

  /// Length bound for a stored incarnation: a UUID is 36 characters; the
  /// bound leaves no room for anything that is not one.
  static const int maxIncarnationLength = 64;

  /// Only lowercase hex and dashes — what the UUID library emits.
  static final RegExp _incarnationPattern = RegExp(r'^[0-9a-f-]{1,64}$');

  /// Strict ingress gate for decoded documents. Null means "not a token".
  static WatchSettingsToken? validate({
    required Object? incarnation,
    required Object? epoch,
  }) {
    if (incarnation is! String || !_incarnationPattern.hasMatch(incarnation)) {
      return null;
    }
    if (epoch is! int || epoch < 0) return null;
    return WatchSettingsToken(incarnation: incarnation, epoch: epoch);
  }

  /// The token after one explicit enable/disable in the same lineage.
  WatchSettingsToken nextEpoch() =>
      WatchSettingsToken(incarnation: incarnation, epoch: epoch + 1);

  /// Whole-token equality (repo convention: no `==` override in domain).
  bool sameAs(WatchSettingsToken other) =>
      other.incarnation == incarnation && other.epoch == epoch;

  /// True when both tokens belong to the same lineage (reset not involved).
  bool sameIncarnation(WatchSettingsToken other) =>
      other.incarnation == incarnation;

  @override
  String toString() => 'WatchSettingsToken(epoch $epoch)';
}
