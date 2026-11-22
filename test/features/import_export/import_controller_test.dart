import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/features/import_export/application/import_controller.dart';
import 'package:pitaka/features/import_export/application/import_library_use_case.dart';
import 'package:pitaka/features/import_export/application/picked_text_file.dart';
import 'package:pitaka/features/import_export/domain/import_format_sniffer.dart';
import 'package:pitaka/features/import_export/domain/import_limits.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/library/application/catalogue_changes.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

import '../../support/fake_document_picker.dart';
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
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async =>
      right(null);
  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) async {
    stored.add(book);
    return right(book);
  }

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async => right(stored);
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAllForInterchange() async =>
      right(stored);
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
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem book) async =>
      right(book);
  @override
  Future<Either<Failure, int>> insertAll(List<CatalogueItem> b) async =>
      right(b.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<CatalogueItem> b) async =>
      right(b.length);
}

/// A catalogue whose transaction waits until the test lets it go. It plays
/// "an import that is still running", so a test can do something in the
/// middle of one: submit again, leave the page, dispose the controller.
class _HeldBookRepo extends _MemBookRepo {
  /// Completes when the import has reached its database transaction.
  final Completer<void> entered = Completer<void>();

  /// The test completes this to let the import go on.
  final Completer<void> release = Completer<void>();

  /// How many imports got as far as the database.
  int transactions = 0;

  /// When true, the transaction throws once it is let go: a bug or a broken
  /// database in the middle of an import.
  bool throwsWhenReleased = false;

  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) async {
    transactions++;
    if (!entered.isCompleted) entered.complete();
    await release.future;
    if (throwsWhenReleased) throw StateError('private path');
    return action();
  }
}

class _MemWishlistRepo implements WishlistRepository {
  @override
  Future<Either<Failure, WishlistBook?>> findByIsbn(String isbn) async =>
      right(null);
  @override
  Future<Either<Failure, WishlistBook>> insert(WishlistBook book) async =>
      right(book);
  @override
  Future<Either<Failure, WishlistBook>> upsert(WishlistBook book) async =>
      right(book);
  @override
  Future<Either<Failure, WishlistBook?>> getById(int id) async => right(null);
  @override
  Future<Either<Failure, WishlistBook>> update(WishlistBook book) async =>
      right(book);
  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async => right(const []);
  @override
  Future<Either<Failure, int>> insertAll(List<WishlistBook> b) async =>
      right(b.length);
}

