import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/text/display_number.dart';

void main() {
  const kb = 1024;
  const mb = 1024 * 1024;
  const gb = 1024 * 1024 * 1024;

  group('formatCount', () {
    test('groups digits in threes', () {
      expect(formatCount(0), '0');
      expect(formatCount(7), '7');
      expect(formatCount(999), '999');
      expect(formatCount(1000), '1,000');
      expect(formatCount(4086), '4,086');
      expect(formatCount(100001), '100,001');
      expect(formatCount(1234567), '1,234,567');
      expect(formatCount(524288000), '524,288,000');
    });

    test('keeps the sign outside the groups', () {
      expect(formatCount(-1), '-1');
      expect(formatCount(-1000), '-1,000');
      expect(formatCount(-123456), '-123,456');
    });
  });

  group('formatSizePair', () {
    test('both sizes use the unit the larger one reaches', () {
      expect(formatSizePair(537 * mb, 500 * mb), (
        first: '537.0 MB',
        second: '500.0 MB',
      ));
      // The smaller size stays in the larger one's unit, even below 1.
      expect(formatSizePair(2 * gb, 512 * mb), (
        first: '2.0 GB',
        second: '0.5 GB',
      ));
      expect(formatSizePair(5 * kb, 4 * kb), (
        first: '5.0 KB',
        second: '4.0 KB',
      ));
    });

    test('one decimal, rounded half up', () {
      // 1.25 MB rounds to 1.3; 1.24 MB rounds to 1.2.
      expect(formatSizePair(mb + mb ~/ 4, mb).first, '1.3 MB');
      expect(formatSizePair(mb + (mb * 24) ~/ 100, mb).first, '1.2 MB');
    });

    test('the whole part is grouped in threes', () {
      // 1 GB + 1 MB against 1 GB: equal at one decimal in GB, so MB is used.
      expect(formatSizePair(gb + mb, gb), (
        first: '1,025.0 MB',
        second: '1,024.0 MB',
      ));
    });

    test('two different sizes never look equal: smaller unit, then bytes', () {
      // 500 MB plus 100 KB: "500.1 MB" is still distinguishable.
      expect(formatSizePair(500 * mb + 100 * kb, 500 * mb), (
        first: '500.1 MB',
        second: '500.0 MB',
      ));
      // 500 MB plus 10 KB rounds to "500.0 MB": KB keeps them apart.
      expect(formatSizePair(500 * mb + 10 * kb, 500 * mb), (
        first: '512,010.0 KB',
        second: '512,000.0 KB',
      ));
      // One byte over: only exact bytes tell the two apart.
      expect(formatSizePair(500 * mb + 1, 500 * mb), (
        first: '524,288,001 bytes',
        second: '524,288,000 bytes',
      ));
      expect(formatSizePair(4 * kb + 1, 4 * kb), (
        first: '4,097 bytes',
        second: '4,096 bytes',
      ));
    });

    test('equal sizes are written once each, in the natural unit', () {
      expect(formatSizePair(4 * mb, 4 * mb), (
        first: '4.0 MB',
        second: '4.0 MB',
      ));
    });

    test('below 1 KB the sizes are whole bytes', () {
      expect(formatSizePair(1000, 900), (
        first: '1,000 bytes',
        second: '900 bytes',
      ));
      expect(formatSizePair(2, 1), (first: '2 bytes', second: '1 byte'));
    });
  });
}
