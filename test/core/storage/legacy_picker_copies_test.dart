/// Decision D33: the copies of chosen files that the `file_selector` plugin
/// left in the app's cache folder are removed, and NOTHING else is.
///
/// The cache folder is shared with other code, so most of these tests are
/// about what must stay: a folder that only looks like the plugin's, a link,
/// a folder that is not directly inside the root.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/storage/legacy_picker_copies.dart';

/// A UUID of version 3 the way Java makes one from a name
/// (`UUID.nameUUIDFromBytes`, read in the Android SDK's `UUID.java`): the
/// MD5 of the name, with the version set to 3 and the variant to "IETF",
/// printed in lower-case hex. The plugin named a copy's folder like this,
/// from the address of the picked document.
String javaNameUuid(String name) {
  final bytes = md5.convert(utf8.encode(name)).bytes.toList();
  bytes[6] = (bytes[6] & 0x0f) | 0x30;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  return _print(bytes);
}

/// A random UUID the way Java makes one (`UUID.randomUUID`): version 4.
/// `image_picker` names its folders in the same cache folder like this.
String javaRandomUuid(Random random) {
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  return _print(bytes);
}

String _print(List<int> bytes) {
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
  return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
      '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
      '${hex.sublist(10).join()}';
}

void main() {
  late Directory cache;

  // Two folder names of the plugin's kind, and one of image_picker's kind.
  final copyA = javaNameUuid('content://com.android.providers/document/1');
  final copyB = javaNameUuid('content://com.android.providers/document/2');
  const randomNamed = '6f1c3b2a-9d4e-4a7b-8c1d-0123456789ab';

  setUp(() {
    cache = Directory.systemTemp.createTempSync('legacy_picker_copies_test');
  });

  tearDown(() {
    if (cache.existsSync()) cache.deleteSync(recursive: true);
  });

  Directory folder(String name) =>
      Directory(p.join(cache.path, name))..createSync(recursive: true);

  File fileIn(Directory dir, String name) =>
      File(p.join(dir.path, name))..writeAsBytesSync([1, 2, 3]);

  Future<bool> remove() => LegacyPickerCopies(cacheRoot: cache.path).remove();

  group('what the plugin left is removed', () {
    test('a folder with its one copy', () async {
      final copy = folder(copyA);
      fileIn(copy, 'library.json');

      expect(await remove(), isTrue);
      expect(copy.existsSync(), isFalse);
    });

    test('several folders, one with two files and one that is empty', () async {
      final first = folder(copyA);
      fileIn(first, 'Pitak-backup.pitabak');
      fileIn(first, 'second.bin');
      final empty = folder(copyB);

      expect(await remove(), isTrue);
      expect(first.existsSync(), isFalse);
      expect(empty.existsSync(), isFalse);
      expect(cache.listSync(), isEmpty);
    });

    test('nothing to remove is done, too', () async {
      expect(await remove(), isTrue);
    });
  });

  group('what is not the plugin\u2019s stays', () {
    /// Removes, then expects [kept] (a path inside the cache) to be there.
    Future<void> expectKept(String kept) async {
      expect(await remove(), isTrue);
      expect(
        FileSystemEntity.typeSync(kept, followLinks: false),
        isNot(FileSystemEntityType.notFound),
        reason: kept,
      );
    }

    test('a folder named with a RANDOM UUID (version 4), as image_picker '
        'makes them', () async {
      final photo = fileIn(folder(randomNamed), 'photo.jpg');
      await expectKept(photo.path);
    });

    test('the app\u2019s own folders and files', () async {
      final picked = fileIn(folder('picked_documents/pick-1'), 'document');
      final work = fileIn(folder('backup_work/run-1'), 'backup.pitabak');
      final loose = fileIn(cache, 'image_picker123.jpg');
      expect(await remove(), isTrue);
      expect(picked.existsSync(), isTrue);
      expect(work.existsSync(), isTrue);
      expect(loose.existsSync(), isTrue);
    });

    test('names that only look like the plugin\u2019s', () async {
      final lookalikes = [
        copyA.toUpperCase(),
        '$copyA.tmp',
        'x$copyA',
        copyA.substring(1),
        copyA.replaceAll('-', ''),
        // A version 3 name with a variant Java never writes.
        '6f1c3b2a-9d4e-3a7b-cc1d-0123456789ab',
        // Versions 1, 2 and 5.
        '6f1c3b2a-9d4e-1a7b-8c1d-0123456789ab',
        '6f1c3b2a-9d4e-2a7b-8c1d-0123456789ab',
        '6f1c3b2a-9d4e-5a7b-8c1d-0123456789ab',
      ];
      final files = [
        for (final name in lookalikes) fileIn(folder(name), 'file.bin'),
      ];
      expect(await remove(), isTrue);
      for (final file in files) {
        expect(file.existsSync(), isTrue, reason: file.path);
      }
    });

    test('a FILE named like a copy\u2019s folder', () async {
      final file = fileIn(cache, copyA);
      await expectKept(file.path);
    });

    test('a folder of the right name that holds a folder: left alone, '
        'whole', () async {
      final copy = folder(copyA);
      final file = fileIn(copy, 'file.bin');
      final inner = fileIn(folder('$copyA/inner'), 'deep.bin');

      expect(await remove(), isTrue);
      expect(file.existsSync(), isTrue, reason: 'not even its files go');
      expect(inner.existsSync(), isTrue);
    });

    test('a folder of the right name that holds a link: left alone, and '
        'the link\u2019s target is untouched', () async {
      final outside = Directory.systemTemp.createTempSync('legacy_outside');
      addTearDown(() => outside.deleteSync(recursive: true));
      final target = File(p.join(outside.path, 'precious.txt'))
        ..writeAsBytesSync([9]);
      final copy = folder(copyA);
      final file = fileIn(copy, 'file.bin');
      Link(p.join(copy.path, 'link')).createSync(target.path);

      expect(await remove(), isTrue);
      expect(file.existsSync(), isTrue);
      expect(target.existsSync(), isTrue);
    });

    test('a LINK named like a copy\u2019s folder is not followed: the link '
        'and what it points at stay', () async {
      final outside = Directory.systemTemp.createTempSync('legacy_outside');
      addTearDown(() => outside.deleteSync(recursive: true));
      final precious = File(p.join(outside.path, 'precious.txt'))
        ..writeAsBytesSync([9]);
      final link = Link(p.join(cache.path, copyA))..createSync(outside.path);

      expect(await remove(), isTrue);
      expect(precious.existsSync(), isTrue);
      expect(
        FileSystemEntity.typeSync(link.path, followLinks: false),
        FileSystemEntityType.link,
      );
    });

    test('a folder of the right name that is NOT directly inside the '
        'cache folder', () async {
      final deep = fileIn(folder('some_plugin/$copyA'), 'file.bin');
      await expectKept(deep.path);
    });
  });

  group('the cache folder itself', () {
    test('a cache folder that is not there: nothing to do', () async {
      final gone = LegacyPickerCopies(cacheRoot: p.join(cache.path, 'nope'));
      expect(await gone.remove(), isTrue);
    });

    test('a cache folder that is a LINK is not followed', () async {
      final real = folder('real');
      final copy = fileIn(
        Directory(p.join(real.path, copyA))..createSync(),
        'file.bin',
      );
      final link = Link(p.join(cache.path, 'link'))..createSync(real.path);

      expect(await LegacyPickerCopies(cacheRoot: link.path).remove(), isTrue);
      expect(copy.existsSync(), isTrue);
    });
  });

  test('a copy that cannot be deleted: the answer is false, and the other '
      'copies still go', () async {
    final stuck = folder(copyA);
    final stuckFile = fileIn(stuck, 'file.bin');
    final other = folder(copyB);
    fileIn(other, 'file.bin');
    // A folder nobody may write to: its file cannot be deleted.
    Process.runSync('chmod', ['500', stuck.path]);
    addTearDown(() => Process.runSync('chmod', ['700', stuck.path]));
    var deletable = true;
    try {
      File(p.join(stuck.path, 'probe')).writeAsBytesSync([1]);
    } on FileSystemException {
      deletable = false;
    }
    if (deletable) {
      // An administrator account may write anywhere, and Windows has no
      // `chmod`: the case cannot be made there.
      markTestSkipped('this account can write into a read-only folder');
      return;
    }

    expect(await remove(), isFalse);
    expect(stuckFile.existsSync(), isTrue);
    expect(other.existsSync(), isFalse);

    // Once the folder can be written to again, the next try removes it.
    Process.runSync('chmod', ['700', stuck.path]);
    expect(await remove(), isTrue);
    expect(stuck.existsSync(), isFalse);
  });

  group('the names that are recognised', () {
    test('every name Java makes from a document\u2019s address is '
        'recognised', () {
      for (var i = 0; i < 500; i++) {
        final name = javaNameUuid(
          'content://com.android.externalstorage.documents/document/'
          'primary%3ADownload%2Ffile-$i.json',
        );
        expect(
          LegacyPickerCopies.folderNamePattern.hasMatch(name),
          isTrue,
          reason: name,
        );
      }
    });

    test('no RANDOM name (version 4) is recognised', () {
      final random = Random(20261114);
      for (var i = 0; i < 500; i++) {
        final name = javaRandomUuid(random);
        expect(
          LegacyPickerCopies.folderNamePattern.hasMatch(name),
          isFalse,
          reason: name,
        );
      }
    });

    test('the helper of this test makes the name Java documents', () {
      // One example worked by hand, by the steps of `UUID.java`: the MD5
      // of the empty text is d41d8cd98f00b204e9800998ecf8427e; `b2` becomes
      // `32` (version 3) and `e9` becomes `a9` (the variant).
      expect(javaNameUuid(''), 'd41d8cd9-8f00-3204-a980-0998ecf8427e');
    });
  });
}
