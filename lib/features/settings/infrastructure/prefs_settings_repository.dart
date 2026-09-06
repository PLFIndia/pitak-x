/// `shared_preferences`-backed settings (infrastructure, AGENTS.md §3.3).
///
/// Stores non-secret preferences only. Keys mirror Kotlin `AppPreferences`
/// where practical so intent is obvious; values are stored as the enum name or
/// raw string. Reads fall back to defaults; nothing here is sensitive.
library;

import 'dart:math' show Random;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
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

  /// Runs one plugin write and turns its boolean/exception contract into a
  /// typed result (M17). `SharedPreferences` setters report success as a
  /// `Future<bool>`; discarding it let the UI confirm preferences the device
  /// never stored. A `false` OR a thrown plugin error is a [StorageFailure].
  Future<Either<Failure, Unit>> _write(
    Future<bool> Function() op,
    String what,
  ) async {
    try {
      final ok = await op();
      if (!ok) return left(StorageFailure('settings write failed: $what'));
      return right(unit);
    } on Exception catch (e) {
      return left(StorageFailure('settings write failed: $what ($e)'));
    }
  }

  @override
  Future<Either<Failure, Unit>> setThemeMode(AppThemeMode mode) =>
      _write(() => _prefs.setString(_themeKey, mode.token), 'theme');

  @override
  Future<Either<Failure, Unit>> setLibraryName(String name) =>
      _write(() => _prefs.setString(_libraryNameKey, name.trim()), 'name');

  @override
  Future<Either<Failure, String>> getOrCreateLibraryId() async {
    final existing = _prefs.getString(_libraryIdKey);
    if (existing != null && existing.isNotEmpty) return right(existing);
    final minted = _mintLibraryId();
    final saved = await _write(
      () => _prefs.setString(_libraryIdKey, minted),
      'library id',
    );
    return saved.match(left, (_) => right(minted));
  }

  @override
  Future<Either<Failure, Unit>> setLibraryId(String id) =>
      _write(() => _prefs.setString(_libraryIdKey, id.trim()), 'library id');

  @override
  Future<Either<Failure, String>> regenerateLibraryId() async {
    final minted = _mintLibraryId();
    final saved = await _write(
      () => _prefs.setString(_libraryIdKey, minted),
      'library id',
    );
    return saved.match(left, (_) => right(minted));
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
  Future<Either<Failure, Unit>> setMaintainerName(String name) => _write(
    () => _prefs.setString(_maintainerNameKey, name.trim()),
    'maintainer name',
  );

  @override
  Future<Either<Failure, Unit>> setLibrarySort(BookSort sort) =>
      _write(() => _prefs.setString(_librarySortKey, sort.token), 'sort');

  @override
  Future<Either<Failure, Unit>> setLoadRemoteCovers({required bool enabled}) =>
      _write(
        () => _prefs.setBool(_loadRemoteCoversKey, enabled),
        'remote covers',
      );

  @override
  Future<Either<Failure, Unit>> setPublishContact({
    required String address,
    required String gps,
    required String email,
    required String phone,
  }) async {
    // One failed field write aborts the whole contact save (M17): the UI
    // must not report a saved contact that is only half on disk.
    final writes = <(String, Future<bool> Function())>[
      (
        _publishAddressKey,
        () => _prefs.setString(_publishAddressKey, address.trim()),
      ),
      (_publishGpsKey, () => _prefs.setString(_publishGpsKey, gps.trim())),
      (
        _publishEmailKey,
        () => _prefs.setString(_publishEmailKey, email.trim()),
      ),
      (
        _publishPhoneKey,
        () => _prefs.setString(_publishPhoneKey, phone.trim()),
      ),
    ];
    for (final (key, op) in writes) {
      final result = await _write(op, 'publish contact ($key)');
      if (result.isLeft()) return result;
    }
    return right(unit);
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
  Future<Either<Failure, Unit>> setLibraryLogo(String reference) => _write(
    () => _prefs.setString(_libraryLogoKey, reference.trim()),
    'library logo',
  );

  @override
  Future<Either<Failure, Unit>> setAppLockBiometric({required bool enabled}) =>
      _write(() => _prefs.setBool(_appLockBiometricKey, enabled), 'app lock');
}
