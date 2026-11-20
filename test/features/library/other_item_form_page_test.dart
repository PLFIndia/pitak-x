/// Widget tests for the Others form (plan S17; ADR 0013 O1, O3): add saves
/// through the REAL generic use case over the fakes (gate included) with
/// `details` always the `OtherItemOf` marker, the Description field maps to
/// the shared notes column, edit mode saves on top of the CURRENT row (N03)
/// and can never flip the kind (D8), and a repository failure renders the
/// shared wording with the 'item' noun.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/widgets/item_cover.dart';
import 'package:pitaka/features/library/application/form_cover_controller.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/library/presentation/pages/other_item_form_page.dart';

import '../../support/a11y.dart';
import '../../support/cover_capture_fakes.dart';
import '../../support/form_back_harness.dart';
import '../periodicals/application/periodical_fakes.dart';

/// The item store of these tests, with two places where a test can hold a
/// call open: the write of a save, and the list reload that follows it.
/// With neither set it behaves exactly like [FakeItems].
class _HeldItems extends FakeItems {
  /// While set, `insert` waits for it before it stores anything.
  Completer<void>? holdInsert;

  /// While set, every list read (`page`) waits for it.
  Completer<void>? holdPage;

  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) async {
    await holdInsert?.future;
    return super.insert(book);
  }

  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    await holdPage?.future;
    return super.page(query, limit: limit, offset: offset);
  }
}

