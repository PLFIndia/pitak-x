/// Widget tests for the Others form (plan S17; ADR 0013 O1, O3): add saves
/// through the REAL generic use case over the fakes (gate included) with
/// `details` always the `OtherItemOf` marker, the Description field maps to
/// the shared notes column, edit mode saves on top of the CURRENT row (N03)
/// and can never flip the kind (D8), and a repository failure renders the
/// shared wording with the 'item' noun.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/widgets/item_cover.dart';
import 'package:pitaka/features/library/application/form_cover_controller.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/library/presentation/pages/other_item_form_page.dart';

import '../../support/a11y.dart';
import '../../support/cover_capture_fakes.dart';
import '../periodicals/application/periodical_fakes.dart';

void main() {
  late FakeItems items;

  setUp(() {
    items = FakeItems();
  });

  /// Hosts the form ABOVE a home route so the pop after a successful save is
  /// observable.
  Widget app({CatalogueItem? edit, CoverCaptureFakes? coverFakes}) {
    return ProviderScope(
      overrides: [
        catalogueItemRepositoryProvider.overrideWith((ref) async => items),
        settingsRepositoryProvider.overrideWith((ref) async => FakeSettings()),
        coversDirProvider.overrideWith((ref) async => '.'),
        if (coverFakes != null)
          formCoverControllerProvider.overrideWith(() => coverFakes.controller),
        // Deterministic language list for the shared field.
        libraryLanguagesProvider.overrideWith((ref) async => ['English']),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OtherItemFormPage(item: edit),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  /// The forms are taller than the default 800x600 test surface, and a
  /// sliver-backed ListView only builds children near the viewport — give
  /// every test a surface tall enough to build the whole form.
  void useBigSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> openForm(
    WidgetTester tester, {
    CatalogueItem? edit,
    CoverCaptureFakes? coverFakes,
  }) async {
    useBigSurface(tester);
    await tester.pumpWidget(app(edit: edit, coverFakes: coverFakes));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Scrolls the lazy form until [finder] is built, then taps it.
  Future<void> scrollTap(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await scrollTap(tester, find.byType(FilledButton));
  }

  testWidgets('add: a valid item is persisted as kind other and the page '
      'pops (O1, O3)', (tester) async {
    await openForm(tester);
    expect(find.text('Add other item'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Title *'),
      'Chess set',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'A wooden chess set, pieces complete.',
    );

    await save(tester);

    expect(find.text('open'), findsOneWidget, reason: 'popped after save');
    final stored = items.inserted.single;
    expect(stored.title, 'Chess set');
    expect(
      stored.notes,
      'A wooden chess set, pieces complete.',
      reason: 'the Description field IS the shared notes column (O1)',
    );
    expect(stored.details, isA<OtherItemOf>());
    expect(stored.kind, ItemKind.other);
    expect(stored.copyCount, 1, reason: 'default copies');
  });

  testWidgets('add: a blank title is flagged and nothing is persisted', (
    tester,
  ) async {
    await openForm(tester);

    await save(tester);

    expect(find.text('A title is required.'), findsOneWidget);
    expect(items.inserted, isEmpty);
  });

  testWidgets('edit: prefilled, saves on top of the current row and keeps '
      'the kind (N03, D8)', (tester) async {
    final existing = items.seed(
      const CatalogueItem(
        title: 'Chess set',
        notes: 'Old description',
        location: 'Shelf B',
        addedBy: 'meera',
        details: OtherItemOf(),
      ),
    );
    await openForm(tester, edit: existing);

    expect(find.text('Edit item'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Chess set'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Old description'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Shelf B'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'A wooden chess set, pieces complete.',
    );
    await save(tester);

    expect(find.text('open'), findsOneWidget, reason: 'popped after save');
    final stored = items.rows[existing.id]!;
    expect(stored.notes, 'A wooden chess set, pieces complete.');
    expect(stored.title, 'Chess set', reason: 'untouched fields kept');
    expect(stored.addedBy, 'meera', reason: 'attribution kept from the row');
    expect(stored.itemUid, existing.itemUid);
    expect(
      stored.details,
      isA<OtherItemOf>(),
      reason: 'an edit can never flip the kind (D8)',
    );
  });

  testWidgets('edit: an untouched cover follows a background replacement and '
      'Save preserves the new reference', (tester) async {
    final existing = items.seed(
      const CatalogueItem(
        title: 'Chess set',
        coverUrl: 'covers/old.jpg',
        details: OtherItemOf(),
      ),
    );
    await openForm(tester, edit: existing);

    items.rows[existing.id] = existing.copyWith(coverUrl: 'covers/new.jpg');
    ProviderScope.containerOf(
      tester.element(find.byType(OtherItemFormPage)),
    ).invalidate(libraryControllerProvider);
    await tester.pumpAndSettle();

    expect(
      tester.widget<ItemCover>(find.byType(ItemCover)).coverUrl,
      'covers/new.jpg',
      reason: 'an untouched form shows the current row cover',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'Edited while the cover completed',
    );
    await save(tester);

    expect(items.rows[existing.id]!.coverUrl, 'covers/new.jpg');
  });

  testWidgets('edit: a deliberate cover removal is not overwritten by a '
      'background replacement', (tester) async {
    final existing = items.seed(
      const CatalogueItem(
        title: 'Chess set',
        coverUrl: 'covers/old.jpg',
        details: OtherItemOf(),
      ),
    );
    await openForm(tester, edit: existing);
    await tester.tap(find.text('Remove cover'));
    await tester.pump();

    items.rows[existing.id] = existing.copyWith(coverUrl: 'covers/new.jpg');
    ProviderScope.containerOf(
      tester.element(find.byType(OtherItemFormPage)),
    ).invalidate(libraryControllerProvider);
    await tester.pumpAndSettle();

    expect(tester.widget<ItemCover>(find.byType(ItemCover)).coverUrl, isNull);
    await save(tester);
    expect(items.rows[existing.id]!.coverUrl, isNull);
  });

  testWidgets('a repository failure renders the shared wording (noun: item)', (
    tester,
  ) async {
    items.insertFailure = const StorageFailure('synthetic');
    await openForm(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Title *'),
      'Chess set',
    );

    await save(tester);

    expect(
      find.text('Could not save the item. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('open'), findsNothing, reason: 'no pop on failure');
  });

  testWidgets('the cover field offers capture (plugin steps untestable)', (
    tester,
  ) async {
    await openForm(tester);
    expect(find.text('Add cover'), findsOneWidget);
  });

  testWidgets('edit: Save stays gated through picker, crop, and cover '
      'storage, then saves the selected reference', (tester) async {
    final coverFakes = installCoverCaptureFakes();
    final existing = items.seed(
      const CatalogueItem(
        title: 'Chess set',
        coverUrl: 'covers/old.jpg',
        details: OtherItemOf(),
      ),
    );
    await openForm(tester, edit: existing, coverFakes: coverFakes);
    final saveButton = find.byType(FilledButton);
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);

    await tester.tap(find.text('Replace cover'));
    await tester.pump();
    await coverFakes.pickerGate.entered;
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

    coverFakes.finishPicker();
    await tester.pump();
    await coverFakes.cropperGate.entered;
    await tester.pump();
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

    coverFakes.finishCropper();
    await tester.pump();
    await coverFakes.storeGate.entered;
    await tester.pump();
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    await tester.tap(saveButton);
    await tester.pump();
    expect(items.updated, isEmpty);
    expect(find.byType(OtherItemFormPage), findsOneWidget);

    coverFakes.finishStore('covers/selected.jpg');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
    await save(tester);

    expect(items.rows[existing.id]!.coverUrl, 'covers/selected.jpg');
    expect(coverFakes.picker.calls, 1);
    expect(coverFakes.cropper.calls, 1);
    expect(coverFakes.controller.calls, 1);
  });

  testWidgets('Date added keeps instant picker semantics', (tester) async {
    final existing = items.seed(
      CatalogueItem(
        title: 'Chess set',
        addedDate: DateTime(2026, 1, 15, 12, 34).millisecondsSinceEpoch,
        details: const OtherItemOf(),
      ),
    );
    await openForm(tester, edit: existing);

    await scrollTap(tester, find.text('Change'));
    await tester.tap(find.text('20').last);
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await save(tester);

    expect(
      items.rows[existing.id]!.addedDate,
      DateTime(2026, 1, 20).millisecondsSinceEpoch,
      reason: 'addedDate is an instant, not a UTC calendar-day field',
    );
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    await openForm(tester);
    await expectMeetsA11yGuidelines(tester);
  });
}
