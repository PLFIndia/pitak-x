/// App settings controller (application layer, AGENTS.md §4).
///
/// A `keepAlive` `@riverpod` AsyncNotifier holding [AppSettings] for the whole
/// app (the root `MaterialApp` watches it for theme; the library watches it for
/// the maintainer stamp + sort; the app-lock gate reads `appLockBiometric`).
///
/// **Review finding M16 — how mutations stay consistent.** Every setter
/// used to copy the whole settings snapshot *before* awaiting its disk write,
/// then publish that whole copy *after*. Two setters in flight at once each
/// copied the same "before"; whichever write finished last silently reverted
/// the other one's field in memory (disk was fine — one prefs key per setter).
/// The dangerous case: a slow theme write publishing `appLockBiometric: false`
/// right after the lock was enabled, so the runtime gate (which reads this
/// state, not disk) stayed open. Two layers now prevent that:
///
///  1. **One at a time.** Every mutation runs through `_serialised`, a tiny
///     FIFO (the same `BasicLock` shape as `CoverFileCoordinator`). A second
///     call waits until the first has published its state.
///  2. **Patch, don't replace.** `_update` applies a `copyWith` patch to the
///     state *as it is after the write*, so a setter can only ever change the
///     field it owns — even if some future caller bypasses the queue.
///
/// **N07 — the library identity has one owner.** This controller implements
/// [LibraryNamespace] so the merge use case adopts an incoming library ID +
/// name THROUGH the FIFO above (one queued turn for both keys, one state
/// patch). Before, the use case wrote the repository directly and every
/// screen watching this state showed the old library name until restart.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/library_namespace.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_controller.g.dart';

