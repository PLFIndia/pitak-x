import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/infrastructure/legacy_bookmarks_reader.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests for [LegacyBookmarksReader] (libNetwork.md §6 "Legacy prefs value"):
/// the stored value is HOSTILE input — every item is re-validated with the
/// old `LibraryBookmark.fromJson` rules and corrupt items are skipped, never
/// thrown.
void main() {
  const key = LegacyBookmarksReader.prefsKey;

  Future<LegacyBookmarksReader> readerWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return LegacyBookmarksReader(await SharedPreferences.getInstance());
  }

  test('the prefs key is the one the deleted feature wrote (wire-stable)', () {
    expect(key, 'library_bookmarks');
  });

  test('reads valid items in stored order, trimmed and normalized', () async {
    final reader = await readerWith({
      key: jsonEncode([
        {'label': '  First  ', 'url': 'https://a.github.io/lib/'},
        {'label': 'Second', 'url': '  https://b.pages.dev/  '},
      ]),
    });

    final items = await reader.read();
    expect(items, [
      (label: 'First', url: 'https://a.github.io/lib/'),
      (label: 'Second', url: 'https://b.pages.dev/'),
    ]);
  });

  test('corrupt items are skipped, valid ones survive', () async {
    final reader = await readerWith({
      key: jsonEncode([
        {'label': 'Good', 'url': 'https://good.github.io/'},
        'not-an-object',
        42,
        null,
        {'label': 'No URL'},
        {'url': 'https://no-label.github.io/'},
        {'label': 7, 'url': 'https://wrong-type.github.io/'},
        {'label': '', 'url': 'https://blank-label.github.io/'},
      ]),
    });
    final items = await reader.read();
    expect(items.map((b) => b.url), ['https://good.github.io/']);
  });

  test('SECURITY: items with non-allow-listed URLs are dropped', () async {
    final reader = await readerWith({
      key: jsonEncode([
        {'label': 'Evil', 'url': 'https://evil.com/'},
        {'label': 'Spoof', 'url': 'https://github.io.evil.com/'},
        {'label': 'Plain http', 'url': 'http://a.github.io/'},
        {'label': 'Creds', 'url': 'https://user:pw@a.github.io/'},
      ]),
    });
    expect(await reader.read(), isEmpty);
  });

  test('blank and over-long labels are dropped (old create() rules)', () async {
    final reader = await readerWith({
      key: jsonEncode([
        {'label': '   ', 'url': 'https://blank.github.io/'},
        {'label': 'x' * 81, 'url': 'https://long.github.io/'},
        {'label': 'x' * 80, 'url': 'https://max.github.io/'},
      ]),
    });
    final items = await reader.read();
    expect(items.map((b) => b.url), ['https://max.github.io/']);
  });

  test('corrupt JSON degrades to empty, never throws', () async {
    final reader = await readerWith({key: '{not json at all'});
    expect(await reader.read(), isEmpty);
  });

  test('a JSON value that is not an array degrades to empty', () async {
    final reader = await readerWith({
      key: jsonEncode({'label': 'x'}),
    });
    expect(await reader.read(), isEmpty);
  });

  test('absent or blank key reads as empty', () async {
    expect(await (await readerWith({})).read(), isEmpty);
    expect(await (await readerWith({key: ''})).read(), isEmpty);
  });

  test(
    'clear() removes the key; clearing an absent key still succeeds',
    () async {
      SharedPreferences.setMockInitialValues({
        key: jsonEncode([
          {'label': 'A', 'url': 'https://a.github.io/'},
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final reader = LegacyBookmarksReader(prefs);

      expect(await reader.clear(), isTrue);
      expect(prefs.getString(key), isNull);
      expect(await reader.read(), isEmpty);
      // Idempotent: a second clear is a successful no-op.
      expect(await reader.clear(), isTrue);
    },
  );
}
