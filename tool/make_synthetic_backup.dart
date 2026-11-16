// Makes a backup file of a chosen size out of made-up data, for the device
// runs (PLAN.md, "Device runs"). Run BY HAND, on a computer, not by CI.
//
// The work, and the reasons for it, are in `synthetic_backup.dart` next to
// this file. Here only the command line is read and the result printed.
//
// How to run it (from the repository root). Compile first: a compiled
// program is much faster at making thousands of pictures.
//
//   dart compile exe tool/make_synthetic_backup.dart -o /tmp/make_synthetic_backup
//   /tmp/make_synthetic_backup --covers 4086 --cover-bytes 20000 --out <folder>
//
// Arguments:
//   --covers N         how many books, each with one cover picture
//   --cover-bytes B    the size of every cover file, in bytes
//   --out FOLDER       where the backup goes; it is created when missing
//   --beyond-limits    make a file the app must REFUSE to restore (more
//                      covers or more content than a backup may hold)
//   --seed S           another seed gives other padding and other uids
//
// The result is FOLDER/pitak-synthetic-<N>x<B>.pitabak (with
// -BEYOND-LIMITS before the ending when that was asked for). An existing
// file is never overwritten.
//
// The files for the runs at today's limits (4,086 covers, 4,096 entries,
// 500 MiB of content):
//   --covers 4000 --cover-bytes 20000
//   --covers 4086 --cover-bytes 20000
//   --covers 4094 --cover-bytes 20000 --beyond-limits
//   --covers 4000 --cover-bytes 125000
//
// Why 4,094 and not 4,087 for the file that must be refused: the app's
// WRITER refuses more than 4,086 covers, but the READER of a restore
// counts entries, and a made-up backup has only three files besides its
// covers. 4,094 covers are 4,097 entries, one more than the reader takes.
// (Asked for 4,087 covers, this tool prints the writer's refusal; with
// --beyond-limits it says that the reader would take the file.)
import 'dart:io';

import 'package:pitaka/core/error/failure.dart';

import 'synthetic_backup.dart';

const String _usage =
    'Usage: make_synthetic_backup --covers N --cover-bytes B --out FOLDER '
    '[--beyond-limits] [--seed S]';

String _megabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// The plain sentence for [failure]. Only the kinds this tool can return
/// have a sentence of their own.
String _sentence(Failure failure) {
  if (failure is BackupTooLargeFailure) {
    return 'The app\u2019s writer refuses this backup (${failure.detail}): '
        'it has ${failure.actual}, a backup can hold ${failure.limit}. '
        'That is what the app would do. To make a file that a RESTORE '
        'must refuse, add --beyond-limits (see the top of this file for '
        'the number of covers that needs).';
  }
  if (failure is ValidationFailure) return failure.message;
  if (failure is StorageFailure) return failure.reason;
  return 'The backup could not be made (${failure.runtimeType}).';
}

Future<void> main(List<String> arguments) async {
  int? covers;
  int? coverBytes;
  String? out;
  var beyondLimits = false;
  var seed = 7;

  // Read by hand: five arguments do not need a package.
  for (var i = 0; i < arguments.length; i++) {
    final argument = arguments[i];
    // The value that belongs to an argument like `--covers`, or null.
    String? value() => i + 1 < arguments.length ? arguments[++i] : null;
    switch (argument) {
      case '--covers':
        covers = int.tryParse(value() ?? '');
      case '--cover-bytes':
        coverBytes = int.tryParse(value() ?? '');
      case '--out':
        out = value();
      case '--seed':
        seed = int.tryParse(value() ?? '') ?? seed;
      case '--beyond-limits':
        beyondLimits = true;
      default:
        stderr.writeln('Not understood: $argument\n$_usage');
        exitCode = 64;
        return;
    }
  }
  if (covers == null || coverBytes == null || out == null) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }

  stdout.writeln(
    'Making a backup of $covers books with covers of $coverBytes bytes'
    '${beyondLimits ? ', beyond the limits on purpose' : ''}...',
  );
  final result = await makeSyntheticBackup(
    covers: covers,
    coverBytes: coverBytes,
    outDir: out,
    beyondLimits: beyondLimits,
    seed: seed,
  );
  result.fold(
    (failure) {
      stderr.writeln(_sentence(failure));
      exitCode = 1;
    },
    (made) => stdout
      ..writeln('Backup file:  ${made.path}')
      ..writeln('Size:         ${_megabytes(made.sizeBytes)}')
      ..writeln('Books/covers: ${made.covers}')
      ..writeln('Time:         ${made.elapsed.inMilliseconds} ms')
      ..writeln('Peak memory:  ${_megabytes(ProcessInfo.maxRss)}')
      ..writeln(
        beyondLimits
            ? 'The reader of a restore REFUSES this file, as intended.'
            : 'The reader of a restore takes this file.',
      ),
  );
}
