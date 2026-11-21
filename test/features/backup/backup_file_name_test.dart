import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/backup_file_name.dart';

/// BR4: the finished backup is shared as a file, and the receiving app sees
/// the name that file has on disk. So the name is made once, from a time
/// and nothing else.
void main() {
  test('the name carries date and time, each part padded', () {
    expect(
      backupFileName(DateTime(2026, 11, 10, 19, 30)),
      'Pitak-backup-20261110-193000.pitabak',
    );
    expect(
      backupFileName(DateTime(2026, 1, 2, 3, 4, 5)),
      'Pitak-backup-20260102-030405.pitabak',
    );
  });

  test('the fields of the given time are used as they are', () {
    // A UTC time is not shifted to local time: the caller decides which
    // clock the name shows.
    expect(
      backupFileName(DateTime.utc(2026, 12, 31, 23, 59, 59)),
      'Pitak-backup-20261231-235959.pitabak',
    );
  });

  test('a small year is padded to four digits', () {
    expect(
      backupFileName(DateTime(987, 6, 5, 4, 3, 2)),
      'Pitak-backup-09870605-040302.pitabak',
    );
  });

  test('the name is one plain path part, whatever the time', () {
    // Nothing in it can leave the folder it is written into.
    final safe = RegExp(r'^Pitak-backup-[0-9-]+\.pitabak$');
    for (final time in [
      DateTime.fromMillisecondsSinceEpoch(0),
      DateTime.fromMillisecondsSinceEpoch(1),
      DateTime.fromMillisecondsSinceEpoch(1700000000000),
      DateTime.fromMillisecondsSinceEpoch(-62198755200000),
      DateTime.fromMillisecondsSinceEpoch(8640000000000000),
    ]) {
      final name = backupFileName(time);
      expect(name, matches(safe), reason: '$time');
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(r'\')));
      expect(name, isNot(contains('..')));
    }
  });
}
