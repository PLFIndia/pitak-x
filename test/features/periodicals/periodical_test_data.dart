import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/calendar_date.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';

/// Builds a series with explicit identity, ISSN, cover and calendar inputs.
///
/// Tests pass `null` as `periodicalUid` when they want the repository to mint
/// an identity. Date-only DateTime inputs contribute calendar FIELDS and are
/// stored at UTC midnight; addedDate/removedAt remain raw instants. Tests of
/// legacy conversion deliberately construct noncanonical values themselves.
int? _calendarDayMillis(DateTime? value) =>
    value == null ? null : CalendarDate.fromPickerDate(value).epochMillis;
Periodical periodicalFixture({
  int id = Periodical.emptyId,
  String? periodicalUid = 'periodical-1',
  String title = 'Frontline',
  String? titleTransliteration,
  String? issn,
  String? publisher,
  String? language,
  String? coverUrl,
  PeriodicalFrequency? frequency,
  DateTime? subscriptionStart,
  DateTime? subscriptionEnd,
  String? location,
  AgeGroup? ageGroup,
  int addedDate = 0,
  bool removed = false,
  int? removedAt,
  String? addedBy,
}) {
  return Periodical(
    id: id,
    periodicalUid: periodicalUid,
    title: title,
    titleTransliteration: titleTransliteration,
    issn: issn,
    publisher: publisher,
    language: language,
    coverUrl: coverUrl,
    frequency: frequency,
    subscriptionStart: _calendarDayMillis(subscriptionStart),
    subscriptionEnd: _calendarDayMillis(subscriptionEnd),
    location: location,
    ageGroup: ageGroup,
    addedDate: addedDate,
    removed: removed,
    removedAt: removedAt,
    addedBy: addedBy,
  );
}

/// Builds an issue with its D6 identity fields and calendar dates in one place.
CatalogueItem issueFixture({
  int id = CatalogueItem.emptyId,
  String? itemUid,
  String title = 'Frontline — test issue',
  String periodicalUid = 'periodical-1',
  int? volume,
  int? number,
  DateTime? date,
  DateTime? until,
  String? label,
  String? publisher,
  String? language,
  String? coverUrl,
  String? notes,
  int? publishedYear,
  int addedDate = 1,
  int copyCount = 1,
}) {
  return CatalogueItem(
    id: id,
    itemUid: itemUid,
    title: title,
    publisher: publisher,
    language: language,
    coverUrl: coverUrl,
    notes: notes,
    publishedYear: publishedYear,
    addedDate: addedDate,
    copyCount: copyCount,
    details: IssueOf(
      periodicalUid: periodicalUid,
      volume: volume,
      issueNumber: number,
      issueDate: _calendarDayMillis(date),
      boundUntil: _calendarDayMillis(until),
      label: label,
    ),
  );
}
