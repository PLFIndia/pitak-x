/// Shared-preferences storage for the public restore-identity handoff.
library;

import 'dart:convert';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/storage/prefs_write.dart';
import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';
import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';
import 'package:pitaka/features/publish/domain/restore/restore_identity_journal.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret [SharedPreferences] journal implementation.
final class PrefsRestoreIdentityJournalStore
    implements RestoreIdentityJournalStore {
  /// Creates the store.
  const PrefsRestoreIdentityJournalStore(this._prefs);

  final SharedPreferences _prefs;
  static const _key = 'publish_restore_identity_journal';
  static const _maxChars = 4096;

  @override
  Future<Either<Failure, RestoreIdentityJournal?>> load() async {
    final raw = _prefs.getString(_key);
    if (raw == null) return right(null);
    if (raw.length > _maxChars) return left(_corrupt);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] != 1) {
        return left(_corrupt);
      }
      final site = decoded['siteUrl'];
      final addedDate = decoded['addedDate'];
      final fingerprint = decoded['fingerprint'];
      if (site is! String || BookmarkUrl.normalize(site) != site) {
        return left(_corrupt);
      }
      if (addedDate is! int || addedDate <= 0) return left(_corrupt);
      if (fingerprint != null &&
          (fingerprint is! String ||
              !LibraryFingerprint.isValid(fingerprint))) {
        return left(_corrupt);
      }
      return right(
        RestoreIdentityJournal(
          siteUrl: site,
          addedDate: addedDate,
          fingerprint: fingerprint as String?,
        ),
      );
    } on FormatException {
      return left(_corrupt);
    }
  }

  @override
  Future<Either<Failure, Unit>> save(RestoreIdentityJournal journal) {
    final encoded = jsonEncode({
      'schemaVersion': 1,
      'siteUrl': journal.siteUrl,
      'addedDate': journal.addedDate,
      'fingerprint': journal.fingerprint,
    });
    return writePrefsString(_prefs, _key, encoded, what: 'restore journal');
  }

  @override
  Future<Either<Failure, Unit>> clear() =>
      removePrefs(_prefs, _key, what: 'restore journal clear');

  static const _corrupt = StorageFailure('restore identity journal unreadable');
}
