import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/bookmarks/application/bookmarks_controller.dart';
import 'package:pitaka/features/bookmarks/domain/bookmarks_repository.dart';
import 'package:pitaka/features/bookmarks/domain/library_bookmark.dart';

/// In-memory bookmarks repo.
class _FakeRepo implements BookmarksRepository {
  final List<LibraryBookmark> _list = [];

  @override
  Future<List<LibraryBookmark>> load() async => List.of(_list);

  @override
  Future<Either<Failure, List<LibraryBookmark>>> add(LibraryBookmark b) async {
    _list.add(b);
    return right(List.of(_list));
  }

  @override
  Future<Either<Failure, List<LibraryBookmark>>> removeAt(int index) async {
    if (index >= 0 && index < _list.length) _list.removeAt(index);
    return right(List.of(_list));
  }
}

ProviderContainer _container() {
  final c = ProviderContainer(
    overrides: [
      bookmarksRepositoryProvider.overrideWith((ref) async => _FakeRepo()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('starts empty', () async {
    final c = _container();
    expect(await c.read(bookmarksControllerProvider.future), isEmpty);
  });

  test('add accepts a valid Pages link and reflects it in state', () async {
    final c = _container();
    final n = c.read(bookmarksControllerProvider.notifier);
    await c.read(bookmarksControllerProvider.future);

    final ok = await n.add(label: 'My Lib', url: 'https://x.github.io/');
    expect(ok, isTrue);
    final list = c.read(bookmarksControllerProvider).value!;
    expect(list.single.label, 'My Lib');
  });

  test('add rejects a non-Pages link and does not change state', () async {
    final c = _container();
    final n = c.read(bookmarksControllerProvider.notifier);
    await c.read(bookmarksControllerProvider.future);

    final ok = await n.add(label: 'Bad', url: 'https://example.com/');
    expect(ok, isFalse);
    expect(c.read(bookmarksControllerProvider).value, isEmpty);
  });

  test('add rejects a blank label', () async {
    final c = _container();
    final n = c.read(bookmarksControllerProvider.notifier);
    await c.read(bookmarksControllerProvider.future);

    expect(await n.add(label: '  ', url: 'https://x.github.io/'), isFalse);
  });

  test('removeAt removes by index', () async {
    final c = _container();
    final n = c.read(bookmarksControllerProvider.notifier);
    await c.read(bookmarksControllerProvider.future);
    await n.add(label: 'A', url: 'https://a.github.io/');
    await n.add(label: 'B', url: 'https://b.pages.dev/');

    expect(await n.removeAt(0), isTrue);
    expect(c.read(bookmarksControllerProvider).value!.single.label, 'B');
  });
}
