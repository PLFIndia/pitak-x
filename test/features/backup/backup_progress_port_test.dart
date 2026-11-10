import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/backup_progress.dart';
import 'package:pitaka/features/backup/infrastructure/backup_progress_port.dart';

/// Plays the worker of a backup: "packs" [covers] covers on another isolate
/// and reports each one through [port], the way the real worker does.
///
/// A top-level function ON PURPOSE (beginner note): the little function
/// handed to `Isolate.run` is copied to the other isolate together with
/// every variable it can see. Here it can see a port and a number, which
/// can both be copied. Inside a test body it would also see the receiving
/// end of the port, which cannot.
Future<void> _reportFromWorker(SendPort port, int covers) => Isolate.run(() {
  final reporter = BackupProgressReporter.toPort(port);
  for (var done = 1; done <= covers; done++) {
    reporter.coverPacked(done, covers);
  }
});

/// BR4 rider 3: how "covers done, of total" gets from the worker isolate to
/// the caller. Two halves, tested apart and then together:
///  - the reporter (worker side) decides WHICH counts go out. Its clock is
///    made up here, so "at most ten a second" is checked without waiting;
///  - the receiver (caller side) turns a message back into a value, drops
///    what is not one, and stops when it is closed.
void main() {
  group('BackupProgressReporter: which counts go out', () {
    late Duration now;
    late List<(int, int)> sent;
    late List<Duration> sentAt;
    late BackupProgressReporter reporter;

    setUp(() {
      now = Duration.zero;
      sent = [];
      sentAt = [];
      reporter = BackupProgressReporter(
        send: (done, total) {
          sent.add((done, total));
          sentAt.add(now);
        },
        elapsed: () => now,
      );
    });

    void advance(int milliseconds) =>
        now += Duration(milliseconds: milliseconds);

    test('the shortest gap between two reports is a tenth of a second', () {
      expect(backupProgressMinGap, const Duration(milliseconds: 100));
    });

    test('the first count goes out at once', () {
      reporter.coverPacked(1, 50);

      expect(sent, [(1, 50)]);
    });

    test('a count inside the gap is held back; one at the gap goes out', () {
      reporter.coverPacked(1, 50);
      advance(99);
      reporter.coverPacked(2, 50);
      expect(sent, [(1, 50)]);

      advance(1);
      reporter.coverPacked(3, 50);
      expect(sent, [(1, 50), (3, 50)]);
    });

    test('the gap is measured from the last count that WENT OUT, not from '
        'the last cover', () {
      reporter.coverPacked(1, 50); // at 0 ms: out
      advance(60);
      reporter.coverPacked(2, 50); // at 60 ms: held back
      advance(60);
      reporter.coverPacked(3, 50); // at 120 ms: out
      advance(60);
      reporter.coverPacked(4, 50); // at 180 ms, 60 after the last: held back

      expect(sent, [(1, 50), (3, 50)]);
    });

    test('the last count always goes out, also inside the gap', () {
      reporter
        ..coverPacked(1, 3)
        ..coverPacked(2, 3)
        ..coverPacked(3, 3);

      expect(sent, [(1, 3), (3, 3)]);
    });

    test('one cover gives exactly one report', () {
      reporter.coverPacked(1, 1);

      expect(sent, [(1, 1)]);
    });

    test('covers packed in the same instant: the first and the last', () {
      for (var done = 1; done <= 500; done++) {
        reporter.coverPacked(done, 500);
      }

      expect(sent, [(1, 500), (500, 500)]);
    });

    test('10,000 covers over ten seconds: ten reports a second and one at '
        'the end, rising, ending on the total', () {
      const covers = 10000;
      for (var done = 1; done <= covers; done++) {
        advance(1); // one cover per millisecond
        reporter.coverPacked(done, covers);
      }

      // At 1 ms, 101 ms, ... 9,901 ms: one hundred. Then the last cover.
      expect(sent, hasLength(101));
      expect(sent.first, (1, covers));
      expect(sent.last, (covers, covers));
      for (var i = 1; i < sent.length; i++) {
        expect(sent[i].$1, greaterThan(sent[i - 1].$1), reason: 'report $i');
        expect(sent[i].$2, covers);
      }
      // Every report but the last keeps the full gap to the one before.
      for (var i = 1; i < sentAt.length - 1; i++) {
        expect(
          sentAt[i] - sentAt[i - 1],
          greaterThanOrEqualTo(backupProgressMinGap),
          reason: 'report $i',
        );
      }
    });
  });

  group('backupProgressFromMessage: what counts as a report', () {
    test('a pair of whole numbers that make sense', () {
      final progress = backupProgressFromMessage((2, 5))!;

      expect(progress.coversDone, 2);
      expect(progress.coversTotal, 5);
    });

    test('anything else is no report', () {
      const notReports = <Object?>[
        null,
        'cover 1 of 2',
        7,
        [1, 2],
        (1, 2, 3),
        (1.5, 2),
        ('1', '2'),
        (done: 1, total: 2),
        // Whole numbers, but not a progress: more done than there are, no
        // covers at all, fewer than none.
        (3, 2),
        (0, 0),
        (-1, 5),
      ];
      for (final message in notReports) {
        expect(backupProgressFromMessage(message), isNull, reason: '$message');
      }
    });
  });

  group('BackupProgressReceiver: the caller end of the port', () {
    late List<BackupProgress> seen;

    setUp(() => seen = []);

    List<String> seenAsText() => [for (final progress in seen) '$progress'];

    test('a report sent to the port reaches the listener', () async {
      final receiver = BackupProgressReceiver(seen.add);
      addTearDown(receiver.close);

      receiver.sendPort.send((2, 5));
      await pumpEventQueue();

      expect(seenAsText(), ['BackupProgress(2 of 5)']);
    });

    test('a message that is no report is dropped, and the port goes on '
        'working', () async {
      final receiver = BackupProgressReceiver(seen.add);
      addTearDown(receiver.close);

      receiver.sendPort
        ..send('cover 1 of 2')
        ..send((3, 2))
        ..send(null)
        ..send((1, 2));
      await pumpEventQueue();

      expect(seenAsText(), ['BackupProgress(1 of 2)']);
    });

    test('after close nothing more reaches the listener; closing twice is '
        'fine', () async {
      final receiver = BackupProgressReceiver(seen.add);
      final port = receiver.sendPort..send((1, 3));
      await pumpEventQueue();

      receiver.close();
      port.send((2, 3));
      receiver.close();
      await pumpEventQueue();

      expect(seenAsText(), ['BackupProgress(1 of 3)']);
    });

    test('a report that was sent but not yet delivered is dropped by '
        'close', () async {
      // The builder promises: no call after the build has returned.
      final receiver = BackupProgressReceiver(seen.add);
      receiver.sendPort.send((1, 3));
      receiver.close();
      await pumpEventQueue();

      expect(seen, isEmpty);
    });

    test('a listener that throws does not stop the port: the error goes to '
        'the zone, and the next report still arrives', () async {
      final errors = <Object>[];
      late final BackupProgressReceiver receiver;
      runZonedGuarded(() {
        receiver = BackupProgressReceiver((progress) {
          seen.add(progress);
          if (progress.coversDone == 1) throw StateError('listener broke');
        });
      }, (error, _) => errors.add(error));
      addTearDown(() => receiver.close());

      receiver.sendPort
        ..send((1, 3))
        ..send((2, 3));
      await pumpEventQueue();

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
      expect(seenAsText(), [
        'BackupProgress(1 of 3)',
        'BackupProgress(2 of 3)',
      ]);
    });

    test('reports from a worker isolate arrive in order, and all of them '
        'BEFORE the worker has returned', () async {
      final receiver = BackupProgressReceiver(seen.add);
      addTearDown(receiver.close);

      await _reportFromWorker(receiver.sendPort, 500);

      // No waiting here ON PURPOSE. The writer closes the port as soon as
      // its worker has returned, so the last report must be in by then.
      expect(seen, isNotEmpty);
      expect('${seen.first}', 'BackupProgress(1 of 500)');
      expect('${seen.last}', 'BackupProgress(500 of 500)');
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i].coversDone, greaterThan(seen[i - 1].coversDone));
      }
    });
  });
}
