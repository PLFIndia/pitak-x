/// Tests for the debug-only publish timings (publish optimisation plan S0).
///
/// What must hold (plan B.2): marks are recorded in the order the stages
/// finished, they carry their coarse counts, the produced log line is numbers
/// only (no path, URL, key, token or title), and a null sink does NO work.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/site/publish_timings.dart';

void main() {
  group('PublishTimingRecorder', () {
    test('records marks in the order the stages finished', () {
      var now = 1000;
      PublishTimings? captured;
      final timings = PublishTimingRecorder(
        sink: (value) => captured = value,
        operation: 'catalogue',
        clock: () => now,
      );

      final reads = timings.begin();
      now += 250;
      timings.end(PublishTimingStage.reads, reads);

      final build = timings.begin();
      now += 125;
      timings.end(
        PublishTimingStage.build,
        build,
        coversRead: 2,
        coversReused: 78,
      );

      now += 25; // gap before finish belongs to the total, not to a stage
      timings.finish();

      final result = captured!;
      expect(result.operation, 'catalogue');
      expect(result.marks.map((mark) => mark.stage), [
        PublishTimingStage.reads,
        PublishTimingStage.build,
      ]);
      expect(result.marks[0].millis, 250);
      expect(result.marks[1].millis, 125);
      expect(result.marks[1].coversRead, 2);
      expect(result.marks[1].coversReused, 78);
      // Total spans the whole recorder, including time between stages.
      expect(result.totalMillis, 400);
    });

    test('carries the coarse counts a stage reports', () {
      var now = 0;
      PublishTimings? captured;
      final timings = PublishTimingRecorder(
        sink: (value) => captured = value,
        operation: 'cloudflare',
        clock: () => now,
      );

      final upload = timings.begin();
      now += 10;
      timings.end(PublishTimingStage.upload, upload, bytes: 4096);
      final readBack = timings.begin();
      now += 10;
      timings
        ..end(PublishTimingStage.readBack, readBack, rounds: 3)
        ..finish();

      final result = captured!;
      expect(result.markFor(PublishTimingStage.upload)!.bytes, 4096);
      expect(result.markFor(PublishTimingStage.readBack)!.rounds, 3);
      // A stage that never ran is absent, not zero.
      expect(result.markFor(PublishTimingStage.commit), isNull);
    });

    test('a null sink does no work and reports nothing', () {
      final timings = PublishTimingRecorder(
        sink: null,
        operation: 'catalogue',
        clock: () => 0,
      );

      expect(timings.enabled, isFalse);
      // begin() is the "recording is off" signal every call site relies on.
      expect(timings.begin(), isNull);
      // A caller that passes a stamp anyway must still record nothing, and
      // reaching the end without a sink call is the assertion: there is none.
      timings
        ..end(PublishTimingStage.reads, 5)
        ..finish();
    });

    test('finish reports once, even when called from error paths too', () {
      var now = 0;
      final reported = <PublishTimings>[];
      final timings = PublishTimingRecorder(
        sink: reported.add,
        operation: 'events',
        clock: () => now,
      );

      final build = timings.begin();
      now += 10;
      timings
        ..end(PublishTimingStage.build, build)
        ..finish()
        ..finish();

      expect(reported, hasLength(1));
    });

    test('a clock that moves backwards never reports a negative duration', () {
      var now = 500;
      PublishTimings? captured;
      final timings = PublishTimingRecorder(
        sink: (value) => captured = value,
        operation: 'catalogue',
        clock: () => now,
      );

      final reads = timings.begin();
      now = 100; // the device clock jumped back
      timings
        ..end(PublishTimingStage.reads, reads)
        ..finish();

      final result = captured!;
      expect(result.marks.single.millis, 0);
      expect(result.totalMillis, 0);
    });

    test('a recorder with no finished marks reports nothing', () {
      final reported = <PublishTimings>[];
      PublishTimingRecorder(
        sink: reported.add,
        operation: 'catalogue',
        clock: () => 0,
      ).finish();

      expect(reported, isEmpty);
    });
  });

  group('PublishTimings.describe', () {
    test('is one line of stage names and numbers only', () {
      var now = 0;
      PublishTimings? captured;
      final timings = PublishTimingRecorder(
        sink: (value) => captured = value,
        operation: 'catalogue',
        clock: () => now,
      );

      final reads = timings.begin();
      now += 100;
      timings.end(PublishTimingStage.reads, reads);
      final build = timings.begin();
      now += 900;
      timings
        ..end(PublishTimingStage.build, build, coversRead: 1, coversReused: 79)
        ..finish();

      expect(
        captured!.describe(),
        'publish timings catalogue: total=1000ms '
        'reads=100ms build=900ms(coversRead=1,coversReused=79)',
      );
    });

    test('the GitHub reconcile reports its tree reads (plan SP4)', () {
      var now = 0;
      PublishTimings? captured;
      final timings = PublishTimingRecorder(
        sink: (value) => captured = value,
        operation: 'catalogue',
        clock: () => now,
      );

      final reconcile = timings.begin();
      now += 300;
      timings
        ..end(PublishTimingStage.reconcile, reconcile, treeReads: 0)
        ..finish();

      expect(captured!.markFor(PublishTimingStage.reconcile)!.treeReads, 0);
      expect(
        captured!.describe(),
        'publish timings catalogue: total=300ms reconcile=300ms(treeReads=0)',
      );
    });

    test('never carries a path, URL or scheme (AGENTS.md §6.2)', () {
      var now = 0;
      PublishTimings? captured;
      final timings = PublishTimingRecorder(
        sink: (value) => captured = value,
        operation: 'events',
        clock: () => now,
      );

      final commit = timings.begin();
      now += 5;
      timings.end(PublishTimingStage.commit, commit, bytes: 12);
      final readBack = timings.begin();
      now += 5;
      timings
        ..end(PublishTimingStage.readBack, readBack, rounds: 2)
        ..finish();

      final line = captured!.describe();
      expect(line, isNot(contains('/')));
      expect(line, isNot(contains('http')));
      expect(line, isNot(contains('@')));
      expect(line, isNot(contains('.json')));
      expect(line, isNot(contains('covers')));
    });
  });
}
