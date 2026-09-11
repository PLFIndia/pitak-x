import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';

void main() {
  group('CatalogueRules primitives (M15)', () {
    test('maxDateMillis matches the Rust core bound', () {
      // rust/src/api.rs MAX_DATE_MILLIS — the two trusted cores must agree.
      expect(CatalogueRules.maxDateMillis, 8640000000000000);
    });

    test('isValidDateMillis: 0 is the unset sentinel, bounds inclusive', () {
      expect(CatalogueRules.isValidDateMillis(0), isTrue); // unset
      expect(CatalogueRules.isValidDateMillis(1), isTrue);
      expect(
        CatalogueRules.isValidDateMillis(CatalogueRules.maxDateMillis),
        isTrue,
      );
      expect(
        CatalogueRules.isValidDateMillis(CatalogueRules.maxDateMillis + 1),
        isFalse,
      );
      expect(CatalogueRules.isValidDateMillis(-1), isFalse);
    });

    test('isValidOptionalDateMillis: null or valid', () {
      expect(CatalogueRules.isValidOptionalDateMillis(null), isTrue);
      expect(CatalogueRules.isValidOptionalDateMillis(0), isTrue);
      expect(CatalogueRules.isValidOptionalDateMillis(-5), isFalse);
      expect(
        CatalogueRules.isValidOptionalDateMillis(
          CatalogueRules.maxDateMillis + 1,
        ),
        isFalse,
      );
    });

    test('isValidYear: 1..9999', () {
      expect(CatalogueRules.isValidYear(null), isTrue);
      expect(CatalogueRules.isValidYear(1), isTrue);
      expect(CatalogueRules.isValidYear(1936), isTrue);
      expect(CatalogueRules.isValidYear(9999), isTrue);
      expect(CatalogueRules.isValidYear(0), isFalse);
      expect(CatalogueRules.isValidYear(-1), isFalse);
      expect(CatalogueRules.isValidYear(10000), isFalse);
    });

    test('isValidCount: null or ≥ 1', () {
      expect(CatalogueRules.isValidCount(null), isTrue);
      expect(CatalogueRules.isValidCount(1), isTrue);
      expect(CatalogueRules.isValidCount(0), isFalse);
      expect(CatalogueRules.isValidCount(-3), isFalse);
    });

    test('isValidPrice: null or finite ≥ 0', () {
      expect(CatalogueRules.isValidPrice(null), isTrue);
      expect(CatalogueRules.isValidPrice(0), isTrue);
      expect(CatalogueRules.isValidPrice(12.5), isTrue);
      expect(CatalogueRules.isValidPrice(-0.01), isFalse);
      expect(CatalogueRules.isValidPrice(double.nan), isFalse);
      expect(CatalogueRules.isValidPrice(double.infinity), isFalse);
      expect(CatalogueRules.isValidPrice(double.negativeInfinity), isFalse);
    });

    test('dateFromMillisOrNull: invalid and unset → null, valid → DateTime', () {
      // Display/export guard for rows persisted before M15: rendering must
      // never throw on an out-of-range legacy value.
      expect(CatalogueRules.dateFromMillisOrNull(0), isNull);
      expect(CatalogueRules.dateFromMillisOrNull(-1), isNull);
      expect(
        CatalogueRules.dateFromMillisOrNull(CatalogueRules.maxDateMillis + 1),
        isNull,
      );
      expect(
        CatalogueRules.dateFromMillisOrNull(1699999999000),
        DateTime.fromMillisecondsSinceEpoch(1699999999000),
      );
      expect(
        CatalogueRules.dateFromMillisOrNull(CatalogueRules.maxDateMillis),
        isNotNull,
      );
    });

    test('isValidFieldText: null or within the cap', () {
      expect(CatalogueRules.isValidFieldText(null), isTrue);
      expect(CatalogueRules.isValidFieldText(''), isTrue);
      expect(
        CatalogueRules.isValidFieldText('x' * CatalogueRules.maxFieldChars),
        isTrue,
      );
      expect(
        CatalogueRules.isValidFieldText(
          'x' * (CatalogueRules.maxFieldChars + 1),
        ),
        isFalse,
      );
    });
  });
}
