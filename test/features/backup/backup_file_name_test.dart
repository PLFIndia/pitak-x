import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/domain/backup_file_name.dart';

/// BR4: the finished backup leaves the app as a file, and whoever takes it
/// sees the name that file has on disk. So the name is made once, from a
/// time and nothing else.
///
/// D169 (stage 8, P4-M6): the form is
/// `pitak-backup-<DDMonYYYY>-<HHMMSS>.pitabak`, for example
/// `pitak-backup-02Nov2026-134659.pitabak`.
void main() {
  test('the name carries the date and the time, each part padded', () {
    expect(
      backupFileName(DateTime(2026, 11, 2, 13, 46, 59)),
      'pitak-backup-02Nov2026-134659.pitabak',
    );
    expect(
      backupFileName(DateTime(2026, 1, 2, 3, 4, 5)),
      'pitak-backup-02Jan2026-030405.pitabak',
    );
    expect(
      backupFileName(DateTime(2026, 11, 10, 19, 30)),
      'pitak-backup-10Nov2026-193000.pitabak',
    );
  });

  test('the month is three English letters, the same on every phone', () {
    // The twelve names are spelled out here on purpose: the function has its
    // own fixed list and asks nobody for the phone's language, so a name
    // made on a Hindi phone reads like one made on an English phone.
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    for (var month = 1; month <= 12; month++) {
      expect(
        backupFileName(DateTime(2026, month, 15, 8)),
        'pitak-backup-15${months[month - 1]}2026-080000.pitabak',
        reason: 'month $month',
      );
    }
  });

  test('the clock counts 24 hours', () {
    expect(
      backupFileName(DateTime(2026, 11, 2)),
      'pitak-backup-02Nov2026-000000.pitabak',
    );
    expect(
      backupFileName(DateTime(2026, 11, 2, 23, 59, 59)),
      'pitak-backup-02Nov2026-235959.pitabak',
    );
  });

  test('two backups of one day do not share a name', () {
    // D169: this is why the time stays behind the date.
    final first = backupFileName(DateTime(2026, 11, 2, 9));
    expect(backupFileName(DateTime(2026, 11, 2, 21)), isNot(first));
    expect(backupFileName(DateTime(2026, 11, 2, 9, 0, 1)), isNot(first));
  });

  test('the fields of the given time are used as they are', () {
    // A UTC time is not shifted to local time: the caller decides which
    // clock the name shows.
    expect(
      backupFileName(DateTime.utc(2026, 12, 31, 23, 59, 59)),
      'pitak-backup-31Dec2026-235959.pitabak',
    );
  });

  test('a small year is padded to four digits', () {
    expect(
      backupFileName(DateTime(987, 6, 5, 4, 3, 2)),
      'pitak-backup-05Jun0987-040302.pitabak',
    );
  });

  test('the name is one plain path part, whatever the time', () {
    // Letters, digits, hyphens and ONE dot: nothing in it can leave the
    // folder it is written into. (The year may be longer than four digits,
    // or carry a minus sign, for a time no clock of a phone will show.)
    final form = RegExp(
      r'^pitak-backup-[0-9]{2}[A-Z][a-z]{2}[0-9-]+-[0-9]{6}\.pitabak$',
    );
    for (final time in [
      DateTime.fromMillisecondsSinceEpoch(0),
      DateTime.fromMillisecondsSinceEpoch(1),
      DateTime.fromMillisecondsSinceEpoch(1700000000000),
      DateTime.fromMillisecondsSinceEpoch(-62198755200000),
      DateTime.fromMillisecondsSinceEpoch(8640000000000000),
    ]) {
      final name = backupFileName(time);
      expect(name, matches(form), reason: '$time');
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(r'\')));
      expect(name, isNot(contains('..')));
      expect('.'.allMatches(name), hasLength(1), reason: '$time');
    }
  });
}
