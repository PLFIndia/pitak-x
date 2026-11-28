import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/database/sqlite_busy_retry.dart';
import 'package:sqlite3/common.dart' show SqliteException;

/// `retryWhileSqliteBusy` decides ALONE how long a reader waits for a write
/// to finish, since SQLite's own wait is not used (see the file's comment).
/// So its rules are pinned here by counting the runs, not by a clock: the
/// tests give the same verdict on a fast and on a slow machine.
void main() {
  // SQLite's result codes: 5 is "busy", 517 is its extended form
  // `SQLITE_BUSY_SNAPSHOT` (5 | 2 << 8), 26 is "file is not a database".
  SqliteException busy() =>
      SqliteException(sqliteBusyCode, 'database is locked');
  const pause = Duration(milliseconds: 1);

  test(
    'an answer at the first run is the result, with no second run',
    () async {
      var runs = 0;

      final result = await retryWhileSqliteBusy(
        () {
          runs++;
          return 'copied';
        },
        attempts: 80,
        pause: pause,
      );

      expect(result, 'copied');
      expect(runs, 1);
    },
  );

  test('"busy" is asked again until the lock is gone', () async {
    var runs = 0;

    final result = await retryWhileSqliteBusy(
      () {
        runs++;
        if (runs <= 3) throw busy();
        return runs;
      },
      attempts: 80,
      pause: pause,
    );

    expect(result, 4, reason: 'three times busy, then the answer');
  });

  test('an extended "busy" code is "busy" too', () async {
    var runs = 0;

    await retryWhileSqliteBusy(
      () {
        runs++;
        if (runs == 1) throw SqliteException(517, 'snapshot is busy');
      },
      attempts: 80,
      pause: pause,
    );

    expect(runs, 2);
  });

  test('a lock that never goes ends after exactly the given number of runs, '
      'with the last "busy"', () async {
    var runs = 0;

    await expectLater(
      retryWhileSqliteBusy<void>(
        () {
          runs++;
          throw SqliteException(sqliteBusyCode, 'locked, run $runs');
        },
        attempts: 5,
        pause: pause,
      ),
      throwsA(
        isA<SqliteException>()
            .having((e) => e.resultCode, 'resultCode', sqliteBusyCode)
            .having((e) => e.message, 'message', 'locked, run 5'),
      ),
    );
    expect(runs, 5);
  });

  test('one run means no second try', () async {
    var runs = 0;

    await expectLater(
      retryWhileSqliteBusy<void>(
        () {
          runs++;
          throw busy();
        },
        attempts: 1,
        pause: pause,
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(runs, 1);
  });

  test(
    'another SQLite failure is thrown on at once, never tried again',
    () async {
      var runs = 0;

      await expectLater(
        retryWhileSqliteBusy<void>(
          () {
            runs++;
            throw SqliteException(26, 'file is not a database');
          },
          attempts: 80,
          pause: pause,
        ),
        throwsA(
          isA<SqliteException>().having((e) => e.resultCode, 'resultCode', 26),
        ),
      );
      expect(runs, 1);
    },
  );

  test('a failure that is not from SQLite is thrown on at once', () async {
    var runs = 0;

    await expectLater(
      retryWhileSqliteBusy<void>(
        () {
          runs++;
          throw StateError('not SQLite');
        },
        attempts: 80,
        pause: pause,
      ),
      throwsStateError,
    );
    expect(runs, 1);
  });

  test('it really pauses between two runs: other work gets its turn', () async {
    // The reason the wait is done with a timer: whoever holds the lock on
    // this thread (in the tests) or needs this thread (the screen, in the
    // app) can go on while the reader waits.
    var runs = 0;
    var otherWorkRan = false;

    await retryWhileSqliteBusy(
      () {
        runs++;
        if (runs == 1) {
          Future<void>.delayed(Duration.zero, () => otherWorkRan = true);
          throw busy();
        }
        return otherWorkRan;
      },
      attempts: 80,
      pause: const Duration(milliseconds: 5),
    );

    expect(otherWorkRan, isTrue, reason: 'the timer of the other work fired');
  });
}
