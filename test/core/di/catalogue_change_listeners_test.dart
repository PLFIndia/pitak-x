// Review finding P3-M4 (ADR 0031; decisions D150, D151): everything that
// shows catalogue data listens to the app's "catalogue changed" signal, and
// NOT to the Library list's own state. Until November 2026 the list's state
// was that signal, so all of these read again whenever the user only
// scrolled the list or typed into its search box.
//
// Nine of the eleven listeners are held here, over one container. The
// borrowed-items snapshot and the availability updater need a vault and a
// lane; each has the same pair of checks in its own test file.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/catalogue_changes.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/application/issue_list_controller.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

import '../../features/periodicals/application/periodical_fakes.dart';
import '../../support/quiet_series_list.dart';

/// [FakeItems] plus the two reads of the chips and the export picker, each
/// written down in `calls` like the others.
class _Items extends FakeItems {
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async {
    calls.add('distinctLanguages');
    return right(const ['Hindi']);
  }

  @override
  Future<Either<Failure, List<String>>> distinctSourceDetails(
    ItemSourceType type,
  ) async {
    calls.add('distinctSourceDetails');
    return right(const []);
  }
}

void main() {
  late _Items items;
  late FakePeriodicals periodicals;
  late ProviderContainer container;
  late Periodical series;
  late CatalogueItem book;

  int itemCalls(String name) => items.calls.where((c) => c == name).length;
  int seriesCalls(String name) =>
      periodicals.calls.where((c) => c == name).length;

  /// The page reads of one series' issues (the series page's list).
  int issuePageReads() =>
      items.pagesSeen.where((p) => p.query.periodicalUid != null).length;

  /// Lets every rebuild that is due run, and its reads end.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await container.pump();
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    items = _Items();
    periodicals = FakePeriodicals();
    series = periodicals.seed(const Periodical(title: 'Frontline'));
    // 150 books, so that the Library list has pages to load.
    book = items.seed(const CatalogueItem(title: 'Book 1'));
    for (var i = 2; i <= 150; i++) {
      items.seed(CatalogueItem(title: 'Book $i'));
    }
    items.seed(
      CatalogueItem(
        title: 'Frontline 1',
        details: IssueOf(periodicalUid: series.periodicalUid!, issueNumber: 1),
      ),
    );
    container = ProviderContainer(
      overrides: [
        catalogueItemRepositoryProvider.overrideWith((ref) async => items),
        periodicalRepositoryProvider.overrideWith((ref) async => periodicals),
        settingsRepositoryProvider.overrideWith((ref) async => FakeSettings()),
        nowTickProvider.overrideWith((ref) => 0),
      ],
    );
    addTearDown(container.dispose);

    // Every listener is open at once, as a busy app has them: the Library
    // list with its chips, an item's page, a loan row, the export picker,
    // the Magazines list, a series page with its issues.
    final listeners = <ProviderSubscription<Object?>>[
      container.listen(libraryControllerProvider, (_, _) {}),
      container.listen(libraryLanguagesProvider, (_, _) {}),
      container.listen(
        librarySourceDetailsProvider(ItemSourceType.gift),
        (_, _) {},
      ),
      container.listen(catalogueItemByIdProvider(book.id), (_, _) {}),
      container.listen(bookTitleProvider(bookId: book.id), (_, _) {}),
      container.listen(periodicalsControllerProvider, (_, _) {}),
      container.listen(
        issueListControllerProvider(series.periodicalUid!),
        (_, _) {},
      ),
      container.listen(periodicalByIdProvider(series.id), (_, _) {}),
      container.listen(
        periodicalByUidProvider(series.periodicalUid!),
        (_, _) {},
      ),
      container.listen(periodicalCoversProvider, (_, _) {}),
    ];
    addTearDown(() {
      for (final listener in listeners) {
        listener.close();
      }
    });
    await container.read(libraryControllerProvider.future);
    await settle();
  });

  test('pages loaded and a letter typed, with nothing written: nobody but '
      'the list itself reads anything', () async {
    final itemCallsBefore = items.calls.length;
    final seriesCallsBefore = periodicals.calls.length;
    final issueReadsBefore = issuePageReads();

    final list = container.read(libraryControllerProvider.notifier);
    await list.loadMore();
    await settle();
    await list.loadMore();
    await settle();
    list.onQueryChanged('Book 1');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await container.read(libraryControllerProvider.future);
    await settle();

    // Two pages and one search: the list's own three reads, and no other.
    expect(items.calls.sublist(itemCallsBefore), ['page', 'page', 'page']);
    expect(issuePageReads(), issueReadsBefore);
    expect(periodicals.calls.sublist(seriesCallsBefore), isEmpty);
  });

  test('"changed" is said once: every listener reads again, and those '
      'that hear nothing else read exactly once', () async {
    final languages = itemCalls('distinctLanguages');
    final sourceDetails = itemCalls('distinctSourceDetails');
    final rowReads = itemCalls('getById');
    final issueReads = issuePageReads();
    final seriesLists = seriesCalls('listAll');
    final seriesById = seriesCalls('getById');
    final seriesByUid = seriesCalls('findByUid');

    container.read(catalogueChangesProvider.notifier).changed();
    await settle();

    expect(itemCalls('distinctLanguages'), languages + 1);
    expect(itemCalls('distinctSourceDetails'), sourceDetails + 1);
    // The item's page and the loan row's title: one read each.
    expect(itemCalls('getById'), rowReads + 2);
    expect(issuePageReads(), issueReads + 1);
    // These three also hear the Magazines list, whose state changes when it
    // is read again, so they may read more than once (a known limit, ADR
    // 0031). The Magazines list itself and the cover map read `listAll`.
    expect(seriesCalls('listAll'), greaterThanOrEqualTo(seriesLists + 2));
    expect(seriesCalls('getById'), greaterThan(seriesById));
    expect(seriesCalls('findByUid'), greaterThan(seriesByUid));
  });

  test('the three series providers hear "changed" themselves, not only '
      'through the Magazines list: one read each for one change', () async {
    final quiet = ProviderContainer(
      overrides: [
        catalogueItemRepositoryProvider.overrideWith((ref) async => items),
        periodicalRepositoryProvider.overrideWith((ref) async => periodicals),
        periodicalsControllerProvider.overrideWith(QuietSeriesList.new),
      ],
    );
    addTearDown(quiet.dispose);
    final listeners = <ProviderSubscription<Object?>>[
      quiet.listen(periodicalByIdProvider(series.id), (_, _) {}),
      quiet.listen(periodicalByUidProvider(series.periodicalUid!), (_, _) {}),
      quiet.listen(periodicalCoversProvider, (_, _) {}),
    ];
    addTearDown(() {
      for (final listener in listeners) {
        listener.close();
      }
    });
    Future<void> settleQuiet() async {
      for (var i = 0; i < 5; i++) {
        await quiet.pump();
        await Future<void>.delayed(Duration.zero);
      }
    }

    await settleQuiet();
    final seriesLists = seriesCalls('listAll');
    final seriesById = seriesCalls('getById');
    final seriesByUid = seriesCalls('findByUid');

    quiet.read(catalogueChangesProvider.notifier).changed();
    await settleQuiet();

    expect(seriesCalls('getById'), seriesById + 1);
    expect(seriesCalls('findByUid'), seriesByUid + 1);
    expect(seriesCalls('listAll'), seriesLists + 1);
  });
}
