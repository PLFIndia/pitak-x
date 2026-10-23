import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/import_export/infrastructure/pitaka_json_importer.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/merge/library_merge_engine.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/settings/domain/library_namespace.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';

import '../library/replacement_harness.dart';
import '../library/replacement_test_guard.dart';
import '../periodicals/application/periodical_fakes.dart';
import '../vault/vault_repository_write_stub.dart';

class _LoanVault with VaultWriteUnsupported implements VaultRepository {
  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async => right(
    const VaultData(
      borrowers: [Borrower(id: 1, name: 'Test borrower')],
      loans: [Loan(itemId: 7, borrowerId: 1, lentDate: 1)],
    ),
  );
}

/// In-memory book repo: just enough surface for the merge use case.
class _FakeBooks implements CatalogueItemRepository {
  _FakeBooks(this._books);

  // CatalogueItemRepository additions (review 2026-09-03): fakes default to "no
  // match" and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, CatalogueItem?>> findByUid(String itemUid) async =>
      right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  final List<CatalogueItem> _books;
  int _nextId = 1000;

  /// Test-only failure injection for [replaceAll].
  Failure? replaceAllFailure;

  /// Test-only failure injection for [insertAll] (N07: a failed Join union).
  Failure? insertAllFailure;

  /// How many times [update] was called (N07: a refused resolution must not
  /// reach the repository at all).
  int updateCalls = 0;

  /// How many times [insert] was called.
  int insertCalls = 0;

  List<CatalogueItem> get books => _books;

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async => right(_books);

  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) async {
    insertCalls++;
    final stored = book.copyWith(
      id: book.id == CatalogueItem.emptyId ? _nextId++ : book.id,
      itemUid: book.itemUid ?? 'minted-$_nextId',
    );
    _books.add(stored);
    return right(stored);
  }

  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem book) async {
    updateCalls++;
    final i = _books.indexWhere((b) => b.id == book.id);
    if (i < 0) return left(const NotFoundFailure());
    _books[i] = book;
    return right(book);
  }

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    _books.removeWhere((b) => b.id == id);
    return right(unit);
  }

  // Unused by the merge use case.
  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    final rows = query.isSearch ? const <CatalogueItem>[] : _books;
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
  Future<Either<Failure, List<String>>> distinctLanguages() async => right([]);
  @override
  Future<Either<Failure, List<String>>> distinctSourceDetails(
    ItemSourceType type,
  ) async => right(const []);
  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async =>
      right(_books.where((b) => b.id == id).firstOrNull);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);
  @override
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async =>
      right(null);
  @override
  Future<Either<Failure, int>> insertAll(List<CatalogueItem> books) async {
    // Mirrors the atomic contract: failure leaves the store untouched.
    final failure = insertAllFailure;
    if (failure != null) return left(failure);
    for (final b in books) {
      await insert(b);
    }
    return right(books.length);
  }

  @override
  Future<Either<Failure, int>> replaceAll(List<CatalogueItem> books) async {
    // Mirrors the transactional contract: failure leaves the store untouched.
    final failure = replaceAllFailure;
    if (failure != null) return left(failure);
    _books.clear();
    for (final b in books) {
      await insert(b);
    }
    return right(books.length);
  }
}

/// In-memory library identity: tracks the id/name the use case adopts (N07:
/// the use case talks to the `LibraryNamespace` port, never the settings
/// repository). [adoptFailure] injects a failed identity write.
class _FakeNamespace implements LibraryNamespace {
  _FakeNamespace({this.libraryId = '', this.libraryName = ''});
  String libraryId;
  String libraryName;

  /// When set, [adopt] fails with it and changes nothing.
  Failure? adoptFailure;

  /// How many times [adopt] was called (any outcome).
  int adoptCalls = 0;

  @override
  Future<Either<Failure, LibraryIdentity>> current() async {
    if (libraryId.isEmpty) libraryId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    return right(LibraryIdentity(id: libraryId, name: libraryName));
  }

  @override
  Future<Either<Failure, Unit>> adopt({
    required String id,
    required String name,
  }) async {
    adoptCalls++;
    final failure = adoptFailure;
    if (failure != null) return left(failure);
    libraryId = id;
    if (name.isNotEmpty) libraryName = name;
    return right(unit);
  }
}

/// Builds a minimal Pitaka-JSON export string with the given envelope + books.
/// Passing [periodicals] makes it a schema-v4 document (ADR 0014 W1) — nested
/// `issue{}` objects in rows ride along via jsonEncode.
String exportJson({
  required List<Map<String, dynamic>> books,
  List<Map<String, dynamic>> periodicals = const [],
  String? libraryId,
  String? libraryName,
}) {
  return jsonEncode({
    'schemaVersion': periodicals.isEmpty ? 3 : 4,
    if (libraryId != null) 'libraryId': libraryId,
    if (libraryName != null) 'libraryName': libraryName,
    'books': books,
    if (periodicals.isNotEmpty) 'periodicals': periodicals,
    'wishlist': <Object>[],
  });
}

