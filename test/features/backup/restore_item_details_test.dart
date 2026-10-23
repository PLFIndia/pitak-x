import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/backup/infrastructure/item_details_archive_codec.dart';
import 'package:pitaka/features/backup/infrastructure/restore_item_details.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

/// The W2 join rules (ADR 0014): kinds apply by `bookUid`; issue entries join
/// before the catalogue write; every disagreement detaches to a plain book
/// and is counted — never guessed, never silent.
void main() {
  const book = CatalogueItem(id: 7, itemUid: 'uid-7', title: 'गोदान');
  const issueBase = CatalogueItem(id: 8, itemUid: 'uid-8', title: 'Issue row');
  const otherBase = CatalogueItem(id: 9, itemUid: 'uid-9', title: 'Carrom');
  const issue = IssueOf(periodicalUid: 'puid-1', volume: 249, issueNumber: 10);
  const series = Periodical(title: 'Chandamama', periodicalUid: 'puid-1');

  DecodedItemKinds kinds(Map<String, ItemKind> map, {int skipped = 0}) =>
      DecodedItemKinds(byUid: map, skipped: skipped);

  DecodedPeriodicals periodicals({
    List<Periodical> list = const [series],
    Map<String, IssueOf> issues = const {'uid-8': issue},
    int periodicalsDropped = 0,
    int issuesDropped = 0,
  }) => DecodedPeriodicals(
    periodicals: list,
    issuesByBookUid: issues,
    periodicalsDropped: periodicalsDropped,
    issuesDropped: issuesDropped,
  );

  test('no entries at all: every row stays a book, all counts zero', () {
    final r = applyRestoredItemDetails(
      books: const [book, issueBase],
      kinds: null,
      periodicals: null,
    );
    expect(r.books, const [book, issueBase]); // unchanged objects
    expect(r.periodicals, isEmpty);
    expect(r.kindsApplied, 0);
    expect(r.issuesLinked, 0);
    expect(r.issuesDetached, 0);
    expect(r.rowsSkippedUnknownKind, 0);
    expect(r.periodicalsDropped, 0);
  });

  test('kinds apply: other gets its marker, an issue links its details', () {
    final r = applyRestoredItemDetails(
      books: const [book, issueBase, otherBase],
      kinds: kinds(const {
        'uid-8': ItemKind.magazineIssue,
        'uid-9': ItemKind.other,
      }),
      periodicals: periodicals(),
    );
    expect(r.books[0].details, isNull); // listed nowhere ⇒ book (W2)
    expect(r.books[1].issue!.sameAs(issue), isTrue);
    expect(r.books[2].details, isA<OtherItemOf>());
    expect(r.kindsApplied, 2);
    expect(r.issuesLinked, 1);
    expect(r.issuesDetached, 0);
    expect(r.periodicals, const [series]);
  });

  test('a declared issue without an issues[] entry detaches to a book', () {
    final r = applyRestoredItemDetails(
      books: const [issueBase],
      kinds: kinds(const {'uid-8': ItemKind.magazineIssue}),
      periodicals: periodicals(issues: const {}),
    );
    expect(r.books.single.details, isNull);
    expect(r.kindsApplied, 0);
    expect(r.issuesDetached, 1);
  });

  test('an issues[] entry for a uid absent from books.db is detached', () {
    final r = applyRestoredItemDetails(
      books: const [book],
      kinds: kinds(const {}),
      periodicals: periodicals(issues: const {'uid-gone': issue}),
    );
    expect(r.books.single.details, isNull);
    expect(r.issuesLinked, 0);
    expect(r.issuesDetached, 1);
  });

  test('an issues[] entry whose uid declared another kind is dropped (W2)', () {
    final r = applyRestoredItemDetails(
      books: const [otherBase],
      kinds: kinds(const {'uid-9': ItemKind.other}),
      periodicals: periodicals(issues: const {'uid-9': issue}),
    );
    // The row is an "other"; the contradicting issue entry is dropped and
    // counted.
    expect(r.books.single.details, isA<OtherItemOf>());
    expect(r.kindsApplied, 1);
    expect(r.issuesLinked, 0);
    expect(r.issuesDetached, 1);
  });

  test('an issue whose series is not in the archive detaches (W1 orphan '
      'parity)', () {
    final r = applyRestoredItemDetails(
      books: const [issueBase],
      kinds: kinds(const {'uid-8': ItemKind.magazineIssue}),
      periodicals: periodicals(list: const []), // series absent
    );
    expect(r.books.single.details, isNull);
    expect(r.kindsApplied, 0);
    expect(r.issuesDetached, 1);
  });

  test('parse-time drops flow into the counts unchanged', () {
    final r = applyRestoredItemDetails(
      books: const [book],
      kinds: kinds(const {}, skipped: 3),
      periodicals: periodicals(
        issues: const {},
        periodicalsDropped: 2,
        issuesDropped: 4,
      ),
    );
    expect(r.rowsSkippedUnknownKind, 3);
    expect(r.periodicalsDropped, 2);
    expect(r.issuesDetached, 4);
  });

  test('a row without a uid can never be keyed — it stays a book', () {
    const uidless = CatalogueItem(id: 11, title: 'No uid');
    final r = applyRestoredItemDetails(
      books: const [uidless],
      kinds: kinds(const {'': ItemKind.other}),
      periodicals: null,
    );
    expect(r.books.single.details, isNull);
    expect(r.kindsApplied, 0);
  });
}
