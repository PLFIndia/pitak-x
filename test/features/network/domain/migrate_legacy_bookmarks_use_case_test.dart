import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/usecases/migrate_legacy_bookmarks_use_case.dart';

/// Tests for [MigrateLegacyBookmarksUseCase] (libNetwork.md §7 S4, D8):
/// idempotent, order-preserving, ONE transaction, and the prefs key is
/// cleared ONLY after the commit succeeded. The prefs side arrives as
/// function ports — this file is pure domain, the reader has its own test.
void main() {
  const urlA = 'https://a.github.io/pitak/';
  const urlB = 'https://b.pages.dev/lib/';
  late _FakeRepo repo;
  late List<LegacyBookmark> legacy;
  late bool keyPresent;
  late int clears;

  setUp(() {
    repo = _FakeRepo();
    legacy = [];
    keyPresent = true;
    clears = 0;
  });

  MigrateLegacyBookmarksUseCase useCase() => MigrateLegacyBookmarksUseCase(
    repository: repo,
    readLegacy: () async => List.of(legacy),
    clearLegacy: () async {
      clears++;
      if (!keyPresent) return true; // removing an absent key is a no-op ok
      keyPresent = false;
      return true;
    },
    clock: () => 4242,
  );

  test(
    'nothing stored: reads, clears the (absent) key, inserts nothing',
    () async {
      keyPresent = false;
      final result = await useCase()();
      expect(result.toNullable(), 0);
      expect(clears, 1);
      expect(repo.applyCalls, isEmpty); // no transaction at all
    },
  );

  test(
    'migrates every bookmark in order, appended after existing rows',
    () async {
      repo.rows = [
        const NetworkLibrary(
          id: 1,
          siteUrl: 'https://old.github.io/',
          sortOrder: 5,
        ),
      ];
      legacy = [
        (label: 'First Library', url: urlA),
        (label: 'Second Library', url: urlB),
      ];

      final result = await useCase()();

      expect(result.toNullable(), 2);
      expect(repo.applyCalls, hasLength(1)); // ONE transaction
      expect(repo.applyCalls.single.$1, isEmpty); // updates: none
      final inserted = repo.applyCalls.single.$2;
      expect(inserted.map((r) => r.siteUrl), [urlA, urlB]);
      expect(inserted.map((r) => r.name), ['First Library', 'Second Library']);
      expect(inserted.every((r) => r.source == NetworkSource.bookmark), isTrue);
      // Order preserved via sortOrder, continuing after the existing maximum.
      expect(inserted.map((r) => r.sortOrder), [6, 7]);
      expect(inserted.every((r) => r.createdAt == 4242), isTrue);
      expect(inserted.every((r) => r.id == 0), isTrue); // ids mint on insert
      expect(keyPresent, isFalse); // cleared only AFTER the commit
    },
  );

  test(
    'idempotent: known URLs are skipped, a full rerun inserts nothing',
    () async {
      legacy = [(label: 'A', url: urlA), (label: 'B', url: urlB)];
      expect((await useCase()()).toNullable(), 2);

      // Simulate the committed rows being on disk now.
      repo.rows = [
        const NetworkLibrary(id: 1, siteUrl: urlA, name: 'A', sortOrder: 1),
        const NetworkLibrary(id: 2, siteUrl: urlB, name: 'B', sortOrder: 2),
      ];
      // The key survived a crash between commit and clear ⇒ rerun:
      keyPresent = true;
      legacy = [(label: 'A', url: urlA), (label: 'B', url: urlB)];
      final second = await useCase()();

      expect(second.toNullable(), 0);
      expect(repo.applyCalls, hasLength(1)); // nothing new was written
      expect(keyPresent, isFalse); // … but the key is gone for good
    },
  );

  test('duplicate URLs inside the legacy list collapse', () async {
    legacy = [(label: 'A', url: urlA), (label: 'A again', url: urlA)];
    expect((await useCase()()).toNullable(), 1);
  });

  test('SECURITY: a label with bidi-override chars degrades to an empty '
      'name (the row still migrates)', () async {
    legacy = [(label: 'Evil\u202EName', url: urlA)];
    final result = await useCase()();
    expect(result.toNullable(), 1);
    expect(repo.applyCalls.single.$2.single.name, '');
  });

  test('a failed commit leaves the key ALONE and reports Left', () async {
    legacy = [(label: 'A', url: urlA)];
    repo.applyResult = left(const StorageFailure('disk gone'));

    final result = await useCase()();

    expect(result.isLeft(), isTrue);
    expect(keyPresent, isTrue); // fail closed: the data is not destroyed
    expect(clears, 0);
  });

  test('a failed key-clear reports Left even though rows committed', () async {
    legacy = [(label: 'A', url: urlA)];
    final useCaseUnderTest = MigrateLegacyBookmarksUseCase(
      repository: repo,
      readLegacy: () async => List.of(legacy),
      clearLegacy: () async => false, // the plugin said "no"
      clock: () => 4242,
    );

    final result = await useCaseUnderTest();

    expect(result.isLeft(), isTrue);
    expect(repo.applyCalls, hasLength(1)); // rows are committed …
    // … and the next run finds them all present and retries the clear.
  });
}

/// Repository fake with the two operations the migration touches.
class _FakeRepo implements NetworkRepository {
  List<NetworkLibrary> rows = [];
  final List<(List<NetworkLibrary>, List<NetworkLibrary>)> applyCalls = [];
  Either<Failure, Unit> applyResult = right(unit);

  @override
  Future<List<NetworkLibrary>> loadAll() async => List.of(rows);

  @override
  Future<Either<Failure, Unit>> applyRefresh(
    List<NetworkLibrary> updated,
    List<NetworkLibrary> discovered,
  ) async {
    applyCalls.add((List.of(updated), List.of(discovered)));
    if (applyResult.isLeft()) return applyResult;
    var nextId = rows.fold(0, (max, r) => r.id > max ? r.id : max);
    for (final insert in discovered) {
      nextId++;
      rows.add(insert.copyWith(id: nextId));
    }
    return right(unit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository operation');
}