void main() {
  const matchingId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const otherId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  test('M03: overwrite refuses to drop an existing loan identity', () async {
    final tmp = Directory.systemTemp.createTempSync('m03_merge_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = VaultStore(baseDir: tmp.path);
    File(store.dbPath).writeAsBytesSync([1]);
    store.writeBlob('synthetic.blob.only');
    final books = _FakeBooks([
      const CatalogueItem(id: 7, itemUid: 'loaned', title: 'Loaned book'),
    ]);
    // Built through the REAL provider: the identity port is the real
    // SettingsController over this settings repo (N07), so the assertion
    // below checks the ID that actually reaches disk.
    final settings = ReplacementSettings()..id = matchingId;
    final container = ProviderContainer(
      overrides: [
        vaultStoreProvider.overrideWith((ref) async => store),
        vaultRepositoryProvider.overrideWithValue(_LoanVault()),
        catalogueItemRepositoryProvider.overrideWith((ref) async => books),
        periodicalRepositoryProvider.overrideWith(
          (ref) async => FakePeriodicals(),
        ),
        settingsRepositoryProvider.overrideWith((ref) async => settings),
      ],
    );
    addTearDown(container.dispose);
    await container.read(vaultSessionControllerProvider.future);
    final unlocked = await container
        .read(vaultSessionControllerProvider.notifier)
        .unlock(SecretBytes(Uint8List.fromList([1, 2, 3])));
    expect(unlocked.isRight(), isTrue);
    final useCase = await container.read(mergeLibraryUseCaseProvider.future);
    final result = await useCase.applyOverwrite(
      const MergeDiffersDecision(
        incomingBooks: [
          CatalogueItem(id: 7, itemUid: 'unrelated', title: 'Other book'),
        ],
        incomingLibraryId: otherId,
        incomingLibraryName: 'Other',
        localLibraryName: 'Mine',
        localIsEmpty: false,
      ),
    );
    expect(result.isLeft(), isTrue);
    expect(books.books.single.itemUid, 'loaned');
    expect(books.books.single.id, 7);
    expect(settings.id, matchingId);
  });

  test('rejects a non-Pitak file with a validation failure', () async {
    final useCase = MergeLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: _FakeBooks([]),
      periodicalRepo: FakePeriodicals(),
      replacementGuard: FakeReplacementGuard(),
      planner: planMergeInline,
      namespace: _FakeNamespace(libraryId: matchingId),
    );
    final res = await useCase.call('title,author\nFoo,Bar');
    expect(res.isLeft(), isTrue);
    expect(res.getLeft().toNullable(), isA<ValidationFailure>());
  });

  test('matching library id merges (add-only union, auto-applied)', () async {
    final repo = _FakeBooks([
      const CatalogueItem(
        id: 1,
        itemUid: 'u1',
        title: 'Godaan',
        isbn: '111',
        addedDate: 1,
      ),
    ]);
    final useCase = MergeLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: repo,
      periodicalRepo: FakePeriodicals(),
      namespace: _FakeNamespace(libraryId: matchingId),
      replacementGuard: FakeReplacementGuard(),
      planner: planMergeInline,
    );
    final json = exportJson(
      libraryId: matchingId,
      books: [
        {'bookUid': 'u2', 'title': '1984', 'isbn': '222'},
      ],
    );

    final res = await useCase.call(json);
    final outcome = res.getOrElse((f) => fail('merge failed: $f'));
    expect(outcome, isA<MergeMerged>());
    final merged = outcome as MergeMerged;
    expect(merged.result.added, 1);
    expect(repo.books.any((b) => b.title == '1984'), isTrue);
    // The added book KEEPS its incoming uid so future merges reconcile.
    expect(repo.books.firstWhere((b) => b.title == '1984').itemUid, 'u2');
  });

  group('N10-c — the plan is computed through the injected planner', () {
    test('the use case awaits the planner and applies ITS plan', () async {
      // The planner is the seam that moves planMerge off the UI isolate. The
      // use case must call it (not planMerge directly) and act on what it
      // returns — here a planner that reports an empty plan, so nothing is
      // inserted even though the file has a genuinely new book.
      final repo = _FakeBooks([
        const CatalogueItem(
          id: 1,
          itemUid: 'u1',
          title: 'Godaan',
          isbn: '111',
          addedDate: 1,
        ),
      ]);
      var calls = 0;
      List<CatalogueItem>? seenLocal;
      List<CatalogueItem>? seenIncoming;
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: repo,
        periodicalRepo: FakePeriodicals(),
        namespace: _FakeNamespace(libraryId: matchingId),
        replacementGuard: FakeReplacementGuard(),
        planner:
            (local, incoming, localPeriodicals, incomingPeriodicals) async {
              calls++;
              seenLocal = local;
              seenIncoming = incoming;
              return const MergePlan(
                toAdd: [],
                conflicts: [],
                possibleDuplicates: [],
                identical: 0,
              );
            },
      );
      final json = exportJson(
        libraryId: matchingId,
        books: [
          {'bookUid': 'u2', 'title': '1984', 'isbn': '222'},
        ],
      );

      final res = await useCase.call(json);
      final outcome = res.getOrElse((f) => fail('merge failed: $f'));
      expect(calls, 1);
      expect(seenLocal!.single.itemUid, 'u1');
      expect(seenIncoming!.single.itemUid, 'u2');
      expect((outcome as MergeMerged).result.added, 0);
      expect(repo.books.any((b) => b.title == '1984'), isFalse);
    });

    test('the composition root wires the worker-isolate planner', () async {
      // N14 makes `planner` a required port; this pins that production DI
      // injects the infrastructure implementation and not a stub, by driving
      // a matching-ID merge through the REAL provider and checking the union
      // lands (the plan must have been computed somewhere).
      final repo = _FakeBooks([
        const CatalogueItem(
          id: 1,
          itemUid: 'u1',
          title: 'Godaan',
          addedDate: 1,
        ),
      ]);
      final settings = ReplacementSettings()..id = matchingId;
      final container = ProviderContainer(
        overrides: [
          catalogueItemRepositoryProvider.overrideWith((ref) async => repo),
          periodicalRepositoryProvider.overrideWith(
            (ref) async => FakePeriodicals(),
          ),
          settingsRepositoryProvider.overrideWith((ref) async => settings),
        ],
      );
      addTearDown(container.dispose);
      final useCase = await container.read(mergeLibraryUseCaseProvider.future);
      final res = await useCase.call(
        exportJson(
          libraryId: matchingId,
          books: [
            {'bookUid': 'u2', 'title': 'Brand New'},
          ],
        ),
      );
      final outcome = res.getOrElse((f) => fail('merge failed: $f'));
      expect((outcome as MergeMerged).result.added, 1);
      expect(repo.books.any((b) => b.title == 'Brand New'), isTrue);
    });
  });

  test('differing library id returns a decision, applies nothing', () async {
    final repo = _FakeBooks([
      const CatalogueItem(id: 1, itemUid: 'u1', title: 'Godaan', addedDate: 1),
    ]);
    final useCase = MergeLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: repo,
      periodicalRepo: FakePeriodicals(),
      namespace: _FakeNamespace(libraryId: matchingId, libraryName: 'Mine'),
      replacementGuard: FakeReplacementGuard(),
      planner: planMergeInline,
    );
    final json = exportJson(
      libraryId: otherId,
      libraryName: 'Riverside',
      books: [
        {'bookUid': 'u2', 'title': 'New One', 'isbn': '222'},
      ],
    );

    final res = await useCase.call(json);
    final outcome = res.getOrElse((f) => fail('failed: $f'));
    expect(outcome, isA<MergeDiffersDecision>());
    final d = outcome as MergeDiffersDecision;
    expect(d.incomingLibraryId, otherId);
    expect(d.incomingLibraryName, 'Riverside');
    expect(d.localLibraryName, 'Mine');
    expect(d.localIsEmpty, isFalse);
    // Nothing applied yet.
    expect(repo.books, hasLength(1));
  });

  test('a corrupt incoming id is treated as absent → decision', () async {
    final repo = _FakeBooks([]);
    final useCase = MergeLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: repo,
      periodicalRepo: FakePeriodicals(),
      namespace: _FakeNamespace(libraryId: matchingId),
      replacementGuard: FakeReplacementGuard(),
      planner: planMergeInline,
    );
    final json = exportJson(
      libraryId: 'NOT-A-VALID-ID',
      books: [
        {'title': 'X'},
      ],
    );

    final res = await useCase.call(json);
    final outcome = res.getOrElse((f) => fail('failed: $f'));
    expect(outcome, isA<MergeDiffersDecision>());
    expect((outcome as MergeDiffersDecision).incomingLibraryId, '');
  });

  test('applyJoin unions books and adopts the incoming id+name', () async {
    final repo = _FakeBooks([]);
    final settings = _FakeNamespace(libraryId: matchingId, libraryName: 'Mine');
    final useCase = MergeLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: repo,
      periodicalRepo: FakePeriodicals(),
      namespace: settings,
      replacementGuard: FakeReplacementGuard(),
      planner: planMergeInline,
    );

    const decision = MergeDiffersDecision(
      incomingBooks: [
        CatalogueItem(
          itemUid: 'u9',
          title: 'Joined',
          isbn: '999',
          addedDate: 1,
        ),
      ],
      incomingLibraryId: otherId,
      incomingLibraryName: 'Riverside',
      localLibraryName: 'Mine',
      localIsEmpty: true,
    );

    final res = await useCase.applyJoin(decision);
    final result = res.getOrElse((f) => fail('join failed: $f'));
    expect(result.added, 1);
    expect(repo.books.any((b) => b.title == 'Joined'), isTrue);
    expect(settings.libraryId, otherId);
    expect(settings.libraryName, 'Riverside');
  });

  test('applyOverwrite replaces local books and adopts the id', () async {
    final repo = _FakeBooks([
      const CatalogueItem(
        id: 1,
        itemUid: 'old',
        title: 'OldBook',
        addedDate: 1,
      ),
    ]);
    final settings = _FakeNamespace(libraryId: matchingId, libraryName: 'Mine');
    final useCase = MergeLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: repo,
      periodicalRepo: FakePeriodicals(),
      namespace: settings,
      replacementGuard: FakeReplacementGuard(),
      planner: planMergeInline,
    );

    const decision = MergeDiffersDecision(
      incomingBooks: [
        CatalogueItem(itemUid: 'u9', title: 'FreshReplica', addedDate: 1),
      ],
      incomingLibraryId: otherId,
      incomingLibraryName: 'Riverside',
      localLibraryName: 'Mine',
      localIsEmpty: false,
    );

    final res = await useCase.applyOverwrite(decision);
    expect(res.isRight(), isTrue);
    expect(repo.books.any((b) => b.title == 'OldBook'), isFalse);
    expect(repo.books.any((b) => b.title == 'FreshReplica'), isTrue);
    expect(settings.libraryId, otherId);
  });

  // Regression for REVIEW_FINDINGS_2 S5 Major: two incoming rows sharing a
  // new ISBN must not both reach the DB (UNIQUE isbn) — the first is added,
  // the second surfaced, and the reported result matches the committed state.
  test(
    'duplicate ISBN within one file: one added, one surfaced, DB matches',
    () async {
      final repo = _FakeBooks([]);
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: repo,
        periodicalRepo: FakePeriodicals(),
        namespace: _FakeNamespace(libraryId: matchingId),
        replacementGuard: FakeReplacementGuard(),
        planner: planMergeInline,
      );
      final json = exportJson(
        libraryId: matchingId,
        books: [
          {'bookUid': 'uA', 'title': 'Sapiens', 'isbn': '9780001'},
          {'bookUid': 'uB', 'title': 'Sapiens dupe', 'isbn': '978-0001'},
        ],
      );

      final res = await useCase.call(json);
      final merged =
          (res.getOrElse((f) => fail('merge failed: $f'))) as MergeMerged;
      expect(merged.result.added, 1);
      expect(merged.result.possibleDuplicates, hasLength(1));
      // Reported state == committed state: exactly one new row.
      expect(repo.books, hasLength(1));
      expect(repo.books.single.itemUid, 'uA');
    },
  );

  // Regression for REVIEW_FINDINGS_2 S5 Major: overwrite must be atomic — a
  // failed replace leaves the local catalogue intact and does NOT adopt the
  // incoming library identity.
  test(
    'applyOverwrite failure keeps the local catalogue and settings',
    () async {
      final repo = _FakeBooks([
        const CatalogueItem(
          id: 1,
          itemUid: 'old',
          title: 'OldBook',
          addedDate: 1,
        ),
      ])..replaceAllFailure = const StorageFailure('disk full');
      final settings = _FakeNamespace(
        libraryId: matchingId,
        libraryName: 'Mine',
      );
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: repo,
        periodicalRepo: FakePeriodicals(),
        namespace: settings,
        replacementGuard: FakeReplacementGuard(),
        planner: planMergeInline,
      );

      const decision = MergeDiffersDecision(
        incomingBooks: [
          CatalogueItem(itemUid: 'u9', title: 'FreshReplica', addedDate: 1),
        ],
        incomingLibraryId: otherId,
        incomingLibraryName: 'Riverside',
        localLibraryName: 'Mine',
        localIsEmpty: false,
      );

      final res = await useCase.applyOverwrite(decision);
      expect(res.isLeft(), isTrue);
      expect(repo.books.map((b) => b.title), ['OldBook']);
      expect(settings.libraryId, matchingId);
      expect(settings.libraryName, 'Mine');
    },
  );

  group('applyResolution', () {
    test('keepMine is a no-op', () async {
      final repo = _FakeBooks([
        const CatalogueItem(
          id: 1,
          itemUid: 'u1',
          title: 'Local',
          genre: 'A',
          addedDate: 1,
        ),
      ]);
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: repo,
        periodicalRepo: FakePeriodicals(),
        namespace: _FakeNamespace(),
        replacementGuard: FakeReplacementGuard(),
        planner: planMergeInline,
      );
      await useCase.applyResolution(
        local: repo.books.first,
        incoming: const CatalogueItem(
          itemUid: 'u1',
          title: 'Local',
          genre: 'B',
          addedDate: 1,
        ),
        resolution: MergeResolution.keepMine,
      );
      expect(repo.books.single.genre, 'A');
    });

    test('takeTheirs overwrites in place, keeping local id + uid', () async {
      final repo = _FakeBooks([
        const CatalogueItem(
          id: 7,
          itemUid: 'u1',
          title: 'Local',
          genre: 'A',
          addedDate: 1,
        ),
      ]);
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: repo,
        periodicalRepo: FakePeriodicals(),
        namespace: _FakeNamespace(),
        replacementGuard: FakeReplacementGuard(),
        planner: planMergeInline,
      );
      await useCase.applyResolution(
        local: repo.books.first,
        incoming: const CatalogueItem(
          id: 999,
          itemUid: 'uOther',
          title: 'Local',
          genre: 'B',
          addedDate: 2,
        ),
        resolution: MergeResolution.takeTheirs,
      );
      final row = repo.books.single;
      expect(row.id, 7); // local id preserved
      expect(row.itemUid, 'u1'); // local uid preserved
      expect(row.genre, 'B'); // their field taken
    });

    // M09 (user decision 2026-09-09): even when the user picks "take theirs",
    // a photo of the physical book taken on this device is kept; the incoming
    // cover lands only when there is no local cover.
    test('M09: takeTheirs keeps the local PHOTO over an incoming https '
        'cover', () async {
      final repo = _FakeBooks([
        const CatalogueItem(
          id: 7,
          itemUid: 'u1',
          title: 'Local',
          genre: 'A',
          coverUrl: 'covers/photo.jpg',
          addedDate: 1,
        ),
      ]);
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: repo,
        periodicalRepo: FakePeriodicals(),
        namespace: _FakeNamespace(),
        replacementGuard: FakeReplacementGuard(),
        planner: planMergeInline,
      );
      await useCase.applyResolution(
        local: repo.books.first,
        incoming: const CatalogueItem(
          id: 999,
          itemUid: 'uOther',
          title: 'Local',
          genre: 'B',
          coverUrl: 'https://covers.openlibrary.org/b/id/1-L.jpg',
          addedDate: 2,
        ),
        resolution: MergeResolution.takeTheirs,
      );
      final row = repo.books.single;
      expect(row.genre, 'B', reason: 'their catalogue field taken');
      expect(row.coverUrl, 'covers/photo.jpg', reason: 'photo wins');
    });

    test('M09: takeTheirs takes the incoming https cover when there is no '
        'local cover', () async {
      final repo = _FakeBooks([
        const CatalogueItem(id: 7, itemUid: 'u1', title: 'Local', addedDate: 1),
      ]);
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: repo,
        periodicalRepo: FakePeriodicals(),
        namespace: _FakeNamespace(),
        replacementGuard: FakeReplacementGuard(),
        planner: planMergeInline,
      );
      await useCase.applyResolution(
        local: repo.books.first,
        incoming: const CatalogueItem(
          itemUid: 'uOther',
          title: 'Local',
          coverUrl: 'https://covers.openlibrary.org/b/id/1-L.jpg',
          addedDate: 2,
        ),
        resolution: MergeResolution.takeTheirs,
      );
      expect(
        repo.books.single.coverUrl,
        'https://covers.openlibrary.org/b/id/1-L.jpg',
      );
    });

    test(
      'keepBoth inserts a fresh-identity duplicate (no uid, no isbn)',
      () async {
        final repo = _FakeBooks([
          const CatalogueItem(
            id: 1,
            itemUid: 'u1',
            title: 'Dohe',
            isbn: '555',
            addedDate: 1,
          ),
        ]);
        final useCase = MergeLibraryUseCase(
          jsonParser: const PitakaJsonImporter(),
          bookRepo: repo,
          periodicalRepo: FakePeriodicals(),
          namespace: _FakeNamespace(),
          replacementGuard: FakeReplacementGuard(),
          planner: planMergeInline,
        );
        await useCase.applyResolution(
          local: repo.books.first,
          incoming: const CatalogueItem(
            itemUid: 'u1',
            title: 'Dohe',
            isbn: '555',
            genre: 'extra',
            addedDate: 1,
          ),
          resolution: MergeResolution.keepBoth,
        );
        expect(repo.books, hasLength(2));
        final dup = repo.books.firstWhere((b) => b.id != 1);
        // Fresh identity: minted uid (not 'u1'), and ISBN dropped to avoid the
        // unique-column collision with the original row (D2).
        expect(dup.itemUid, isNot('u1'));
        expect(dup.isbn, isNull);
        expect(dup.genre, 'extra'); // catalogue fields preserved
      },
    );

    // N07 part 2: the review UI can now reach these branches, so they get
    // the same two guards every other write path has.
    group('N07 — guards', () {
      test('takeTheirs on an in-file collision (local never persisted) is '
          'refused with a clear message and no repository call', () async {
        // `PossibleDuplicate.local` for an in-file key collision is the
        // EARLIER INCOMING row (engine `keyHolder`), id == emptyId. Before,
        // this reached `update(id: 0)` and came back as a misleading
        // NotFoundFailure.
        final repo = _FakeBooks([]);
        final useCase = MergeLibraryUseCase(
          jsonParser: const PitakaJsonImporter(),
          bookRepo: repo,
          periodicalRepo: FakePeriodicals(),
          namespace: _FakeNamespace(),
          replacementGuard: FakeReplacementGuard(),
          planner: planMergeInline,
        );

        final result = await useCase.applyResolution(
          local: const CatalogueItem(
            itemUid: 'uB',
            title: 'Godaan',
            addedDate: 1,
          ),
          incoming: const CatalogueItem(
            itemUid: 'uB',
            title: 'Godaan (duplicate row)',
            addedDate: 1,
          ),
          resolution: MergeResolution.takeTheirs,
        );

        expect(result.isLeft(), isTrue);
        final failure = result.getLeft().toNullable();
        expect(failure, isA<ValidationFailure>());
        expect(
          (failure! as ValidationFailure).message,
          contains('same file'),
          reason: 'the copy must explain WHY, not say "not found"',
        );
        expect(repo.updateCalls, 0);
        expect(repo.insertCalls, 0);
      });

      test(
        'takeTheirs validates the built book before writing (M15 gate)',
        () async {
          final repo = _FakeBooks([
            const CatalogueItem(
              id: 7,
              itemUid: 'u1',
              title: 'Local',
              addedDate: 1,
            ),
          ]);
          final useCase = MergeLibraryUseCase(
            jsonParser: const PitakaJsonImporter(),
            bookRepo: repo,
            periodicalRepo: FakePeriodicals(),
            namespace: _FakeNamespace(),
            replacementGuard: FakeReplacementGuard(),
            planner: planMergeInline,
          );

          final result = await useCase.applyResolution(
            local: repo.books.first,
            incoming: const CatalogueItem(
              itemUid: 'uOther',
              title: 'Local',
              copyCount: 0, // invalid: must be at least 1
              addedDate: 1,
            ),
            resolution: MergeResolution.takeTheirs,
          );

          expect(result.getLeft().toNullable(), isA<ValidationFailure>());
          expect(repo.updateCalls, 0);
          expect(repo.books.single.copyCount, 1, reason: 'row untouched');
        },
      );

      test('keepBoth validates the fresh copy before inserting', () async {
        final repo = _FakeBooks([
          const CatalogueItem(
            id: 1,
            itemUid: 'u1',
            title: 'Dohe',
            addedDate: 1,
          ),
        ]);
        final useCase = MergeLibraryUseCase(
          jsonParser: const PitakaJsonImporter(),
          bookRepo: repo,
          periodicalRepo: FakePeriodicals(),
          namespace: _FakeNamespace(),
          replacementGuard: FakeReplacementGuard(),
          planner: planMergeInline,
        );

        final result = await useCase.applyResolution(
          local: repo.books.first,
          incoming: const CatalogueItem(
            itemUid: 'u1',
            title: 'Dohe',
            publishedYear: 0, // invalid: outside 1..9999
            addedDate: 1,
          ),
          resolution: MergeResolution.keepBoth,
        );

        expect(result.getLeft().toNullable(), isA<ValidationFailure>());
        expect(repo.insertCalls, 0);
        expect(repo.books, hasLength(1));
      });

      test('takeTheirs writes the NORMALISED book (cover dropped when '
          'disallowed)', () async {
        // `CatalogueItem.validate` normalises rather than rejects a bad cover
        // ref (M15) — the row that lands must be the normalised one.
        final repo = _FakeBooks([
          const CatalogueItem(
            id: 7,
            itemUid: 'u1',
            title: 'Local',
            addedDate: 1,
          ),
        ]);
        final useCase = MergeLibraryUseCase(
          jsonParser: const PitakaJsonImporter(),
          bookRepo: repo,
          periodicalRepo: FakePeriodicals(),
          namespace: _FakeNamespace(),
          replacementGuard: FakeReplacementGuard(),
          planner: planMergeInline,
        );

        final result = await useCase.applyResolution(
          local: repo.books.first,
          incoming: const CatalogueItem(
            itemUid: 'uOther',
            title: 'Local',
            coverUrl: 'https://evil.example/x.jpg',
            addedDate: 1,
          ),
          resolution: MergeResolution.takeTheirs,
        );

        expect(result.isRight(), isTrue);
        expect(repo.books.single.coverUrl, isNull);
      });
    });
  });

  // Review finding N07: "a failed Join can still change future merge
  // identity" — the incoming library ID used to be adopted BEFORE the books
  // were inserted, so a failed insert left this device re-identified with
  // none of the data; the next merge of the same file then auto-applied
  // under the adopted ID with no Join decision. Data first, identity second.
  group('N07 — namespace adoption is coordinated with the data', () {
    const decision = MergeDiffersDecision(
      incomingBooks: [
        CatalogueItem(
          itemUid: 'u9',
          title: 'Their book',
          isbn: '999',
          addedDate: 1,
        ),
      ],
      incomingLibraryId: otherId,
      incomingLibraryName: 'Riverside',
      localLibraryName: 'Mine',
      localIsEmpty: false,
    );

    test('a failed Join insert leaves the local identity untouched', () async {
      final repo = _FakeBooks([])
        ..insertAllFailure = const StorageFailure('disk full');
      final namespace = _FakeNamespace(
        libraryId: matchingId,
        libraryName: 'Mine',
      );
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: repo,
        periodicalRepo: FakePeriodicals(),
        namespace: namespace,
        replacementGuard: FakeReplacementGuard(),
        planner: planMergeInline,
      );

      final res = await useCase.applyJoin(decision);

      expect(res.isLeft(), isTrue);
      expect(repo.books, isEmpty);
      expect(namespace.adoptCalls, 0, reason: 'identity must not be touched');
      expect(namespace.libraryId, matchingId);
      expect(namespace.libraryName, 'Mine');
    });

    test('Join: books land, identity write fails → success with the omission '
        'reported, NOT an error', () async {
      final repo = _FakeBooks([]);
      final namespace = _FakeNamespace(
        libraryId: matchingId,
        libraryName: 'Mine',
      )..adoptFailure = const StorageFailure('prefs write failed');
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: repo,
        periodicalRepo: FakePeriodicals(),
        namespace: namespace,
        replacementGuard: FakeReplacementGuard(),
        planner: planMergeInline,
      );

      final res = await useCase.applyJoin(decision);

      final result = res.getOrElse((f) => fail('join must succeed: $f'));
      expect(result.added, 1);
      expect(repo.books.single.title, 'Their book');
      expect(result.namespace, MergeNamespaceOutcome.adoptionFailed);
      expect(result.hasOmissions, isTrue);
      expect(namespace.libraryId, matchingId, reason: 'old ID still in force');
    });

    test('Join success reports the identity as adopted (id + name)', () async {
      final namespace = _FakeNamespace(
        libraryId: matchingId,
        libraryName: 'Mine',
      );
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: _FakeBooks([]),
        periodicalRepo: FakePeriodicals(),
        namespace: namespace,
        replacementGuard: FakeReplacementGuard(),
        planner: planMergeInline,
      );

      final result = (await useCase.applyJoin(
        decision,
      )).getOrElse((f) => fail('join failed: $f'));

      expect(result.namespace, MergeNamespaceOutcome.adopted);
      expect(result.replaced, isFalse);
      expect(namespace.libraryId, otherId);
      expect(namespace.libraryName, 'Riverside');
    });

    test('a file with no library ID has nothing to adopt', () async {
      final namespace = _FakeNamespace(libraryId: matchingId);
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: _FakeBooks([]),
        periodicalRepo: FakePeriodicals(),
        namespace: namespace,
        replacementGuard: FakeReplacementGuard(),
        planner: planMergeInline,
      );
      const noId = MergeDiffersDecision(
        incomingBooks: [
          CatalogueItem(itemUid: 'u9', title: 'Their book', addedDate: 1),
        ],
        incomingLibraryId: '',
        incomingLibraryName: 'Riverside',
        localLibraryName: 'Mine',
        localIsEmpty: false,
      );

      final result = (await useCase.applyJoin(
        noId,
      )).getOrElse((f) => fail('join failed: $f'));

      expect(result.namespace, MergeNamespaceOutcome.unchanged);
      expect(namespace.adoptCalls, 0);
      expect(namespace.libraryId, matchingId);
    });

    test(
      'Overwrite is reported as a replacement with the real count',
      () async {
        final repo = _FakeBooks([
          const CatalogueItem(
            id: 1,
            itemUid: 'old',
            title: 'OldBook',
            addedDate: 1,
          ),
        ]);
        final namespace = _FakeNamespace(
          libraryId: matchingId,
          libraryName: 'Mine',
        );
        final useCase = MergeLibraryUseCase(
          jsonParser: const PitakaJsonImporter(),
          bookRepo: repo,
          periodicalRepo: FakePeriodicals(),
          namespace: namespace,
          replacementGuard: FakeReplacementGuard(),
          planner: planMergeInline,
        );

        final result = (await useCase.applyOverwrite(
          decision,
        )).getOrElse((f) => fail('overwrite failed: $f'));

        expect(result.replaced, isTrue);
        expect(
          result.added,
          1,
          reason: 'books now on the device, not "added 0"',
        );
        expect(result.namespace, MergeNamespaceOutcome.adopted);
        expect(repo.books.single.title, 'Their book');
      },
    );

    test('Overwrite: catalogue replaced, identity write fails → success with '
        'the omission reported', () async {
      final repo = _FakeBooks([
        const CatalogueItem(
          id: 1,
          itemUid: 'old',
          title: 'OldBook',
          addedDate: 1,
        ),
      ]);
      final namespace = _FakeNamespace(
        libraryId: matchingId,
        libraryName: 'Mine',
      )..adoptFailure = const StorageFailure('prefs write failed');
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: repo,
        periodicalRepo: FakePeriodicals(),
        namespace: namespace,
        replacementGuard: FakeReplacementGuard(),
        planner: planMergeInline,
      );

      final result = (await useCase.applyOverwrite(
        decision,
      )).getOrElse((f) => fail('overwrite must succeed: $f'));

      expect(result.replaced, isTrue);
      expect(result.namespace, MergeNamespaceOutcome.adoptionFailed);
      expect(repo.books.single.title, 'Their book');
      expect(namespace.libraryId, matchingId);
    });
  });

  // N07: "nonempty parsed payloads also discard parse warnings, including
  // skipped rows". A file with one good row and one invalid row used to
  // import the good row and say nothing about the other.
  group('N07 — skipped rows and adjustments are preserved', () {
    // Row 2 has copyCount 0, which M15 rejects (a book has at least one copy).
    final mixed = exportJson(
      libraryId: matchingId,
      books: [
        {'bookUid': 'u1', 'title': 'Good row', 'isbn': '111'},
        {'bookUid': 'u2', 'title': 'Bad row', 'copyCount': 0},
      ],
    );
    // A notes field over `CatalogueRules.maxFieldChars` (8000) is truncated +
    // reported (M15 D2).
    final long = exportJson(
      libraryId: matchingId,
      books: [
        {'bookUid': 'u1', 'title': 'Long notes', 'notes': 'x' * 9000},
      ],
    );

    test('same-ID merge carries skipped rows and adjustments', () async {
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: _FakeBooks([]),
        periodicalRepo: FakePeriodicals(),
        namespace: _FakeNamespace(libraryId: matchingId),
        replacementGuard: FakeReplacementGuard(),
        planner: planMergeInline,
      );

      final merged =
          (await useCase.call(mixed)).getOrElse((f) => fail('merge failed: $f'))
              as MergeMerged;
      expect(merged.result.added, 1);
      expect(merged.result.skippedRows, hasLength(1));
      expect(merged.result.skippedRows.single, contains('copyCount'));
      // M15's row label (short title + row number + field) so the user can
      // find the row; the INVALID VALUE itself is never echoed.
      expect(merged.result.skippedRows.single, contains('row 2'));
      expect(merged.result.skippedRows.single, isNot(contains(': 0')));
      expect(merged.result.hasOmissions, isTrue);

      final adjusted =
          (await useCase.call(long)).getOrElse((f) => fail('merge failed: $f'))
              as MergeMerged;
      expect(adjusted.result.adjustments, hasLength(1));
      expect(adjusted.result.adjustments.single, contains('notes'));
    });

    test('the differ decision carries them into Join and Overwrite', () async {
      final repo = _FakeBooks([]);
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: repo,
        periodicalRepo: FakePeriodicals(),
        namespace: _FakeNamespace(libraryId: otherId),
        replacementGuard: FakeReplacementGuard(),
        planner: planMergeInline,
      );

      final outcome = (await useCase.call(
        mixed,
      )).getOrElse((f) => fail('merge failed: $f'));
      final decision = outcome as MergeDiffersDecision;
      expect(decision.skippedRows, hasLength(1));
      expect(decision.incomingBooks, hasLength(1));

      final joined = (await useCase.applyJoin(
        decision,
      )).getOrElse((f) => fail('join failed: $f'));
      expect(joined.skippedRows, decision.skippedRows);

      final replaced = (await useCase.applyOverwrite(
        decision,
      )).getOrElse((f) => fail('overwrite failed: $f'));
      expect(replaced.skippedRows, decision.skippedRows);
    });

    test(
      'zero good rows + errors is still a hard validation failure',
      () async {
        final useCase = MergeLibraryUseCase(
          jsonParser: const PitakaJsonImporter(),
          bookRepo: _FakeBooks([]),
          periodicalRepo: FakePeriodicals(),
          namespace: _FakeNamespace(libraryId: matchingId),
          replacementGuard: FakeReplacementGuard(),
          planner: planMergeInline,
        );
        final allBad = exportJson(
          libraryId: matchingId,
          books: [
            {'bookUid': 'u2', 'title': 'Bad row', 'copyCount': 0},
          ],
        );

        final res = await useCase.call(allBad);
        expect(res.getLeft().toNullable(), isA<ValidationFailure>());
      },
    );
  });

  // Plan S19 (ADR 0013 D6 / ADR 0014 W1): a v4 file's `periodicals[]` were
  // silently DROPPED by the merge before S19. The series union applies first
  // (add-only; the local row wins every match), then the items, then every
  // merged series' issues are re-projected — all in one transaction.
  group('S19 — periodicals in the merge', () {
    MergeLibraryUseCase useCaseWith(
      CatalogueItemRepository books,
      FakePeriodicals periodicals,
    ) => MergeLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: books,
      periodicalRepo: periodicals,
      namespace: _FakeNamespace(libraryId: matchingId),
      replacementGuard: FakeReplacementGuard(),
      planner: planMergeInline,
    );

    Map<String, dynamic> seriesRow({
      required String uid,
      required String title,
      String? issn,
    }) => {
      'periodicalUid': uid,
      'title': title,
      if (issn != null) 'issn': issn,
    };

    Map<String, dynamic> issueRow({
      required String uid,
      required String title,
      required String seriesUid,
      int? issueNumber,
    }) => {
      'bookUid': uid,
      'title': title,
      'kind': 'magazine-issue',
      'issue': {
        'periodicalUid': seriesUid,
        if (issueNumber != null) 'issueNumber': issueNumber,
      },
    };

    test(
      'a v4 file merges series + issues (the pre-S19 silent drop)',
      () async {
        final books = _FakeBooks([]);
        final periodicals = FakePeriodicals();
        final useCase = useCaseWith(books, periodicals);
        final json = exportJson(
          libraryId: matchingId,
          periodicals: [seriesRow(uid: 'p9', title: 'National Geographic')],
          books: [
            issueRow(
              uid: 'i9',
              title: 'National Geographic — No 1',
              seriesUid: 'p9',
              issueNumber: 1,
            ),
          ],
        );

        final outcome = (await useCase.call(
          json,
        )).getOrElse((f) => fail('merge failed: $f'));

        final result = (outcome as MergeMerged).result;
        expect(result.periodicalsAdded, 1);
        expect(result.added, 1);
        // The series landed (insertAll keeps the file's uid) …
        expect(periodicals.rows.values.single.periodicalUid, 'p9');
        expect(periodicals.rows.values.single.title, 'National Geographic');
        // … and the issue landed anchored to it, with the composed title.
        final issue = books.books.single;
        expect(issue.issue?.periodicalUid, 'p9');
        expect(issue.title, 'National Geographic — No 1');
      },
    );

    test('an ISSN-matched series is kept local; its issues re-anchor to the '
        'local uid', () async {
      final books = _FakeBooks([]);
      final periodicals = FakePeriodicals()
        ..seed(
          const Periodical(
            periodicalUid: 'p-local',
            title: 'Chandamama',
            issn: '0976-3279',
            addedDate: 1,
          ),
        );
      final useCase = useCaseWith(books, periodicals);
      final json = exportJson(
        libraryId: matchingId,
        periodicals: [
          seriesRow(uid: 'p-inc', title: 'Chandamama', issn: '0976-3279'),
        ],
        books: [
          issueRow(
            uid: 'i9',
            title: 'Chandamama — No 4',
            seriesUid: 'p-inc',
            issueNumber: 4,
          ),
        ],
      );

      final outcome = (await useCase.call(
        json,
      )).getOrElse((f) => fail('merge failed: $f'));

      final result = (outcome as MergeMerged).result;
      // Same series, equal content: identical, NOT added.
      expect(result.periodicalsAdded, 0);
      expect(result.periodicalsIdentical, 1);
      expect(periodicals.rows, hasLength(1));
      // The issue re-anchored to the LOCAL series uid (D6).
      expect(books.books.single.issue?.periodicalUid, 'p-local');
    });

    test('the stale-projection seam: a series conflict repairs the stored '
        'issues (D3)', () async {
      // This device renamed the series; an S18 import left the stored issue
      // rows carrying the OLD projected title. The incoming file still has
      // the old series name. The merge keeps the local series and repairs
      // the stored issue rows.
      final books = _FakeBooks([
        const CatalogueItem(
          id: 5,
          itemUid: 'i1',
          title: 'Old Name — No 1',
          addedDate: 1,
          details: IssueOf(periodicalUid: 'p1', issueNumber: 1),
        ),
      ]);
      final periodicals = FakePeriodicals()
        ..seed(
          const Periodical(
            periodicalUid: 'p1',
            title: 'New Name',
            addedDate: 1,
          ),
        );
      // The issue read behind re-projection answers from the series store.
      periodicals.issues['p1'] = [
        const CatalogueItem(
          id: 5,
          itemUid: 'i1',
          title: 'Old Name — No 1',
          addedDate: 1,
          details: IssueOf(periodicalUid: 'p1', issueNumber: 1),
        ),
      ];
      final useCase = useCaseWith(books, periodicals);
      final json = exportJson(
        libraryId: matchingId,
        periodicals: [seriesRow(uid: 'p1', title: 'Old Name')],
        books: [
          issueRow(
            uid: 'i1',
            title: 'Old Name — No 1',
            seriesUid: 'p1',
            issueNumber: 1,
          ),
        ],
      );

      final outcome = (await useCase.call(
        json,
      )).getOrElse((f) => fail('merge failed: $f'));

      final result = (outcome as MergeMerged).result;
      // The series rename is a conflict (local kept) — but the ISSUE is not
      // a per-row conflict storm (risk D.2).
      expect(result.periodicalConflicts.single.incoming.title, 'Old Name');
      expect(result.conflicts, isEmpty);
      expect(result.identical, 1);
      // … and the STORED issue row was re-projected to the kept series.
      expect(books.books.single.title, 'New Name — No 1');
    });

    test(
      'a failed series insertAll fails the merge and writes nothing',
      () async {
        final books = _FakeBooks([]);
        final periodicals = FakePeriodicals()
          ..insertAllFailure = const StorageFailure('disk full');
        final useCase = useCaseWith(books, periodicals);
        final json = exportJson(
          libraryId: matchingId,
          periodicals: [seriesRow(uid: 'p9', title: 'New Series')],
          books: [
            {'bookUid': 'b9', 'title': 'New book'},
          ],
        );

        final res = await useCase.call(json);

        expect(res.isLeft(), isTrue);
        expect(books.books, isEmpty, reason: 'the transaction rolled back');
        expect(periodicals.rows, isEmpty);
      },
    );

    test('overwrite replaces the periodicals too', () async {
      final books = _FakeBooks([
        const CatalogueItem(id: 1, itemUid: 'old', title: 'Old', addedDate: 1),
      ]);
      final periodicals = FakePeriodicals()
        ..seed(const Periodical(periodicalUid: 'old-p', title: 'Old Series'));
      final useCase = useCaseWith(books, periodicals);
      const decision = MergeDiffersDecision(
        incomingBooks: [
          CatalogueItem(itemUid: 'new', title: 'New', addedDate: 1),
        ],
        incomingPeriodicals: [
          Periodical(periodicalUid: 'new-p', title: 'New Series'),
        ],
        incomingLibraryId: otherId,
        incomingLibraryName: 'Riverside',
        localLibraryName: 'Mine',
        localIsEmpty: false,
      );

      final result = (await useCase.applyOverwrite(
        decision,
      )).getOrElse((f) => fail('overwrite failed: $f'));

      expect(result.replaced, isTrue);
      expect(result.periodicalsAdded, 1);
      expect(periodicals.rows.values.single.periodicalUid, 'new-p');
      expect(periodicals.rows.values.single.title, 'New Series');
      expect(books.books.single.title, 'New');
    });

    test('a differ decision carries the series into Join, and a titles-only '
        'library is not empty', () async {
      final books = _FakeBooks([]);
      final periodicals = FakePeriodicals()
        ..seed(const Periodical(periodicalUid: 'mine-p', title: 'Mine'));
      final useCase = useCaseWith(books, periodicals);
      final json = exportJson(
        libraryId: otherId,
        periodicals: [seriesRow(uid: 'p9', title: 'Their Series')],
        books: [
          {'bookUid': 'b9', 'title': 'Their book'},
        ],
      );

      final outcome = (await useCase.call(
        json,
      )).getOrElse((f) => fail('failed: $f'));

      // No books locally, but ONE series: "empty" must see the whole
      // library (overwrite replaces series too).
      final decision = outcome as MergeDiffersDecision;
      expect(decision.localIsEmpty, isFalse);
      expect(decision.incomingPeriodicals.single.periodicalUid, 'p9');

      final joined = (await useCase.applyJoin(
        decision,
      )).getOrElse((f) => fail('join failed: $f'));
      expect(joined.periodicalsAdded, 1);
      expect(periodicals.rows.values.map((p) => p.title), [
        'Mine',
        'Their Series',
      ]);
    });

    test('resolutions guard the kind rules (D6/D8)', () async {
      final books = _FakeBooks([
        const CatalogueItem(id: 7, itemUid: 'u1', title: 'T', addedDate: 1),
      ]);
      final useCase = useCaseWith(books, FakePeriodicals());
      const incomingIssue = CatalogueItem(
        itemUid: 'u1',
        title: 'T',
        addedDate: 1,
        details: IssueOf(periodicalUid: 'p1', issueNumber: 3),
      );

      // take-theirs across kinds would flip the stored row's kind — refused.
      final flipped = await useCase.applyResolution(
        local: books.books.single,
        incoming: incomingIssue,
        resolution: MergeResolution.takeTheirs,
      );
      expect(flipped.isLeft(), isTrue);
      expect(books.updateCalls, 0);

      // keep-both keeps the KIND: the stored copy is still an issue.
      final kept = await useCase.applyResolution(
        local: books.books.single,
        incoming: incomingIssue,
        resolution: MergeResolution.keepBoth,
      );
      expect(kept.isRight(), isTrue);
      expect(books.books.last.details, isA<IssueOf>());
      expect(books.books.last.itemUid, isNot('u1'), reason: 'fresh identity');
    });
  });
}
