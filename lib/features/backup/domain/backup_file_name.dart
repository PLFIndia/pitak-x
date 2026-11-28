/// The file name of a finished backup (backup domain, backup rework BR4).
///
/// WHY THE NAME IS MADE HERE (beginner note): since BR4 the backup leaves
/// the app as a FILE. The save window proposes the name that file has on
/// disk, and an app that takes it from the share sheet is shown the same.
/// So the name has to be right when the file is written, not when it is
/// shared. It is built from a time and nothing else, so no text a person
/// typed can ever become part of a path.
library;

/// The twelve months as the name spells them (D169).
///
/// WHY A LIST OF ITS OWN (beginner note): a file name is a format, not a
/// text for the screen. It must read the same on every phone, whatever
/// language the phone is set to, and it must not change when the wording of
/// a date on a page changes. So nothing here asks the phone how it spells a
/// month, and this list is not shared with the code that shows dates.
const List<String> _monthNames = [
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

/// The name of the backup written at [time]:
/// `pitak-backup-<DDMonYYYY>-<HHMMSS>.pitabak`, for example
/// `pitak-backup-02Nov2026-134659.pitabak` (D169).
///
/// The time (24-hour clock) stands behind the date so that two backups made
/// on one day do not share a name.
///
/// The fields of [time] are used as they are. Pass a local time to get a
/// name in the user's own clock time, which is what the app does.
String backupFileName(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  // `DateTime.month` is always 1 to 12, so the list is never read outside
  // its twelve entries.
  final date =
      '${two(time.day)}${_monthNames[time.month - 1]}'
      '${time.year.toString().padLeft(4, '0')}';
  final clock = '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  return 'pitak-backup-$date-$clock.pitabak';
}
