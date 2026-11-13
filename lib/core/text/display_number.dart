/// User-visible numbers and sizes (pure Dart, no locale service).
///
/// The app has no `intl` package on purpose (AGENTS.md §9: every dependency
/// is a risk), and it needs only two things: digits grouped in threes, and a
/// pair of sizes a person can compare at a glance.
library;

const int _kibibyte = 1024;

/// The units a size is shown in, largest first. A unit is 1,024 of the next
/// smaller one and is labelled the everyday way ("MB"), as `PRIVACY.md` does
/// for the user. A limit of 500 × 1,024 × 1,024 bytes therefore reads
/// "500.0 MB", the round number it was chosen as.
const List<({int bytes, String label})> _units = [
  (bytes: _kibibyte * _kibibyte * _kibibyte, label: 'GB'),
  (bytes: _kibibyte * _kibibyte, label: 'MB'),
  (bytes: _kibibyte, label: 'KB'),
];

/// Writes a whole number with its digits grouped in threes: `4300` becomes
/// `4,300`.
String formatCount(int value) {
  final text = value.toString();
  final negative = text.startsWith('-');
  final digits = negative ? text.substring(1) : text;
  final out = StringBuffer(negative ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Writes two sizes, given in bytes, in the SAME unit with one decimal, so a
/// sentence can set them side by side: `(first: '512.3 MB', second:
/// '500.0 MB')`.
///
/// Two rules keep the pair honest:
///  - the unit is the largest one the larger size reaches, so neither number
///    reads as "0.0";
///  - two DIFFERENT sizes never look equal. "500.0 MB; a backup can hold
///    500.0 MB" would be a riddle, so when rounding makes them look the same
///    the next smaller unit is used, down to exact bytes.
({String first, String second}) formatSizePair(int first, int second) {
  final larger = first > second ? first : second;
  for (final unit in _units) {
    if (larger < unit.bytes) continue;
    final a = _oneDecimal(first, unit.bytes);
    final b = _oneDecimal(second, unit.bytes);
    if (a != b || first == second) {
      return (first: '$a ${unit.label}', second: '$b ${unit.label}');
    }
  }
  return (first: _wholeBytes(first), second: _wholeBytes(second));
}

/// [bytes] divided by [unit], rounded to one decimal (half up) with whole
/// numbers only, so no floating-point error can change the last digit.
String _oneDecimal(int bytes, int unit) {
  final tenths = (bytes * 10 + unit ~/ 2) ~/ unit;
  return '${formatCount(tenths ~/ 10)}.${tenths % 10}';
}

String _wholeBytes(int bytes) =>
    bytes == 1 ? '1 byte' : '${formatCount(bytes)} bytes';
