/// Ingress validation for an authoritative merge OVERWRITE (application
/// layer). Parser-produced decisions are validated already, but the public
/// `applyOverwrite` boundary also accepts directly constructed decisions.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

/// Canonical collections accepted for an authoritative replacement.
typedef ValidatedMergeOverwrite = ({
  List<CatalogueItem> items,
  List<Periodical> periodicals,
});

/// Validates and normalizes every incoming row before ANY existing row is
/// deleted. Instant fields pass through their domain gates unchanged; issue
/// and subscription calendar days become canonical UTC-midnight values.
Either<Failure, ValidatedMergeOverwrite> validateMergeOverwrite(
  List<CatalogueItem> items,
  List<Periodical> periodicals,
) {
  final validPeriodicals = <Periodical>[];
  for (final periodical in periodicals) {
    final result = Periodical.validate(periodical);
    final errors = result.getLeft().toNullable();
    if (errors != null) {
      return left(ValidationFailure(errors.first.userMessage));
    }
    validPeriodicals.add(result.toNullable()!);
  }

  final validItems = <CatalogueItem>[];
  for (final item in items) {
    final result = CatalogueItem.validate(item);
    final errors = result.getLeft().toNullable();
    if (errors != null) {
      return left(ValidationFailure(errors.first.userMessage));
    }
    validItems.add(result.toNullable()!);
  }
  return right((items: validItems, periodicals: validPeriodicals));
}
