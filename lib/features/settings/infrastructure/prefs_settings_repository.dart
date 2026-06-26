/// `shared_preferences`-backed settings (infrastructure, AGENTS.md §3.3).
///
/// Stores non-secret preferences only. Keys mirror Kotlin `AppPreferences`
/// where practical so intent is obvious; values are stored as the enum name or
/// raw string. Reads fall back to defaults; nothing here is sensitive.
library;

import 'dart:math' show Random;

import 'package:flutter/material.dart' show ThemeMode;
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
  static const _publishLocationKey = 'publish_contact_location';
  static const _publishEmailKey = 'publish_contact_email';
  static const _publishPhoneKey = 'publish_contact_phone';
  static const _libraryLogoKey = 'library_logo';
  static const _appLockBiometricKey = 'app_lock_biometric';

  @override
  Future<AppSettings> load() async {
    return AppSettings(
      themeMode: _themeFromToken(_prefs.getString(_themeKey)),
      libraryName: _prefs.getString(_libraryNameKey) ?? '',
      libraryId: _prefs.getString(_libraryIdKey) ?? '',
      maintainerName: _prefs.getString(_maintainerNameKey) ?? '',
      librarySort: BookSortX.fromToken(_prefs.getString(_librarySortKey)),
      loadRemoteCovers: _prefs.getBool(_loadRemoteCoversKey) ?? false,
      publishContactLocation: _prefs.getString(_publishLocationKey) ?? '',
      publishContactEmail: _prefs.getString(_publishEmailKey) ?? '',
      publishContactPhone: _prefs.getString(_publishPhoneKey) ?? '',
      libraryLogo: _prefs.getString(_libraryLogoKey) ?? '',
      appLockBiometric: _prefs.getBool(_appLockBiometricKey) ?? false,
    );
  }

  @override
  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setString(_themeKey, mode.name);

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
    required String location,
    required String email,
    required String phone,
  }) async {
    await _prefs.setString(_publishLocationKey, location.trim());
    await _prefs.setString(_publishEmailKey, email.trim());
    await _prefs.setString(_publishPhoneKey, phone.trim());
  }

  @override
  Future<void> setLibraryLogo(String reference) =>
      _prefs.setString(_libraryLogoKey, reference.trim());

  @override
  Future<void> setAppLockBiometric({required bool enabled}) =>
      _prefs.setBool(_appLockBiometricKey, enabled);

  /// Maps a stored token to a [ThemeMode]; unknown/blank → system.
  static ThemeMode _themeFromToken(String? raw) {
    for (final m in ThemeMode.values) {
      if (m.name == raw) return m;
    }
    return ThemeMode.system;
  }
}
