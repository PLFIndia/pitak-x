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
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/library_namespace.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';

import '../library/replacement_harness.dart';
import '../library/replacement_test_guard.dart';
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
      loans: [Loan(bookId: 7, borrowerId: 1, lentDate: 1)],
    ),
  );
}

/// In-memory book repo: just enough surface for the merge use case.
class _FakeBooks implements BookRepository {
  _FakeBooks(this._books);

  // BookRepository additions (review 2026-09-03): fakes default to "no match"
  // and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, Book?>> findByUid(String bookUid) async => right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();
  final List<Book> _books;
  int _nextId = 1000;

  /// Test-only failure injection for [replaceAll].
  Failure? replaceAllFailure;

  /// Test-only failure injection for [insertAll] (N07: a failed Join union).
  Failure? insertAllFailure;

  List<Book> get books => _books;

  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(_books);

  @override
  Future<Either<Failure, Book>> insert(Book book) async {
    final stored = book.copyWith(
      id: book.id == Book.emptyId ? _nextId++ : book.id,
      bookUid: book.bookUid ?? 'minted-$_nextId',
    );
    _books.add(stored);
    return right(stored);
  }

  @override
  Future<Either<Failure, Book>> update(Book book) async {
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
  Future<Either<Failure, List<Book>>> query({
    required BookSort sort,
    String? language,
  }) async => right(_books);
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async => right([]);
  @override
  Future<Either<Failure, Book?>> getById(int id) async =>
      right(_books.where((b) => b.id == id).firstOrNull);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);
  @override
  Future<Either<Failure, List<Book>>> search(String query) async => right([]);
  @override
  Future<Either<Failure, Book?>> findByIsbn(String isbn) async => right(null);
  @override
  Future<Either<Failure, int>> insertAll(List<Book> books) async {
    // Mirrors the atomic contract: failure leaves the store untouched.
    final failure = insertAllFailure;
    if (failure != null) return left(failure);
    for (final b in books) {
      await insert(b);
    }
    return right(books.length);
  }

