/// The words the add/edit forms show for the choices of their "Source" and
/// "Age group" dropdowns (presentation layer).
///
/// These two functions stood, word for word, at the end of three forms (the
/// book form, the other-item form and the magazine-title form). They live
/// here once, so the three forms cannot drift apart and each form file
/// stays under its size limit (review finding P4-M1, step 1: a move only,
/// no wording changed).
library;

import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';

/// The form's word for where an item came from ("Purchased", "Gift", …).
String itemSourceLabel(ItemSourceType type) => switch (type) {
  ItemSourceType.purchased => 'Purchased',
  ItemSourceType.gift => 'Gift',
  ItemSourceType.donated => 'Donated',
  ItemSourceType.inherited => 'Inherited',
  ItemSourceType.other => 'Other',
};

/// The form's word for a reader age band ("Ages 3+", …, "Advanced").
String ageGroupLabel(AgeGroup group) => switch (group) {
  AgeGroup.above3 => 'Ages 3+',
  AgeGroup.above6 => 'Ages 6+',
  AgeGroup.above10 => 'Ages 10+',
  AgeGroup.above15 => 'Ages 15+',
  AgeGroup.advanced => 'Advanced',
};
