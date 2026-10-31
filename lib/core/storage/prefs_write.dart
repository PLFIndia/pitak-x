/// The ONE way this app writes a `SharedPreferences` value (core/storage).
///
/// Why these helpers exist (beginner note): `shared_preferences` writes to its
/// in-memory cache BEFORE it asks the platform to store the value. When the
/// platform write fails — a full disk, a locked keystore, a mock that reports
/// failure — the cache still holds the NEW value for the rest of the session
/// while the device holds the OLD one. The app then behaves as if a record was
/// saved (a pending move banner appears, Retry may retire a site) and a restart
/// silently loses it (fix-plan L9).
///
/// These helpers put the previous value back through the same API after a
/// failed write, so "the write failed" and "the cache says it succeeded" can
/// never both be true. The write is still reported as a typed
/// [StorageFailure] — repairing the cache does not make the write work.
///
/// Rejected alternatives (recorded in the fix plan): `reload()` depends on
/// another platform read succeeding; `SharedPreferencesWithCache` also updates
/// its cache first; `SharedPreferencesAsync` needs an async load and a data
/// migration.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Writes one string preference, restoring the previous cached value on
/// failure. [what] is a short diagnostic label, never shown to users.
Future<Either<Failure, Unit>> writePrefsString(
  SharedPreferences prefs,
  String key,
  String value, {
  required String what,
}) {
  final previous = prefs.getString(key);
  return _guardedWrite(
    write: () => prefs.setString(key, value),
    restore: previous == null
        ? () => prefs.remove(key)
        : () => prefs.setString(key, previous),
    what: what,
  );
}

/// Writes one boolean preference, restoring the previous cached value on
/// failure.
Future<Either<Failure, Unit>> writePrefsBool(
  SharedPreferences prefs,
  String key, {
  required bool value,
  required String what,
}) {
  final previous = prefs.getBool(key);
  return _guardedWrite(
    write: () => prefs.setBool(key, value),
    restore: previous == null
        ? () => prefs.remove(key)
        : () => prefs.setBool(key, previous),
    what: what,
  );
}

/// Removes one preference, restoring the previous cached value on failure.
///
/// A remove that fails must not leave the in-memory cache believing the key is
/// gone: the next read would then treat a real record as absent.
Future<Either<Failure, Unit>> removePrefs(
  SharedPreferences prefs,
  String key, {
  required String what,
}) {
  final previous = prefs.getString(key);
  return _guardedWrite(
    write: () => prefs.remove(key),
    restore: previous == null
        ? () async => true
        : () => prefs.setString(key, previous),
    what: what,
  );
}

Future<Either<Failure, Unit>> _guardedWrite({
  required Future<bool> Function() write,
  required Future<bool> Function() restore,
  required String what,
}) async {
  try {
    if (await write()) return right(unit);
  } on Object {
    // A thrown plugin error and a `false` result are the same fact: the value
    // is not stored. Both continue to the cache repair below.
  }
  try {
    await restore();
  } on Object {
    // Best effort. If even the restore fails the cache may be wrong, but the
    // caller still gets the honest typed failure, so no success is reported.
  }
  return left(StorageFailure(what));
}
