import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/channel_document_picker.dart';
import 'package:pitaka/core/platform/document_picker.dart';

/// BR5b (decisions D8 and D19): the Dart side of the app's own document
/// picker. Android is played by a mock handler on the method channel; the
/// folders and files are real.
///
/// What these tests guard:
///  - Dart sends the cap and nothing else;
///  - every answer of the Android side maps to exactly one result, and a
///    missing Android side is "not available", never a second way (D19);
///  - a success answer is CHECKED: only `<temp>/picked_documents/
///    pick-…/document` with the announced size is accepted, and a folder of
///    ours that came with a wrong answer is removed;
///  - only our own folders are ever deleted, and a copy in use is not swept.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.khoj.pitaka/picked_document');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory temp;
  late List<MethodCall> calls;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pitaka_document_picker_');
    calls = <MethodCall>[];
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Directory root() =>
      Directory('${temp.path}/${ChannelDocumentPicker.directoryName}');

  ChannelDocumentPicker picker() => ChannelDocumentPicker(tempRoot: temp.path);

  /// Android answers every call with [answer] (a value, or it throws).
  void android(Object? Function(MethodCall call) answer) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return answer(call);
    });
  }

  /// A copy the way the Android side leaves it. Returns the folder.
  Directory copyOnDisk(String folderName, {List<int> bytes = const [1, 2, 3]}) {
    final folder = Directory('${root().path}/$folderName')
      ..createSync(recursive: true);
    File('${folder.path}/document').writeAsBytesSync(bytes);
    return folder;
  }

  Map<String, Object?> answerFor(
    Directory folder, {
    String name = 'backup.pitabak',
    int size = 3,
  }) => {'path': '${folder.path}/document', 'name': name, 'size': size};

  group('the call', () {
    test('sends the cap and nothing else', () async {
      android((_) => throw PlatformException(code: 'cancelled'));

      await picker().pickCopy(maxBytes: 528482304);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'pickAndCopy');
      expect(calls.single.arguments, {'maxBytes': 528482304});
    });

    test('a cap of zero or less never reaches Android', () async {
      android((_) => fail('Android must not be called'));

      for (final cap in [0, -1, -528482304]) {
        expect(
          await picker().pickCopy(maxBytes: cap),
          isA<DocumentPickFailed>(),
        );
      }
      expect(calls, isEmpty);
    });

    test('no Android side is "not available" (D19)', () async {
      // No handler registered: what every platform but Android looks like.
      expect(
        await picker().pickCopy(maxBytes: 1000),
        isA<DocumentPickUnavailable>(),
      );
      expect(root().existsSync(), isFalse);
    });

    test('each error code is exactly one answer', () async {
      final expected = <String, Matcher>{
        'cancelled': isA<DocumentPickCancelled>(),
        'too_large': isA<DocumentPickTooLarge>(),
        'unreadable': isA<DocumentPickUnreadable>(),
        'storage': isA<DocumentPickNotSaved>(),
        'unavailable': isA<DocumentPickUnavailable>(),
        // Mistakes in code, and anything this side does not know.
        'busy': isA<DocumentPickFailed>(),
        'invalid': isA<DocumentPickFailed>(),
        'failed': isA<DocumentPickFailed>(),
        'something_new': isA<DocumentPickFailed>(),
        'CANCELLED': isA<DocumentPickFailed>(),
        '': isA<DocumentPickFailed>(),
        '/data/user/0/secret path': isA<DocumentPickFailed>(),
      };
      for (final MapEntry(key: code, value: matcher) in expected.entries) {
        android((_) => throw PlatformException(code: code, message: 'x'));

        expect(
          await picker().pickCopy(maxBytes: 1000),
          matcher,
          reason: 'code "$code"',
        );
      }
    });
  });

  group('the debug log', () {
    test('gets a code of ours, never foreign text', () async {
      final lines = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        lines.add(message ?? '');
      };
      addTearDown(() => debugPrint = previous);

      for (final code in ['busy', '/data/user/0/secret path', 'Name.pitabak']) {
        android(
          (_) => throw PlatformException(code: code, message: 'secret text'),
        );
        await picker().pickCopy(maxBytes: 1000);
      }

      expect(lines, [
        'document_picker: pick failed: busy',
        'document_picker: pick failed: unknown code',
        'document_picker: pick failed: unknown code',
      ]);
    });

    test('gets nothing for an answer a user can act on', () async {
      final lines = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        lines.add(message ?? '');
      };
      addTearDown(() => debugPrint = previous);
      final folder = copyOnDisk('pick-quiet');

      android((_) => answerFor(folder, name: 'Family library.pitabak'));
      await picker().pickCopy(maxBytes: 1000);
      android((_) => throw PlatformException(code: 'too_large'));
      await picker().pickCopy(maxBytes: 1000);
      android((_) => {'path': '/somewhere/else', 'name': 'a', 'size': 3});
      await picker().pickCopy(maxBytes: 1000);

      expect(lines, isEmpty);
    });
  });

  group('a success answer', () {
    test('gives the copy: path, name and size', () async {
      final folder = copyOnDisk('pick-3f2a9c', bytes: List.filled(700, 7));
      android((_) => answerFor(folder, name: 'My backup.pitabak', size: 700));

      final result = await picker().pickCopy(maxBytes: 1000);

      expect(result, isA<DocumentPicked>());
      final document = (result as DocumentPicked).document;
      expect(document.path, '${folder.path}/document');
      expect(document.displayName, 'My backup.pitabak');
      expect(document.sizeBytes, 700);
      expect(File(document.path).lengthSync(), 700);
    });

    test('a copy of exactly the cap is accepted', () async {
      final folder = copyOnDisk('pick-atcap', bytes: List.filled(1000, 7));
      android((_) => answerFor(folder, size: 1000));

      expect(await picker().pickCopy(maxBytes: 1000), isA<DocumentPicked>());
    });

    test('an empty copy is accepted as an empty copy', () async {
      final folder = copyOnDisk('pick-empty', bytes: const []);
      android((_) => answerFor(folder, size: 0, name: ''));

      final result = await picker().pickCopy(maxBytes: 1000);

      expect((result as DocumentPicked).document.sizeBytes, 0);
      expect(result.document.displayName, '');
    });

    test('the path handed on is our own tidy spelling', () async {
      final folder = copyOnDisk('pick-tidy');
      android(
        (_) => {
          'path': '${root().path}/pick-x/../pick-tidy/./document',
          'name': 'a',
          'size': 3,
        },
      );

      final result = await picker().pickCopy(maxBytes: 1000);

      expect(
        (result as DocumentPicked).document.path,
        '${folder.path}/document',
      );
    });

    test('toString shows neither the name nor the path', () async {
      final folder = copyOnDisk('pick-private');
      android((_) => answerFor(folder, name: 'Family library.pitabak'));

      final result = await picker().pickCopy(maxBytes: 1000);
      final text = (result as DocumentPicked).document.toString();

      expect(text, 'PickedDocument(3 bytes)');
      expect(text, isNot(contains('Family')));
      expect(text, isNot(contains('pick-')));
    });
  });

  group('a success answer that is wrong', () {
    test('is refused when it is not the expected map', () async {
      final wrong = <Object?>[
        null,
        'a path',
        42,
        <Object?>['path'],
        <String, Object?>{},
        <String, Object?>{'name': 'a', 'size': 3},
        <String, Object?>{'path': 7, 'name': 'a', 'size': 3},
        <String, Object?>{'path': null, 'name': 'a', 'size': 3},
      ];
      for (final reply in wrong) {
        android((_) => reply);

        expect(
          await picker().pickCopy(maxBytes: 1000),
          isA<DocumentPickFailed>(),
          reason: 'reply $reply',
        );
      }
    });

    test('a path outside our folder is refused and never deleted', () async {
      final elsewhere = Directory('${temp.path}/databases/pick-abc')
        ..createSync(recursive: true);
      final file = File('${elsewhere.path}/document')
        ..writeAsBytesSync([1, 2, 3]);
      final wrongName = copyOnDisk('other-abc');
      final paths = <String>[
        file.path,
        elsewhere.path,
        // Right folder of all picks, wrong folder name.
        '${wrongName.path}/document',
        // A file directly in the folder of all picks.
        '${root().path}/document',
        // `..` out of a rightly named folder.
        '${root().path}/pick-abc/../../databases/pick-abc/document',
        '',
        '/',
      ];
      for (final path in paths) {
        android((_) => {'path': path, 'name': 'a', 'size': 3});

        expect(
          await picker().pickCopy(maxBytes: 1000),
          isA<DocumentPickFailed>(),
          reason: 'path "$path"',
        );
      }
      expect(file.readAsBytesSync(), [1, 2, 3]);
      expect(File('${wrongName.path}/document').existsSync(), isTrue);
    });

    test('a file one level too deep is refused; a sweep clears it', () async {
      final folder = copyOnDisk('pick-deep');
      Directory('${folder.path}/sub').createSync();
      File('${folder.path}/sub/document').writeAsBytesSync([1, 2, 3]);
      android(
        (_) => {'path': '${folder.path}/sub/document', 'name': 'a', 'size': 3},
      );
      final subject = picker();

      expect(await subject.pickCopy(maxBytes: 1000), isA<DocumentPickFailed>());
      // It was never taken over, so it is stale and the sweep removes it.
      await subject.sweep();
      expect(folder.existsSync(), isFalse);
    });

    test('a folder of ours with a wrong answer is removed', () async {
      // Each case: what lies on disk, and what Android claims about it.
      final cases = <String, Map<String, Object?> Function(Directory)>{
        'another file name': (f) {
          File('${f.path}/other').writeAsBytesSync([1, 2, 3]);
          return {'path': '${f.path}/other', 'name': 'a', 'size': 3};
        },
        'the folder itself': (f) => {'path': f.path, 'name': 'a', 'size': 3},
        'no file in it': (f) {
          File('${f.path}/document').deleteSync();
          return answerFor(f);
        },
        'a folder where the file should be': (f) {
          File('${f.path}/document').deleteSync();
          Directory('${f.path}/document').createSync();
          return answerFor(f);
        },
        'a size that is not the one of the file': (f) => answerFor(f, size: 4),
        'a size below the one of the file': (f) => answerFor(f, size: 2),
        'a negative size': (f) => answerFor(f, size: -3),
        'a size that is no whole number': (f) => {...answerFor(f), 'size': 3.0},
        'a size as text': (f) => {...answerFor(f), 'size': '3'},
        'no size': (f) => answerFor(f)..remove('size'),
        'no name': (f) => answerFor(f)..remove('name'),
        'a name that is no text': (f) => {...answerFor(f), 'name': 7},
      };
      var number = 0;
      for (final MapEntry(key: what, value: prepare) in cases.entries) {
        final folder = copyOnDisk('pick-case${number++}');
        final reply = prepare(folder);
        android((_) => reply);

        expect(
          await picker().pickCopy(maxBytes: 1000),
          isA<DocumentPickFailed>(),
          reason: what,
        );
        expect(folder.existsSync(), isFalse, reason: '$what: folder removed');
      }
    });

    test('a copy above the cap is refused and removed', () async {
      // The Android side counts too. This is the second lock on the door.
      final folder = copyOnDisk('pick-big', bytes: List.filled(1001, 7));
      android((_) => answerFor(folder, size: 1001));

      expect(
        await picker().pickCopy(maxBytes: 1000),
        isA<DocumentPickFailed>(),
      );
      expect(folder.existsSync(), isFalse);
    });

    test(
      'a link where the file should be is refused; its target stays',
      () async {
        final target = File('${temp.path}/target')..writeAsBytesSync([1, 2, 3]);
        final folder = copyOnDisk('pick-link');
        File('${folder.path}/document').deleteSync();
        Link('${folder.path}/document').createSync(target.path);
        android((_) => answerFor(folder));

        expect(
          await picker().pickCopy(maxBytes: 1000),
          isA<DocumentPickFailed>(),
        );
        expect(folder.existsSync(), isFalse);
        expect(target.readAsBytesSync(), [1, 2, 3]);
      },
    );

    test(
      'a link where the folder should be is refused and left alone',
      () async {
        final target = Directory('${temp.path}/target')..createSync();
        File('${target.path}/document').writeAsBytesSync([1, 2, 3]);
        root().createSync(recursive: true);
        final link = Link('${root().path}/pick-link')..createSync(target.path);
        android(
          (_) => {'path': '${link.path}/document', 'name': 'a', 'size': 3},
        );

        expect(
          await picker().pickCopy(maxBytes: 1000),
          isA<DocumentPickFailed>(),
        );
        expect(File('${target.path}/document').readAsBytesSync(), [1, 2, 3]);
      },
    );
  });

  group('the display name', () {
    String clean(String raw) => ChannelDocumentPicker.cleanDisplayName(raw);

    test('loses control characters and is cut at 255', () {
      expect(clean('backup.pitabak'), 'backup.pitabak');
      expect(clean('a\n\r\t\u0000\u001b\u007f\u0085b'), 'ab');
      expect(clean('x' * 100000).length, 255);
      expect(clean(''), '');
    });

    test('never ends in half a two-part character', () {
      const book = '\u{1F4DA}'; // two UTF-16 units
      expect(clean('${'x' * 254}$book'), 'x' * 254);
      expect(clean('${'x' * 253}$book'), '${'x' * 253}$book');
      // A half on its own is dropped wherever it stands.
      final loneHalf = String.fromCharCode(0xd83d);
      expect(clean('a${loneHalf}b'), 'ab');
    });

    test('keeps the joiners that Indic scripts need', () {
      const kssa = '\u0915\u094D\u200D\u0937';
      expect(clean(kssa), kssa);
    });

    test('is cleaned on the way in, whatever Android sent', () async {
      final folder = copyOnDisk('pick-name');
      android((_) => answerFor(folder, name: 'my\nbackup\u0000${'x' * 1000}'));

      final result = await picker().pickCopy(maxBytes: 1000);
      final name = (result as DocumentPicked).document.displayName;

      expect(name.length, 255);
      expect(name, startsWith('mybackupxxx'));
    });
  });

  group('discard and sweep', () {
    Future<PickedDocument> pickWith(
      ChannelDocumentPicker subject,
      String folderName,
    ) async {
      final folder = copyOnDisk(folderName);
      android((_) => answerFor(folder));
      final result = await subject.pickCopy(maxBytes: 1000);
      return (result as DocumentPicked).document;
    }

    test(
      'discard removes the copy with its folder, and may be repeated',
      () async {
        final subject = picker();
        final document = await pickWith(subject, 'pick-one');

        await subject.discard(document);
        expect(File(document.path).parent.existsSync(), isFalse);
        await subject.discard(document);
        expect(root().existsSync(), isTrue, reason: 'only the one folder goes');
      },
    );

    test('discard of a path that is not ours deletes nothing', () async {
      final foreign = File('${temp.path}/catalogue.db')..writeAsBytesSync([9]);
      final other = copyOnDisk('other-name');
      final subject = picker();

      await subject.discard(
        PickedDocument(path: foreign.path, displayName: '', sizeBytes: 1),
      );
      await subject.discard(
        PickedDocument(path: temp.path, displayName: '', sizeBytes: 1),
      );
      await subject.discard(
        PickedDocument(
          path: '${other.path}/document',
          displayName: '',
          sizeBytes: 3,
        ),
      );

      expect(foreign.existsSync(), isTrue);
      expect(temp.existsSync(), isTrue);
      expect(File('${other.path}/document').existsSync(), isTrue);
    });

    test('a sweep spares a copy in use and removes a stale one', () async {
      final subject = picker();
      final inUse = await pickWith(subject, 'pick-inuse');
      final stale = copyOnDisk('pick-stale');

      await subject.sweep();

      expect(File(inUse.path).existsSync(), isTrue);
      expect(stale.existsSync(), isFalse);

      // Once discarded it is gone, and a later sweep has nothing to do.
      await subject.discard(inUse);
      await subject.sweep();
      expect(File(inUse.path).existsSync(), isFalse);
    });

    test('a second pick does not remove the first', () async {
      final subject = picker();
      final first = await pickWith(subject, 'pick-first');
      final second = await pickWith(subject, 'pick-second');

      expect(File(first.path).existsSync(), isTrue);
      expect(File(second.path).existsSync(), isTrue);
    });

    test('the next app start sweeps what this one left in use', () async {
      final document = await pickWith(picker(), 'pick-left');

      // A new object stands for the next start of the app.
      await picker().sweep();

      expect(File(document.path).parent.existsSync(), isFalse);
    });

    test('a sweep with nothing there does nothing', () async {
      await picker().sweep();

      expect(root().existsSync(), isFalse);
    });
  });

  // BR6 (design point 4): Dart learns of a copy's folder only when Android
  // answers. Until then the folder looks like one nobody uses, and a sweep
  // would delete it under the copy that is still being written.
  group('a sweep and a pick at the same time', () {
    test('a sweep during a pick removes nothing, and works again '
        'afterwards', () async {
      final subject = picker();
      final stale = copyOnDisk('pick-stale');
      final arrived = Completer<Directory>();
      final mayAnswer = Completer<void>();
      // Android has made the folder and is still copying into it.
      messenger.setMockMethodCallHandler(channel, (call) async {
        final folder = copyOnDisk('pick-busy');
        arrived.complete(folder);
        await mayAnswer.future;
        return answerFor(folder);
      });

      final pick = subject.pickCopy(maxBytes: 1000);
      final busy = await arrived.future;
      await subject.sweep();

      expect(busy.existsSync(), isTrue, reason: 'the copy being written');
      expect(stale.existsSync(), isTrue, reason: 'this sweep does nothing');

      mayAnswer.complete();
      final result = await pick;
      expect(result, isA<DocumentPicked>());

      // The pick is over: a sweep removes the stale copy and spares the
      // picked one, which is in use now.
      await subject.sweep();
      expect(stale.existsSync(), isFalse);
      expect(
        File((result as DocumentPicked).document.path).existsSync(),
        isTrue,
      );
    });

    test('a pick that ends without a copy lets the next sweep run', () async {
      final subject = picker();
      final outcomes = <String, Object? Function(MethodCall)>{
        'an error code': (_) => throw PlatformException(code: 'unreadable'),
        'an answer that is refused': (_) => 'not a map',
        'an error nobody expected': (_) => throw StateError('boom'),
      };
      for (final MapEntry(key: label, value: answer) in outcomes.entries) {
        android(answer);
        expect(
          await subject.pickCopy(maxBytes: 1000),
          isNot(isA<DocumentPicked>()),
          reason: label,
        );
        final stale = copyOnDisk('pick-stale');

        await subject.sweep();

        expect(stale.existsSync(), isFalse, reason: label);
      }
      // The same without any Android side (D19).
      messenger.setMockMethodCallHandler(channel, null);
      expect(
        await subject.pickCopy(maxBytes: 1000),
        isA<DocumentPickUnavailable>(),
      );
      final stale = copyOnDisk('pick-stale');
      await subject.sweep();
      expect(stale.existsSync(), isFalse);
    });

    test(
      'a cap that never reaches Android does not hold a sweep back',
      () async {
        final subject = picker();
        expect(await subject.pickCopy(maxBytes: 0), isA<DocumentPickFailed>());
        final stale = copyOnDisk('pick-stale');

        await subject.sweep();

        expect(stale.existsSync(), isFalse);
      },
    );

    test('a pick that starts during a sweep keeps its copy', () async {
      final subject = picker();
      for (var i = 0; i < 50; i++) {
        copyOnDisk('pick-stale$i');
      }
      // Android makes its folder the moment it is called.
      late Directory folder;
      android((_) {
        folder = copyOnDisk('pick-late');
        return answerFor(folder);
      });

      final sweep = subject.sweep();
      final result = await subject.pickCopy(maxBytes: 1000);
      await sweep;

      expect(result, isA<DocumentPicked>());
      expect(folder.existsSync(), isTrue);
      expect(Directory('${root().path}/pick-stale0').existsSync(), isFalse);
    });
  });

  group('the provider', () {
    test(
      'builds one picker per app session, under the temporary folder',
      () async {
        final container = ProviderContainer(
          overrides: [appTempDirProvider.overrideWith((ref) async => temp)],
        );
        addTearDown(container.dispose);

        final first = await container.read(documentPickerProvider.future);
        // Let auto-dispose run, if the provider were auto-disposed.
        await Future<void>.delayed(Duration.zero);
        final second = await container.read(documentPickerProvider.future);

        expect(first, isA<ChannelDocumentPicker>());
        // One object: it has to remember what is in use.
        expect(identical(first, second), isTrue);

        // And it accepts a copy under THIS temporary folder.
        final folder = copyOnDisk('pick-provider');
        android((_) => answerFor(folder));
        expect(await first.pickCopy(maxBytes: 1000), isA<DocumentPicked>());
      },
    );
  });
}
