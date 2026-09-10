/// App settings controller (application layer, AGENTS.md §4).
///
/// A `keepAlive` `@riverpod` AsyncNotifier holding [AppSettings] for the whole
/// app (the root `MaterialApp` watches it for theme; the library watches it for
/// the maintainer stamp + sort; the app-lock gate reads `appLockBiometric`).
///
/// **M16 (astra-review.md) — how mutations stay consistent.** Every setter
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
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_controller.g.dart';

/// Loads and mutates the app-wide [AppSettings].
@Riverpod(keepAlive: true)
class SettingsController extends _$SettingsController {
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
  /// typed `Either`, so a failed write can never be confirmed). A prefs write
  /// failure — typed [Failure] or unexpected throw — is folded into an
  /// [AsyncError] state instead of escaping as an unhandled async error from
  /// an un-awaited setter; every consumer renders that with a safe fallback.
  /// The in-memory value is left unchanged — fail closed rather than show a
  /// preference the device never actually stored (Riverpod keeps the previous
  /// value reachable via `valueOrNull` on the error state).
  Future<void> _update(
    Future<Either<Failure, Unit>> Function(SettingsRepository repo) persist,
    AppSettings Function(AppSettings current) patch,
  ) => _serialised(() async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    final Either<Failure, Unit> result;
    try {
      result = await persist(repo);
    } on Object catch (e, st) {
      state = AsyncError(e, st);
      return;
    }
    state = result.match(
      (failure) => AsyncError(failure, StackTrace.current),
      // Patch what is there NOW — not a snapshot taken before the await.
      (_) => AsyncData(patch(_current)),
    );
  });

  /// Serialised write-then-publish for the ID-minting methods, which return
  /// the minted value to the caller. A left is returned untouched and nothing
  /// is published (no phantom ID, M17).
  Future<Either<Failure, String>> _mintLibraryId(
    Future<Either<Failure, String>> Function(SettingsRepository repo) mint,
  ) => _serialised(() async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    final minted = await mint(repo);
    final id = minted.getOrElse((_) => '');
    if (minted.isRight() && _current.libraryId != id) {
      state = AsyncData(_current.copyWith(libraryId: id));
    }
    return minted;
  });

  /// Sets the appearance mode.
  Future<void> setThemeMode(AppThemeMode mode) => _update(
    (repo) => repo.setThemeMode(mode),
    (s) => s.copyWith(themeMode: mode),
  );

  /// Sets the library display name.
  Future<void> setLibraryName(String name) => _update(
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
  Future<void> setLibraryId(String id) => _update(
    (repo) => repo.setLibraryId(id),
    (s) => s.copyWith(libraryId: id.trim()),
  );

  /// Mints a brand-new library ID (CSPRNG), detaching this device from the
  /// previous namespace, and reflects it into state. Left on persist failure
  /// (M17) — the old ID then stays in force.
  Future<Either<Failure, String>> regenerateLibraryId() =>
      _mintLibraryId((repo) => repo.regenerateLibraryId());

  /// Sets the maintainer name (stamped onto newly-added books).
  Future<void> setMaintainerName(String name) => _update(
    (repo) => repo.setMaintainerName(name),
    (s) => s.copyWith(maintainerName: name.trim()),
  );

  /// Sets the persisted library sort.
  Future<void> setLibrarySort(BookSort sort) => _update(
    (repo) => repo.setLibrarySort(sort),
    (s) => s.copyWith(librarySort: sort),
  );

  /// Sets the remote-cover opt-in (#31, §2a.4). Default is off.
  Future<void> setLoadRemoteCovers({required bool enabled}) => _update(
    (repo) => repo.setLoadRemoteCovers(enabled: enabled),
    (s) => s.copyWith(loadRemoteCovers: enabled),
  );

  /// Sets the optional public publish-contact fields (#32). [address] is free
  /// text; [gps] is a "lat, lng" pin. Both optional.
  Future<void> setPublishContact({
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

  /// Sets (or clears, when blank) the user's library-logo reference.
  Future<void> setLibraryLogo(String reference) => _update(
    (repo) => repo.setLibraryLogo(reference),
    (s) => s.copyWith(libraryLogo: reference.trim()),
  );

  /// Enables/disables the opt-in app-wide biometric gate (default off).
  Future<void> setAppLockBiometric({required bool enabled}) => _update(
    (repo) => repo.setAppLockBiometric(enabled: enabled),
    (s) => s.copyWith(appLockBiometric: enabled),
  );
}
