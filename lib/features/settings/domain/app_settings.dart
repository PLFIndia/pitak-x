/// App-wide non-secret settings (domain, pure Dart, AGENTS.md §3.1).
///
/// Mirrors the subset of Kotlin `AppPreferences` this build uses: appearance
/// (theme), library identity (name + maintainer), and the persisted library
/// sort. Logo image, publish contacts, and localization flags are deferred to
/// their own features. Secrets are NEVER stored here.
library;

import 'package:flutter/material.dart' show ThemeMode;

/// Library list sort order (Kotlin `BookSort`). Stored as the enum name.
enum BookSort {
  /// Newest-added first (default).
  recentlyAdded,

  /// By language A→Z.
  languageAsc,

  /// By reader age band.
  ageGroupAsc,
}

/// Tolerant parsing for [BookSort].
extension BookSortX on BookSort {
  /// Stable storage token (the enum name).
  String get token => name;

  /// Parses a stored token; unknown/blank → [BookSort.recentlyAdded].
  static BookSort fromToken(String? raw) {
    for (final v in BookSort.values) {
      if (v.name == raw) return v;
    }
    return BookSort.recentlyAdded;
  }
}

/// Immutable snapshot of user settings.
class AppSettings {
  /// Creates a settings snapshot.
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.libraryName = '',
    this.libraryId = '',
    this.maintainerName = '',
    this.librarySort = BookSort.recentlyAdded,
    this.loadRemoteCovers = false,
    this.publishContactAddress = '',
    this.publishContactGps = '',
    this.publishContactEmail = '',
    this.publishContactPhone = '',
    this.libraryLogo = '',
    this.appLockBiometric = false,
  });

  /// Sensible first-run defaults.
  static const AppSettings defaults = AppSettings();

  /// Light / dark / follow-system appearance.
  final ThemeMode themeMode;

  /// Display name for the library (blank → app default title).
  final String libraryName;

  /// Opaque random namespace token (16–64 lowercase hex) identifying WHICH
  /// library this app maintains (PLAN-merge.md D40). Minted lazily on first
  /// merge/export via `SettingsRepository.getOrCreateLibraryId`. Baked into the
  /// JSON export so a recipient's merge gate can decide match-vs-decision.
  /// Blank means "not yet minted". Not PII.
  final String libraryId;

  /// Maintainer/cataloguer name; stamped onto newly-added books (`addedBy`).
  final String maintainerName;

  /// Persisted library list sort.
  final BookSort librarySort;

  /// Opt-in to fetching `https://` book covers over the network (#31).
  /// Default false: remote covers show a placeholder and nothing leaves the
  /// device until the user explicitly enables this in Settings (§2a.4).
  final bool loadRemoteCovers;

  /// Optional public library address shown on the published page (#32): free
  /// text (e.g. "14 Banyan Road, Bengaluru"). PII the user DELIBERATELY chose
  /// to publish. Rendered as a Maps *search* link.
  final String publishContactAddress;

  /// Optional public GPS pin on the published page (#32): "lat, lng". Rendered
  /// as a precise Google Maps pin. Separate from [publishContactAddress] so a
  /// library can show a human address, an exact pin, or both.
  final String publishContactGps;

  /// Optional public contact email shown on the published page (#32).
  final String publishContactEmail;

  /// Optional public contact phone shown on the published page (#32).
  final String publishContactPhone;

  /// Reference to the user's custom library logo image, or blank when unset.
  ///
  /// Stored in the same shape as a book cover (`covers/<uuid>.jpg`) so it reuses
  /// the existing on-device cover store + resolution path. Blank → the default
  /// Pitak icon is shown in the splash, drawer header, and app-bar button.
  final String libraryLogo;

  /// Opt-in app-wide biometric gate (default OFF). When true the app requires a
  /// biometric (or device PIN/pattern fallback) before showing the library, and
  /// re-prompts on every resume from background. This is a UI gate only — it
  /// does NOT encrypt data at rest (the encrypted vault remains the secure
  /// store); it deters casual snooping on an unlocked device.
  final bool appLockBiometric;

  /// Returns a copy with the given fields replaced.
  AppSettings copyWith({
    ThemeMode? themeMode,
    String? libraryName,
    String? libraryId,
    String? maintainerName,
    BookSort? librarySort,
    bool? loadRemoteCovers,
    String? publishContactAddress,
    String? publishContactGps,
    String? publishContactEmail,
    String? publishContactPhone,
    String? libraryLogo,
    bool? appLockBiometric,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      libraryName: libraryName ?? this.libraryName,
      libraryId: libraryId ?? this.libraryId,
      maintainerName: maintainerName ?? this.maintainerName,
      librarySort: librarySort ?? this.librarySort,
      loadRemoteCovers: loadRemoteCovers ?? this.loadRemoteCovers,
      publishContactAddress:
          publishContactAddress ?? this.publishContactAddress,
      publishContactGps: publishContactGps ?? this.publishContactGps,
      publishContactEmail: publishContactEmail ?? this.publishContactEmail,
      publishContactPhone: publishContactPhone ?? this.publishContactPhone,
      libraryLogo: libraryLogo ?? this.libraryLogo,
      appLockBiometric: appLockBiometric ?? this.appLockBiometric,
    );
  }
}
