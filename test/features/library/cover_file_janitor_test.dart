import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/cover_file_janitor.dart';
import 'package:pitaka/features/library/domain/cover_file_coordinator.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/infrastructure/cover_store.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

class _Books implements CatalogueItemRepository {
  const _Books(this.rows, {this.fail = false});
  final List<CatalogueItem> rows;
  final bool fail;

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async =>
      fail ? left(const StorageFailure('db closed')) : right(rows);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

class _Settings implements SettingsRepository {
  _Settings({this.logo = ''});
  final String logo;

  @override
  Future<AppSettings> load() async =>
      AppSettings.defaults.copyWith(libraryLogo: logo);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

/// M11: wishlist rows are cover-reference owners too.
class _Wishlist implements WishlistRepository {
  const _Wishlist(this.rows, {this.fail = false});
  final List<WishlistBook> rows;
  final bool fail;

  @override
  Future<Either<Failure, List<WishlistBook>>> getAll() async =>
      fail ? left(const StorageFailure('db closed')) : right(rows);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

/// W4 (ADR 0014): periodicals own series covers in the same directory.
class _Periodicals implements PeriodicalRepository {
  const _Periodicals(this.rows, {this.fail = false});
  final List<Periodical> rows;
  final bool fail;

  @override
  Future<Either<Failure, List<PeriodicalSummary>>> listAll() async => fail
      ? left(const StorageFailure('db closed'))
      : right([
          for (final p in rows) PeriodicalSummary(periodical: p, issueCount: 0),
        ]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

void main() {
  late Directory tmp;
  late CoverStore store;

  const a = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg';
  const b = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jpg';
  const logo = 'cccccccc-cccc-cccc-cccc-cccccccccccc.jpg';
  const orphan = 'dddddddd-dddd-dddd-dddd-dddddddddddd.jpg';

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('janitor');
    store = CoverStore(coversDir: tmp.path);
    for (final leaf in [a, b, logo, orphan, 'notes.txt']) {
      File('${tmp.path}/$leaf').writeAsBytesSync([1]);
    }
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Set<String> leaves() => store.listLeaves().toSet();

  test('sweep removes only unreferenced cover-shaped files', () async {
    final janitor = CoverFileJanitor(
      books: const _Books([
        CatalogueItem(title: 'A', coverUrl: 'covers/$a'),
        CatalogueItem(
          title: 'B',
          coverUrl: 'file:///old/path/$b',
        ), // legacy ref
        CatalogueItem(title: 'R', coverUrl: 'https://covers.openlibrary.org/x'),
      ]),
      wishlist: const _Wishlist([]),
      periodicals: const _Periodicals([]),
      settings: _Settings(logo: 'covers/$logo'),
      store: store,
      coordinator: CoverFileCoordinator(),
    );
    final removed = await janitor.sweep();
    expect(removed, 1);
    // Referenced covers, the logo, and a non-cover file all survive.
    expect(leaves(), {a, b, logo, 'notes.txt'});
  });

  test('sweep deletes NOTHING when the database cannot be read', () async {
    final janitor = CoverFileJanitor(
      books: const _Books([], fail: true),
      wishlist: const _Wishlist([]),
      periodicals: const _Periodicals([]),
      settings: _Settings(),
      store: store,
      coordinator: CoverFileCoordinator(),
    );
    expect(await janitor.sweep(), 0);
    expect(leaves(), {a, b, logo, orphan, 'notes.txt'});
  });

  test(
    'releaseReference deletes a file only once nothing points at it',
    () async {
      final janitor = CoverFileJanitor(
        books: const _Books([CatalogueItem(title: 'A', coverUrl: 'covers/$a')]),
        wishlist: const _Wishlist([]),
        periodicals: const _Periodicals([]),
        settings: _Settings(logo: 'covers/$logo'),
        store: store,
        coordinator: CoverFileCoordinator(),
      );
      await janitor.releaseReference('covers/$a'); // still referenced by A
      expect(File('${tmp.path}/$a').existsSync(), isTrue);
      await janitor.releaseReference('covers/$logo'); // still the logo
      expect(File('${tmp.path}/$logo').existsSync(), isTrue);
      await janitor.releaseReference('covers/$orphan'); // nobody's
      expect(File('${tmp.path}/$orphan').existsSync(), isFalse);
      // Remote / blank / traversal references are ignored, never IO.
      await janitor.releaseReference('https://x/y.jpg');
      await janitor.releaseReference('covers/../notes.txt');
      await janitor.releaseReference(null);
      expect(File('${tmp.path}/notes.txt').existsSync(), isTrue);
    },
  );

  // M11 regression: the janitor used to collect references from library
  // books + logo ONLY, so a startup sweep deleted covers owned solely by a
  // wishlist entry, and releasing a library book could delete a cover the
  // wishlist still shared.
  test('M11: a wishlist-only cover survives the startup sweep', () async {
    final janitor = CoverFileJanitor(
      books: const _Books([]), // no library book references $orphan...
      wishlist: const _Wishlist([
        WishlistBook(
          title: 'W',
          coverUrl: 'covers/$orphan',
        ), // ...wishlist does
      ]),
      periodicals: const _Periodicals([]),
      settings: _Settings(),
      store: store,
      coordinator: CoverFileCoordinator(),
    );
    await janitor.sweep();
    expect(File('${tmp.path}/$orphan').existsSync(), isTrue);
  });

  test(
    'M11: a cover shared with the wishlist survives a book release',
    () async {
      final janitor = CoverFileJanitor(
        books: const _Books([]), // the library book is already gone...
        wishlist: const _Wishlist([
          WishlistBook(
            title: 'W',
            coverUrl: 'covers/$a',
          ), // ...wishlist still holds it
        ]),
        periodicals: const _Periodicals([]),
        settings: _Settings(),
        store: store,
        coordinator: CoverFileCoordinator(),
      );
      await janitor.releaseReference('covers/$a');
      expect(File('${tmp.path}/$a').existsSync(), isTrue);
    },
  );

  test('M11: an unreadable wishlist fails closed (nothing deleted)', () async {
    final janitor = CoverFileJanitor(
      books: const _Books([]),
      wishlist: const _Wishlist([], fail: true),
      periodicals: const _Periodicals([]),
      settings: _Settings(),
      store: store,
      coordinator: CoverFileCoordinator(),
    );
    expect(await janitor.sweep(), 0);
    expect(leaves(), {a, b, logo, orphan, 'notes.txt'});
  });

  // W4 (ADR 0014): a periodical's series cover lives in the same directory
  // and is the fallback cover of every issue without one of its own. The
  // janitor must count it as a live reference — the M11 bug class again.
  test('W4: a series cover survives the startup sweep', () async {
    final janitor = CoverFileJanitor(
      books: const _Books([]), // no catalogue row references $orphan...
      wishlist: const _Wishlist([]),
      periodicals: const _Periodicals([
        Periodical(title: 'Chandamama', coverUrl: 'covers/$orphan'),
      ]), // ...the series does
      settings: _Settings(),
      store: store,
      coordinator: CoverFileCoordinator(),
    );
    await janitor.sweep();
    expect(File('${tmp.path}/$orphan').existsSync(), isTrue);
  });

  test('W4: a cover shared with a series survives an item release', () async {
    final janitor = CoverFileJanitor(
      books: const _Books([]), // the issue that shared it is already gone...
      wishlist: const _Wishlist([]),
      periodicals: const _Periodicals([
        Periodical(title: 'Chandamama', coverUrl: 'covers/$a'),
      ]), // ...the series still holds it
      settings: _Settings(),
      store: store,
      coordinator: CoverFileCoordinator(),
    );
    await janitor.releaseReference('covers/$a');
    expect(File('${tmp.path}/$a').existsSync(), isTrue);
  });

  test('W4: an unreadable periodicals store fails closed', () async {
    final janitor = CoverFileJanitor(
      books: const _Books([]),
      wishlist: const _Wishlist([]),
      periodicals: const _Periodicals([], fail: true),
      settings: _Settings(),
      store: store,
      coordinator: CoverFileCoordinator(),
    );
    expect(await janitor.sweep(), 0);
    expect(leaves(), {a, b, logo, orphan, 'notes.txt'});
    await janitor.releaseReference('covers/$orphan');
    expect(File('${tmp.path}/$orphan').existsSync(), isTrue);
  });
}
