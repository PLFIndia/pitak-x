import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/periodicals/application/add_issue_use_case.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

import '../periodical_test_data.dart';
import 'periodical_fakes.dart';

/// `AddIssueUseCase` (plan S12; ADR 0013 D1, D3, D4, D6): series lookup,
/// projection, the shared gate, the identity pre-check per issue shape, and
/// fail-closed behaviour on every read failure.
void main() {
  late FakePeriodicals periodicals;
  late FakeItems items;
  late AddIssueUseCase useCase;
  late Periodical series;
  late String uid;

  final oct2026 = DateTime(2026, 10);
  final sep2027 = DateTime(2027, 9);

  setUp(() {
    periodicals = FakePeriodicals();
    items = FakeItems();
    useCase = AddIssueUseCase(periodicals: periodicals, items: items);
    series = periodicals.seed(
      periodicalFixture(
        periodicalUid: null,
        title: 'Chandamama',
        titleTransliteration: 'Chandamama',
        publisher: 'House',
        language: 'Telugu',
        ageGroup: AgeGroup.above6,
      ),
    );
    uid = series.periodicalUid!;
  });

  /// What a form hands in: the issue's own fields plus the series link. The
  /// title is deliberately blank — it is projected, never typed.
  CatalogueItem issue({
    String periodicalUid = '',
    int? volume,
    int? number,
    DateTime? date,
    DateTime? until,
    String? label,
  }) => issueFixture(
    title: '',
    periodicalUid: periodicalUid.isEmpty ? uid : periodicalUid,
    volume: volume,
    number: number,
    date: date,
    until: until,
    label: label,
    copyCount: 2,
    notes: 'own notes',
  );

  test('projects the series onto the row, validates, inserts', () async {
    final saved = ok(await useCase(issue(volume: 3, number: 1, date: oct2026)));
    expect(saved.id, isNot(CatalogueItem.emptyId));
    expect(saved.itemUid, isNotNull);
    expect(saved.kind, ItemKind.magazineIssue);
    expect(saved.title, 'Chandamama — Vol 3 No 1 (Oct 2026)');
    expect(saved.titleTransliteration, 'Chandamama — Vol 3 No 1 (Oct 2026)');
    expect(saved.publisher, 'House');
    expect(saved.language, 'Telugu');
    expect(saved.ageGroup, AgeGroup.above6);
    expect(saved.publishedYear, 2026);
    // The issue's own fields are kept.
    expect(saved.copyCount, 2);
    expect(saved.notes, 'own notes');
    expect(saved.issue?.volume, 3);
    expect(periodicals.calls, ['findByUid', 'findIssue']);
    expect(items.calls, ['insert']);
  });

  test('a bound volume composes the range title', () async {
    final saved = ok(await useCase(issue(date: oct2026, until: sep2027)));
    expect(saved.title, 'Chandamama — Oct 2026 – Sep 2027');
    expect(saved.issue?.isBound, isTrue);
    expect(periodicals.calls, ['findByUid', 'findBoundVolume']);
  });

  test('a date-only issue has no identity key: no lookup, inserted', () async {
    final saved = ok(await useCase(issue(date: oct2026)));
    expect(saved.title, 'Chandamama — Oct 2026');
    expect(periodicals.calls, ['findByUid']);
    expect(items.inserted, hasLength(1));
  });

  test(
    'normalizes a legacy day before projecting its title and year',
    () async {
      final legacyJanuary = DateTime(2026, 1, 15);
      final legacyInput = issue().copyWith(
        details: IssueOf(
          periodicalUid: uid,
          issueDate: legacyJanuary.millisecondsSinceEpoch,
        ),
      );

      final saved = ok(await useCase(legacyInput));

      expect(saved.title, 'Chandamama — Jan 2026');
      expect(saved.titleTransliteration, 'Chandamama — Jan 2026');
      expect(saved.publishedYear, 2026);
      expect(
        saved.issue!.issueDate,
        DateTime.utc(2026, 1, 15).millisecondsSinceEpoch,
      );
    },
  );

  test('a non-issue item is a caller bug: UnexpectedFailure', () async {
    final failure = failureOf(
      await useCase(const CatalogueItem(title: 'A novel')),
    );
    expect(failure, isA<UnexpectedFailure>());
    expect(periodicals.calls, isEmpty);
    expect(items.calls, isEmpty);
  });

  test('an unknown series is a ValidationFailure', () async {
    final failure = failureOf(
      await useCase(issue(periodicalUid: 'nope', number: 1)),
    );
    expect(failure, isA<ValidationFailure>());
    expect(
      (failure as ValidationFailure).message,
      'The magazine title no longer exists.',
    );
    expect(items.calls, isEmpty);
  });

  test('a failed series lookup aborts the add (fail closed)', () async {
    periodicals.findByUidFailure = const StorageFailure('db closed');
    final failure = failureOf(await useCase(issue(number: 1)));
    expect(failure, isA<StorageFailure>());
    expect(items.calls, isEmpty);
  });

  test('the gate rejects an issue without a number or a date', () async {
    final failure = failureOf(await useCase(issue(volume: 3)));
    expect(failure, isA<ValidationFailure>());
    expect(
      (failure as ValidationFailure).message,
      'An issue number or an issue date is required.',
    );
    expect(periodicals.calls, ['findByUid'], reason: 'no identity lookup');
    expect(items.calls, isEmpty);
  });

  test('the gate rejects a bound volume whose range runs backwards', () async {
    final failure = failureOf(
      await useCase(issue(date: sep2027, until: oct2026)),
    );
    expect(failure, isA<ValidationFailure>());
    expect(
      (failure as ValidationFailure).message,
      'The last issue date must not be before the first issue date.',
    );
    expect(items.calls, isEmpty);
  });

  test("the gate rejects the issue's own invalid fields too", () async {
    final failure = failureOf(
      await useCase(issue(number: 1).copyWith(copyCount: 0)),
    );
    expect(failure, isA<ValidationFailure>());
    expect(
      (failure as ValidationFailure).message,
      'Copies must be at least 1.',
    );
  });

  test('a numbered duplicate is refused, naming the existing row', () async {
    final existing = items.seed(
      issueFixture(
        title: 'Chandamama — Vol 3 No 1',
        periodicalUid: uid,
        volume: 3,
        number: 1,
      ),
    );
    periodicals.issues[uid] = [existing];
    final failure = failureOf(await useCase(issue(volume: 3, number: 1)));
    expect(failure, isA<DuplicateIssueFailure>());
    failure as DuplicateIssueFailure;
    expect(failure.existingTitle, 'Chandamama — Vol 3 No 1');
    expect(failure.existingItemId, existing.id);
    expect(items.calls, isEmpty);
  });

  test('a null volume and volume 0 are the same key (D6)', () async {
    periodicals.issues[uid] = [
      items.seed(issueFixture(title: 'No 5', periodicalUid: uid, number: 5)),
    ];
    // Same number, no volume on either side → duplicate; another number
    // or another volume → a new issue.
    expect(
      failureOf(await useCase(issue(number: 5))),
      isA<DuplicateIssueFailure>(),
    );
    ok(await useCase(issue(number: 6)));
    ok(await useCase(issue(volume: 1, number: 5)));
  });

  test('a bound duplicate is refused on its date range', () async {
    periodicals.issues[uid] = [
      items.seed(
        issueFixture(
          title: 'bound',
          periodicalUid: uid,
          date: oct2026,
          until: sep2027,
        ),
      ),
    ];
    expect(
      failureOf(await useCase(issue(date: oct2026, until: sep2027))),
      isA<DuplicateIssueFailure>(),
    );
    // A single issue on the first date is a different thing (D6: bound
    // volumes never answer the numbered/date key and vice versa).
    ok(await useCase(issue(date: oct2026)));
  });

  test('a failed identity pre-check aborts the add (fail closed)', () async {
    periodicals.findIssueFailure = const StorageFailure('db closed');
    final failure = failureOf(await useCase(issue(number: 1)));
    expect(failure, isA<StorageFailure>());
    expect(items.calls, isEmpty, reason: 'insert must not be attempted');

    periodicals
      ..findIssueFailure = null
      ..findBoundVolumeFailure = const StorageFailure('db closed');
    expect(
      failureOf(await useCase(issue(date: oct2026, until: sep2027))),
      isA<StorageFailure>(),
    );
    expect(items.calls, isEmpty);
  });

  test('the repository failure is returned unchanged', () async {
    items.insertFailure = const DuplicateIssueFailure(existingTitle: 'race');
    final failure = failureOf(await useCase(issue(number: 1)));
    expect(failure, isA<DuplicateIssueFailure>());
    expect((failure as DuplicateIssueFailure).existingTitle, 'race');
  });
}
