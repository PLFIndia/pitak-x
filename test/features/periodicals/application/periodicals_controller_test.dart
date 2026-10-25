/// `PeriodicalsController` (plan S13): the Magazines page state is every
/// series with its issue summary and a subscription status DERIVED from the
/// injected clock (ADR 0013 D5) — never stored. Writes fail closed (§5):
/// a repository Left becomes `AsyncError`, never a silent "success" refresh;
/// a delete REFUSAL is returned to the caller and leaves the list intact.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/calendar_date.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/application/delete_periodical_use_case.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/subscription_status.dart';

import 'periodical_fakes.dart';

void main() {
  final t0 = DateTime(2026, 10, 23, 12).millisecondsSinceEpoch;
  final today = CalendarDate.fromPickerDate(DateTime(2026, 10, 23, 12));
  int dayFromToday(int offset) => today.addDays(offset).epochMillis;
  const day = 24 * 60 * 60 * 1000;

  late FakePeriodicals periodicals;
  late List<String?> releasedCovers;
  late int now;

  setUp(() {
    periodicals = FakePeriodicals();
    releasedCovers = [];
    now = t0;
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        periodicalRepositoryProvider.overrideWith((ref) async => periodicals),
        // S9: the Magazines list also watches the library mutation signal.
        // Keep that provider on explicit in-memory dependencies in unit tests.
        catalogueItemRepositoryProvider.overrideWith(
          (ref) async => FakeItems(),
        ),
        settingsRepositoryProvider.overrideWith((ref) async => FakeSettings()),
        // A fixed value except in the tick test, which advances `now` before
        // invalidating so the watched value actually changes.
        nowTickProvider.overrideWith((ref) => now),
        clockProvider.overrideWithValue(() => now),
        deletePeriodicalUseCaseProvider.overrideWith(
          (ref) async => DeletePeriodicalUseCase(
            periodicals: periodicals,
            releaseCover: (ref) async => releasedCovers.add(ref),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Keeps the controller alive (autoDispose) and awaits its first build.
  Future<List<PeriodicalListEntry>> load(ProviderContainer c) {
    final sub = c.listen(periodicalsControllerProvider, (_, _) {});
    addTearDown(sub.close);
    return c.read(periodicalsControllerProvider.future);
  }

  test('build lists every series in store order with its summary and the '
      'status derived from the clock (D5)', () async {
    final untracked = periodicals.seed(const Periodical(title: 'Chandamama'));
    final active = periodicals.seed(
      Periodical(title: 'Frontline', subscriptionEnd: dayFromToday(60)),
    );
    final expiring = periodicals.seed(
      Periodical(title: 'Outlook', subscriptionEnd: dayFromToday(10)),
    );
    final lapsed = periodicals.seed(
      Periodical(title: 'Sportstar', subscriptionEnd: dayFromToday(-1)),
    );
    periodicals.issues[active.periodicalUid!] = [
      CatalogueItem(
        id: 1,
        title: 'Frontline — No 1',
        details: IssueOf(
          periodicalUid: active.periodicalUid!,
          issueNumber: 1,
          issueDate: dayFromToday(-30),
        ),
      ),
      CatalogueItem(
        id: 2,
        title: 'Frontline — No 2',
        details: IssueOf(
          periodicalUid: active.periodicalUid!,
          issueNumber: 2,
          issueDate: dayFromToday(-2),
        ),
      ),
    ];

    final entries = await load(makeContainer());

    expect(entries.map((e) => e.periodical.id), [
      untracked.id,
      active.id,
      expiring.id,
      lapsed.id,
    ]);
    expect(entries.map((e) => e.status), [
      SubscriptionStatus.untracked,
      SubscriptionStatus.active,
      SubscriptionStatus.expiringSoon,
      SubscriptionStatus.lapsed,
    ]);
    expect(entries[1].issueCount, 2);
    expect(entries[1].latestIssueDate, dayFromToday(-2));
    expect(entries[0].issueCount, 0);
    expect(entries[0].latestIssueDate, isNull);
    expect(() => entries.add(entries.first), throwsUnsupportedError);
  });

  test(
    'N04: the status rolls over when the tick fires after the end date',
    () async {
      periodicals.seed(
        Periodical(title: 'Outlook', subscriptionEnd: dayFromToday(10)),
      );
      final container = makeContainer();
      final before = await load(container);
      expect(before.single.status, SubscriptionStatus.expiringSoon);

      // Time passes beyond the end date; the periodic tick fires (simulated
      // by invalidating the tick provider — the same rebuild path).
      now = t0 + 11 * day;
      container.invalidate(nowTickProvider);
      await container.pump();

      final after = await container.read(periodicalsControllerProvider.future);
      expect(after.single.status, SubscriptionStatus.lapsed);
    },
  );

  test('S9: the shared library signal refreshes title, count and latest date '
      'without a tick or route recreation', () async {
    final series = periodicals.seed(const Periodical(title: 'Frontline'));
    periodicals.issues[series.periodicalUid!] = [
      CatalogueItem(
        id: 1,
        title: 'Frontline — No 1',
        details: IssueOf(
          periodicalUid: series.periodicalUid!,
          issueNumber: 1,
          issueDate: dayFromToday(-30),
        ),
      ),
    ];
    final container = makeContainer();
    final before = await load(container);
    final notifier = container.read(periodicalsControllerProvider.notifier);
    await container.read(libraryControllerProvider.future);
    await container.pump();
    expect(before.single.periodical.title, 'Frontline');
    expect(before.single.issueCount, 1);
    expect(before.single.latestIssueDate, dayFromToday(-30));

    // This is the shared signal emitted by import, merge, restore and the
    // issue-delete action. The store changes first; no minute tick fires and
    // the PeriodicalsController listener stays open throughout.
    periodicals.rows[series.id] = series.copyWith(title: 'Frontline Weekly');
    periodicals.issues[series.periodicalUid!] = [
      ...periodicals.issues[series.periodicalUid!]!,
      CatalogueItem(
        id: 2,
        title: 'Frontline Weekly — No 2',
        details: IssueOf(
          periodicalUid: series.periodicalUid!,
          issueNumber: 2,
          issueDate: dayFromToday(-2),
        ),
      ),
    ];
    container.invalidate(libraryControllerProvider);
    await container.read(libraryControllerProvider.future);
    await container.pump();

    final after = await container.read(periodicalsControllerProvider.future);
    expect(after.single.periodical.title, 'Frontline Weekly');
    expect(after.single.issueCount, 2);
    expect(after.single.latestIssueDate, dayFromToday(-2));
    expect(
      identical(
        notifier,
        container.read(periodicalsControllerProvider.notifier),
      ),
      isTrue,
      reason: 'the kept-alive route/provider was not recreated',
    );
  });

  test('a failed read surfaces AsyncError(Failure), never raw text', () async {
    periodicals.listAllFailure = const StorageFailure('disk gone');
    final container = makeContainer();
    final sub = container.listen(periodicalsControllerProvider, (_, _) {});
    addTearDown(sub.close);

    await expectLater(
      container.read(periodicalsControllerProvider.future),
      throwsA(isA<StorageFailure>()),
    );
    expect(
      container.read(periodicalsControllerProvider).error,
      isA<StorageFailure>(),
    );
  });

  group('remove / restoreRemoved', () {
    test(
      'remove stamps the clock, then refreshes with the removed row',
      () async {
        final series = periodicals.seed(const Periodical(title: 'Outlook'));
        final container = makeContainer();
        await load(container);

        await container
            .read(periodicalsControllerProvider.notifier)
            .remove(series.id);

        expect(periodicals.calls, contains('markRemoved:${series.id}@$t0'));
        final entries = container.read(periodicalsControllerProvider).value!;
        expect(entries.single.periodical.removed, isTrue);
        expect(entries.single.periodical.removedAt, t0);
      },
    );

    test('remove failure surfaces AsyncError(Failure) — never a silent '
        '"success" refresh (§5 fail closed)', () async {
      final series = periodicals.seed(const Periodical(title: 'Outlook'));
      periodicals.markRemovedFailure = const StorageFailure('disk full');
      final container = makeContainer();
      await load(container);
      await container.read(libraryControllerProvider.future);
      await container.pump();
      final readsBefore = periodicals.calls.where((c) => c == 'listAll').length;

      await container
          .read(periodicalsControllerProvider.notifier)
          .remove(series.id);

      final state = container.read(periodicalsControllerProvider);
      expect(state, isA<AsyncError<List<PeriodicalListEntry>>>());
      expect(state.error, isA<StorageFailure>());
      expect(
        periodicals.calls.where((c) => c == 'listAll').length,
        readsBefore,
        reason: 'a failed write must not trigger a success refresh',
      );
    });

    test('restoreRemoved clears the flag, then refreshes', () async {
      final series = periodicals.seed(
        const Periodical(title: 'Outlook', removed: true, removedAt: 1),
      );
      final container = makeContainer();
      await load(container);

      await container
          .read(periodicalsControllerProvider.notifier)
          .restoreRemoved(series.id);

      expect(periodicals.calls, contains('restoreRemoved:${series.id}'));
      final entries = container.read(periodicalsControllerProvider).value!;
      expect(entries.single.periodical.removed, isFalse);
    });

    test('restoreRemoved failure surfaces AsyncError(Failure)', () async {
      final series = periodicals.seed(const Periodical(title: 'Outlook'));
      periodicals.restoreRemovedFailure = const StorageFailure('disk full');
      final container = makeContainer();
      await load(container);

      await container
          .read(periodicalsControllerProvider.notifier)
          .restoreRemoved(series.id);

      final state = container.read(periodicalsControllerProvider);
      expect(state.error, isA<StorageFailure>());
    });
  });

  group('delete', () {
    test('a series that still has issues is REFUSED: the typed failure is '
        'returned and the list is left exactly as it was (D8)', () async {
      final series = periodicals.seed(const Periodical(title: 'Outlook'));
      periodicals.issues[series.periodicalUid!] = [
        CatalogueItem(
          id: 1,
          title: 'Outlook — No 1',
          details: IssueOf(
            periodicalUid: series.periodicalUid!,
            issueNumber: 1,
          ),
        ),
      ];
      final container = makeContainer();
      final before = await load(container);

      final result = await container
          .read(periodicalsControllerProvider.notifier)
          .delete(series.id);

      final failure = failureOf(result);
      expect(failure, isA<PeriodicalHasIssuesFailure>());
      expect((failure as PeriodicalHasIssuesFailure).issueCount, 1);
      final state = container.read(periodicalsControllerProvider);
      expect(state.hasError, isFalse, reason: 'the list is still valid');
      expect(state.isLoading, isFalse);
      expect(identical(state.value, before), isTrue, reason: 'no refresh');
      expect(periodicals.rows, contains(series.id));
      expect(releasedCovers, isEmpty);
    });

    test('a series without issues is deleted, its cover released and the '
        'list refreshed', () async {
      final series = periodicals.seed(
        const Periodical(title: 'Outlook', coverUrl: 'cover-1.jpg'),
      );
      final keep = periodicals.seed(const Periodical(title: 'Sportstar'));
      final container = makeContainer();
      await load(container);

      final result = await container
          .read(periodicalsControllerProvider.notifier)
          .delete(series.id);

      expect(result.isRight(), isTrue);
      expect(releasedCovers, ['cover-1.jpg']);
      final entries = container.read(periodicalsControllerProvider).value!;
      expect(entries.map((e) => e.periodical.id), [keep.id]);
    });
  });
}
