import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/materialize_remote_cover_use_case.dart';
import 'package:pitaka/features/library/domain/cover_owner.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/infrastructure/cover_store.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/publish/domain/cover_fetch_result.dart';

import '../../support/async_value_gate.dart';

/// In-memory rows with scriptable update failure. `getById` is the FRESH read
/// the use case must rely on (not a UI snapshot).
class _FakeBookRepo implements CatalogueItemRepository {
  _FakeBookRepo(this.rows);
  final List<CatalogueItem> rows;
  Failure? failUpdateWith;
  Failure? failGetByIdWith;
  int getByIdCalls = 0;

  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async {
    getByIdCalls++;
    final f = failGetByIdWith;
    if (f != null) return left(f);
    return right(rows.where((b) => b.id == id).firstOrNull);
  }

  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem book) async {
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

class _FakePeriodicalRepo implements PeriodicalRepository {
  _FakePeriodicalRepo(this.rows);

  final List<Periodical> rows;
  int findByUidCalls = 0;
  Failure? failUpdateWith;

  @override
  Future<Either<Failure, Periodical?>> findByUid(String periodicalUid) async {
    findByUidCalls++;
    return right(
      rows.where((row) => row.periodicalUid == periodicalUid).firstOrNull,
    );
  }

  @override
  Future<Either<Failure, Periodical>> update(Periodical periodical) async {
    final failure = failUpdateWith;
    if (failure != null) return left(failure);
    final index = rows.indexWhere((row) => row.id == periodical.id);
    if (index < 0) return left(const NotFoundFailure());
    rows[index] = periodical;
    return right(periodical);
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
  late List<(CoverOwner, CoverRefusal)> refusals;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('materialize_test');
    downloaded = [];
    released = [];
    refusals = [];
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  MaterializeRemoteCoverUseCase make(
    _FakeBookRepo repo, {
    _FakePeriodicalRepo? periodicals,
    FutureOr<CoverFetchResult> Function(String url)? download,
  }) {
    return MaterializeRemoteCoverUseCase(
      books: repo,
      periodicals: periodicals ?? _FakePeriodicalRepo(const []),
      files: CoverStore(coversDir: tmp.path),
      download: (url) async {
        downloaded.add(url);
        return (download ?? (_) => const CoverFetched([1, 2, 3]))(url);
      },
      releaseReference: (ref) async => released.add(ref),
      onRefused: (owner, reason) => refusals.add((owner, reason)),
    );
  }

  test('fetches an allow-listed URL once and rewrites the row to a local '
      'cover file', () async {
    final repo = _FakeBookRepo([
      const CatalogueItem(id: 7, title: 'Dune', coverUrl: _allowListed),
    ]);
    final result = await make(repo)(CoverOwners.item(7), _allowListed);

    expect(result.isRight(), isTrue);
    expect(downloaded, [_allowListed]);
    final row = repo.rows.single;
    expect(row.coverUrl, startsWith('covers/'));
    final leaf = row.coverUrl!.split('/').last;
    expect(File('${tmp.path}/$leaf').readAsBytesSync(), [1, 2, 3]);
    expect(released, [_allowListed], reason: 'old ref handed to the janitor');
  });

  test('reads the row FRESH before download and again before update', () async {
    final repo = _FakeBookRepo([
      const CatalogueItem(id: 7, title: 'Dune', coverUrl: _allowListed),
    ]);
    await make(repo)(CoverOwners.item(7), _allowListed);
    expect(repo.getByIdCalls, 2);
  });

  test(
    'a stale requested URL does not download or overwrite the current one',
    () async {
      const current = 'https://covers.openlibrary.org/b/id/2-L.jpg';
      final repo = _FakeBookRepo([
        const CatalogueItem(id: 7, title: 'Dune', coverUrl: current),
      ]);

      final result = await make(repo)(CoverOwners.item(7), _allowListed);

      expect(result.isRight(), isTrue);
      expect(downloaded, isEmpty);
      expect(repo.rows.single.coverUrl, current);
    },
  );

  test(
    'a cover replaced DURING download wins; the downloaded file is deleted',
    () async {
      const initial = CatalogueItem(
        id: 7,
        title: 'Dune',
        coverUrl: _allowListed,
      );
      final repo = _FakeBookRepo([initial]);
      final gate = AsyncValueGate<CoverFetchResult>();
      final pending = make(repo, download: (_) => gate.wait())(
        CoverOwners.item(7),
        _allowListed,
      );
      await gate.entered;

      repo.rows[0] = initial.copyWith(
        title: 'User edition',
        coverUrl: 'covers/user.jpg',
      );
      gate.succeed(const CoverFetched([1, 2, 3]));
      final result = await pending;

      expect(result.isRight(), isTrue);
      expect(repo.rows.single.title, 'User edition');
      expect(repo.rows.single.coverUrl, 'covers/user.jpg');
      expect(tmp.listSync(), isEmpty, reason: 'stale downloaded file removed');
      expect(released, isEmpty, reason: 'the user cover is never released');
    },
  );

  test('an unrelated field edited DURING download is preserved by the '
      'pre-update fresh read', () async {
    const initial = CatalogueItem(id: 7, title: 'Dune', coverUrl: _allowListed);
    final repo = _FakeBookRepo([initial]);
    final gate = AsyncValueGate<CoverFetchResult>();
    final pending = make(repo, download: (_) => gate.wait())(
      CoverOwners.item(7),
      _allowListed,
    );
    await gate.entered;

    repo.rows[0] = initial.copyWith(title: 'Dune Messiah');
    gate.succeed(const CoverFetched([1, 2, 3]));
    final result = await pending;

    expect(result.isRight(), isTrue);
    expect(repo.rows.single.title, 'Dune Messiah');
    expect(repo.rows.single.coverUrl, startsWith('covers/'));
    expect(released, [_allowListed]);
  });

  test('a periodical changed DURING download is not overwritten by the '
      'materialized snapshot', () async {
    const initial = Periodical(
      id: 3,
      periodicalUid: 'per-1',
      title: 'Weekly',
      coverUrl: _allowListed,
    );
    final books = _FakeBookRepo([]);
    final periodicals = _FakePeriodicalRepo([initial]);
    final gate = AsyncValueGate<CoverFetchResult>();
    final pending = make(
      books,
      periodicals: periodicals,
      download: (_) => gate.wait(),
    )(CoverOwners.periodical('per-1'), _allowListed);
    await gate.entered;

    periodicals.rows[0] = initial.copyWith(
      publisher: 'New publisher',
      coverUrl: 'covers/user-series.jpg',
    );
    gate.succeed(const CoverFetched([1, 2, 3]));
    final result = await pending;

    expect(result.isRight(), isTrue);
    expect(periodicals.rows.single.publisher, 'New publisher');
    expect(periodicals.rows.single.coverUrl, 'covers/user-series.jpg');
    expect(tmp.listSync(), isEmpty);
    expect(released, isEmpty);
  });

  test('a remote series cover materializes on the periodical only, leaving '
      'two coverless issues untouched', () async {
    final books = _FakeBookRepo([
      const CatalogueItem(
        id: 11,
        title: 'Weekly — No 1',
        details: IssueOf(periodicalUid: 'per-1', issueNumber: 1),
      ),
      const CatalogueItem(
        id: 12,
        title: 'Weekly — No 2',
        details: IssueOf(periodicalUid: 'per-1', issueNumber: 2),
      ),
    ]);
    final periodicals = _FakePeriodicalRepo([
      const Periodical(
        id: 3,
        periodicalUid: 'per-1',
        title: 'Weekly',
        coverUrl: _allowListed,
      ),
    ]);

    final result = await make(books, periodicals: periodicals)(
      CoverOwners.periodical('per-1'),
      _allowListed,
    );

    expect(result.isRight(), isTrue);
    expect(downloaded, [_allowListed]);
    expect(periodicals.findByUidCalls, 2);
    expect(periodicals.rows.single.coverUrl, startsWith('covers/'));
    expect(books.rows.map((row) => row.coverUrl), [null, null]);
    expect(released, [_allowListed]);
  });

  test(
    'a periodical refusal reports the periodical owner, not an item id',
    () async {
      final books = _FakeBookRepo([]);
      final periodicals = _FakePeriodicalRepo([
        const Periodical(
          id: 3,
          periodicalUid: 'per-1',
          title: 'Weekly',
          coverUrl: _allowListed,
        ),
      ]);

      await make(
        books,
        periodicals: periodicals,
        download: (_) => const CoverRefused(CoverRefusal.timedOut),
      )(CoverOwners.periodical('per-1'), _allowListed);

      expect(refusals, [
        (CoverOwners.periodical('per-1'), CoverRefusal.timedOut),
      ]);
    },
  );

  test(
    'a failed periodical update deletes the new file and keeps the URL',
    () async {
      final books = _FakeBookRepo([]);
      final periodicals = _FakePeriodicalRepo([
        const Periodical(
          id: 3,
          periodicalUid: 'per-1',
          title: 'Weekly',
          coverUrl: _allowListed,
        ),
      ])..failUpdateWith = const StorageFailure('disk full');

      final result = await make(books, periodicals: periodicals)(
        CoverOwners.periodical('per-1'),
        _allowListed,
      );

      expect(result.isLeft(), isTrue);
      expect(periodicals.rows.single.coverUrl, _allowListed);
      expect(tmp.listSync(), isEmpty);
      expect(released, isEmpty);
    },
  );

  test('malformed owner ids fail closed before reads or network', () async {
    final books = _FakeBookRepo([]);
    final periodicals = _FakePeriodicalRepo([]);
    final useCase = make(books, periodicals: periodicals);

    final itemResult = await useCase((
      kind: CoverOwnerKind.catalogueItem,
      id: 'not-an-int',
    ), _allowListed);
    final periodicalResult = await useCase((
      kind: CoverOwnerKind.periodical,
      id: ' ',
    ), _allowListed);

    for (final result in [itemResult, periodicalResult]) {
      result.match(
        (failure) => expect(failure, isA<ValidationFailure>()),
        (_) => fail('expected a validation failure'),
      );
    }
    expect(books.getByIdCalls, 0);
    expect(periodicals.findByUidCalls, 0);
    expect(downloaded, isEmpty);
  });

  test(
    'a NON-allow-listed https URL is never downloaded (M09 finding)',
    () async {
      final repo = _FakeBookRepo([
        const CatalogueItem(id: 7, title: 'Dune', coverUrl: _attacker),
      ]);
      final result = await make(repo)(CoverOwners.item(7), _attacker);

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
        const CatalogueItem(id: 7, title: 'Dune', coverUrl: 'covers/photo.jpg'),
      ]);
      final result = await make(repo)(CoverOwners.item(7), _allowListed);
      expect(result.isRight(), isTrue);
      expect(downloaded, isEmpty);
      expect(repo.rows.single.coverUrl, 'covers/photo.jpg');
    },
  );

  test('a blank cover or a missing book is a no-op', () async {
    final repo = _FakeBookRepo([const CatalogueItem(id: 7, title: 'Dune')]);
    expect(
      (await make(repo)(CoverOwners.item(7), _allowListed)).isRight(),
      isTrue,
    );
    expect(
      (await make(repo)(CoverOwners.item(999), _allowListed)).isRight(),
      isTrue,
    );
    expect(downloaded, isEmpty);
  });

  test('a refused / failed download → NetworkFailure, URL kept for a later '
      'retry, no file written', () async {
    final repo = _FakeBookRepo([
      const CatalogueItem(id: 7, title: 'Dune', coverUrl: _allowListed),
    ]);
    final result = await make(
      repo,
      download: (_) => const CoverRefused(CoverRefusal.tooLarge),
    )(CoverOwners.item(7), _allowListed);

    result.match(
      (f) => expect(f, isA<NetworkFailure>()),
      (_) => fail('expected a failure'),
    );
    expect(repo.rows.single.coverUrl, _allowListed);
    expect(tmp.listSync(), isEmpty);
    expect(released, isEmpty);
  });

  // N08 / N11 D4-b: a refused download used to vanish silently. The use case
  // is the one place that knows BOTH the book id and the reason, so it
  // reports them through an injected port — never the URL.
  test('a refusal is reported with the book id and reason (no URL)', () async {
    final repo = _FakeBookRepo([
      const CatalogueItem(id: 7, title: 'Dune', coverUrl: _allowListed),
    ]);
    await make(
      repo,
      download: (_) => const CoverRefused(CoverRefusal.redirectRefused),
    )(CoverOwners.item(7), _allowListed);

    expect(refusals, [(CoverOwners.item(7), CoverRefusal.redirectRefused)]);
  });

  test('a successful download reports nothing', () async {
    final repo = _FakeBookRepo([
      const CatalogueItem(id: 7, title: 'Dune', coverUrl: _allowListed),
    ]);
    await make(repo)(CoverOwners.item(7), _allowListed);
    expect(refusals, isEmpty);
  });

  test('the refusal port is optional (publish-style wiring)', () async {
    final repo = _FakeBookRepo([
      const CatalogueItem(id: 7, title: 'Dune', coverUrl: _allowListed),
    ]);
    final useCase = MaterializeRemoteCoverUseCase(
      books: repo,
      periodicals: _FakePeriodicalRepo(const []),
      files: CoverStore(coversDir: tmp.path),
      download: (_) async => const CoverRefused(CoverRefusal.timedOut),
      releaseReference: (_) async {},
    );
    final result = await useCase(CoverOwners.item(7), _allowListed);
    expect(result.isLeft(), isTrue);
  });

  test('a failed row update deletes the new file and surfaces the failure '
      '(fail closed, no orphan)', () async {
    final repo = _FakeBookRepo([
      const CatalogueItem(id: 7, title: 'Dune', coverUrl: _allowListed),
    ])..failUpdateWith = const StorageFailure('disk full');
    final result = await make(repo)(CoverOwners.item(7), _allowListed);

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
      const CatalogueItem(id: 7, title: 'Dune', coverUrl: _allowListed),
    ])..failGetByIdWith = const StorageFailure('db locked');
    final result = await make(repo)(CoverOwners.item(7), _allowListed);
    expect(result.isLeft(), isTrue);
    expect(downloaded, isEmpty);
  });

  test('a file-store write failure → StorageFailure, row untouched', () async {
    final repo = _FakeBookRepo([
      const CatalogueItem(id: 7, title: 'Dune', coverUrl: _allowListed),
    ]);
    // Point the store at a path that cannot be a directory.
    final blocker = File('${tmp.path}/not-a-dir')..writeAsBytesSync([0]);
    final useCase = MaterializeRemoteCoverUseCase(
      books: repo,
      periodicals: _FakePeriodicalRepo(const []),
      files: CoverStore(coversDir: blocker.path),
      download: (_) async => CoverFetched(Uint8List.fromList([1, 2, 3])),
      releaseReference: (_) async {},
    );
    final result = await useCase(CoverOwners.item(7), _allowListed);
    result.match(
      (f) => expect(f, isA<StorageFailure>()),
      (_) => fail('expected a failure'),
    );
    expect(repo.rows.single.coverUrl, _allowListed);
  });
}
