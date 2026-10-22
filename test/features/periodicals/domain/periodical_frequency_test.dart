import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';

void main() {
  group('PeriodicalFrequency', () {
    test('tokens round-trip, are distinct and lower-case letters only', () {
      final safe = RegExp(r'^[a-z]+$');
      for (final f in PeriodicalFrequency.values) {
        expect(PeriodicalFrequency.fromToken(f.token), f);
        expect(safe.hasMatch(f.token), isTrue, reason: f.token);
      }
      expect(
        PeriodicalFrequency.values.map((f) => f.token).toSet(),
        hasLength(PeriodicalFrequency.values.length),
      );
    });

    test('fromToken is tolerant; unknown/blank → null', () {
      expect(
        PeriodicalFrequency.fromToken(' Monthly '),
        PeriodicalFrequency.monthly,
      );
      expect(
        PeriodicalFrequency.fromToken('QUARTERLY'),
        PeriodicalFrequency.quarterly,
      );
      expect(PeriodicalFrequency.fromToken('daily'), isNull);
      expect(PeriodicalFrequency.fromToken(''), isNull);
      expect(PeriodicalFrequency.fromToken(null), isNull);
    });

    test('every cadence except irregular has exactly one kind of step', () {
      for (final f in PeriodicalFrequency.values) {
        if (f == PeriodicalFrequency.irregular) {
          expect(f.hasStep, isFalse);
          expect(f.days, isNull);
          expect(f.months, isNull);
        } else {
          expect(f.hasStep, isTrue, reason: f.token);
          expect(
            (f.days == null) != (f.months == null),
            isTrue,
            reason: f.token,
          );
        }
      }
      expect(PeriodicalFrequency.weekly.days, 7);
      expect(PeriodicalFrequency.fortnightly.days, 14);
      expect(PeriodicalFrequency.monthly.months, 1);
      expect(PeriodicalFrequency.bimonthly.months, 2);
      expect(PeriodicalFrequency.quarterly.months, 3);
      expect(PeriodicalFrequency.annual.months, 12);
    });

    test('labels are non-empty and distinct', () {
      final labels = PeriodicalFrequency.values.map((f) => f.label).toSet();
      expect(labels, hasLength(PeriodicalFrequency.values.length));
      expect(labels.any((l) => l.trim().isEmpty), isFalse);
    });
  });
}
