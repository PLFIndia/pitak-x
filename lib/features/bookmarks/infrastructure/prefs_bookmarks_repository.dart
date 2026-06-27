/// `shared_preferences`-backed bookmarks store (infrastructure, §3.3).
///
/// Persists the bookmark list as a single JSON-array string under one key.
/// Non-secret public data (library URLs the user chose to save) — never a
/// secret, so prefs is appropriate. A corrupt/loadable value degrades to an
/// empty list rather than crashing.
library;

import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/bookmarks/domain/bookmarks_repository.dart';
import 'package:pitaka/features/bookmarks/domain/library_bookmark.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists bookmarks via [SharedPreferences].
final class PrefsBookmarksRepository implements BookmarksRepository {
  /// Creates the repository over [_prefs].
  const PrefsBookmarksRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'library_bookmarks';

  @override
  Future<List<LibraryBookmark>> load() async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (LibraryBookmark.fromJson(item) case final b?) b,
      ];
    } on FormatException {
      return const []; // corrupt value → treat as empty, never crash
    }
  }

  @override
  Future<Either<Failure, List<LibraryBookmark>>> add(
    LibraryBookmark bookmark,
  ) async {
    final current = await load();
    final next = [...current, bookmark];
    return _persist(next);
  }

  @override
  Future<Either<Failure, List<LibraryBookmark>>> removeAt(int index) async {
    final current = await load();
    if (index < 0 || index >= current.length) return right(current);
    final next = [...current]..removeAt(index);
    return _persist(next);
  }

  Future<Either<Failure, List<LibraryBookmark>>> _persist(
    List<LibraryBookmark> list,
  ) async {
    try {
      final encoded = jsonEncode([for (final b in list) b.toJson()]);
      final ok = await _prefs.setString(_key, encoded);
      if (!ok) return left(const StorageFailure('bookmark save failed'));
      return right(list);
    } on Exception catch (e) {
      return left(StorageFailure('bookmark save failed: $e'));
    }
  }
}
