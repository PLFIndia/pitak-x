/// Tries a SQLite call again while the database file is locked by another
/// connection (core/database).
///
/// WHY THIS FILE EXISTS (beginner note): the app writes its catalogue on a
/// background thread, with SQLite's default journal. For the moment a write
/// is committed there, SQLite lets nobody else read the file, and a reader
/// on a connection of its own gets the answer "busy" at once. The cure is
/// to wait a little and ask again.
///
/// SQLite has a wait of its own (`PRAGMA busy_timeout`). It is NOT used
/// here, for two reasons:
///  - it counts the pauses it ASKS for, not the time that passes. In a debug
///    or test run on Android and Linux the Dart profiler interrupts every
///    thread with a signal once a millisecond, each pause ends early, and
///    "two seconds" are over after a few hundredths of a second (seen on
///    the CI runner, 2026-11-13);
///  - it blocks the thread that waits. For a caller on the screen's thread
///    the screen would stand still for the whole wait.
/// A Dart timer does neither: it never ends early, and the thread is free
/// while it runs.
library;

import 'package:sqlite3/common.dart' show SqliteException;

/// SQLite's primary result code for "the file is locked by another
/// connection right now" (`SQLITE_BUSY`). Its extended forms (for example
/// `SQLITE_BUSY_SNAPSHOT`) share this primary code.
const int sqliteBusyCode = 5;

/// Runs [attempt]. While SQLite answers "busy", waits [pause] and runs it
/// again, at most [attempts] times in all.
///
/// The answer of the first run that is not "busy" is the result: its value,
/// or its exception. When every run was "busy", the last "busy" is thrown
/// on. An exception that is not "busy" is never tried again: a damaged file
/// or a full disk does not get better by asking again.
///
/// So the longest wait is `(attempts - 1) × pause`, or more when the
/// device is slow; it is never less.
Future<T> retryWhileSqliteBusy<T>(
  T Function() attempt, {
  required int attempts,
  required Duration pause,
}) async {
  assert(attempts >= 1, 'attempts must be at least 1');
  for (var run = 1; ; run++) {
    try {
      return attempt();
    } on SqliteException catch (e) {
      if (e.resultCode != sqliteBusyCode || run >= attempts) rethrow;
    }
    await Future<void>.delayed(pause);
  }
}
