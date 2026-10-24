/// `IssueListController` (plan S13): a series page is the catalogue narrowed
/// to one `periodicalUid` — ONE paged read through
/// `CatalogueItemRepository.page` (N10-d, ADR 0013 U2) whose rows reach the
/// UI verbatim (the repository owns the issue order), re-read on the
/// catalogue mutation signal to the depth the user had scrolled to (D2-b).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/application/library_window.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/application/issue_list_controller.dart';

import 'periodical_fakes.dart';

void main() {
  const uid = 'series-a';
  const otherUid = 'series-b';
  const day = 24 * 60 * 60 * 1000;

  late FakeItems items;

  setUp(() => items = FakeItems());

  /// Seeds [n] issues of [periodicalUid], numbered 1..n, dated one day apart
  /// (so the newest-first order the fake applies is observable).
  void seedIssues(String periodicalUid, int n) {
    for (var i = 1; i <= n; i++) {
      items.seed(
        CatalogueItem(
          title: '$periodicalUid — No $i',
          details: IssueOf(
            periodicalUid: periodicalUid,
            issueNumber: i,
            issueDate: i * day,
          ),
        ),
      );
    }
  }

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        catalogueItemRepositoryProvider.overrideWith((ref) async => items),
        settingsRepositoryProvider.overrideWith((ref) async => FakeSettings()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Keeps the family instance alive (autoDispose) and awaits its build.
  Future<LibraryWindow> load(ProviderContainer c, String periodicalUid) {
    final sub = c.listen(issueListControllerProvider(periodicalUid), (_, _) {});
    addTearDown(sub.close);
    return c.read(issueListControllerProvider(periodicalUid).future);
  }

  /// The page reads the SERIES list asked for (the watched library
  /// controller pages the whole catalogue through the same fake).
  List<({LibraryQuery query, int limit, int offset})> seriesReads() =>
      items.pagesSeen.where((p) => p.query.periodicalUid == uid).toList();

  test('build asks for ONE page of the series (facet set, no text, no '
      'kind) and shows the repository rows verbatim', () async {
    seedIssues(uid, 3);
    seedIssues(otherUid, 2);
    items.seed(const CatalogueItem(title: 'A book'));

    final window = await load(makeContainer(), uid);

    // The watched library controller settles (loading → data) during the
    // first open, which re-runs build once more; every read has the same
    // shape and the N05 revision guard makes the superseded one harmless.
    expect(seriesReads(), isNotEmpty);
    for (final read in seriesReads()) {
      expect(read.query.periodicalUid, uid);
      expect(read.query.text, '');
      expect(read.query.kind, isNull);
      expect(read.query.language, isNull);
      expect(read.limit, libraryPageSize);
      expect(read.offset, 0);
    }
    expect(window.books.map((b) => b.issue!.issueNumber), [3, 2, 1]);
    expect(window.books.every((b) => b.issue!.periodicalUid == uid), isTrue);
    expect(window.hasMore, isFalse);
    expect(window.isLoadingMore, isFalse);
  });

  test('loadMore appends the next page at offset = rows shown', () async {
    seedIssues(uid, libraryPageSize + 5);
    final container = makeContainer();
    final first = await load(container, uid);
    expect(first.books, hasLength(libraryPageSize));
    expect(first.hasMore, isTrue);

    await container.read(issueListControllerProvider(uid).notifier).loadMore();

    final second = seriesReads().last;
    expect(second.offset, libraryPageSize);
    expect(second.limit, libraryPageSize);
    final window = container.read(issueListControllerProvider(uid)).value!;
    expect(window.books, hasLength(libraryPageSize + 5));
    expect(window.hasMore, isFalse);
    expect(window.isLoadingMore, isFalse);
    // Still newest first across the page seam.
    final numbers = window.books.map((b) => b.issue!.issueNumber!).toList();
    expect(numbers, List.generate(numbers.length, (i) => numbers.length - i));
  });

  test('D2-b: the catalogue mutation signal reloads the rows the user had '
      'already scrolled to, in ONE read', () async {
    seedIssues(uid, libraryPageSize + 5);
    final container = makeContainer();
    await load(container, uid);
    await container.read(issueListControllerProvider(uid).notifier).loadMore();
    final readsBefore = seriesReads().length;

    // An issue is added elsewhere; every write path fires this signal.
    items.seed(
      const CatalogueItem(
        title: 'new',
        details: IssueOf(
          periodicalUid: uid,
          issueNumber: 999,
          issueDate: 999 * day,
        ),
      ),
    );
    await container.read(libraryControllerProvider.notifier).refresh();
    final window = await container.read(
      issueListControllerProvider(uid).future,
    );

    expect(seriesReads().length, greaterThan(readsBefore));
    expect(
      seriesReads().skip(readsBefore).every((r) => r.offset == 0),
      isTrue,
      reason: 'a reload starts at the head',
    );
    expect(
      seriesReads().last.limit,
      libraryPageSize + 5,
      reason: 'to the depth already loaded, not one page',
    );
    // The depth is "rows the user had scrolled to": the new row pushes the
    // last one past the window, and the store says more exists.
    expect(window.books.first.issue!.issueNumber, 999);
    expect(window.books, hasLength(libraryPageSize + 5));
    expect(window.hasMore, isTrue);
  });

  test('a failed first page surfaces AsyncError(Failure)', () async {
    items.pageFailure = const StorageFailure('disk gone');
    final container = makeContainer();
    final sub = container.listen(issueListControllerProvider(uid), (_, _) {});
    addTearDown(sub.close);

    await expectLater(
      container.read(issueListControllerProvider(uid).future),
      throwsA(isA<StorageFailure>()),
    );
    expect(
      container.read(issueListControllerProvider(uid)).error,
      isA<StorageFailure>(),
    );
  });

  test('a failed loadMore keeps the rows already shown and clears the '
      'in-flight flag', () async {
    seedIssues(uid, libraryPageSize + 5);
    final container = makeContainer();
    final first = await load(container, uid);

    items.pageFailure = const StorageFailure('disk gone');
    await container.read(issueListControllerProvider(uid).notifier).loadMore();

    final state = container.read(issueListControllerProvider(uid));
    expect(state.hasError, isFalse);
    expect(state.value!.books, hasLength(first.books.length));
    expect(state.value!.isLoadingMore, isFalse);
    expect(state.value!.hasMore, isTrue, reason: 'scrolling again retries');
  });

  test('family instances are independent per series', () async {
    seedIssues(uid, 2);
    seedIssues(otherUid, 1);
    final container = makeContainer();

    final a = await load(container, uid);
    final b = await load(container, otherUid);

    expect(a.books.map((x) => x.issue!.periodicalUid).toSet(), {uid});
    expect(b.books.map((x) => x.issue!.periodicalUid).toSet(), {otherUid});
  });
}
