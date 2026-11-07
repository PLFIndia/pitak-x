/// Ports of the background event check (PLAN.md §1, §4–§6). Pure Dart
/// interfaces; infrastructure implements them, tests fake them.
///
/// Why typed ports instead of calling plugins directly (beginner note):
/// the worker's correctness depends on *what* each call guarantees — "the
/// job is really registered", "the notification was really submitted". A
/// plugin method returning normally does not always mean that. Each port
/// below states the guarantee in its doc, the adapter is responsible for
/// honouring it, and tests can exercise every failure path with fakes.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_settings.dart';
import 'package:pitaka/features/network/domain/events_watch/events_watch_state.dart';
import 'package:pitaka/features/network/domain/events_watch/pending_change.dart';

/// What a store found when asked to read a document.
sealed class WatchDocumentRead<T> {
  const WatchDocumentRead();
}

/// The document is absent (never written).
final class WatchDocumentMissing<T> extends WatchDocumentRead<T> {
  /// Creates the missing result.
  const WatchDocumentMissing();
}

/// The document was read and validated.
final class WatchDocumentPresent<T> extends WatchDocumentRead<T> {
  /// Creates the present result.
  const WatchDocumentPresent(this.value);

  /// The validated document.
  final T value;
}

/// The document exists but is unreadable in this build's format (corrupt,
/// oversized, hostile). Recovery rules in PLAN.md §6 decide what happens.
final class WatchDocumentCorrupt<T> extends WatchDocumentRead<T> {
  /// Creates the corrupt result.
  const WatchDocumentCorrupt();
}

/// The document declares a schema NEWER than this build understands. It
/// must never be overwritten; the feature fails closed with an
/// update-required state.
final class WatchDocumentNewerSchema<T> extends WatchDocumentRead<T> {
  /// Creates the newer-schema result.
  const WatchDocumentNewerSchema();
}

/// Persistence of the foreground-owned settings document.
abstract interface class EventsWatchSettingsStore {
  /// Reads and strictly validates the document.
  Future<Either<Failure, WatchDocumentRead<EventsWatchSettings>>> read();

  /// Atomically replaces the document. Only the foreground controller may
  /// call this (PLAN.md §1 ownership).
  Future<Either<Failure, Unit>> write(EventsWatchSettings settings);
}

/// Persistence of the worker-owned state document.
abstract interface class EventsWatchStateStore {
  /// Reads and strictly validates the document, enforcing size caps.
  Future<Either<Failure, WatchDocumentRead<EventsWatchState>>> read();

  /// Atomically replaces the document. Only the worker's serialized reducer
  /// may call this (PLAN.md §1 ownership).
  Future<Either<Failure, Unit>> write(EventsWatchState state);
}

/// Whether notifications from this feature can currently reach the user.
enum NotificationDelivery {
  /// Both the app-level permission and the feature's channel are enabled.
  deliverable,

  /// The app-level permission is denied/revoked, or the channel is blocked.
  blocked,
}

/// Outcome of asking the OS for notification permission.
enum NotificationPermissionOutcome {
  /// Granted (or not required on this platform/version).
  granted,

  /// Denied by the user this time.
  denied,

  /// Denied permanently / blocked in system settings; prompting again is
  /// pointless — offer system settings instead.
  permanentlyDenied,
}

/// What to show for one library. The notifier owns the wording and the
/// fixed fallback line for a null caption; the domain never formats UI.
final class LibraryAlert {
  /// Creates one library's alert.
  LibraryAlert({
    required this.notificationId,
    required this.siteUrl,
    required this.publicName,
    required List<PendingChange> changes,
  }) : changes = List.unmodifiable(changes);

  /// Stable, persisted notification id for this library (never 0).
  final int notificationId;

  /// Canonical site URL — the ONLY payload the tap handler receives.
  final String siteUrl;

  /// Descriptor-confirmed public name, or null → generic title
  /// (PLAN.md decision 13).
  final String? publicName;

  /// Up to two changes to describe.
  final List<PendingChange> changes;
}

/// Submission of notifications. "Submitted" means Android's
/// `NotificationManager` accepted the call — NOT that the user saw it.
abstract interface class LocalNotifier {
  /// Current effective delivery state (app permission AND channel).
  Future<Either<Failure, NotificationDelivery>> delivery();

  /// Shows (or replaces, same id) one library's alert.
  Future<Either<Failure, Unit>> showLibrary(LibraryAlert alert);

  /// Shows (or replaces) the group summary. [libraryCount] is the number of
  /// libraries with alerts in this run.
  Future<Either<Failure, Unit>> showSummary({required int libraryCount});

  /// Cancels one library's alert by id. Idempotent.
  Future<Either<Failure, Unit>> cancelLibrary(int notificationId);

  /// Cancels every notification this feature ever posted (its own tag /
  /// channel only — never another feature's). Idempotent.
  Future<Either<Failure, Unit>> cancelAllFeatureAlerts();
}

/// Foreground-only permission prompt (not needed by the worker). On
/// platforms/versions without a runtime prompt it resolves to
/// [NotificationPermissionOutcome.granted] without a dialog.
typedef NotificationPermissionRequest =
    Future<Either<Failure, NotificationPermissionOutcome>> Function();

/// Registration state of the periodic job.
enum WatchJobRegistration {
  /// Registered (enqueued or running).
  registered,

  /// Not registered.
  notRegistered,
}

/// Scheduling of the periodic worker. Every method verifies the NATIVE
/// state after the call (PLAN.md §5: a returned method-channel call is not
/// proof of completion).
abstract interface class EventsWatchScheduler {
  /// Registers the fixed periodic job if absent, or updates it if its
  /// specification changed. Returns only after registration is observed.
  Future<Either<Failure, Unit>> ensureRegistered();

  /// Cancels the periodic job. Returns only after cancellation is observed.
  Future<Either<Failure, Unit>> cancel();

  /// Current registration state. A failure here means UNKNOWN, which
  /// callers must treat as not registered (fail closed, decision 14).
  Future<Either<Failure, WatchJobRegistration>> registration();
}

/// Injectable wall clock and monotonic clock.
abstract interface class WatchClock {
  /// Epoch millis.
  int nowEpochMillis();

  /// A stopwatch started now, for deadlines that must not jump with the
  /// wall clock.
  Stopwatch startStopwatch();
}
