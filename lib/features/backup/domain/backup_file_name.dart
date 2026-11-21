/// The file name of a finished backup (backup domain, backup rework BR4).
///
/// WHY THE NAME IS MADE HERE (beginner note): since BR4 the backup is handed
/// to the share sheet as a FILE, and the receiving app is shown the name
/// that file has on disk. So the name has to be right when the file is
/// written, not when it is shared. It is built from a time and nothing else,
/// so no text a person typed can ever become part of a path.
library;

/// The name of the backup written at [time]:
/// `Pitak-backup-YYYYMMDD-HHMMSS.pitabak`.
///
/// The fields of [time] are used as they are. Pass a local time to get a
/// name in the user's own clock time, which is what the app does.
String backupFileName(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  final date =
      '${time.year.toString().padLeft(4, '0')}'
      '${two(time.month)}${two(time.day)}';
  final clock = '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  return 'Pitak-backup-$date-$clock.pitabak';
}
