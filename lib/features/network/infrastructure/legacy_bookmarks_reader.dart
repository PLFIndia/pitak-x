/// Reader for the LEGACY bookmarks prefs key (network infrastructure;
/// libNetwork.md §6 "Legacy prefs value", ADR 0012).
///
/// The bookmarks feature is deleted, but its stored data must stay readable
/// until the one-time migration has run: this class owns the prefs key
/// `library_bookmarks` (the exact key `PrefsBookmarksRepository` used) and
/// re-implements the old `LibraryBookmark.fromJson` validation rules —
/// each item must be an object with a String `label` (trimmed, 1–80 chars)
/// and a String `url` passing [BookmarkUrl.normalize]. Anything else —
/// a corrupt JSON value, a non-array, a malformed item — is SKIPPED, never
/// thrown (§6: corrupt ⇒ skipped).
///
/// Not a secret: library URLs the user chose to save. SharedPreferences is
/// the right store for the legacy value (AGENTS §6.3 concerns secrets only).
library;

import 'dart:convert';

import 'package:pitaka/features/network/domain/usecases/migrate_legacy_bookmarks_use_case.dart';
import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';
import 'package:pitaka/features/network/domain/value_objects/network_name.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads and clears the legacy `library_bookmarks` prefs value.
final class LegacyBookmarksReader {
  /// Creates the reader over [_prefs].
  const LegacyBookmarksReader(this._prefs);

  /// The prefs key the deleted bookmarks feature wrote (wire-stable: this
  /// string is how existing installs' data is found).
  static const String prefsKey = 'library_bookmarks';

  final SharedPreferences _prefs;

  /// The validated legacy bookmarks, in stored order. Empty when the key is
  /// absent, blank, corrupt, or holds no valid item. Never throws.
  Future<List<LegacyBookmark>> read() async {
    final raw = _prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return const [];

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const []; // corrupt value → nothing migratable, never crash
    }
    if (decoded is! List) return const [];

    return [
      for (final item in decoded)
        if (_parseItem(item) case final bookmark?) bookmark,
    ];
  }

  /// Removes the prefs key; true when it is gone afterwards. (Removing an
  /// absent key is a successful no-op, which keeps the migration idempotent.)
  Future<bool> clear() => _prefs.remove(prefsKey);

  /// The old `LibraryBookmark.fromJson` rules, re-implemented here because
  /// the class died with its feature: String label + String url, label
  /// trimmed and 1–80 chars (the old `maxLabelLength` equals
  /// [NetworkName.maxLength]), url through the [BookmarkUrl] allow-list.
  static LegacyBookmark? _parseItem(Object? item) {
    if (item is! Map<String, dynamic>) return null;
    final label = item['label'];
    final url = item['url'];
    if (label is! String || url is! String) return null;
    final trimmed = label.trim();
    if (trimmed.isEmpty || trimmed.length > NetworkName.maxLength) return null;
    final normalized = BookmarkUrl.normalize(url);
    if (normalized == null) return null;
    return (label: trimmed, url: normalized);
  }
}
