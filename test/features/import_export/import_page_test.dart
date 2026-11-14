import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/import_export/presentation/pages/import_page.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

import '../../support/a11y.dart';
import '../../support/fake_document_picker.dart';
import '../../support/fake_picked_document_reader.dart';

import '../periodicals/application/periodical_fakes.dart';

class _MemBookRepo implements CatalogueItemRepository {
  // CatalogueItemRepository additions (review 2026-09-03): fakes default to "no
  // match" and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, CatalogueItem?>> findByUid(String itemUid) async =>
      right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  final List<CatalogueItem> stored = [];
  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) async {
    stored.add(book);
    return right(book);
  }

  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem book) async =>
      right(book);
  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    final rows = query.isSearch
        ? const <CatalogueItem>[]
        : (await getAll()).getOrElse((_) => const []);
    final start = offset.clamp(0, rows.length);
    final end = (start + limit).clamp(start, rows.length);
    return right(
      CatalogueItemPage(
        items: rows.sublist(start, end),
        hasMore: end < rows.length,
      ),
    );
  }

  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async =>
      right(const []);
  @override
  Future<Either<Failure, List<String>>> distinctSourceDetails(
    ItemSourceType type,
  ) async => right(const []);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);

  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async =>
      right(null);
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async => right(stored);
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAllForInterchange() async =>
      right(stored);
  @override
  Future<Either<Failure, int>> insertAll(List<CatalogueItem> b) async =>
      right(b.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<CatalogueItem> b) async =>
      right(b.length);
}

class _MemWishlistRepo implements WishlistRepository {
  @override
  Future<Either<Failure, WishlistBook>> insert(WishlistBook b) async =>
      right(b);
  @override
  Future<Either<Failure, WishlistBook>> upsert(WishlistBook b) async =>
      right(b);
  @override
  Future<Either<Failure, WishlistBook>> update(WishlistBook b) async =>
      right(b);
  @override
  Future<Either<Failure, WishlistBook?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, WishlistBook?>> findByIsbn(String i) async =>
      right(null);
  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async => right(const []);
  @override
  Future<Either<Failure, int>> insertAll(List<WishlistBook> b) async =>
      right(b.length);
}

