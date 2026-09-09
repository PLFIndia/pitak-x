import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/materialize_remote_cover_use_case.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/infrastructure/cover_store.dart';

/// In-memory rows with scriptable update failure. `getById` is the FRESH read
/// the use case must rely on (not a UI snapshot).
class _FakeBookRepo implements BookRepository {
  _FakeBookRepo(this.rows);
  final List<Book> rows;
  Failure? failUpdateWith;
  Failure? failGetByIdWith;
  int getByIdCalls = 0;

  @override
  Future<Either<Failure, Book?>> getById(int id) async {
    getByIdCalls++;
    final f = failGetByIdWith;
    if (f != null) return left(f);
    return right(rows.where((b) => b.id == id).firstOrNull);
  }

  @override
  Future<Either<Failure, Book>> update(Book book) async {
    final f = failUpdateWith;
    if (f != null) return left(f);
    final i = rows.indexWhere((b) => b.id == book.id);
    if (i < 0) return left(const NotFoundFailure());
    rows[i] = book;
    return right(book);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

const _allowListed = 'https://covers.openlibrary.org/b/id/1-L.jpg';
const _attacker = 'https://example.com/c.jpg';

void main() {
  late Directory tmp;
  late List<String> downloaded;
  late List<String?> released;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('materialize_test');
    downloaded = [];
    released = [];
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  MaterializeRemoteCoverUseCase make(
    _FakeBookRepo repo, {
    List<int>? Function(String url)? download,
  }) {
    return MaterializeRemoteCoverUseCase(
      books: repo,
      files: CoverStore(coversDir: tmp.path),
      download: (url) async {
        downloaded.add(url);
        return (download ?? (_) => [1, 2, 3])(url);
      },
      releaseReference: (ref) async => released.add(ref),
    );
  }

  test('fetches an allow-listed URL once and rewrites the row to a local '
      'cover file', () async {
    final repo = _FakeBookRepo([
      const Book(id: 7, title: 'Dune', coverUrl: _allowListed),
    ]);
    final result = await make(repo)(7);

    expect(result.isRight(), isTrue);
    expect(downloaded, [_allowListed]);
    final row = repo.rows.single;
    expect(row.coverUrl, startsWith('covers/'));
    final leaf = row.coverUrl!.split('/').last;
    expect(File('${tmp.path}/$leaf').readAsBytesSync(), [1, 2, 3]);
    expect(released, [_allowListed], reason: 'old ref handed to the janitor');
  });

  test('reads the row FRESH by id, never trusting a snapshot', () async {
    final repo = _FakeBookRepo([
      const Book(id: 7, title: 'Dune', coverUrl: _allowListed),
    ]);
    await make(repo)(7);
    expect(repo.getByIdCalls, 1);
  });

  test(
    'a NON-allow-listed https URL is never downloaded (M09 finding)',
    () async {
      final repo = _FakeBookRepo([
        const Book(id: 7, title: 'Dune', coverUrl: _attacker),
      ]);
      final result = await make(repo)(7);

      expect(result.isRight(), isTrue, reason: 'nothing to do is not an error');
      expect(downloaded, isEmpty);
      expect(repo.rows.single.coverUrl, _attacker, reason: 'row untouched');
      expect(tmp.listSync(), isEmpty);
    },
  );

  test(
    'an already-local cover is left alone (no download, no write)',
    () async {
      final repo = _FakeBookRepo([
        const Book(id: 7, title: 'Dune', coverUrl: 'covers/photo.jpg'),
      ]);
      final result = await make(repo)(7);
      expect(result.isRight(), isTrue);
      expect(downloaded, isEmpty);
      expect(repo.rows.single.coverUrl, 'covers/photo.jpg');
    },
  );

  test('a blank cover or a missing book is a no-op', () async {
    final repo = _FakeBookRepo([const Book(id: 7, title: 'Dune')]);
    expect((await make(repo)(7)).isRight(), isTrue);
    expect((await make(repo)(999)).isRight(), isTrue);
    expect(downloaded, isEmpty);
  });

  test('a refused / failed download → NetworkFailure, URL kept for a later '
      'retry, no file written', () async {
    final repo = _FakeBookRepo([
      const Book(id: 7, title: 'Dune', coverUrl: _allowListed),
    ]);
    final result = await make(repo, download: (_) => null)(7);

    result.match(
      (f) => expect(f, isA<NetworkFailure>()),
      (_) => fail('expected a failure'),
    );
    expect(repo.rows.single.coverUrl, _allowListed);
    expect(tmp.listSync(), isEmpty);
    expect(released, isEmpty);
  });

  test('a failed row update deletes the new file and surfaces the failure '
      '(fail closed, no orphan)', () async {
    final repo = _FakeBookRepo([
      const Book(id: 7, title: 'Dune', coverUrl: _allowListed),
    ])..failUpdateWith = const StorageFailure('disk full');
    final result = await make(repo)(7);

    result.match(
      (f) => expect(f, isA<StorageFailure>()),
      (_) => fail('expected a failure'),
    );
    expect(repo.rows.single.coverUrl, _allowListed);
    expect(tmp.listSync(), isEmpty, reason: 'new file removed');
    expect(released, isEmpty);
  });

  test('a repository read failure is propagated, nothing downloaded', () async {
    final repo = _FakeBookRepo([
      const Book(id: 7, title: 'Dune', coverUrl: _allowListed),
    ])..failGetByIdWith = const StorageFailure('db locked');
    final result = await make(repo)(7);
    expect(result.isLeft(), isTrue);
    expect(downloaded, isEmpty);
  });

  test('a file-store write failure → StorageFailure, row untouched', () async {
    final repo = _FakeBookRepo([
      const Book(id: 7, title: 'Dune', coverUrl: _allowListed),
    ]);
    // Point the store at a path that cannot be a directory.
    final blocker = File('${tmp.path}/not-a-dir')..writeAsBytesSync([0]);
    final useCase = MaterializeRemoteCoverUseCase(
      books: repo,
      files: CoverStore(coversDir: blocker.path),
      download: (_) async => Uint8List.fromList([1, 2, 3]),
      releaseReference: (_) async {},
    );
    final result = await useCase(7);
    result.match(
      (f) => expect(f, isA<StorageFailure>()),
      (_) => fail('expected a failure'),
    );
    expect(repo.rows.single.coverUrl, _allowListed);
  });
}
