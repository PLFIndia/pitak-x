/// `shared_preferences`-backed settings (infrastructure, AGENTS.md §3.3).
///
/// Stores non-secret preferences only. Keys mirror Kotlin `AppPreferences`
/// where practical so intent is obvious; values are stored as the enum name or
/// raw string. Reads fall back to defaults; nothing here is sensitive.
library;

import 'dart:math' show Random;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/storage/prefs_write.dart';
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
  // Location-sharing mode (docs/ARCHITECTURE.md §6 location sharing). Read with a first-read rule —
  // see [_readLocationSharing].
  static const _publishLocationSharingKey = 'publish_location_sharing';
  // OSM tiles consent for the network map (docs/ARCHITECTURE.md §1 network egress). Plain bool;
  // absent ⇒ false (no consent given yet — fail closed).
  static const _networkMapTilesConsentKey = 'network_map_tiles_consent';
  static const _libraryLogoKey = 'library_logo';
  static const _appLockBiometricKey = 'app_lock_biometric';

  @override
  Future<AppSettings> load() async {
    return AppSettings(
      themeMode: AppThemeModeX.fromToken(_prefs.getString(_themeKey)),
      libraryName: _prefs.getString(_libraryNameKey) ?? '',
      libraryId: _prefs.getString(_libraryIdKey) ?? '',
      maintainerName: _prefs.getString(_maintainerNameKey) ?? '',
      librarySort: LibrarySortX.fromToken(_prefs.getString(_librarySortKey)),
      loadRemoteCovers: _prefs.getBool(_loadRemoteCoversKey) ?? false,
      publishContactAddress: _readAddressWithMigration(),
      publishContactGps: _readGpsWithMigration(),
      publishContactEmail: _prefs.getString(_publishEmailKey) ?? '',
      publishContactPhone: _prefs.getString(_publishPhoneKey) ?? '',
      publishLocationSharing: _readLocationSharing(),
      networkMapTilesConsent:
          _prefs.getBool(_networkMapTilesConsentKey) ?? false,
      libraryLogo: _prefs.getString(_libraryLogoKey) ?? '',
      appLockBiometric: _prefs.getBool(_appLockBiometricKey) ?? false,
    );
  }

  /// One plugin write turned into a typed result (M17) AND a repaired cache.
  ///
  /// `SharedPreferences` setters report success as a `Future<bool>`; discarding
  /// it let the UI confirm preferences the device never stored. The shared
  /// helper additionally restores the previous cached value after a failure, so
  /// a failed save cannot look saved for the rest of the session (fix-plan L9).
  Future<Either<Failure, Unit>> _writeString(String key, String value) =>
      writePrefsString(_prefs, key, value, what: 'settings write: $key');

  Future<Either<Failure, Unit>> _writeBool(String key, bool value) =>
      writePrefsBool(_prefs, key, value, what: 'settings write: $key');

  @override
  Future<Either<Failure, Unit>> setThemeMode(AppThemeMode mode) =>
      _writeString(_themeKey, mode.token);

  @override
  Future<Either<Failure, Unit>> setLibraryName(String name) =>
      _writeString(_libraryNameKey, name.trim());

  @override
  Future<Either<Failure, String>> getOrCreateLibraryId() async {
    final existing = _prefs.getString(_libraryIdKey);
    if (existing != null && existing.isNotEmpty) return right(existing);
    final minted = _mintLibraryId();
    final saved = await _writeString(_libraryIdKey, minted);
    return saved.match(left, (_) => right(minted));
  }

  @override
  Future<Either<Failure, Unit>> setLibraryId(String id) =>
      _writeString(_libraryIdKey, id.trim());

  @override
  Future<Either<Failure, String>> regenerateLibraryId() async {
    final minted = _mintLibraryId();
    final saved = await _writeString(_libraryIdKey, minted);
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
  Future<Either<Failure, Unit>> setMaintainerName(String name) =>
      _writeString(_maintainerNameKey, name.trim());

  @override
  Future<Either<Failure, Unit>> setLibrarySort(LibrarySort sort) =>
      _writeString(_librarySortKey, sort.token);

  @override
  Future<Either<Failure, Unit>> setLoadRemoteCovers({required bool enabled}) =>
      _writeBool(_loadRemoteCoversKey, enabled);

  @override
  Future<Either<Failure, Unit>> setPublishContact({
    required String address,
    required String gps,
    required String email,
    required String phone,
  }) async {
    // One failed field write aborts the whole contact save (M17): the UI
    // must not report a saved contact that is only half on disk.
    final writes = <(String, String)>[
      (_publishAddressKey, address.trim()),
      (_publishGpsKey, gps.trim()),
      (_publishEmailKey, email.trim()),
      (_publishPhoneKey, phone.trim()),
    ];
    for (final (key, value) in writes) {
      final result = await _writeString(key, value);
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
  /// `GeoPoint.parse` (the network-domain value object the publish renderer
  /// uses); duplicated here so the settings layer stays free of a
  /// publish/network-feature import.
  static bool _looksLikeLatLng(String v) {
    final parts = v.split(',').map((s) => s.trim()).toList();
    if (parts.length != 2) return false;
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    if (lat == null || lng == null) return false;
    return lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0;
  }

  /// Location-sharing mode with the FIRST-READ RULE (docs/ARCHITECTURE.md §6 location sharing):
  /// when the key is ABSENT — the user never touched the switch, e.g. an
  /// install from before the setting existed — a device that already has a
  /// GPS value keeps publishing its pin, so the effective mode is `exact`
  /// (behaviour-preserving: the pin existed before the switch did). Absent
  /// key + blank GPS ⇒ `off` (new devices never publish coordinates by
  /// default). Once the user moves the segmented control the key EXISTS and
  /// this rule never fires again — including for a user who deliberately
  /// picks `off` with a GPS value sitting in the field.
  LocationSharing _readLocationSharing() {
    final stored = _prefs.getString(_publishLocationSharingKey);
    if (stored != null) return LocationSharingX.fromToken(stored);
    return _readGpsWithMigration().trim().isEmpty
        ? LocationSharing.off
        : LocationSharing.exact;
  }

  @override
  Future<Either<Failure, Unit>> setPublishLocationSharing(
    LocationSharing sharing,
  ) => _writeString(_publishLocationSharingKey, sharing.token);

  @override
  Future<Either<Failure, Unit>> setNetworkMapTilesConsent({
    required bool enabled,
  }) => _writeBool(_networkMapTilesConsentKey, enabled);

  @override
  Future<Either<Failure, Unit>> setLibraryLogo(String reference) =>
      _writeString(_libraryLogoKey, reference.trim());

  @override
  Future<Either<Failure, Unit>> setAppLockBiometric({required bool enabled}) =>
      _writeBool(_appLockBiometricKey, enabled);
}
