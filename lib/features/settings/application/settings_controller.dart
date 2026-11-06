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
      await _publishActual(repo);
      return left(StorageFailure('settings write threw: ${e.runtimeType}'));
    }
    if (result.isRight()) {
      // Patch what is there NOW — not a snapshot taken before the await.
      state = AsyncData(patch(_current));
      return result;
    }
    // A multi-key identity write can be partially applied even when it returns
    // a left. Reload the actual persisted state; ordinary failed writes simply
    // reload their last good value. Never turn a loaded screen into an error.
    await _publishActual(repo);
    return result;
  });

  /// Publishes what is really on disk after a failed multi-key operation.
  Future<void> _publishActual(SettingsRepository repo) async {
    try {
      state = AsyncData(await repo.load());
    } on Object {
      final current = state.valueOrNull;
      if (current != null) state = AsyncData(current);
    }
  }

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
    Future<Either<Failure, String>> Function(SettingsRepository repo) mint, {
    bool clearPublishedFingerprint = false,
  }) => _serialised(() async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    final Either<Failure, String> minted;
    try {
      minted = await mint(repo);
    } on Object catch (e) {
      appLog('settings mint threw: ${e.runtimeType}');
      await _publishActual(repo);
      return left(StorageFailure('settings mint threw: ${e.runtimeType}'));
    }
    final id = minted.getOrElse((_) => '');
    if (minted.isRight() &&
        (clearPublishedFingerprint || _current.libraryId != id)) {
      final current = _current;
      state = AsyncData(
        clearPublishedFingerprint
            ? current.copyWith(libraryId: id, publishedFingerprint: null)
            : current.copyWith(libraryId: id),
      );
    } else if (minted.isLeft()) {
      await _publishActual(repo);
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
    (s) => s.copyWith(libraryId: id.trim(), publishedFingerprint: null),
  );

  /// Saves or clears the recovered public fingerprint through the one writer.
  Future<Either<Failure, Unit>> setPublishedFingerprint(String? fingerprint) =>
      _update((repo) {
        final store = repo is PublishedFingerprintStore
            ? repo as PublishedFingerprintStore
            : null;
        if (store == null) {
          return Future.value(
            left(
              const StorageFailure('published fingerprint store unavailable'),
            ),
          );
        }
        return store.setPublishedFingerprint(fingerprint);
      }, (s) => s.copyWith(publishedFingerprint: fingerprint));

  /// Mints a brand-new library ID (CSPRNG), detaching this device from the
  /// previous namespace, and reflects it into state. Left on persist failure
  /// (M17) — the old ID then stays in force.
  Future<Either<Failure, String>> regenerateLibraryId() => _mintLibraryId(
    (repo) => repo.regenerateLibraryId(),
    clearPublishedFingerprint: true,
  );

  /// The merge use case's read of this device's identity (N07): the ID via
  /// the FIFO like [getOrCreateLibraryId], the name from the loaded settings.
  @override
  Future<Either<Failure, LibraryIdentity>> current() async {
    final id = await getOrCreateLibraryId();
    final settings = (await loaded()).toNullable() ?? _current;
    return id.map(
      (value) => LibraryIdentity(
        id: value,
        name: settings.libraryName,
        publishedFingerprint: settings.publishedFingerprint,
      ),
    );
  }

  /// Adopts identity fields in one queued turn. A backup's public fingerprint
  /// is written AFTER the ID (which clears the old override). Any later
  /// failure rolls back the ID, name and previous override as far as the
  /// preference store allows; a failed rollback publishes the partial truth.
  @override
  Future<LibraryAdoption> adopt({
    required String id,
    required String name,
    String? publishedFingerprint,
  }) => _serialised(() async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    final trimmedId = id.trim();
    final trimmedName = name.trim();
    final previous = _current;

    final Either<Failure, Unit> idWritten;
    try {
      idWritten = await repo.setLibraryId(trimmedId);
    } on Object catch (e) {
      await _publishActual(repo);
      return _notAdopted(_writeThrew(e));
    }
    if (idWritten case Left(value: final failure)) {
      await _publishActual(repo);
      return _notAdopted(failure);
    }

    final restoreName = trimmedName.isNotEmpty;
    if (restoreName) {
      final Either<Failure, Unit> nameWritten;
      try {
        nameWritten = await repo.setLibraryName(trimmedName);
      } on Object catch (e) {
        return _rollBackAdoption(
          repo,
          previous,
          restoreName: false,
          cause: _writeThrew(e),
        );
      }
      if (nameWritten case Left(value: final failure)) {
        return _rollBackAdoption(
          repo,
          previous,
          restoreName: false,
          cause: failure,
        );
      }
    }

    if (publishedFingerprint != null) {
      final written = await _writeFingerprint(repo, publishedFingerprint);
      if (written case Left(value: final failure)) {
        return _rollBackAdoption(
          repo,
          previous,
          restoreName: restoreName,
          cause: failure,
        );
      }
    }
    _publishIdentity(
      id: trimmedId,
      name: restoreName ? trimmedName : previous.libraryName,
      publishedFingerprint: publishedFingerprint,
    );
    return (outcome: LibraryAdoptionOutcome.adopted, failure: null);
  });

  static LibraryAdoption _notAdopted(Failure failure) =>
      (outcome: LibraryAdoptionOutcome.notAdopted, failure: failure);

  static Failure _writeThrew(Object error) =>
      StorageFailure('settings write threw: ${error.runtimeType}');

  Future<Either<Failure, Unit>> _writeFingerprint(
    SettingsRepository repo,
    String? fingerprint,
  ) async {
    final store = repo is PublishedFingerprintStore
        ? repo as PublishedFingerprintStore
        : null;
    if (store == null) {
      return left(
        const StorageFailure('published fingerprint store unavailable'),
      );
    }
    try {
      return await store.setPublishedFingerprint(fingerprint);
    } on Object catch (e) {
      return left(_writeThrew(e));
    }
  }

  Future<LibraryAdoption> _rollBackAdoption(
    SettingsRepository repo,
    AppSettings previous, {
    required bool restoreName,
    required Failure cause,
  }) async {
    var restored = true;
    try {
      restored &= (await repo.setLibraryId(previous.libraryId)).isRight();
    } on Object {
      restored = false;
    }
    if (restoreName) {
      try {
        restored &= (await repo.setLibraryName(previous.libraryName)).isRight();
      } on Object {
        restored = false;
      }
    }
    if (previous.publishedFingerprint != null) {
      restored &= (await _writeFingerprint(
        repo,
        previous.publishedFingerprint,
      )).isRight();
    }
    await _publishActual(repo);
    if (restored) return _notAdopted(cause);
    return (outcome: LibraryAdoptionOutcome.partiallyAdopted, failure: cause);
  }

  /// Publishes the identity fields only, patching whatever is there NOW (M16:
  /// never replace the whole snapshot).
  void _publishIdentity({
    required String id,
    required String name,
    required String? publishedFingerprint,
  }) {
    state = AsyncData(
      _current.copyWith(
        libraryId: id,
        libraryName: name,
        publishedFingerprint: publishedFingerprint,
      ),
    );
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