void main() {
  // The system's picker and the copy it makes, played by a fake that
  // writes real files (decision D24). The copy is read by the REAL reader:
  // these tests run on the real clock.
  late Directory tmp;
  late FakeDocumentPicker picker;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('import_controller_test');
    picker = FakeDocumentPicker(Directory('${tmp.path}/picked_documents'));
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('ImportController exposes a summary after importText', () async {
    final useCase = ImportLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: _MemBookRepo(),
      wishlistRepo: _MemWishlistRepo(),
      periodicalRepo: FakePeriodicals(),
    );

    final container = ProviderContainer(
      overrides: [
        importLibraryUseCaseProvider.overrideWith((ref) async => useCase),
      ],
    );
    addTearDown(container.dispose);

    final json = jsonEncode({
      'schemaVersion': 3,
      'exportedAt': 0,
      'books': [
        {'title': 'A', 'isbn': '111'},
      ],
      'wishlist': <dynamic>[],
    });

    await container.read(importControllerProvider.notifier).importText(json);
    final state = container.read(importControllerProvider);

    expect(state.hasValue, isTrue);
    expect(state.value!.format, ImportFormat.pitakaJson);
    expect(state.value!.booksAdded, 1);
    // N11, D151: the import says "catalogue changed" once, from the
    // controller, so the lists under a page that is gone read again.
    expect(container.read(catalogueChangesProvider), 1);
  });

  test(
    'controller surfaces SchemaTooNewFailure for a too-new JSON file',
    () async {
      final books = _MemBookRepo();
      final periodicals = FakePeriodicals();
      final useCase = ImportLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: books,
        wishlistRepo: _MemWishlistRepo(),
        periodicalRepo: periodicals,
      );
      final container = ProviderContainer(
        overrides: [
          importLibraryUseCaseProvider.overrideWith((ref) async => useCase),
          documentPickerProvider.overrideWith((ref) async => picker),
        ],
      );
      addTearDown(container.dispose);

      final json = jsonEncode({
        'schemaVersion': 99,
        'books': [
          {'bookUid': 'new-book', 'title': 'New book'},
        ],
        'wishlist': <dynamic>[],
      });
      picker.willPick(utf8.encode(json));
      final problem = await container
          .read(importControllerProvider.notifier)
          .importFile();

      // The file WAS taken: what is wrong with it is the import's result.
      expect(problem, isNull);
      final state = container.read(importControllerProvider);
      expect(state.error, isA<SchemaTooNewFailure>());
      expect((state.error! as SchemaTooNewFailure).schemaVersion, 99);
      expect(books.stored, isEmpty);
      expect(periodicals.rows, isEmpty);
    },
  );

  test(
    'ImportController surfaces AsyncError on a unrecognized failure path',
    () async {
      // Unrecognized format returns a Right(summary with null format), not an
      // error — verify the controller still lands in data state with no books.
      final useCase = ImportLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: _MemBookRepo(),
        wishlistRepo: _MemWishlistRepo(),
        periodicalRepo: FakePeriodicals(),
      );
      final container = ProviderContainer(
        overrides: [
          importLibraryUseCaseProvider.overrideWith((ref) async => useCase),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(importControllerProvider.notifier)
          .importText('not a known format');
      final state = container.read(importControllerProvider);

      expect(state.hasValue, isTrue);
      expect(state.value!.format, isNull);
      expect(state.value!.parseErrors, isNotEmpty);
    },
  );

  test('importFile reads the picked file under the text cap, imports it '
      'through the text path and removes the copy', () async {
    final useCase = ImportLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: _MemBookRepo(),
      wishlistRepo: _MemWishlistRepo(),
      periodicalRepo: FakePeriodicals(),
    );
    final container = ProviderContainer(
      overrides: [
        importLibraryUseCaseProvider.overrideWith((ref) async => useCase),
        documentPickerProvider.overrideWith((ref) async => picker),
      ],
    );
    addTearDown(container.dispose);

    final json = jsonEncode({
      'schemaVersion': 3,
      'exportedAt': 0,
      'books': [
        {'title': 'FromBytes', 'isbn': '222'},
      ],
      'wishlist': <dynamic>[],
    });

    picker.willPick(utf8.encode(json));
    final problem = await container
        .read(importControllerProvider.notifier)
        .importFile();
    final state = container.read(importControllerProvider);

    expect(problem, isNull);
    expect(state.value!.format, ImportFormat.pitakaJson);
    expect(state.value!.booksAdded, 1);
    // The picker was asked once, with the cap the parsers have for a text.
    expect(picker.caps, [ImportLimits.defaults.maxTextChars]);
    expect(picker.caps.single, 64 * 1024 * 1024);
    // The copy was a plain duplicate of the user's file: it is gone.
    expect(picker.discarded, hasLength(1));
    expect(picker.copiesOnDisk(), isEmpty);
  });

  test('importFile refuses a picked ZIP: nothing is written, no use case '
      'and no cover store is asked for, and the copy is removed '
      '(D29)', () async {
    // Until BR7 this file was a valid Pitak bundle and its book was
    // imported: `library.json` with one row, written by a real ZIP encoder.
    final libraryJson = utf8.encode(
      jsonEncode({
        'schemaVersion': 3,
        'exportedAt': 0,
        'books': [
          {'title': 'Bundled', 'isbn': '333'},
        ],
        'wishlist': <dynamic>[],
      }),
    );
    final archive = Archive()
      ..addFile(ArchiveFile('library.json', libraryJson.length, libraryJson));
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
    // Sanity: the bytes really start with the ZIP magic.
    expect(zipBytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);

    final books = _MemBookRepo();
    final asked = <String>[];
    final container = ProviderContainer(
      overrides: [
        // Neither may be asked for: the refusal needs no use case, and a
        // cover store is what an import WITH pictures would open.
        importLibraryUseCaseProvider.overrideWith((ref) async {
          asked.add('use case');
          return ImportLibraryUseCase(
            jsonParser: const PitakaJsonImporter(),
            bookRepo: books,
            wishlistRepo: _MemWishlistRepo(),
            periodicalRepo: FakePeriodicals(),
          );
        }),
        bundleCoverFilesProvider.overrideWith((ref) async {
          asked.add('cover store');
          throw StateError('Import must not ask for a cover store');
        }),
        documentPickerProvider.overrideWith((ref) async => picker),
      ],
    );
    addTearDown(container.dispose);

    picker.willPick(zipBytes);
    final problem = await container
        .read(importControllerProvider.notifier)
        .importFile();
    final state = container.read(importControllerProvider);

    // The page is told why, and says so. Nothing was imported, so the
    // state is what it was before: idle, with no summary and no error.
    expect(problem, PickedFileProblem.zipFile);
    expect(state.hasValue, isTrue);
    expect(state.value, isNull);
    expect(books.stored, isEmpty);
    expect(asked, isEmpty);
    expect(picker.discarded, hasLength(1));
    expect(picker.copiesOnDisk(), isEmpty);
  });

  // How the controller behaves OVER TIME. These rules were tested through
  // the bundle route until BR7 removed it; they belong to every import, so
  // they are held here on the route that stays.
  group('one import at a time, and it outlives its page', () {
    final oneBook = jsonEncode({
      'schemaVersion': 3,
      'exportedAt': 0,
      'books': [
        {'title': 'A', 'isbn': '111'},
      ],
      'wishlist': <dynamic>[],
    });

    ProviderContainer containerOver(_MemBookRepo books) => ProviderContainer(
      overrides: [
        importLibraryUseCaseProvider.overrideWith(
          (ref) async => ImportLibraryUseCase(
            jsonParser: const PitakaJsonImporter(),
            bookRepo: books,
            wishlistRepo: _MemWishlistRepo(),
            periodicalRepo: FakePeriodicals(),
          ),
        ),
        documentPickerProvider.overrideWith((ref) async => picker),
      ],
    );

    test('a second submit while one runs is ignored', () async {
      final books = _HeldBookRepo();
      final c = containerOver(books);
      addTearDown(c.dispose);
      final sub = c.listen(importControllerProvider, (_, _) {});
      addTearDown(sub.close);
      final controller = c.read(importControllerProvider.notifier);

      final running = controller.importText(oneBook);
      await books.entered.future;
      expect(c.read(importControllerProvider).isLoading, isTrue);

      // Both ways in. An ignored submit returns at once; one that was NOT
      // ignored would wait for the held transaction and never get here.
      var ignored = 0;
      unawaited(controller.importText(oneBook).then((_) => ignored++));
      unawaited(controller.importFile().then((_) => ignored++));
      await Future<void>.delayed(Duration.zero);
      expect(ignored, 2);
      // The second way in did not even open the picker.
      expect(picker.caps, isEmpty);
      expect(books.transactions, 1);
      expect(c.read(importControllerProvider).isLoading, isTrue);

      books.release.complete();
      await running;
      expect(c.read(importControllerProvider).requireValue!.booksAdded, 1);
      expect(books.stored, hasLength(1));
    });

    test('the run survives its page: nobody listens, and the controller '
        'stays until the import is over', () async {
      final books = _HeldBookRepo();
      final c = containerOver(books);
      addTearDown(c.dispose);
      // No listener, as after the Import page was left.
      final running = c
          .read(importControllerProvider.notifier)
          .importText(oneBook);
      await books.entered.future;
      await c.pump();
      expect(c.exists(importControllerProvider), isTrue);
      expect(c.read(importControllerProvider).isLoading, isTrue);

      books.release.complete();
      await running;
      expect(c.read(importControllerProvider).requireValue!.booksAdded, 1);
      expect(books.stored, hasLength(1));
      // And it is let go once the run is over.
      await c.pump();
      expect(c.exists(importControllerProvider), isFalse);
    });

    test('a disposal in the middle of a run: the import still finishes, '
        'and the controller touches no state afterwards', () async {
      final books = _HeldBookRepo();
      final c = containerOver(books);
      final controller = c.read(importControllerProvider.notifier);
      final running = controller.importText(oneBook);
      await books.entered.future;

      c.dispose();
      books.release.complete();
      // Setting state, or refreshing the lists, on a disposed controller
      // throws. The run must end without doing either.
      await running;
      expect(books.stored, hasLength(1));

      // A disposed controller starts nothing new.
      await controller.importText(oneBook);
      expect(books.transactions, 1);
      expect(books.stored, hasLength(1));
    });

    test('a disposal in the middle of a run that then THROWS: nothing '
        'reaches the caller', () async {
      // The page that started the run is gone; an error it can no longer
      // show must not come back at it as an unhandled one.
      final books = _HeldBookRepo()..throwsWhenReleased = true;
      final c = containerOver(books);
      final running = c
          .read(importControllerProvider.notifier)
          .importText(oneBook);
      await books.entered.future;

      c.dispose();
      books.release.complete();
      await running;
      expect(books.stored, isEmpty);
    });

    test('an unexpected throw becomes a safe failure, without the private '
        'text of the error', () async {
      final c = ProviderContainer(
        overrides: [
          importLibraryUseCaseProvider.overrideWith(
            (ref) => throw StateError('private path /data/user/0/secret'),
          ),
        ],
      );
      addTearDown(c.dispose);

      await c.read(importControllerProvider.notifier).importText(oneBook);

      final error = c.read(importControllerProvider).error;
      expect(error, isA<UnexpectedFailure>());
      expect((error! as UnexpectedFailure).debugReason, 'Import failed.');
      expect('$error', isNot(contains('private path')));
      expect(c.read(catalogueChangesProvider), 0, reason: 'nothing written');
    });
  });

  // Decision D24: what the CONTROLLER does between the tap on "Choose
  // file" and the import. The file's own way (pick, look, read, remove the
  // copy) is tested in `picked_text_file_test.dart`.
  group('a chosen file (D24)', () {
    final oneBook = jsonEncode({
      'schemaVersion': 3,
      'exportedAt': 0,
      'books': [
        {'title': 'A', 'isbn': '111'},
      ],
      'wishlist': <dynamic>[],
    });
    final oneBookFile = utf8.encode(oneBook);

    late _MemBookRepo books;

    /// How often the use case was asked for: 0 means "no import started".
    late int useCasesAsked;

    setUp(() {
      books = _MemBookRepo();
      useCasesAsked = 0;
    });

    ProviderContainer container() => ProviderContainer(
      overrides: [
        importLibraryUseCaseProvider.overrideWith((ref) async {
          useCasesAsked++;
          return ImportLibraryUseCase(
            jsonParser: const PitakaJsonImporter(),
            bookRepo: books,
            wishlistRepo: _MemWishlistRepo(),
            periodicalRepo: FakePeriodicals(),
          );
        }),
        documentPickerProvider.overrideWith((ref) async => picker),
      ],
    );

    /// A container somebody listens to, as while the Import page is open.
    ProviderContainer watched() {
      final c = container();
      addTearDown(c.dispose);
      final sub = c.listen(importControllerProvider, (_, _) {});
      addTearDown(sub.close);
      return c;
    }

    const answers = <(DocumentPickResult, PickedFileProblem)>[
      (DocumentPickTooLarge(), PickedFileProblem.tooLarge),
      (DocumentPickUnreadable(), PickedFileProblem.unreadable),
      (DocumentPickNotSaved(), PickedFileProblem.notSaved),
      (DocumentPickUnavailable(), PickedFileProblem.unavailable),
      (DocumentPickFailed(), PickedFileProblem.failed),
    ];
    for (final (answer, expected) in answers) {
      test('${answer.runtimeType}: the page is told "${expected.name}", '
          'nothing is imported, and the state is what it was', () async {
        final c = watched();
        picker.willAnswer(answer);

        final problem = await c
            .read(importControllerProvider.notifier)
            .importFile();

        expect(problem, expected);
        final state = c.read(importControllerProvider);
        expect(state.isLoading, isFalse);
        expect(state.hasError, isFalse);
        expect(state.value, isNull);
        expect(useCasesAsked, 0);
        expect(books.stored, isEmpty);
      });
    }

    test('closing the picker says nothing and keeps an earlier '
        'summary', () async {
      final c = watched();
      final controller = c.read(importControllerProvider.notifier);
      await controller.importText(oneBook);
      final earlier = c.read(importControllerProvider).requireValue;
      expect(earlier!.booksAdded, 1);

      // Nothing is scripted: the fake picker answers "cancelled".
      final said = c.read(catalogueChangesProvider);
      expect(await controller.importFile(), isNull);

      expect(c.read(catalogueChangesProvider), said, reason: 'no import');
      expect(picker.caps, hasLength(1), reason: 'the picker did open');
      expect(c.read(importControllerProvider).value, same(earlier));
      expect(books.stored, hasLength(1));
    });

    test('a file that is not taken keeps an earlier summary too', () async {
      final c = watched();
      final controller = c.read(importControllerProvider.notifier);
      await controller.importText(oneBook);
      final earlier = c.read(importControllerProvider).requireValue;

      picker.willPick([0x50, 0x4B, 0x03, 0x04, 1, 2, 3]);
      expect(await controller.importFile(), PickedFileProblem.zipFile);

      expect(c.read(importControllerProvider).value, same(earlier));
      expect(books.stored, hasLength(1));
    });

    test('closing the picker keeps an earlier FAILURE on the page', () async {
      final c = watched();
      final controller = c.read(importControllerProvider.notifier);
      await controller.importText(
        jsonEncode({
          'schemaVersion': 99,
          'books': <dynamic>[],
          'wishlist': <dynamic>[],
        }),
      );
      expect(
        c.read(importControllerProvider).error,
        isA<SchemaTooNewFailure>(),
      );

      expect(await controller.importFile(), isNull);

      expect(
        c.read(importControllerProvider).error,
        isA<SchemaTooNewFailure>(),
      );
    });

    test('"loading" from the tap on; while the picker is open a second '
        'tap and a pasted text are ignored', () async {
      final c = watched();
      final controller = c.read(importControllerProvider.notifier);
      final pickerOpen = Completer<void>();
      picker
        ..holdNextPick = pickerOpen
        ..willPick(oneBookFile);

      final running = controller.importFile();
      await pumpEventQueue();
      expect(picker.caps, hasLength(1), reason: 'the picker is open');
      expect(c.read(importControllerProvider).isLoading, isTrue);

      // Both return at once. One that was NOT ignored would open a second
      // picker, or import the pasted text.
      expect(await controller.importFile(), isNull);
      await controller.importText(oneBook);
      expect(picker.caps, hasLength(1));
      expect(useCasesAsked, 0);
      expect(books.stored, isEmpty);
      expect(c.read(importControllerProvider).isLoading, isTrue);

      pickerOpen.complete();
      expect(await running, isNull);
      expect(c.read(importControllerProvider).requireValue!.booksAdded, 1);
      expect(books.stored, hasLength(1));
    });

    test('the run survives its page while the picker is open: nobody '
        'listens, and the file is still imported', () async {
      final c = container();
      addTearDown(c.dispose);
      final pickerOpen = Completer<void>();
      picker
        ..holdNextPick = pickerOpen
        ..willPick(oneBookFile);

      // No listener, as after the Import page was left.
      final running = c.read(importControllerProvider.notifier).importFile();
      await pumpEventQueue();
      await c.pump();
      expect(c.exists(importControllerProvider), isTrue);

      pickerOpen.complete();
      expect(await running, isNull);
      expect(books.stored, hasLength(1));
      expect(picker.copiesOnDisk(), isEmpty);
      // And it is let go once the run is over.
      await c.pump();
      expect(c.exists(importControllerProvider), isFalse);
    });

    test('a teardown while the picker is open: the copy is still removed, '
        'nothing is imported, and nothing throws', () async {
      final c = container();
      final pickerOpen = Completer<void>();
      picker
        ..holdNextPick = pickerOpen
        ..willPick(oneBookFile);

      final running = c.read(importControllerProvider.notifier).importFile();
      await pumpEventQueue();
      expect(picker.caps, hasLength(1), reason: 'the picker is open');

      c.dispose();
      pickerOpen.complete();
      // Reading a provider, or setting state, on a disposed controller
      // throws. The run must end without doing either.
      expect(await running, isNull);

      expect(picker.discarded, hasLength(1));
      expect(picker.copiesOnDisk(), isEmpty);
      expect(useCasesAsked, 0);
      expect(books.stored, isEmpty);
    });

    test('a picker that cannot be set up is a pick that failed, without '
        'the private text of the error', () async {
      final c = ProviderContainer(
        overrides: [
          documentPickerProvider.overrideWith(
            (ref) => throw StateError('private path /data/user/0/secret'),
          ),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(importControllerProvider, (_, _) {});
      addTearDown(sub.close);

      final problem = await c
          .read(importControllerProvider.notifier)
          .importFile();

      expect(problem, PickedFileProblem.failed);
      final state = c.read(importControllerProvider);
      expect(state.hasError, isFalse);
      expect(state.value, isNull);
    });

    test('bytes that are not UTF-8 reach the importer as text and end as '
        '"import failed", not as a crash', () async {
      final c = watched();
      picker.willPick([0xFF, 0xFE, 0xFD, 0x00, 0x01]);

      final problem = await c
          .read(importControllerProvider.notifier)
          .importFile();

      expect(problem, isNull, reason: 'the file was taken');
      final summary = c.read(importControllerProvider).requireValue!;
      expect(summary.format, isNull);
      expect(summary.parseErrors, [kImportUnrecognizedFormatMessage]);
      expect(books.stored, isEmpty);
    });
  });

  test('S9: import refreshes a kept-alive Magazines list through the shared '
      'library signal', () async {
    final books = _MemBookRepo();
    final periodicals = FakePeriodicals();
    final useCase = ImportLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: books,
      wishlistRepo: _MemWishlistRepo(),
      periodicalRepo: periodicals,
    );
    final container = ProviderContainer(
      overrides: [
        importLibraryUseCaseProvider.overrideWith((ref) async => useCase),
        catalogueItemRepositoryProvider.overrideWith((ref) async => books),
        periodicalRepositoryProvider.overrideWith((ref) async => periodicals),
        settingsRepositoryProvider.overrideWith((ref) async => FakeSettings()),
        nowTickProvider.overrideWith((ref) => 0),
      ],
    );
    addTearDown(container.dispose);
    final librarySub = container.listen(libraryControllerProvider, (_, _) {});
    addTearDown(librarySub.close);
    var periodicalEvents = 0;
    final sub = container.listen(
      periodicalsControllerProvider,
      (_, _) => periodicalEvents++,
      fireImmediately: true,
    );
    addTearDown(sub.close);
    await container.read(libraryControllerProvider.future);
    expect(await container.read(periodicalsControllerProvider.future), isEmpty);
    await container.pump();
    final baseline = periodicalEvents;

    await container
        .read(importControllerProvider.notifier)
        .importText(
          jsonEncode({
            'schemaVersion': 4,
            'exportedAt': 0,
            'periodicals': [
              {'periodicalUid': 'p1', 'title': 'Chandamama'},
            ],
            'books': [
              {
                'bookUid': 'u1',
                'title': 'Chandamama — No 3',
                'kind': 'magazine-issue',
                'issue': {'periodicalUid': 'p1', 'issueNumber': 3},
              },
            ],
            'wishlist': <Object>[],
          }),
        );
    expect(container.read(importControllerProvider).hasValue, isTrue);
    await container.pump();

    final entries = await container.read(periodicalsControllerProvider.future);
    expect(periodicalEvents, greaterThan(baseline));
    expect(entries.map((entry) => entry.periodical.title), ['Chandamama']);
  });
}
