/// `shared_preferences`-backed settings (infrastructure, AGENTS.md §3.3).
///
/// Stores non-secret preferences only. Keys mirror Kotlin `AppPreferences`
/// where practical so intent is obvious; values are stored as the enum name or
/// raw string. Reads fall back to defaults; nothing here is sensitive.
library;

import 'dart:math' show Random;

import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists [AppSettings] via [SharedPreferences].
class PrefsSettingsRepository implements SettingsRepository {
  /// Creates the repository over [_prefs].
  const PrefsSettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _themeKey = 'theme_mode';
  static const _libraryNameKey = 'library_name';
  static const _libraryIdKey = 'library_id';
  static const _maintainerNameKey = 'maintainer_name';
  static const _librarySortKey = 'library_sort';
  static const _loadRemoteCoversKey = 'load_remote_covers';
  // Split fields (#32): address (free text) + gps ("lat, lng").
  static const _publishAddressKey = 'publish_contact_address';
  static const _publishGpsKey = 'publish_contact_gps';
  // Legacy single "location" key (pre-split). Read once for migration only.
  static const _legacyPublishLocationKey = 'publish_contact_location';
  static const _publishEmailKey = 'publish_contact_email';
  static const _publishPhoneKey = 'publish_contact_phone';
  static const _libraryLogoKey = 'library_logo';
  static const _appLockBiometricKey = 'app_lock_biometric';

  @override
  Future<AppSettings> load() async {
    return AppSettings(
      themeMode: AppThemeModeX.fromToken(_prefs.getString(_themeKey)),
      libraryName: _prefs.getString(_libraryNameKey) ?? '',
      libraryId: _prefs.getString(_libraryIdKey) ?? '',
      maintainerName: _prefs.getString(_maintainerNameKey) ?? '',
      librarySort: BookSortX.fromToken(_prefs.getString(_librarySortKey)),
      loadRemoteCovers: _prefs.getBool(_loadRemoteCoversKey) ?? false,
      publishContactAddress: _readAddressWithMigration(),
      publishContactGps: _readGpsWithMigration(),
      publishContactEmail: _prefs.getString(_publishEmailKey) ?? '',
      publishContactPhone: _prefs.getString(_publishPhoneKey) ?? '',
      libraryLogo: _prefs.getString(_libraryLogoKey) ?? '',
      appLockBiometric: _prefs.getBool(_appLockBiometricKey) ?? false,
    );
  }

  @override
  Future<void> setThemeMode(AppThemeMode mode) =>
      _prefs.setString(_themeKey, mode.token);

  @override
  Future<void> setLibraryName(String name) =>
      _prefs.setString(_libraryNameKey, name.trim());

  @override
  Future<String> getOrCreateLibraryId() async {
    final existing = _prefs.getString(_libraryIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final minted = _mintLibraryId();
    await _prefs.setString(_libraryIdKey, minted);
    return minted;
  }

  @override
  Future<void> setLibraryId(String id) =>
      _prefs.setString(_libraryIdKey, id.trim());

  @override
  Future<String> regenerateLibraryId() async {
    final minted = _mintLibraryId();
    await _prefs.setString(_libraryIdKey, minted);
    return minted;
  }

  /// Mints a 32-char lowercase-hex ID from 16 CSPRNG bytes (§6.4: never the
  /// non-secure `Random()`). Matches the Kotlin shape accepted by `LibraryId`.
  static String _mintLibraryId() {
    final rng = Random.secure();
    final buf = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buf.write(rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  @override
  Future<void> setMaintainerName(String name) =>
      _prefs.setString(_maintainerNameKey, name.trim());

  @override
  Future<void> setLibrarySort(BookSort sort) =>
      _prefs.setString(_librarySortKey, sort.token);

  @override
  Future<void> setLoadRemoteCovers({required bool enabled}) =>
      _prefs.setBool(_loadRemoteCoversKey, enabled);

  @override
  Future<void> setPublishContact({
    required String address,
    required String gps,
    required String email,
    required String phone,
  }) async {
    await _prefs.setString(_publishAddressKey, address.trim());
    await _prefs.setString(_publishGpsKey, gps.trim());
    await _prefs.setString(_publishEmailKey, email.trim());
    await _prefs.setString(_publishPhoneKey, phone.trim());
  }

  /// Address value, migrating a legacy single "location" that is NOT a
  /// coordinate pair into the new address field (one-time, read-only). The new
  /// key wins once the user saves; we never write during a read.
  String _readAddressWithMigration() {
    final current = _prefs.getString(_publishAddressKey);
    if (current != null) return current;
    final legacy = (_prefs.getString(_legacyPublishLocationKey) ?? '').trim();
    if (legacy.isEmpty) return '';
    // A coordinate pair migrates to GPS instead; free text → address.
    return _looksLikeLatLng(legacy) ? '' : legacy;
  }

  /// GPS value, migrating a legacy single "location" that IS a coordinate pair
  /// into the new gps field (one-time, read-only).
  String _readGpsWithMigration() {
    final current = _prefs.getString(_publishGpsKey);
    if (current != null) return current;
    final legacy = (_prefs.getString(_legacyPublishLocationKey) ?? '').trim();
    if (legacy.isEmpty) return '';
    return _looksLikeLatLng(legacy) ? legacy : '';
  }

  /// True when [v] is "lat, lng" with both in valid range. Kept in sync with
  /// `PublishContactLinks._parseLatLng` (the publish-side renderer); duplicated
  /// here so the settings layer stays free of a publish-feature import.
  static bool _looksLikeLatLng(String v) {
    final parts = v.split(',').map((s) => s.trim()).toList();
    if (parts.length != 2) return false;
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    if (lat == null || lng == null) return false;
    return lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0;
  }

  @override
  Future<void> setLibraryLogo(String reference) =>
      _prefs.setString(_libraryLogoKey, reference.trim());

  @override
  Future<void> setAppLockBiometric({required bool enabled}) =>
      _prefs.setBool(_appLockBiometricKey, enabled);
}
