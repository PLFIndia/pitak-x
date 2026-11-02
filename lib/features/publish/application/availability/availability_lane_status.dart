/// What the availability lane is doing, for the status row (application
/// layer; ADR 0019 Decision 8, plan C.4 status table).
///
/// Immutable values only: the lane computes one, the UI renders it. The
/// sentences inside are fixed and safe (AGENTS.md §5): never response text,
/// URLs or exception messages. Times are epoch milliseconds; the widget
/// formats them for the user's locale.
library;

/// The lane's current status.
///
/// Sealed (beginner note): the status row must handle every case, so a new
/// status cannot silently render as nothing.
sealed class AvailabilityLaneStatus {
  const AvailabilityLaneStatus();
}

/// The lane has not looked at the saved state and the inputs yet.
final class AvailabilityLaneStarting extends AvailabilityLaneStatus {
  /// Creates the status.
  const AvailabilityLaneStarting();
}

/// The switch in Settings is off (and any removal is already on the site).
final class AvailabilityLaneOff extends AvailabilityLaneStatus {
  /// Creates the status.
  const AvailabilityLaneOff();
}

/// The lane cannot publish yet, and retrying on a timer would not help:
/// connect a host, publish the catalogue once, or unlock the vault once.
/// The next change, app resume, a catalogue publish or the button retries.
final class AvailabilityLaneNotReady extends AvailabilityLaneStatus {
  /// Creates the status with a fixed, safe [reason].
  const AvailabilityLaneNotReady(this.reason);

  /// Why, as a fixed sentence.
  final String reason;
}

/// A publish is due at [at].
final class AvailabilityLaneScheduled extends AvailabilityLaneStatus {
  /// Creates the status.
  const AvailabilityLaneScheduled(this.at, {this.gitHubMayDelay = false});

  /// When the publish starts (epoch milliseconds).
  final int at;

  /// True after **Update availability now** when GitHub's hourly budget is
  /// already used up (ADR 0019 Decision 8): "GitHub may delay this update".
  final bool gitHubMayDelay;
}

/// A publish is running now.
final class AvailabilityLanePublishing extends AvailabilityLaneStatus {
  /// Creates the status.
  const AvailabilityLanePublishing();
}

/// The host accepted the set changed at [asOf]; it is not yet proven live
/// (GitHub Pages is still building, or a Cloudflare read-back ran out).
final class AvailabilityLaneGoingLive extends AvailabilityLaneStatus {
  /// Creates the status.
  const AvailabilityLaneGoingLive(this.asOf);

  /// The published set's `asOf` (epoch milliseconds, whole minutes).
  final int asOf;
}

/// The site shows the set changed at [asOf].
final class AvailabilityLaneUpToDate extends AvailabilityLaneStatus {
  /// Creates the status.
  const AvailabilityLaneUpToDate(this.asOf);

  /// The published set's `asOf` (epoch milliseconds, whole minutes).
  final int asOf;
}

/// A publish failed and the set is kept; the lane retries at [retryAt]
/// (AV11: bounded backoff, never a loop, never a replacement).
final class AvailabilityLanePending extends AvailabilityLaneStatus {
  /// Creates the status with a fixed, safe [reason].
  const AvailabilityLanePending(this.reason, {this.retryAt});

  /// Why, as a fixed sentence.
  final String reason;

  /// When the next automatic try starts, or null when none is scheduled.
  final int? retryAt;
}

/// Everything the status row shows: the status and whether the one-time
/// notice is due (plan C.8: "Availability now updates by itself after
/// lending. You can turn this off in Settings.").
final class AvailabilityLaneView {
  /// Creates the view.
  const AvailabilityLaneView({required this.status, this.noticeDue = false});

  /// The view before the lane has started.
  static const AvailabilityLaneView starting = AvailabilityLaneView(
    status: AvailabilityLaneStarting(),
  );

  /// The lane's status.
  final AvailabilityLaneStatus status;

  /// True when the one-time notice should be shown.
  final bool noticeDue;
}

/// Fixed status sentences only the lane produces (plan C.4 drafts; plan S8
/// sets the final words).
abstract final class AvailabilityLaneMessages {
  /// Loan counts were never known in this run and nothing is saved.
  static const String unlockVault =
      'Unlock the vault once so Pitak can read loans.';
}