void main() {
  // The system's picker and the private copy it makes, played by a fake
  // that writes real files; and a reader that reads them at once (a widget
  // test cannot wait for real file work). Decision D24.
  late Directory tmp;
  late FakeDocumentPicker picker;
  late FakePickedDocumentReader reader;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('import_page_test');
    picker = FakeDocumentPicker(Directory('${tmp.path}/picked_documents'));
    reader = FakePickedDocumentReader();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget page(ImportLibraryUseCase useCase) => ProviderScope(
    overrides: [
      importLibraryUseCaseProvider.overrideWith((ref) async => useCase),
      // Library/Wishlist controllers refresh on success — give them repos.
      catalogueItemRepositoryProvider.overrideWith(
        (ref) async => _MemBookRepo(),
      ),
      wishlistRepositoryProvider.overrideWith(
        (ref) async => _MemWishlistRepo(),
      ),
      documentPickerProvider.overrideWith((ref) async => picker),
      pickedDocumentReaderProvider.overrideWith((ref) => reader),
    ],
    child: const MaterialApp(home: ImportPage()),
  );

  ImportLibraryUseCase useCaseWith(_MemBookRepo books) => ImportLibraryUseCase(
    jsonParser: const PitakaJsonImporter(),
    bookRepo: books,
    wishlistRepo: _MemWishlistRepo(),
    periodicalRepo: FakePeriodicals(),
  );

  const tooLargeSentence =
      'This file is too large to import. Import reads files of up to '
      '64.0 MB. To load a backup (.pitabak), use \u201cRestore backup\u201d.';

  group("a chosen file comes through the app's own picker (D24, M05)", () {
    final smallJson = utf8.encode(
      jsonEncode({
        'schemaVersion': 3,
        'exportedAt': 0,
        'books': [
          {'title': 'From file', 'isbn': '888'},
        ],
        'wishlist': <dynamic>[],
      }),
    );

    testWidgets('a file above the cap is refused with a sentence that names '
        'the cap, and nothing is read', (tester) async {
      final books = _MemBookRepo();
      picker.willAnswer(const DocumentPickTooLarge());
      await tester.pumpWidget(page(useCaseWith(books)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();

      expect(find.text(tooLargeSentence), findsOneWidget);
      expect(find.text('Import complete'), findsNothing);
      expect(find.text('Import failed'), findsNothing);
      // The cap the picker copies under is the one the parsers have.
      expect(picker.caps, [64 * 1024 * 1024]);
      expect(reader.asked, isEmpty);
      expect(books.stored, isEmpty, reason: 'nothing may reach the use case');
    });

    testWidgets('a ZIP pick is refused unread, with the sentence (D29)', (
      tester,
    ) async {
      // Import reads no ZIP (BR7). A picked file that starts like one is
      // turned away on its first four bytes, and nothing more of it is
      // asked for.
      final books = _MemBookRepo();
      picker.willPick([0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0]);
      await tester.pumpWidget(page(useCaseWith(books)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();

      expect(reader.asked, ['firstBytes 4']);
      expect(find.text(kImportZipRefusedMessage), findsOneWidget);
      expect(
        kImportZipRefusedMessage,
        'Import reads Pitak JSON and Goodreads CSV files, not ZIP files. '
        'To load a backup (.pitabak), use “Restore backup”.',
      );
      expect(find.text('Import complete'), findsNothing);
      expect(find.text('Import failed'), findsNothing);
      expect(books.stored, isEmpty, reason: 'nothing may reach the use case');
      expect(picker.copiesOnDisk(), isEmpty, reason: 'the copy is removed');
    });

    testWidgets('an honest small text pick still imports', (tester) async {
      final books = _MemBookRepo();
      picker.willPick(smallJson);
      await tester.pumpWidget(page(useCaseWith(books)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();

      expect(find.textContaining('too large'), findsNothing);
      expect(find.text('Import complete'), findsOneWidget);
      expect(books.stored.single.title, 'From file');
      expect(picker.caps, [64 * 1024 * 1024]);
      expect(picker.copiesOnDisk(), isEmpty, reason: 'the copy is removed');
    });

    // The four answers that read the same on every page that picks a file.
    const sentences = <(DocumentPickResult, String)>[
      (
        DocumentPickUnreadable(),
        'That file could not be read. If it is kept online, check the '
            'connection and try again.',
      ),
      (
        DocumentPickNotSaved(),
        'The file could not be copied to this phone. Free some storage and '
            'try again.',
      ),
      (
        DocumentPickUnavailable(),
        'Choosing a file is not available on this device.',
      ),
      (
        DocumentPickFailed(),
        'Something went wrong choosing the file. Please try again.',
      ),
    ];
    for (final (answer, sentence) in sentences) {
      testWidgets('${answer.runtimeType} shows its own sentence', (
        tester,
      ) async {
        final books = _MemBookRepo();
        picker.willAnswer(answer);
        await tester.pumpWidget(page(useCaseWith(books)));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Choose file'));
        await tester.pumpAndSettle();

        expect(find.text(sentence), findsOneWidget);
        expect(find.text('Import complete'), findsNothing);
        expect(books.stored, isEmpty);
      });
    }

    testWidgets('a copy that cannot be read shows the "could not be read" '
        'sentence', (tester) async {
      picker.willPick(smallJson);
      reader.failing = true;
      await tester.pumpWidget(page(useCaseWith(_MemBookRepo())));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();

      expect(find.textContaining('could not be read'), findsOneWidget);
      expect(picker.copiesOnDisk(), isEmpty, reason: 'the copy is removed');
    });

    testWidgets('closing the picker says nothing, and a new tap clears the '
        'sentence of the pick before', (tester) async {
      picker.willAnswer(const DocumentPickTooLarge());
      await tester.pumpWidget(page(useCaseWith(_MemBookRepo())));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();
      expect(find.text(tooLargeSentence), findsOneWidget);

      // Nothing is scripted now: the fake picker answers "cancelled".
      await tester.tap(find.text('Choose file'));
      await tester.pumpAndSettle();

      expect(picker.caps, hasLength(2));
      expect(find.text(tooLargeSentence), findsNothing);
      expect(find.text('Import complete'), findsNothing);
      expect(find.text('Import failed'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('while the picker is open both buttons are off and the '
        'spinner shows', (tester) async {
      final books = _MemBookRepo();
      final pickerOpen = Completer<void>();
      picker
        ..holdNextPick = pickerOpen
        ..willPick(smallJson);
      await tester.pumpWidget(page(useCaseWith(books)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose file'));
      // Not `pumpAndSettle`: the spinner never comes to rest.
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final choose = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Choose file'),
      );
      final paste = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Import text'),
      );
      expect(choose.onPressed, isNull);
      expect(paste.onPressed, isNull);
      expect(picker.caps, hasLength(1));

      pickerOpen.complete();
      await tester.pumpAndSettle();
      expect(find.text('Import complete'), findsOneWidget);
      expect(books.stored.single.title, 'From file');
    });
  });

  testWidgets('the page names the kinds of file it reads, and no bundle', (
    tester,
  ) async {
    await tester.pumpWidget(page(useCaseWith(_MemBookRepo())));
    await tester.pumpAndSettle();

    expect(find.textContaining('file (JSON or CSV).'), findsOneWidget);
    expect(find.textContaining('bundle'), findsNothing);
  });

  testWidgets('pasting JSON and tapping Import shows a summary', (
    tester,
  ) async {
    final useCase = ImportLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: _MemBookRepo(),
      wishlistRepo: _MemWishlistRepo(),
      periodicalRepo: FakePeriodicals(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          importLibraryUseCaseProvider.overrideWith((ref) async => useCase),
          // Library/Wishlist controllers refresh on success — give them repos.
          catalogueItemRepositoryProvider.overrideWith(
            (ref) async => _MemBookRepo(),
          ),
          wishlistRepositoryProvider.overrideWith(
            (ref) async => _MemWishlistRepo(),
          ),
        ],
        child: const MaterialApp(home: ImportPage()),
      ),
    );
    await tester.pumpAndSettle();

    final json = jsonEncode({
      'schemaVersion': 3,
      'exportedAt': 0,
      'books': [
        {'title': 'Imported', 'isbn': '999'},
      ],
      'wishlist': <dynamic>[],
    });

    await tester.enterText(find.byType(TextField), json);
    await tester.tap(find.text('Import text'));
    await tester.pumpAndSettle();

    expect(find.text('Import complete'), findsOneWidget);
    expect(find.text('Books added: 1'), findsOneWidget);
  });

  testWidgets(
    'too-new pasted JSON shows update guidance, not Import complete',
    (tester) async {
      final books = _MemBookRepo();
      await tester.pumpWidget(page(useCaseWith(books)));
      await tester.pumpAndSettle();

      final json = jsonEncode({
        'schemaVersion': 99,
        'books': [
          {'bookUid': 'new-book', 'title': 'New book'},
        ],
        'wishlist': <dynamic>[],
      });
      await tester.enterText(find.byType(TextField), json);
      await tester.tap(find.text('Import text'));
      await tester.pumpAndSettle();

      expect(find.text('Import complete'), findsNothing);
      expect(
        find.text(
          'This file was created by a newer version of Pitak. '
          'Update the app before importing.',
        ),
        findsOneWidget,
      );
      expect(books.stored, isEmpty);
    },
  );

  testWidgets('N11: leaving the page mid-import neither crashes nor loses '
      'the import', (tester) async {
    // The import outlives the page (the controller keep-alives the run and
    // owns the post-success list refresh). Popping Import mid-run used to
    // throw StateError in the page's post-await `ref.read` (widget ref dead).
    final gate = Completer<void>();
    final books = _MemBookRepo();
    final useCase = ImportLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: books,
      wishlistRepo: _MemWishlistRepo(),
      periodicalRepo: FakePeriodicals(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          importLibraryUseCaseProvider.overrideWith((ref) async {
            await gate.future;
            return useCase;
          }),
          catalogueItemRepositoryProvider.overrideWith(
            (ref) async => _MemBookRepo(),
          ),
          wishlistRepositoryProvider.overrideWith(
            (ref) async => _MemWishlistRepo(),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ImportPage()),
                ),
                child: const Text('open import'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open import'));
    await tester.pumpAndSettle();

    final json = jsonEncode({
      'schemaVersion': 3,
      'exportedAt': 0,
      'books': [
        {'title': 'Imported', 'isbn': '999'},
      ],
      'wishlist': <dynamic>[],
    });
    await tester.enterText(find.byType(TextField), json);
    await tester.tap(find.text('Import text'));
    await tester.pump(); // the import is now parked on the gated provider

    // Leave the page mid-import. Settle FIRST: the pop animation must
    // finish so the widget is fully disposed before the import completes —
    // otherwise the continuation races the disposal and the test is flaky.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      books.stored.single.title,
      'Imported',
      reason: 'the import itself must still complete (keep-alive)',
    );
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    final books = _MemBookRepo();
    await tester.pumpWidget(page(useCaseWith(books)));
    await tester.pumpAndSettle();
    await expectMeetsA11yGuidelines(tester);
  });
}
