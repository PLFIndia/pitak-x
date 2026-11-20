/// Pins the words of the forms' "Source" and "Age group" choices.
///
/// The two functions were moved out of three forms into one file (review
/// finding P4-M1, step 1). The move must not change a word: every value of
/// both enums is listed here with the label the forms showed before.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/presentation/widgets/catalogue_choice_labels.dart';

void main() {
  test('every source has the word the forms showed before the move', () {
    expect(
      {for (final type in ItemSourceType.values) type: itemSourceLabel(type)},
      {
        ItemSourceType.purchased: 'Purchased',
        ItemSourceType.gift: 'Gift',
        ItemSourceType.donated: 'Donated',
        ItemSourceType.inherited: 'Inherited',
        ItemSourceType.other: 'Other',
      },
    );
  });

  test('every age group has the word the forms showed before the move', () {
    expect(
      {for (final group in AgeGroup.values) group: ageGroupLabel(group)},
      {
        AgeGroup.above3: 'Ages 3+',
        AgeGroup.above6: 'Ages 6+',
        AgeGroup.above10: 'Ages 10+',
        AgeGroup.above15: 'Ages 15+',
        AgeGroup.advanced: 'Advanced',
      },
    );
  });
}