/// Loads and mutates the app-wide [AppSettings].
@Riverpod(keepAlive: true)
class SettingsController extends _$SettingsController
    implements LibraryNamespace {
  /// Tail of the mutation FIFO; null when idle. Adapted from synchronized
  /// 3.4.0+1 `BasicLock` (Tekartik, MIT) via `CoverFileCoordinator` — no new
  /// dependency, no reentrancy (a mutator must never call another mutator).
  Future<void>? _tail;

  @override
  FutureOr<AppSettings> build() async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    return repo.load();
  }

  /// The settings to patch against: the live value, or defaults while the
  /// first load is still pending / after an error with nothing cached.
  AppSettings get _current => state.valueOrNull ?? AppSettings.defaults;

  /// Runs [action] after every previously queued mutation has finished.
  Future<T> _serialised<T>(Future<T> Function() action) async {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    try {
      if (previous != null) await previous;
      return await action();
    } finally {
      if (identical(_tail, released.future)) _tail = null;
      released.complete();
    }
  }

  /// Serialised write-then-publish for the `Either<Failure, Unit>` setters.
  ///
  /// Persists via [persist], then publishes `patch(currentState)` only when
  /// the write actually succeeded (M17: the plugin's success boolean is a
  /// typed `Either`, so a failed write can never be confirmed).
  ///
  /// A failed write KEEPS the last persisted value in [AsyncData] and returns
  /// the typed failure to the caller (fix-plan M8). It used to publish an
  /// [AsyncError]; because `Failure` is not an `Exception`, every
  /// `await settingsControllerProvider.future` then threw a non-`Exception`
  /// that the publish/events/move paths did not catch, freezing a spinner for
  /// the rest of the session — and the settings screens showed "Couldn't load
  /// settings" after one failed toggle. The UI now reports the save failure.
  Future<Either<Failure, Unit>> _update(
    Future<Either<Failure, Unit>> Function(SettingsRepository repo) persist,
    AppSettings Function(AppSettings current) patch,
  ) => _serialised(() async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    final Either<Failure, Unit> result;
    try {
      result = await persist(repo);
    } on Object catch (e) {
      // Name the type only: platform text may carry private detail.
      appLog('settings write threw: ${e.runtimeType}');
      return left(StorageFailure('settings write threw: ${e.runtimeType}'));
    }
    if (result.isRight()) {
      // Patch what is there NOW — not a snapshot taken before the await.
      state = AsyncData(patch(_current));
      return result;
    }
    // Fail closed: never show a preference the device did not store, and never
    // turn a loaded screen into an error for a failed SAVE.
    final current = state.valueOrNull;
    if (current != null) state = AsyncData(current);
    return result;
  });

  /// The last good settings, or a typed failure when none was ever loaded.
  ///
  /// This is the ONLY read publishing paths may use (fix-plan M8): it answers
  /// the cached value after any amount of write failures, and it never
  /// invents defaults for a corrupt read (handoff §13).
  Future<Either<Failure, AppSettings>> loaded() async {
    final cached = state.valueOrNull;
    if (cached != null) return right(cached);
    try {
      return right(await future);
    } on Object {
      return left(const StorageFailure('settings unavailable'));
    }
  }

  /// Serialised write-then-publish for the ID-minting methods, which return
  /// the minted value to the caller. A left is returned untouched and nothing
  /// is published (no phantom ID, M17).
  Future<Either<Failure, String>> _mintLibraryId(
    Future<Either<Failure, String>> Function(SettingsRepository repo) mint,
  ) => _serialised(() async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    final Either<Failure, String> minted;
    try {
      minted = await mint(repo);
    } on Object catch (e) {
      appLog('settings mint threw: ${e.runtimeType}');
      return left(StorageFailure('settings mint threw: ${e.runtimeType}'));
    }
    final id = minted.getOrElse((_) => '');
    if (minted.isRight() && _current.libraryId != id) {
      state = AsyncData(_current.copyWith(libraryId: id));
    }
    return minted;
  });

  /// Sets the appearance mode.
  Future<Either<Failure, Unit>> setThemeMode(AppThemeMode mode) => _update(
    (repo) => repo.setThemeMode(mode),
    (s) => s.copyWith(themeMode: mode),
  );

  /// Sets the library display name.
  Future<Either<Failure, Unit>> setLibraryName(String name) => _update(
    (repo) => repo.setLibraryName(name),
    (s) => s.copyWith(libraryName: name.trim()),
  );

  /// Returns this app's library ID, minting one on first call, and reflects it
  /// into state so the UI can show it (PLAN-merge.md D40). A failed mint or
  /// persist is a left (M17) — callers must not proceed with a phantom ID.
  Future<Either<Failure, String>> getOrCreateLibraryId() =>
      _mintLibraryId((repo) => repo.getOrCreateLibraryId());

  /// Adopts [id] as this app's library ID (from a Join/Overwrite merge or a
  /// scanned pairing QR). The caller must pass a value already validated by
  /// `LibraryId.normalizeOrNull`.
  Future<Either<Failure, Unit>> setLibraryId(String id) => _update(
    (repo) => repo.setLibraryId(id),
    (s) => s.copyWith(libraryId: id.trim()),
  );

  /// Mints a brand-new library ID (CSPRNG), detaching this device from the
  /// previous namespace, and reflects it into state. Left on persist failure
  /// (M17) — the old ID then stays in force.
  Future<Either<Failure, String>> regenerateLibraryId() =>
      _mintLibraryId((repo) => repo.regenerateLibraryId());

  /// The merge use case's read of this device's identity (N07): the ID via
  /// the FIFO like [getOrCreateLibraryId], the name from the loaded settings.
  @override
  Future<Either<Failure, LibraryIdentity>> current() async {
    final id = await getOrCreateLibraryId();
    final name = await _loadedLibraryName();
    return id.map((value) => LibraryIdentity(id: value, name: name));
  }

  /// The library name once the first load has finished. `future` rejects when
  /// an earlier setter published an [AsyncError] (a failed prefs write); the
  /// last good value is still cached on that state, so use it — the name only
  /// feeds the merge's "which library is this?" copy, never a gate.
  Future<String> _loadedLibraryName() async {
    final loadedSettings = await loaded();
    return loadedSettings.toNullable()?.libraryName ?? _current.libraryName;
  }

  /// Adopts an incoming library ID + name in ONE queued turn (N07), with
  /// rollback when the second write fails (review finding 4).
  ///
  /// Why rollback (beginner note): the settings store has no multi-key
  /// transaction, so "write the ID, then the name" can stop half-way. Before,
  /// that left the ID on disk while memory still showed the old one, and the
  /// restore screen said "unchanged". Now:
  ///  - ID write refused → nothing changed, [LibraryAdoptionOutcome
  ///    .notAdopted];
  ///  - blank incoming name → adopt the ID alone (the current name stays);
  ///  - name write refused (or threw) → put the previous ID back;
  ///  - that rollback also fails → publish the true partial state (new ID,
  ///    previous name) and report [LibraryAdoptionOutcome.partiallyAdopted],
  ///    so no screen can claim the old identity is still in force.
  @override
  Future<LibraryAdoption> adopt({required String id, required String name}) =>
      _serialised(() async {
        final repo = await ref.read(settingsRepositoryProvider.future);
        final trimmedId = id.trim();
        final trimmedName = name.trim();
        // Read BEFORE writing: this is what a rollback must restore.
        final previous = _current;

        final Either<Failure, Unit> idWritten;
        try {
          idWritten = await repo.setLibraryId(trimmedId);
        } on Object catch (e) {
          return _notAdopted(_writeThrew(e));
        }
        if (idWritten case Left(value: final failure)) {
          return _notAdopted(failure);
        }
        if (trimmedName.isEmpty) {
          _publishIdentity(id: trimmedId, name: previous.libraryName);
          return (outcome: LibraryAdoptionOutcome.adopted, failure: null);
        }

        final Either<Failure, Unit> nameWritten;
        try {
          nameWritten = await repo.setLibraryName(trimmedName);
        } on Object catch (e) {
          return _rollBackId(repo, previous, trimmedId, _writeThrew(e));
        }
        if (nameWritten case Left(value: final failure)) {
          return _rollBackId(repo, previous, trimmedId, failure);
        }
        _publishIdentity(id: trimmedId, name: trimmedName);
        return (outcome: LibraryAdoptionOutcome.adopted, failure: null);
      });

  static LibraryAdoption _notAdopted(Failure failure) =>
      (outcome: LibraryAdoptionOutcome.notAdopted, failure: failure);

  static Failure _writeThrew(Object error) =>
      StorageFailure('settings write threw: ${error.runtimeType}');

  /// Undoes the ID write after the name write failed.
  ///
  /// Successful rollback: disk is back on [previous] and memory never left it
  /// → `notAdopted` with the ORIGINAL failure (the one the caller can act on).
  /// Failed rollback: the ID is on disk and cannot be undone, so memory is
  /// published as the partial truth and the outcome says so.
  Future<LibraryAdoption> _rollBackId(
    SettingsRepository repo,
    AppSettings previous,
    String newId,
    Failure cause,
  ) async {
    Either<Failure, Unit> rolledBack;
    try {
      rolledBack = await repo.setLibraryId(previous.libraryId);
    } on Object catch (e) {
      rolledBack = left(_writeThrew(e));
    }
    if (rolledBack.isRight()) return _notAdopted(cause);
    _publishIdentity(id: newId, name: previous.libraryName);
    return (
      outcome: LibraryAdoptionOutcome.partiallyAdopted,
      failure: rolledBack.getLeft().toNullable() ?? cause,
    );
  }

  /// Publishes the identity fields only, patching whatever is there NOW (M16:
  /// never replace the whole snapshot).
  void _publishIdentity({required String id, required String name}) {
    state = AsyncData(_current.copyWith(libraryId: id, libraryName: name));
  }

  /// Sets the maintainer name (stamped onto newly-added books).
  Future<Either<Failure, Unit>> setMaintainerName(String name) => _update(
    (repo) => repo.setMaintainerName(name),
    (s) => s.copyWith(maintainerName: name.trim()),
  );

  /// Sets the persisted library sort.
  Future<Either<Failure, Unit>> setLibrarySort(LibrarySort sort) => _update(
    (repo) => repo.setLibrarySort(sort),
    (s) => s.copyWith(librarySort: sort),
  );

  /// Sets the remote-cover opt-in (#31, §2a.4). Default is off.
  Future<Either<Failure, Unit>> setLoadRemoteCovers({required bool enabled}) =>
      _update(
        (repo) => repo.setLoadRemoteCovers(enabled: enabled),
        (s) => s.copyWith(loadRemoteCovers: enabled),
      );

  /// Sets the optional public publish-contact fields (#32). [address] is free
  /// text; [gps] is a "lat, lng" pin. Both optional.
  Future<Either<Failure, Unit>> setPublishContact({
    required String address,
    required String gps,
    required String email,
    required String phone,
  }) => _update(
    (repo) => repo.setPublishContact(
      address: address,
      gps: gps,
      email: email,
      phone: phone,
    ),
    (s) => s.copyWith(
      publishContactAddress: address.trim(),
      publishContactGps: gps.trim(),
      publishContactEmail: email.trim(),
      publishContactPhone: phone.trim(),
    ),
  );

  /// Sets the location-sharing mode (docs/ARCHITECTURE.md §6 location sharing): what the published
  /// GPS pin and the network `library.json` location may reveal. Mirrored
  /// through [_update] like every other setter (M16: one serialised writer).
  Future<Either<Failure, Unit>> setPublishLocationSharing(
    LocationSharing sharing,
  ) => _update(
    (repo) => repo.setPublishLocationSharing(sharing),
    (s) => s.copyWith(publishLocationSharing: sharing),
  );

  /// Sets the OpenStreetMap tiles consent for the network map
  /// (docs/ARCHITECTURE.md §1 network egress). Mirrored through [_update]
  /// like every other setter (M16).
  Future<Either<Failure, Unit>> setNetworkMapTilesConsent({
    required bool enabled,
  }) => _update(
    (repo) => repo.setNetworkMapTilesConsent(enabled: enabled),
    (s) => s.copyWith(networkMapTilesConsent: enabled),
  );

  /// Sets (or clears, when blank) the user's library-logo reference.
  Future<Either<Failure, Unit>> setLibraryLogo(String reference) => _update(
    (repo) => repo.setLibraryLogo(reference),
    (s) => s.copyWith(libraryLogo: reference.trim()),
  );

  /// Enables/disables the opt-in app-wide biometric gate (default off).
  Future<Either<Failure, Unit>> setAppLockBiometric({required bool enabled}) =>
      _update(
        (repo) => repo.setAppLockBiometric(enabled: enabled),
        (s) => s.copyWith(appLockBiometric: enabled),
      );

  /// Turns automatic availability updates on or off (ADR 0019, plan P3;
  /// default on). The lane reacts to the new value: off publishes one
  /// removal of `availability.json`, on publishes the current set.
  Future<Either<Failure, Unit>> setAutoPublishAvailability({
    required bool enabled,
  }) => _update(
    (repo) => repo.setAutoPublishAvailability(enabled: enabled),
    (s) => s.copyWith(autoPublishAvailability: enabled),
  );

  /// Sets whether a successful ISBN scan immediately searches online.
  /// Default off: the user explicitly taps Lookup instead.
  Future<Either<Failure, Unit>> setLookupIsbnAfterScan({
    required bool enabled,
  }) => _update(
    (repo) => repo.setLookupIsbnAfterScan(enabled: enabled),
    (s) => s.copyWith(lookupIsbnAfterScan: enabled),
  );
}
