/// App settings controller (application layer, AGENTS.md §4).
///
/// A `keepAlive` `@riverpod` AsyncNotifier holding [AppSettings] for the whole
/// app (the root `MaterialApp` watches it for theme; the library watches it for
/// the maintainer stamp + sort). Each setter persists through the repository
/// then updates state so the UI reacts immediately.
library;

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_controller.g.dart';

/// Loads and mutates the app-wide [AppSettings].
@Riverpod(keepAlive: true)
class SettingsController extends _$SettingsController {
  @override
  FutureOr<AppSettings> build() async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    return repo.load();
  }

  Future<void> _update(
    Future<void> Function() persist,
    AppSettings next,
  ) async {
    await persist();
    state = AsyncData(next);
  }

  /// Sets the appearance mode.
  Future<void> setThemeMode(AppThemeMode mode) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    final current = state.valueOrNull ?? AppSettings.defaults;
    await _update(
      () => repo.setThemeMode(mode),
      current.copyWith(themeMode: mode),
    );
  }

  /// Sets the library display name.
  Future<void> setLibraryName(String name) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    final current = state.valueOrNull ?? AppSettings.defaults;
    await _update(
      () => repo.setLibraryName(name),
      current.copyWith(libraryName: name.trim()),
    );
  }

  /// Returns this app's library ID, minting one on first call, and reflects it
  /// into state so the UI can show it (PLAN-merge.md D40).
  Future<String> getOrCreateLibraryId() async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    final id = await repo.getOrCreateLibraryId();
    final current = state.valueOrNull ?? AppSettings.defaults;
    if (current.libraryId != id) {
      state = AsyncData(current.copyWith(libraryId: id));
    }
    return id;
  }

  /// Adopts [id] as this app's library ID (from a Join/Overwrite merge or a
  /// scanned pairing QR). The caller must pass a value already validated by
  /// `LibraryId.normalizeOrNull`.
  Future<void> setLibraryId(String id) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    final current = state.valueOrNull ?? AppSettings.defaults;
    await _update(
      () => repo.setLibraryId(id),
      current.copyWith(libraryId: id.trim()),
    );
  }

  /// Mints a brand-new library ID (CSPRNG), detaching this device from the
  /// previous namespace, and reflects it into state.
  Future<void> regenerateLibraryId() async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    final current = state.valueOrNull ?? AppSettings.defaults;
    final minted = await repo.regenerateLibraryId();
    state = AsyncData(current.copyWith(libraryId: minted));
  }

  /// Sets the maintainer name (stamped onto newly-added books).
  Future<void> setMaintainerName(String name) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    final current = state.valueOrNull ?? AppSettings.defaults;
    await _update(
      () => repo.setMaintainerName(name),
      current.copyWith(maintainerName: name.trim()),
    );
  }

  /// Sets the persisted library sort.
  Future<void> setLibrarySort(BookSort sort) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    final current = state.valueOrNull ?? AppSettings.defaults;
    await _update(
      () => repo.setLibrarySort(sort),
      current.copyWith(librarySort: sort),
    );
  }

  /// Sets the remote-cover opt-in (#31, §2a.4). Default is off.
  Future<void> setLoadRemoteCovers({required bool enabled}) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    final current = state.valueOrNull ?? AppSettings.defaults;
    await _update(
      () => repo.setLoadRemoteCovers(enabled: enabled),
      current.copyWith(loadRemoteCovers: enabled),
    );
  }

  /// Sets the optional public publish-contact fields (#32). [address] is free
  /// text; [gps] is a "lat, lng" pin. Both optional.
  Future<void> setPublishContact({
    required String address,
    required String gps,
    required String email,
    required String phone,
  }) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    final current = state.valueOrNull ?? AppSettings.defaults;
    await _update(
      () => repo.setPublishContact(
        address: address,
        gps: gps,
        email: email,
        phone: phone,
      ),
      current.copyWith(
        publishContactAddress: address.trim(),
        publishContactGps: gps.trim(),
        publishContactEmail: email.trim(),
        publishContactPhone: phone.trim(),
      ),
    );
  }

  /// Sets (or clears, when blank) the user's library-logo reference.
  Future<void> setLibraryLogo(String reference) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    final current = state.valueOrNull ?? AppSettings.defaults;
    await _update(
      () => repo.setLibraryLogo(reference),
      current.copyWith(libraryLogo: reference.trim()),
    );
  }

  /// Enables/disables the opt-in app-wide biometric gate (default off).
  Future<void> setAppLockBiometric({required bool enabled}) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    final current = state.valueOrNull ?? AppSettings.defaults;
    await _update(
      () => repo.setAppLockBiometric(enabled: enabled),
      current.copyWith(appLockBiometric: enabled),
    );
  }
}
