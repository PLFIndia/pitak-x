/// `shared_preferences`-backed [ShareCardStyleStore] (infrastructure, §3.3).
///
/// One non-secret key: the enum token of the last share-card style the user
/// chose. Same shape as `PrefsBookmarksRepository` — a tiny preference that
/// does not belong on `AppSettings` (which every settings fake would then
/// have to mirror).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/share_card_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the chosen [ShareCardStyle] in [SharedPreferences].
final class PrefsShareCardStyleStore implements ShareCardStyleStore {
  /// Creates the store over [_prefs].
  const PrefsShareCardStyleStore(this._prefs);

  final SharedPreferences _prefs;

  /// Storage key. Public so tests can seed `setMockInitialValues`.
  static const String key = 'share_card_style';

  @override
  Future<ShareCardStyle> load() async =>
      ShareCardStyleX.fromToken(_prefs.getString(key));

  @override
  Future<Either<Failure, Unit>> save(ShareCardStyle style) async {
    // `SharedPreferences.setString` reports success as a bool; a `false` is
    // a real failure the UI must not paper over (M17).
    try {
      final ok = await _prefs.setString(key, style.token);
      if (!ok) return left(const StorageFailure('share card style write'));
      return right(unit);
    } on Exception catch (e) {
      return left(StorageFailure('share card style write ($e)'));
    }
  }
}
