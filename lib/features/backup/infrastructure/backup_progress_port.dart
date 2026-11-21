/// Carries the progress of a backup from the worker isolate to the isolate
/// that asked for it (backup infrastructure; backup rework BR4, rider 3).
///
/// WHY THIS FILE EXISTS (beginner note): the backup is packed on a worker
/// isolate so that the screen keeps painting. Two isolates share no memory,
/// so the worker cannot call a function of the screen. It can only SEND a
/// message through a port. This file holds both ends of that port:
///
///  - [BackupProgressReporter], used inside the worker: decides which
///    counts are worth sending and sends them;
///  - [BackupProgressReceiver], used by the caller: turns each message back
///    into a [BackupProgress] and hands it to the listener.
///
/// What travels is two whole numbers, `(done, total)`. Nothing else: no
/// title, no file name, no path.
///
/// In its own file because `backup_archive_writer.dart` is close to the
/// 500-line ceiling, and so that the "how often" rule can be tested with a
/// made-up clock instead of a real wait.
library;

import 'dart:isolate';

import 'package:pitaka/features/backup/domain/backup_progress.dart';

/// The shortest time between two reports: a tenth of a second, so at most
/// ten a second. A person cannot read a number that changes faster, and a
/// library of 10,000 pictures would otherwise send 10,000 messages.
const Duration backupProgressMinGap = Duration(milliseconds: 100);

/// Worker side: is told about EVERY packed cover and passes on only some.
///
/// The rule:
///  - the first count goes out at once;
///  - after that, a count goes out only when [backupProgressMinGap] has
///    passed since the last one that went out;
///  - the LAST count (done equals total) always goes out, so the listener
///    ends on the full number.
final class BackupProgressReporter {
  /// Creates a reporter that hands the chosen counts to [send] and reads
  /// the time from [elapsed] (time since some fixed start; it must never
  /// run backwards). Tests pass a made-up clock.
  BackupProgressReporter({
    required void Function(int coversDone, int coversTotal) send,
    required Duration Function() elapsed,
  }) : _send = send,
       _elapsed = elapsed;

  /// The reporter the worker uses: sends through [port], timed by a
  /// stopwatch that starts now.
  factory BackupProgressReporter.toPort(SendPort port) {
    final clock = Stopwatch()..start();
    return BackupProgressReporter(
      // A record of two whole numbers: plain data, which is all that may
      // cross to another isolate.
      send: (coversDone, coversTotal) => port.send((coversDone, coversTotal)),
      elapsed: () => clock.elapsed,
    );
  }

  final void Function(int coversDone, int coversTotal) _send;
  final Duration Function() _elapsed;

  /// When the last report went out; null before the first.
  Duration? _lastSentAt;

  /// Call after each cover is packed, with the running count.
  void coverPacked(int coversDone, int coversTotal) {
    final now = _elapsed();
    final last = _lastSentAt;
    final isLast = coversDone >= coversTotal;
    final isDue = last == null || now - last >= backupProgressMinGap;
    if (!isLast && !isDue) return;
    _lastSentAt = now;
    _send(coversDone, coversTotal);
  }
}

/// Caller side: owns the port the worker reports to.
///
/// The port MUST be closed when the build is over ([close]), on every way
/// out: an open port is a resource the app would hold for good.
final class BackupProgressReceiver {
  /// Opens the port and hands every well-formed report to [listener].
  ///
  /// [listener] runs on the isolate that created this object, in the zone
  /// that created it (a `ReceivePort` is a stream, and a stream calls its
  /// listener in the zone that subscribed). An error thrown by [listener]
  /// is reported to that zone like any other uncaught error; it does not
  /// reach the build.
  BackupProgressReceiver(BackupProgressListener listener) {
    _port.listen((Object? message) {
      final progress = backupProgressFromMessage(message);
      if (progress != null) listener(progress);
    });
  }

  final ReceivePort _port = ReceivePort('pitaka-backup-progress');

  /// What the worker sends to. Plain data: it may travel to another isolate.
  SendPort get sendPort => _port.sendPort;

  /// Closes the port. A report that arrives later is dropped, and the
  /// listener is never called again. Safe to call twice.
  void close() => _port.close();
}

/// The [BackupProgress] a port [message] stands for, or null when it is not
/// a pair of whole numbers that make sense as "done, of total".
///
/// Checked although only this app's own worker holds the port: whatever
/// crosses between isolates is treated as input, not as a typed value.
BackupProgress? backupProgressFromMessage(Object? message) {
  if (message case (final int coversDone, final int coversTotal)) {
    return BackupProgress.tryCreate(
      coversDone: coversDone,
      coversTotal: coversTotal,
    );
  }
  return null;
}
