import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/application/update_issue_use_case.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

import 'periodical_fakes.dart';

/// `UpdateIssueUseCase` (plan S12; ADR 0013 D3, D6, D8): the stored row must
/// exist and already be an issue (no kind change), the inherited fields are
/// re-projected from the series the edited row names, and the identity
/// pre-check ignores the row's own key.
void main() {
  late FakePeriodicals periodicals;
  late FakeItems items;
  late UpdateIssueUseCase useCase;
  late Periodical series;
  late String uid;

  final oct2026 = DateTime(2026, 10).millisecondsSinceEpoch;

  setUp(() {
    periodicals = FakePeriodicals();
    items = FakeItems();
    useCase = UpdateIssueUseCase(periodicals: periodicals, items: items);
    series = periodicals.seed(
      const Periodical(title: 'Chandamama', publisher: 'House'),
    );
    uid = series.periodicalUid!;
  });

  /// A stored issue of [series], listed by the periodical fake too.
  CatalogueItem storedIssue({
    String? periodicalUid,
    int? volume,
    int? number,
    int? date,
    int? until,
  }) {
    final row = items.seed(
      CatalogueItem(
        title: 'Chandamama — stored',
        publisher: 'House',
        addedDate: 1,
        details: IssueOf(
          periodicalUid: periodicalUid ?? uid,
          volume: volume,
          issueNumber: number,
          issueDate: date,
          boundUntil: until,
        ),
      ),
    );
    periodicals.issues.putIfAbsent(periodicalUid ?? uid, () => []).add(row);
    return row;
  }

  test('re-projects and updates a stored issue', () async {
    final stored = storedIssue(number: 1);
    final edited = stored.copyWith(
      notes: 'edited',
      details: IssueOf(periodicalUid: uid, issueNumber: 1, issueDate: oct2026),
    );
    final saved = ok(await useCase(edited));
    expect(saved.id, stored.id);
    expect(saved.itemUid, stored.itemUid);
    expect(saved.title, 'Chandamama — No 1 (Oct 2026)');
    expect(saved.publishedYear, 2026);
    expect(saved.notes, 'edited');
    expect(items.calls, ['getById', 'update']);
    expect(periodicals.calls, ['findByUid', 'findIssue']);
  });

  test('an unpersisted item (emptyId) is NotFound; no store access', () async {
    final failure = failureOf(
      await useCase(
        CatalogueItem(
          title: '',
          details: IssueOf(periodicalUid: uid, issueNumber: 1),
        ),
      ),
    );
    expect(failure, isA<NotFoundFailure>());
    expect(items.calls, isEmpty);
    expect(periodicals.calls, isEmpty);
  });

  test('a vanished row is NotFound', () async {
    final failure = failureOf(
      await useCase(
        CatalogueItem(
          id: 404,
          title: '',
          details: IssueOf(periodicalUid: uid, issueNumber: 1),
        ),
      ),
    );
    expect(failure, isA<NotFoundFailure>());
    expect(items.calls, ['getById']);
  });

  test('a failed row read aborts the edit (fail closed)', () async {
    final stored = storedIssue(number: 1);
    items.getByIdFailure = const StorageFailure('db closed');
    final failure = failureOf(await useCase(stored.copyWith(notes: 'x')));
    expect(failure, isA<StorageFailure>());
    expect(items.updated, isEmpty);
  });

  test('refuses to turn a book into an issue (D8: no kind change)', () async {
    final book = items.seed(const CatalogueItem(title: 'A novel'));
    final failure = failureOf(
      await useCase(
        book.copyWith(details: IssueOf(periodicalUid: uid, issueNumber: 1)),
      ),
    );
    expect(failure, isA<ValidationFailure>());
    expect((failure as ValidationFailure).message, contains('kind'));
    expect(items.updated, isEmpty);
    expect(periodicals.calls, isEmpty, reason: 'refused before any lookup');
  });

  test('refuses to turn an "other" item into an issue', () async {
    final other = items.seed(
      const CatalogueItem(title: 'Board game', details: OtherItemOf()),
    );
    final failure = failureOf(
      await useCase(
        other.copyWith(details: IssueOf(periodicalUid: uid, issueNumber: 1)),
      ),
    );
    expect(failure, isA<ValidationFailure>());
    expect(items.updated, isEmpty);
  });

  test('a stored issue edited as a non-issue is a caller bug', () async {
    final stored = storedIssue(number: 1);
    // `copyWith` cannot drop details; a hand-built row without them can.
    final failure = failureOf(
      await useCase(CatalogueItem(id: stored.id, title: 'typed title')),
    );
    expect(failure, isA<UnexpectedFailure>());
    expect(items.updated, isEmpty);
  });

  test('an unknown series is a ValidationFailure', () async {
    final stored = storedIssue(number: 1);
    final failure = failureOf(
      await useCase(
        stored.copyWith(
          details: const IssueOf(periodicalUid: 'nope', issueNumber: 1),
        ),
      ),
    );
    expect(failure, isA<ValidationFailure>());
    expect(
      (failure as ValidationFailure).message,
      'The magazine title no longer exists.',
    );
    expect(items.updated, isEmpty);
  });

  test('the gate rejects an invalid edit', () async {
    final stored = storedIssue(number: 1);
    final failure = failureOf(
      await useCase(
        stored.copyWith(details: IssueOf(periodicalUid: uid, volume: 0)),
      ),
    );
    expect(failure, isA<ValidationFailure>());
    expect(items.updated, isEmpty);
  });

  test("keeping the row's own identity key is no collision", () async {
    final stored = storedIssue(volume: 2, number: 1);
    final saved = ok(await useCase(stored.copyWith(notes: 'still No 1')));
    expect(saved.notes, 'still No 1');
    expect(periodicals.calls, contains('findIssue'));
  });

  test("moving onto ANOTHER row's key is DuplicateIssueFailure", () async {
    final other = storedIssue(volume: 2, number: 2);
    final mine = storedIssue(volume: 2, number: 1);
    final failure = failureOf(
      await useCase(
        mine.copyWith(
          details: IssueOf(periodicalUid: uid, volume: 2, issueNumber: 2),
        ),
      ),
    );
    expect(failure, isA<DuplicateIssueFailure>());
    expect((failure as DuplicateIssueFailure).existingItemId, other.id);
    expect(items.updated, isEmpty);
  });

  test(
    'a bound volume is checked on its date range, excluding itself',
    () async {
      final until = DateTime(2027, 9).millisecondsSinceEpoch;
      final mine = storedIssue(date: oct2026, until: until);
      ok(await useCase(mine.copyWith(notes: 'same range')));
      expect(periodicals.calls, contains('findBoundVolume'));
    },
  );

  test('moving an issue to another series re-projects from it', () async {
    final otherSeries = periodicals.seed(
      const Periodical(title: 'Balamitra', publisher: 'Other House'),
    );
    final otherUid = otherSeries.periodicalUid!;
    // Balamitra already has a No 1, so the move must pick a free number.
    storedIssue(periodicalUid: otherUid, number: 1);
    final mine = storedIssue(number: 1);

    final clash = failureOf(
      await useCase(
        mine.copyWith(
          details: IssueOf(periodicalUid: otherUid, issueNumber: 1),
        ),
      ),
    );
    expect(clash, isA<DuplicateIssueFailure>());

    final moved = ok(
      await useCase(
        mine.copyWith(
          details: IssueOf(periodicalUid: otherUid, issueNumber: 2),
        ),
      ),
    );
    expect(moved.title, 'Balamitra — No 2');
    expect(moved.publisher, 'Other House');
    expect(moved.issue?.periodicalUid, otherUid);
  });

  test('a failed identity pre-check aborts the edit (fail closed)', () async {
    final stored = storedIssue(number: 1);
    periodicals.findIssueFailure = const StorageFailure('db closed');
    final failure = failureOf(await useCase(stored.copyWith(notes: 'x')));
    expect(failure, isA<StorageFailure>());
    expect(items.updated, isEmpty);
  });

  test('the repository failure is returned unchanged', () async {
    final stored = storedIssue(number: 1);
    items
      ..failUpdateAt = 1
      ..updateFailure = const UnsupportedItemKindFailure('future-kind');
    final failure = failureOf(await useCase(stored.copyWith(notes: 'x')));
    expect(failure, isA<UnsupportedItemKindFailure>());
  });
}
