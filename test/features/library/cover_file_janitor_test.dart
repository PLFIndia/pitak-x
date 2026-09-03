import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/cover_file_janitor.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/library/infrastructure/cover_store.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';

class _Books implements BookRepository {
  _Books(this.rows, {this.fail = false});
  final List<Book> rows;
  final bool fail;

  @override
  Future<Either<Failure, List<Book>>> getAll() async =>
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
      books: _Books([
        const Book(title: 'A', coverUrl: 'covers/$a'),
        const Book(title: 'B', coverUrl: 'file:///old/path/$b'), // legacy ref
        const Book(title: 'R', coverUrl: 'https://covers.openlibrary.org/x'),
      ]),
      settings: _Settings(logo: 'covers/$logo'),
      store: store,
    );
    final removed = await janitor.sweep();
    expect(removed, 1);
    // Referenced covers, the logo, and a non-cover file all survive.
    expect(leaves(), {a, b, logo, 'notes.txt'});
  });

  test('sweep deletes NOTHING when the database cannot be read', () async {
    final janitor = CoverFileJanitor(
      books: _Books(const [], fail: true),
      settings: _Settings(),
      store: store,
    );
    expect(await janitor.sweep(), 0);
    expect(leaves(), {a, b, logo, orphan, 'notes.txt'});
  });

  test(
    'releaseReference deletes a file only once nothing points at it',
    () async {
      final janitor = CoverFileJanitor(
        books: _Books([const Book(title: 'A', coverUrl: 'covers/$a')]),
        settings: _Settings(logo: 'covers/$logo'),
        store: store,
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
}
