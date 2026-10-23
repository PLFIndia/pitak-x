/// `PeriodicalFormController` (plan S13): a one-shot add/edit of a magazine
/// title that fails closed (a use-case Left — including the typed
/// `DuplicateIssnFailure` — becomes `AsyncError(Failure)`), saves edits on
/// top of the CURRENT row (N03) and, on success, fires BOTH catalogue
/// mutation signals itself: a series edit re-projects its issues (D3), so
/// the item list is stale too, not only the Magazines page.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/application/periodical_form_controller.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

import 'periodical_fakes.dart';

void main() {
  late FakePeriodicals periodicals;
  late FakeItems items;

  setUp(() {
    periodicals = FakePeriodicals();
    items = FakeItems();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        periodicalRepositoryProvider.overrideWith((ref) async => periodicals),
        catalogueItemRepositoryProvider.overrideWith((ref) async => items),
        settingsRepositoryProvider.overrideWith((ref) async => FakeSettings()),
        clockProvider.overrideWithValue(() => 0),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Keeps both mutation-signal providers alive and awaits their first
  /// build, so a later `invalidate` is observable as a second read.
  Future<void> watchSignals(ProviderContainer c) async {
    final a = c.listen(libraryControllerProvider, (_, _) {});
    final b = c.listen(periodicalsControllerProvider, (_, _) {});
    addTearDown(a.close);
    addTearDown(b.close);
    await c.read(libraryControllerProvider.future);
    await c.read(periodicalsControllerProvider.future);
  }

  int libraryReads() => items.calls.where((c) => c == 'page').length;
  int seriesReads() => periodicals.calls.where((c) => c == 'listAll').length;

  group('save', () {
    test(
      'a persisted id is refused — edits must go through saveEdit',
      () async {
        final container = makeContainer();

        await container
            .read(periodicalFormControllerProvider.notifier)
            .save(const Periodical(id: 3, title: 'Frontline'));

        expect(
          container.read(periodicalFormControllerProvider).error,
          isA<ValidationFailure>(),
        );
        expect(periodicals.calls, isNot(contains('insert')));
      },
    );

    test('inserts the normalised row, exposes it with id + uid, and fires '
        'both mutation signals', () async {
      final container = makeContainer();
      await watchSignals(container);
      final libraryBefore = libraryReads();
      final seriesBefore = seriesReads();

      await container
          .read(periodicalFormControllerProvider.notifier)
          .save(const Periodical(title: '  Frontline ', issn: '03178471'));

      final saved = container.read(periodicalFormControllerProvider).value!;
      expect(saved.id, isNot(Periodical.emptyId));
      expect(saved.periodicalUid, isNotNull);
      expect(saved.title, 'Frontline');
      expect(saved.issn, '0317-8471', reason: 'canonical form (D7)');

      await container.read(libraryControllerProvider.future);
      await container.read(periodicalsControllerProvider.future);
      expect(libraryReads(), greaterThan(libraryBefore));
      expect(seriesReads(), greaterThan(seriesBefore));
    });

    test('a duplicate ISSN is the typed failure naming the existing title, '
        'and fires no signal', () async {
      periodicals.seed(const Periodical(title: 'Frontline', issn: '0317-8471'));
      final container = makeContainer();
      await watchSignals(container);
      final libraryBefore = libraryReads();
      final seriesBefore = seriesReads();

      await container
          .read(periodicalFormControllerProvider.notifier)
          .save(const Periodical(title: 'Copy', issn: '0317-8471'));

      final error = container.read(periodicalFormControllerProvider).error!;
      expect(error, isA<DuplicateIssnFailure>());
      expect((error as DuplicateIssnFailure).existingTitle, 'Frontline');
      await container.pump();
      expect(libraryReads(), libraryBefore);
      expect(seriesReads(), seriesBefore);
    });
  });

  group('saveEdit', () {
    test('a vanished row is NotFoundFailure, nothing is written', () async {
      final container = makeContainer();

      await container
          .read(periodicalFormControllerProvider.notifier)
          .saveEdit(42, (current) => current);

      expect(
        container.read(periodicalFormControllerProvider).error,
        isA<NotFoundFailure>(),
      );
      expect(periodicals.calls, isNot(contains('update')));
    });

    test('a failed re-read is propagated unchanged', () async {
      periodicals.getByIdFailure = const StorageFailure('disk gone');
      final container = makeContainer();

      await container
          .read(periodicalFormControllerProvider.notifier)
          .saveEdit(1, (current) => current);

      expect(
        container.read(periodicalFormControllerProvider).error,
        isA<StorageFailure>(),
      );
      expect(periodicals.calls, isNot(contains('update')));
    });

    test('N03 + D3: edits apply on top of the CURRENT row, the issues are '
        're-projected, and both signals fire', () async {
      final stored = periodicals.seed(
        const Periodical(title: 'Frontline', coverUrl: 'covers/old.jpg'),
      );
      final issue = items.seed(
        CatalogueItem(
          title: 'Frontline — No 1',
          details: IssueOf(
            periodicalUid: stored.periodicalUid!,
            issueNumber: 1,
          ),
        ),
      );
      periodicals.issues[stored.periodicalUid!] = [issue];
      final container = makeContainer();
      await watchSignals(container);
      final libraryBefore = libraryReads();
      final seriesBefore = seriesReads();
      // The row moves on behind the form (a cover captured elsewhere).
      periodicals.rows[stored.id] = stored.copyWith(
        coverUrl: 'covers/fresh.jpg',
      );

      await container
          .read(periodicalFormControllerProvider.notifier)
          .saveEdit(stored.id, (current) => current.copyWith(title: 'FL'));

      final saved = container.read(periodicalFormControllerProvider).value!;
      expect(saved.title, 'FL');
      expect(
        saved.coverUrl,
        'covers/fresh.jpg',
        reason: 'current row, not snapshot',
      );
      expect(saved.periodicalUid, stored.periodicalUid, reason: 'uid kept');
      expect(items.updated.single.title, 'FL — No 1', reason: 're-projected');

      await container.read(libraryControllerProvider.future);
      await container.read(periodicalsControllerProvider.future);
      expect(libraryReads(), greaterThan(libraryBefore));
      expect(seriesReads(), greaterThan(seriesBefore));
    });
  });
}
