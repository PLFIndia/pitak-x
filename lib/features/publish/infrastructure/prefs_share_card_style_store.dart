/// `shared_preferences`-backed [ShareCardStyleStore] (infrastructure, §3.3).
///
/// One non-secret key: the enum token of the last share-card style the user
/// chose. Same shape as `PrefsBookmarksRepository` — a tiny preference that
/// does not belong on `AppSettings` (which every settings fake would then
/// have to mirror).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/storage/prefs_write.dart';
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
  Future<Either<Failure, Unit>> save(ShareCardStyle style) =>
      // Reports a failed platform write (M17) and restores the previous cached
      // value, so the share sheet cannot show a style the device never stored
      // (fix-plan L9).
      writePrefsString(
        _prefs,
        key,
        style.token,
        what: 'share card style write',
      );
}
