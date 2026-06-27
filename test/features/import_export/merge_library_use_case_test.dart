import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/application/merge_library_use_case.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';

/// In-memory book repo: just enough surface for the merge use case.
class _FakeBooks implements BookRepository {
  _FakeBooks(this._books);
  final List<Book> _books;
  int _nextId = 1000;

  List<Book> get books => _books;

  @override
  Future<Either<Failure, List<Book>>> getAll() async => right(_books);

  @override
  Future<Either<Failure, Book>> insert(Book book) async {
    final stored = book.copyWith(
      id: _nextId++,
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
    for (final b in books) {
      await insert(b);
    }
    return right(books.length);
  }
}

/// In-memory settings: tracks the library id/name the use case adopts.
class _FakeSettings implements SettingsRepository {
  _FakeSettings({this.libraryId = '', this.libraryName = ''});
  String libraryId;
  String libraryName;

  @override
  Future<AppSettings> load() async =>
      AppSettings(libraryName: libraryName, libraryId: libraryId);

  @override
  Future<String> getOrCreateLibraryId() async {
    if (libraryId.isEmpty) libraryId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    return libraryId;
  }

  @override
  Future<void> setLibraryId(String id) async => libraryId = id;

  @override
  Future<String> regenerateLibraryId() async =>
      libraryId = 'cccccccccccccccccccccccccccccccc';

  @override
  Future<void> setLibraryName(String name) async => libraryName = name;

  // Unused.
  @override
  Future<void> setThemeMode(ThemeMode mode) async {}
  @override
  Future<void> setMaintainerName(String name) async {}
  @override
  Future<void> setLibrarySort(BookSort sort) async {}
  @override
  Future<void> setLoadRemoteCovers({required bool enabled}) async {}
  @override
  Future<void> setPublishContact({
    required String address,
    required String gps,
    required String email,
    required String phone,
  }) async {}
  @override
  Future<void> setLibraryLogo(String reference) async {}
  @override
  Future<void> setAppLockBiometric({required bool enabled}) async {}
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

  test('rejects a non-Pitak file with a validation failure', () async {
    final useCase = MergeLibraryUseCase(
      bookRepo: _FakeBooks([]),
      settings: _FakeSettings(libraryId: matchingId),
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
      bookRepo: repo,
      settings: _FakeSettings(libraryId: matchingId),
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
      bookRepo: repo,
      settings: _FakeSettings(libraryId: matchingId, libraryName: 'Mine'),
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
      bookRepo: repo,
      settings: _FakeSettings(libraryId: matchingId),
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
    final settings = _FakeSettings(libraryId: matchingId, libraryName: 'Mine');
    final useCase = MergeLibraryUseCase(bookRepo: repo, settings: settings);

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
    final settings = _FakeSettings(libraryId: matchingId, libraryName: 'Mine');
    final useCase = MergeLibraryUseCase(bookRepo: repo, settings: settings);

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
        bookRepo: repo,
        settings: _FakeSettings(),
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
        bookRepo: repo,
        settings: _FakeSettings(),
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
          bookRepo: repo,
          settings: _FakeSettings(),
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
}