  @override
  Future<Either<Failure, int>> replaceAll(List<Book> books) async {
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
String exportJson({
  required List<Map<String, dynamic>> books,
  String? libraryId,
  String? libraryName,
}) {
  final env = <String>[
    '"schemaVersion": 3',
    if (libraryId != null) '"libraryId": "$libraryId"',
    if (libraryName != null) '"libraryName": "$libraryName"',
  ];
  final bookJson = books
      .map((b) {
        final parts = b.entries.map((e) {
          final v = e.value;
          return v is String ? '"${e.key}": "$v"' : '"${e.key}": $v';
        });
        return '{${parts.join(',')}}';
      })
      .join(',');
  return '{${env.join(',')}, "books": [$bookJson], "wishlist": []}';
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
      const Book(id: 7, bookUid: 'loaned', title: 'Loaned book'),
    ]);
    // Built through the REAL provider: the identity port is the real
    // SettingsController over this settings repo (N07), so the assertion
    // below checks the ID that actually reaches disk.
    final settings = ReplacementSettings()..id = matchingId;
    final container = ProviderContainer(
      overrides: [
        vaultStoreProvider.overrideWith((ref) async => store),
        vaultRepositoryProvider.overrideWithValue(_LoanVault()),
        bookRepositoryProvider.overrideWith((ref) async => books),
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
        incomingBooks: [Book(id: 7, bookUid: 'unrelated', title: 'Other book')],
        incomingLibraryId: otherId,
        incomingLibraryName: 'Other',
        localLibraryName: 'Mine',
        localIsEmpty: false,
      ),
    );
    expect(result.isLeft(), isTrue);
    expect(books.books.single.bookUid, 'loaned');
    expect(books.books.single.id, 7);
    expect(settings.id, matchingId);
  });

  test('rejects a non-Pitak file with a validation failure', () async {
    final useCase = MergeLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: _FakeBooks([]),
      replacementGuard: FakeReplacementGuard(),
      namespace: _FakeNamespace(libraryId: matchingId),
    );
    final res = await useCase.call('title,author\nFoo,Bar');
    expect(res.isLeft(), isTrue);
    expect(res.getLeft().toNullable(), isA<ValidationFailure>());
  });

  test('matching library id merges (add-only union, auto-applied)', () async {
    final repo = _FakeBooks([
      const Book(
        id: 1,
        bookUid: 'u1',
        title: 'Godaan',
        isbn: '111',
        addedDate: 1,
      ),
    ]);
    final useCase = MergeLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: repo,
      namespace: _FakeNamespace(libraryId: matchingId),
      replacementGuard: FakeReplacementGuard(),
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
    expect(repo.books.firstWhere((b) => b.title == '1984').bookUid, 'u2');
  });

  test('differing library id returns a decision, applies nothing', () async {
    final repo = _FakeBooks([
      const Book(id: 1, bookUid: 'u1', title: 'Godaan', addedDate: 1),
    ]);
    final useCase = MergeLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: repo,
      namespace: _FakeNamespace(libraryId: matchingId, libraryName: 'Mine'),
      replacementGuard: FakeReplacementGuard(),
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
      namespace: _FakeNamespace(libraryId: matchingId),
      replacementGuard: FakeReplacementGuard(),
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
      namespace: settings,
      replacementGuard: FakeReplacementGuard(),
    );

    const decision = MergeDiffersDecision(
      incomingBooks: [
        Book(bookUid: 'u9', title: 'Joined', isbn: '999', addedDate: 1),
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
      const Book(id: 1, bookUid: 'old', title: 'OldBook', addedDate: 1),
    ]);
    final settings = _FakeNamespace(libraryId: matchingId, libraryName: 'Mine');
    final useCase = MergeLibraryUseCase(
      jsonParser: const PitakaJsonImporter(),
      bookRepo: repo,
      namespace: settings,
      replacementGuard: FakeReplacementGuard(),
    );

    const decision = MergeDiffersDecision(
      incomingBooks: [Book(bookUid: 'u9', title: 'FreshReplica', addedDate: 1)],
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
        namespace: _FakeNamespace(libraryId: matchingId),
        replacementGuard: FakeReplacementGuard(),
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
      expect(repo.books.single.bookUid, 'uA');
    },
  );

  // Regression for REVIEW_FINDINGS_2 S5 Major: overwrite must be atomic — a
  // failed replace leaves the local catalogue intact and does NOT adopt the
  // incoming library identity.
  test(
    'applyOverwrite failure keeps the local catalogue and settings',
    () async {
      final repo = _FakeBooks([
        const Book(id: 1, bookUid: 'old', title: 'OldBook', addedDate: 1),
      ])..replaceAllFailure = const StorageFailure('disk full');
      final settings = _FakeNamespace(
        libraryId: matchingId,
        libraryName: 'Mine',
      );
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: repo,
        namespace: settings,
        replacementGuard: FakeReplacementGuard(),
      );

      const decision = MergeDiffersDecision(
        incomingBooks: [
          Book(bookUid: 'u9', title: 'FreshReplica', addedDate: 1),
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
        const Book(
          id: 1,
          bookUid: 'u1',
          title: 'Local',
          genre: 'A',
          addedDate: 1,
        ),
      ]);
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: repo,
        namespace: _FakeNamespace(),
        replacementGuard: FakeReplacementGuard(),
      );
      await useCase.applyResolution(
        local: repo.books.first,
        incoming: const Book(
          bookUid: 'u1',
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
        const Book(
          id: 7,
          bookUid: 'u1',
          title: 'Local',
          genre: 'A',
          addedDate: 1,
        ),
      ]);
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: repo,
        namespace: _FakeNamespace(),
        replacementGuard: FakeReplacementGuard(),
      );
      await useCase.applyResolution(
        local: repo.books.first,
        incoming: const Book(
          id: 999,
          bookUid: 'uOther',
          title: 'Local',
          genre: 'B',
          addedDate: 2,
        ),
        resolution: MergeResolution.takeTheirs,
      );
      final row = repo.books.single;
      expect(row.id, 7); // local id preserved
      expect(row.bookUid, 'u1'); // local uid preserved
      expect(row.genre, 'B'); // their field taken
    });

    // M09 (user decision 2026-09-09): even when the user picks "take theirs",
    // a photo of the physical book taken on this device is kept; the incoming
    // cover lands only when there is no local cover.
    test('M09: takeTheirs keeps the local PHOTO over an incoming https '
        'cover', () async {
      final repo = _FakeBooks([
        const Book(
          id: 7,
          bookUid: 'u1',
          title: 'Local',
          genre: 'A',
          coverUrl: 'covers/photo.jpg',
          addedDate: 1,
        ),
      ]);
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: repo,
        namespace: _FakeNamespace(),
        replacementGuard: FakeReplacementGuard(),
      );
      await useCase.applyResolution(
        local: repo.books.first,
        incoming: const Book(
          id: 999,
          bookUid: 'uOther',
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
        const Book(id: 7, bookUid: 'u1', title: 'Local', addedDate: 1),
      ]);
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: repo,
        namespace: _FakeNamespace(),
        replacementGuard: FakeReplacementGuard(),
      );
      await useCase.applyResolution(
        local: repo.books.first,
        incoming: const Book(
          bookUid: 'uOther',
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
          const Book(
            id: 1,
            bookUid: 'u1',
            title: 'Dohe',
            isbn: '555',
            addedDate: 1,
          ),
        ]);
        final useCase = MergeLibraryUseCase(
          jsonParser: const PitakaJsonImporter(),
          bookRepo: repo,
          namespace: _FakeNamespace(),
          replacementGuard: FakeReplacementGuard(),
        );
        await useCase.applyResolution(
          local: repo.books.first,
          incoming: const Book(
            bookUid: 'u1',
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
        expect(dup.bookUid, isNot('u1'));
        expect(dup.isbn, isNull);
        expect(dup.genre, 'extra'); // catalogue fields preserved
      },
    );
  });

  // N07 (astra-review.md): "a failed Join can still change future merge
  // identity" — the incoming library ID used to be adopted BEFORE the books
  // were inserted, so a failed insert left this device re-identified with
  // none of the data; the next merge of the same file then auto-applied
  // under the adopted ID with no Join decision. Data first, identity second.
  group('N07 — namespace adoption is coordinated with the data', () {
    const decision = MergeDiffersDecision(
      incomingBooks: [
        Book(bookUid: 'u9', title: 'Their book', isbn: '999', addedDate: 1),
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
        namespace: namespace,
        replacementGuard: FakeReplacementGuard(),
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
        namespace: namespace,
        replacementGuard: FakeReplacementGuard(),
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
        namespace: namespace,
        replacementGuard: FakeReplacementGuard(),
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
        namespace: namespace,
        replacementGuard: FakeReplacementGuard(),
      );
      const noId = MergeDiffersDecision(
        incomingBooks: [Book(bookUid: 'u9', title: 'Their book', addedDate: 1)],
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
          const Book(id: 1, bookUid: 'old', title: 'OldBook', addedDate: 1),
        ]);
        final namespace = _FakeNamespace(
          libraryId: matchingId,
          libraryName: 'Mine',
        );
        final useCase = MergeLibraryUseCase(
          jsonParser: const PitakaJsonImporter(),
          bookRepo: repo,
          namespace: namespace,
          replacementGuard: FakeReplacementGuard(),
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
        const Book(id: 1, bookUid: 'old', title: 'OldBook', addedDate: 1),
      ]);
      final namespace = _FakeNamespace(
        libraryId: matchingId,
        libraryName: 'Mine',
      )..adoptFailure = const StorageFailure('prefs write failed');
      final useCase = MergeLibraryUseCase(
        jsonParser: const PitakaJsonImporter(),
        bookRepo: repo,
        namespace: namespace,
        replacementGuard: FakeReplacementGuard(),
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
        namespace: _FakeNamespace(libraryId: matchingId),
        replacementGuard: FakeReplacementGuard(),
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
        namespace: _FakeNamespace(libraryId: otherId),
        replacementGuard: FakeReplacementGuard(),
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
          namespace: _FakeNamespace(libraryId: matchingId),
          replacementGuard: FakeReplacementGuard(),
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
}
