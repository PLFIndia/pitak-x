import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/bookmarks/domain/library_bookmark.dart';
import 'package:pitaka/features/bookmarks/infrastructure/prefs_bookmarks_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PrefsBookmarksRepository> repo() async {
    final prefs = await SharedPreferences.getInstance();
    return PrefsBookmarksRepository(prefs);
  }

  LibraryBookmark mk(String label, String url) =>
      LibraryBookmark.create(label: label, url: url)!;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('load is empty when nothing stored', () async {
    final loaded = await (await repo()).load();
    expect(loaded, isEmpty);
  });

  test('add appends and persists across instances', () async {
    final r = await repo();
    await r.add(mk('A', 'https://a.github.io/'));
    await r.add(mk('B', 'https://b.pages.dev/'));

    // A fresh repo over the same prefs sees both, in order.
    final reloaded = await (await repo()).load();
    expect(reloaded.map((b) => b.label), ['A', 'B']);
    expect(reloaded[1].url, 'https://b.pages.dev/');
  });

  test(
    'removeAt removes the right one; out-of-range is a safe no-op',
    () async {
      final r = await repo();
      await r.add(mk('A', 'https://a.github.io/'));
      await r.add(mk('B', 'https://b.github.io/'));

      final afterRemove = await r.removeAt(0);
      expect(afterRemove.getOrElse((_) => []).map((b) => b.label), ['B']);

      final afterBad = await r.removeAt(9);
      expect(afterBad.getOrElse((_) => []).map((b) => b.label), ['B']);
    },
  );

  test('a corrupt stored value degrades to empty, never throws', () async {
    SharedPreferences.setMockInitialValues({'library_bookmarks': '{ not json'});
    final loaded = await (await repo()).load();
    expect(loaded, isEmpty);
  });

  test('a stored entry with a now-invalid url is dropped on load', () async {
    // Simulate a tampered/older value containing a non-Pages url.
    SharedPreferences.setMockInitialValues({
      'library_bookmarks':
          '[{"label":"ok","url":"https://x.github.io/"},'
          '{"label":"bad","url":"https://evil.com/"}]',
    });
    final loaded = await (await repo()).load();
    expect(loaded.map((b) => b.label), ['ok']);
  });
}
