import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';
import 'package:pitaka/features/periodicals/infrastructure/periodical_mapper.dart';

/// The companion side of the periodical mapper: the invariants that must
/// hold at the single persistence choke point (ADR 0013 D2, D7). The row →
/// entity direction is covered end to end by the repository test.
void main() {
  test('refuses to build a companion without a uid (fail closed)', () {
    // The column is NOT NULL and every issue links to it; the repository
    // mints before persisting, so reaching the mapper without one is a bug
    // that must not become a stored blank.
    expect(() => const Periodical(title: 'A').toCompanion(), throwsStateError);
    expect(
      () => const Periodical(title: 'A', periodicalUid: '  ').toCompanion(),
      throwsStateError,
    );
  });

  test('stores tokens, the lowercase sort shadow and NULL for blanks', () {
    const periodical = Periodical(
      id: 7,
      periodicalUid: 'u-7',
      title: 'ಬಾಲಮಂಗಳ Bālamaṅgaḷa',
      issn: '   ',
      frequency: PeriodicalFrequency.fortnightly,
      sourceType: ItemSourceType.gift,
      ageGroup: AgeGroup.above6,
    );
    final companion = periodical.toCompanion();
    expect(companion.id, const Value(7));
    expect(companion.periodicalUid, const Value('u-7'));
    // Dart's Unicode-aware lowercasing, not SQLite's ASCII-only LOWER().
    expect(companion.titleSort, const Value('ಬಾಲಮಂಗಳ bālamaṅgaḷa'));
    expect(companion.issn, const Value<String?>(null), reason: 'blank → NULL');
    expect(companion.frequency, const Value<String?>('fortnightly'));
    expect(companion.sourceType, const Value<String?>('GIFT'));
    expect(companion.ageGroup, const Value<String?>('above-6'));
  });

  test('an unsaved row leaves the id absent so SQLite assigns one', () {
    final companion = const Periodical(
      title: 'A',
      periodicalUid: 'u',
      issn: '0317-8471',
    ).toCompanion();
    expect(companion.id.present, isFalse);
    expect(companion.issn, const Value<String?>('0317-8471'));
  });

  test('companion normalizes subscription days and preserves instants', () {
    final addedDate = DateTime(2026, 1, 10, 12, 34).millisecondsSinceEpoch;
    final removedAt = DateTime(2026, 1, 11, 13, 35).millisecondsSinceEpoch;
    final companion = Periodical(
      title: 'A',
      periodicalUid: 'u',
      subscriptionStart: DateTime(2026, 1, 15).millisecondsSinceEpoch,
      subscriptionEnd: DateTime(2026, 2, 15).millisecondsSinceEpoch,
      addedDate: addedDate,
      removedAt: removedAt,
    ).toCompanion();

    expect(
      companion.subscriptionStart.value,
      DateTime.utc(2026, 1, 15).millisecondsSinceEpoch,
    );
    expect(
      companion.subscriptionEnd.value,
      DateTime.utc(2026, 2, 15).millisecondsSinceEpoch,
    );
    expect(companion.addedDate.value, addedDate);
    expect(companion.removedAt.value, removedAt);
  });
}