void main() {
  late _HeldItems items;

  setUp(() {
    items = _HeldItems();
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

  // Review finding P4-M1: Back must not throw away what was typed without
  // asking. "The form is gone" means the home page's button shows again.
  group('leaving the form (P4-M1)', () {
    final title = find.widgetWithText(TextField, 'Title *');
    final page = find.byType(OtherItemFormPage);
    final home = find.text('open');

    void expectGoneWithoutQuestion() {
      expect(findDiscardQuestion(), findsNothing);
      expect(page, findsNothing);
      expect(home, findsOneWidget);
    }

    void expectAsked() {
      expect(findDiscardQuestion(), findsOneWidget);
      expect(page, findsOneWidget);
    }

    /// Taps Save without waiting for the screen to come to rest: while a
    /// save is held open the button shows a spinner that never rests.
    Future<void> tapSaveAndHold(WidgetTester tester) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.pump();
    }

    Future<void> pickFrom(
      WidgetTester tester,
      Finder dropdown,
      String choice,
    ) async {
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      // The open menu repeats the selected text; `.last` is the menu's.
      await tester.tap(find.text(choice).last);
      await tester.pumpAndSettle();
    }

    /// Has the library list loaded and listened to before a save, as it is
    /// in the app, where the Library screen under the form watches it.
    /// Without this the list is built for the FIRST time by the form's
    /// reload after a save, which never happens in the app.
    Future<void> keepLibraryListLoaded(WidgetTester tester) async {
      final subscription = ProviderScope.containerOf(
        tester.element(page),
      ).listen(libraryControllerProvider, (_, _) {});
      addTearDown(subscription.close);
      await tester.pumpAndSettle();
    }

    CatalogueItem seedWithCover() => items.seed(
      const CatalogueItem(
        title: 'Chess set',
        notes: 'Old description',
        coverUrl: 'covers/old.jpg',
        details: OtherItemOf(),
      ),
    );

    testWidgets('untouched, Back: the form leaves at once', (tester) async {
      await openForm(tester);
      await pressSystemBack(tester);

      expectGoneWithoutQuestion();
    });

    testWidgets('an edit form opened and left as it was: Back leaves', (
      tester,
    ) async {
      await openForm(tester, edit: seedWithCover());
      await pressSystemBack(tester);

      expectGoneWithoutQuestion();
    });

    testWidgets('a title typed, Back: the question. "Keep editing" keeps '
        'the form and the text; Back again and "Discard" leaves', (
      tester,
    ) async {
      await openForm(tester);
      await tester.enterText(title, 'Chess set');
      await pressSystemBack(tester);
      expectAsked();
      expect(
        find.text('What you entered on this page has not been saved.'),
        findsOneWidget,
      );

      await tester.tap(findKeepEditing());
      await tester.pumpAndSettle();
      expect(findDiscardQuestion(), findsNothing);
      expect(find.widgetWithText(TextField, 'Chess set'), findsOneWidget);

      await pressSystemBack(tester);
      await tester.tap(findDiscard());
      await tester.pumpAndSettle();
      expectGoneWithoutQuestion();
      expect(items.inserted, isEmpty, reason: 'discarded, not saved');
    });

    testWidgets('the arrow of the app bar asks as well', (tester) async {
      await openForm(tester);
      await tester.enterText(title, 'Chess set');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expectAsked();
    });

    testWidgets('typed and put back, Back: leaves', (tester) async {
      await openForm(tester);
      await tester.enterText(title, 'Chess set');
      await tester.enterText(title, '');
      await pressSystemBack(tester);

      expectGoneWithoutQuestion();
    });

    // Every text field the form shows. A field that is added to the page
    // has to be added here (the count below fails otherwise), and then its
    // own test says whether the guard knows of it.
    const textFields = [
      'Title *',
      'Title (transliteration)',
      'Description',
      'Shelf location',
      'Copies',
      'Source detail',
    ];

    testWidgets('the form shows exactly the text fields these tests know', (
      tester,
    ) async {
      await openForm(tester);

      expect(find.byType(TextField), findsNWidgets(textFields.length));
      for (final label in textFields) {
        expect(find.widgetWithText(TextField, label), findsOneWidget);
      }
    });

    for (final label in textFields) {
      testWidgets('"$label" changed, Back: the question', (tester) async {
        await openForm(tester);
        // A digit: the fields for numbers take nothing else.
        await tester.enterText(find.widgetWithText(TextField, label), '7');
        await pressSystemBack(tester);

        expectAsked();
      });
    }

    group('a value that is not typed text', () {
      final language = find.byKey(const ValueKey('language-dropdown'));

      testWidgets('a language picked: the question', (tester) async {
        await openForm(tester);
        await pickFrom(tester, language, 'English');
        await pressSystemBack(tester);

        expectAsked();
      });

      testWidgets('"Other…" picked and a language typed: the question', (
        tester,
      ) async {
        await openForm(tester);
        await pickFrom(tester, language, 'Other…');
        await tester.enterText(
          find.widgetWithText(TextField, 'Other language'),
          'Marathi',
        );
        await pressSystemBack(tester);

        expectAsked();
      });

      testWidgets('"Other…" picked and nothing typed: Back leaves (Save '
          'would store nothing else than before)', (tester) async {
        await openForm(tester);
        await pickFrom(tester, language, 'Other…');
        await pressSystemBack(tester);

        expectGoneWithoutQuestion();
      });

      testWidgets('a source picked: the question', (tester) async {
        await openForm(tester);
        await pickFrom(
          tester,
          find.byType(DropdownButtonFormField<ItemSourceType?>),
          'Gift',
        );
        await pressSystemBack(tester);

        expectAsked();
      });

      testWidgets('an age group picked: the question', (tester) async {
        await openForm(tester);
        await pickFrom(
          tester,
          find.byType(DropdownButtonFormField<AgeGroup?>),
          'Ages 6+',
        );
        await pressSystemBack(tester);

        expectAsked();
      });

      testWidgets('another "Date added" picked: the question', (tester) async {
        await openForm(tester);
        await scrollTap(tester, find.text('Change'));
        await tester.tap(find.text('1').last);
        await tester.pump();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        await pressSystemBack(tester);

        expectAsked();
      });

      testWidgets('a cover photographed: the question', (tester) async {
        final coverFakes = installCoverCaptureFakes();
        await openForm(tester, coverFakes: coverFakes);
        await tester.tap(find.text('Add cover'));
        await tester.pump();
        await coverFakes.pickerGate.entered;
        coverFakes.finishPicker();
        await tester.pump();
        await coverFakes.cropperGate.entered;
        coverFakes.finishCropper();
        await tester.pump();
        await coverFakes.storeGate.entered;
        coverFakes.finishStore('covers/new.jpg');
        await tester.pumpAndSettle();
        await pressSystemBack(tester);

        expectAsked();
      });

      testWidgets('a cover that is still being stored: the question', (
        tester,
      ) async {
        final coverFakes = installCoverCaptureFakes();
        await openForm(tester, coverFakes: coverFakes);
        await tester.tap(find.text('Add cover'));
        await tester.pump();
        await coverFakes.pickerGate.entered;
        coverFakes.finishPicker();
        await tester.pump();
        await coverFakes.cropperGate.entered;
        coverFakes.finishCropper();
        await tester.pump();
        await coverFakes.storeGate.entered;
        await tester.pump();
        // The cover field shows a spinner now: no waiting for rest.
        await pressSystemBack(tester, settle: false);

        expectAsked();

        await tester.tap(findKeepEditing());
        coverFakes.finishStore('covers/new.jpg');
        await tester.pumpAndSettle();
        expect(page, findsOneWidget);
      });

      testWidgets('edit: the cover removed: the question', (tester) async {
        await openForm(tester, edit: seedWithCover());
        await tester.tap(find.text('Remove cover'));
        await tester.pump();
        await pressSystemBack(tester);

        expectAsked();
      });

      testWidgets('edit: a cover that arrives in the background while the '
          'form is untouched is no change: Back leaves', (tester) async {
        final existing = seedWithCover();
        await openForm(tester, edit: existing);
        items.rows[existing.id] = existing.copyWith(coverUrl: 'covers/new.jpg');
        ProviderScope.containerOf(
          tester.element(page),
        ).invalidate(libraryControllerProvider);
        await tester.pumpAndSettle();
        await pressSystemBack(tester);

        expectGoneWithoutQuestion();
      });
    });

    testWidgets('Back while the save runs does nothing; the form then '
        'leaves by itself, with no question (D95)', (tester) async {
      await openForm(tester);
      await tester.enterText(title, 'Chess set');
      items.holdInsert = Completer<void>();
      await tapSaveAndHold(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await pressSystemBack(tester, settle: false);
      expect(findDiscardQuestion(), findsNothing);
      expect(page, findsOneWidget, reason: 'Back waits for the save');

      items.holdInsert!.complete();
      await tester.pumpAndSettle();
      expectGoneWithoutQuestion();
      expect(items.inserted, hasLength(1));
    });

    testWidgets('after a save that failed, Back asks', (tester) async {
      items.insertFailure = const StorageFailure('synthetic');
      await openForm(tester);
      await tester.enterText(title, 'Chess set');
      await save(tester);
      expect(
        find.text('Could not save the item. Please try again.'),
        findsOneWidget,
      );
      await pressSystemBack(tester);

      expectAsked();
    });

    // The form reloads the library list between its save and leaving the
    // screen. In that moment the item IS saved.
    testWidgets('Back in the moment of the list reload after a good save: '
        'the form leaves, no question, and the item is there once', (
      tester,
    ) async {
      await openForm(tester);
      await keepLibraryListLoaded(tester);
      await tester.enterText(title, 'Chess set');
      items.holdPage = Completer<void>();
      await tapSaveAndHold(tester);
      expect(items.inserted, hasLength(1), reason: 'the save is through');
      expect(page, findsOneWidget, reason: 'the reload is held open');

      await pressSystemBack(tester);
      expectGoneWithoutQuestion();

      items.holdPage!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expectGoneWithoutQuestion();
      expect(items.inserted, hasLength(1));
    });

    testWidgets('a letter typed in the moment of the list reload, then '
        'Back: still no question (the item is saved)', (tester) async {
      await openForm(tester);
      await keepLibraryListLoaded(tester);
      await tester.enterText(title, 'Chess set');
      items.holdPage = Completer<void>();
      await tapSaveAndHold(tester);
      expect(items.inserted, hasLength(1), reason: 'the save is through');

      await tester.enterText(title, 'Chess set, and more');
      await pressSystemBack(tester);
      expectGoneWithoutQuestion();

      items.holdPage!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expectGoneWithoutQuestion();
      expect(items.inserted, hasLength(1));
    });
  });
}
