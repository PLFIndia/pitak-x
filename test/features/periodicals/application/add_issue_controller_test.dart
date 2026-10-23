/// `AddIssueController` (plan S13): a one-shot add/edit of a magazine issue
/// that fails closed (a use-case Left becomes `AsyncError(Failure)`), saves
/// edits on top of the CURRENT row (N03) and, on success, fires BOTH
/// catalogue mutation signals itself — the item list and the series summary
/// both change when an issue is written.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/application/add_issue_controller.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

import 'periodical_fakes.dart';

void main() {
  late FakePeriodicals periodicals;
  late FakeItems items;
  late Periodical series;

  setUp(() {
    periodicals = FakePeriodicals();
    items = FakeItems();
    series = periodicals.seed(
      const Periodical(title: 'Frontline', publisher: 'The Hindu'),
    );
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

  /// A form's output: no title (projected from the series), one number.
  CatalogueItem newIssue() => CatalogueItem(
    title: '',
    details: IssueOf(periodicalUid: series.periodicalUid!, issueNumber: 1),
  );

  group('save', () {
    test(
      'a persisted id is refused — edits must go through saveEdit',
      () async {
        final container = makeContainer();
        final notifier = container.read(addIssueControllerProvider.notifier);

        await notifier.save(newIssue().copyWith(id: 7));

        final state = container.read(addIssueControllerProvider);
        expect(state.error, isA<ValidationFailure>());
        expect(items.inserted, isEmpty);
      },
    );

    test('inserts the projected row, exposes it, and fires both mutation '
        'signals', () async {
      final container = makeContainer();
      await watchSignals(container);
      final libraryBefore = libraryReads();
      final seriesBefore = seriesReads();

      await container
          .read(addIssueControllerProvider.notifier)
          .save(newIssue());

      final saved = container.read(addIssueControllerProvider).value!;
      expect(saved.id, isNot(CatalogueItem.emptyId));
      expect(saved.title, 'Frontline — No 1', reason: 'projected (D3)');
      expect(saved.publisher, 'The Hindu');
      expect(items.inserted, hasLength(1));

      await container.read(libraryControllerProvider.future);
      await container.read(periodicalsControllerProvider.future);
      expect(libraryReads(), greaterThan(libraryBefore));
      expect(seriesReads(), greaterThan(seriesBefore));
    });

    test('a use-case failure becomes AsyncError and fires no signal', () async {
      final container = makeContainer();
      await watchSignals(container);
      final libraryBefore = libraryReads();
      final seriesBefore = seriesReads();

      await container
          .read(addIssueControllerProvider.notifier)
          .save(
            const CatalogueItem(
              title: '',
              details: IssueOf(periodicalUid: 'no-such-series', issueNumber: 1),
            ),
          );

      final state = container.read(addIssueControllerProvider);
      expect(state.error, isA<ValidationFailure>());
      expect(items.inserted, isEmpty);
      await container.pump();
      expect(libraryReads(), libraryBefore);
      expect(seriesReads(), seriesBefore);
    });
  });

  group('saveEdit', () {
    test('a vanished row is NotFoundFailure, nothing is written', () async {
      final container = makeContainer();

      await container
          .read(addIssueControllerProvider.notifier)
          .saveEdit(42, (current) => current);

      expect(
        container.read(addIssueControllerProvider).error,
        isA<NotFoundFailure>(),
      );
      expect(items.updated, isEmpty);
    });

    test('a failed re-read is propagated unchanged', () async {
      items.getByIdFailure = const StorageFailure('disk gone');
      final container = makeContainer();

      await container
          .read(addIssueControllerProvider.notifier)
          .saveEdit(1, (current) => current);

      expect(
        container.read(addIssueControllerProvider).error,
        isA<StorageFailure>(),
      );
      expect(items.updated, isEmpty);
    });

    test('N03: edits are applied on top of the CURRENT row, not the '
        'snapshot the form opened with', () async {
      final stored = items.seed(
        newIssue().copyWith(
          title: 'Frontline — No 1',
          coverUrl: 'covers/old.jpg',
        ),
      );
      final container = makeContainer();
      await watchSignals(container);
      final libraryBefore = libraryReads();
      // The row moves on behind the form (a cover captured elsewhere).
      items.rows[stored.id] = stored.copyWith(coverUrl: 'covers/fresh.jpg');

      await container
          .read(addIssueControllerProvider.notifier)
          .saveEdit(stored.id, (current) => current.copyWith(notes: 'read'));

      final saved = container.read(addIssueControllerProvider).value!;
      expect(saved.notes, 'read');
      expect(
        saved.coverUrl,
        'covers/fresh.jpg',
        reason: 'current row, not snapshot',
      );
      expect(items.updated.single.id, stored.id);
      await container.read(libraryControllerProvider.future);
      expect(libraryReads(), greaterThan(libraryBefore));
    });
  });
}
