import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/channel_document_saver.dart';
import 'package:pitaka/core/platform/document_saver.dart';

/// Review finding P4-M6 (decisions D168, D171 and D176): the Dart side of
/// "save a copy of this file where the user says". Android is played by a
/// mock handler on the method channel; the file is real.
///
/// What these tests guard:
///  - Dart sends the path and nothing else, and only for a file that is
///    there and is named as a file that may be saved;
///  - every answer of the Android side maps to exactly one result, and a
///    missing Android side is "not available", never a second way (D171);
///  - a success is CHECKED: "saved" is said only when the size Android
///    counted is the length of the file that was sent. Anything else is
///    "left behind", because something lies at the place by then;
///  - the name the place gave is cleaned again, and no name reaches a log.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.khoj.pitaka/saved_document');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const saver = ChannelDocumentSaver();
  const backupName = 'pitak-backup-02Nov2026-134659.pitabak';

  late Directory temp;
  late Directory run;
  late File file;
  late List<MethodCall> calls;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pitaka_document_saver_');
    run = Directory('${temp.path}/backup_work/run-a')
      ..createSync(recursive: true);
    file = File('${run.path}/$backupName')
      ..writeAsBytesSync(List<int>.filled(700, 7));
    calls = <MethodCall>[];
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  /// Android answers every call with [answer] (a value, or it throws).
  void android(Object? Function(MethodCall call) answer) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return answer(call);
    });
  }

  /// What Android answers after a whole copy.
  Map<String, Object?> saved({Object? name = backupName, Object? size = 700}) =>
      {'name': name, 'size': size};

  /// Collects what would be written to the debug log during a test.
  List<String> debugLines() {
    final lines = <String>[];
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      lines.add(message ?? '');
    };
    addTearDown(() => debugPrint = previous);
    return lines;
  }

  group('the call', () {
    test('sends the path and nothing else', () async {
      android((_) => throw PlatformException(code: 'cancelled'));

      await saver.saveCopy(path: file.path);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'saveCopy');
      expect(calls.single.arguments, {'path': file.path});
    });

    test('a file that is not there is "source gone", and Android is never '
        'asked', () async {
      android((_) => saved());

      expect(
        await saver.saveCopy(path: '${run.path}/pitak-export-20261122.json'),
        isA<DocumentSaveSourceGone>(),
      );
      // A folder is not a file either.
      final folder = Directory('${run.path}/pitak-library-20261122.csv')
        ..createSync();
      expect(
        await saver.saveCopy(path: folder.path),
        isA<DocumentSaveSourceGone>(),
      );
      // Nor is a link, even one that points at a file that may be saved.
      final link = Link('${run.path}/pitak-20261122.pdf')
        ..createSync(file.path);
      expect(
        await saver.saveCopy(path: link.path),
        isA<DocumentSaveSourceGone>(),
      );
      expect(calls, isEmpty);
    });

    test('a name a saved file may not have never reaches Android', () async {
      android((_) => saved());
      final catalogue = File('${run.path}/library.db')..writeAsBytesSync([1]);

      expect(
        await saver.saveCopy(path: catalogue.path),
        isA<DocumentSaveFailed>(),
      );
      expect(calls, isEmpty);
    });

    test('no Android side is "not available" (D171)', () async {
      // No handler registered: what every platform but Android looks like.
      expect(
        await saver.saveCopy(path: file.path),
        isA<DocumentSaveUnavailable>(),
      );
    });

    test('each error code is exactly one answer', () async {
      final expected = <String, Matcher>{
        'cancelled': isA<DocumentSaveCancelled>(),
        'not_saved': isA<DocumentSaveNotSaved>(),
        'source': isA<DocumentSaveSourceGone>(),
        'left_behind': isA<DocumentSaveLeftBehind>(),
        'not_empty': isA<DocumentSaveNotEmpty>(),
        'unconfirmed': isA<DocumentSaveUnconfirmed>(),
        'unavailable': isA<DocumentSaveUnavailable>(),
        // Mistakes in code, and anything this side does not know.
        'busy': isA<DocumentSaveFailed>(),
        'invalid': isA<DocumentSaveFailed>(),
        'failed': isA<DocumentSaveFailed>(),
        'something_new': isA<DocumentSaveFailed>(),
        'CANCELLED': isA<DocumentSaveFailed>(),
        '': isA<DocumentSaveFailed>(),
        '/data/user/0/secret path': isA<DocumentSaveFailed>(),
      };
      for (final MapEntry(key: code, value: matcher) in expected.entries) {
        android((_) => throw PlatformException(code: code, message: 'x'));

        expect(
          await saver.saveCopy(path: file.path),
          matcher,
          reason: 'code "$code"',
        );
      }
    });
  });

  group('the debug log', () {
    test('gets a code of ours, never foreign text', () async {
      final lines = debugLines();

      for (final code in ['busy', '/data/user/0/secret path', backupName]) {
        android(
          (_) => throw PlatformException(code: code, message: 'secret text'),
        );
        await saver.saveCopy(path: file.path);
      }

      expect(lines, [
        'document_saver: save failed: busy',
        'document_saver: save failed: unknown code',
        'document_saver: save failed: unknown code',
      ]);
    });

    test('gets nothing for an answer a user can act on, and never a path or '
        'a name', () async {
      final lines = debugLines();

      for (final code in [
        'cancelled',
        'not_saved',
        'source',
        'left_behind',
        'not_empty',
        'unconfirmed',
        'unavailable',
      ]) {
        android((_) => throw PlatformException(code: code));
        await saver.saveCopy(path: file.path);
      }
      // A success, and a success that does not pass the check.
      android((_) => saved());
      await saver.saveCopy(path: file.path);
      android((_) => saved(size: 699));
      await saver.saveCopy(path: file.path);
      // A file that is not there, and a name that is not allowed.
      await saver.saveCopy(path: '${run.path}/pitak-export-20261122.json');
      File('${run.path}/library.db').writeAsBytesSync([1]);
      await saver.saveCopy(path: '${run.path}/library.db');

      expect(lines.join('\n'), isNot(contains(temp.path)));
      expect(lines.join('\n'), isNot(contains('pitak-')));
      expect(lines, [
        'document_saver: save failed: answer not as expected',
        'document_saver: save failed: file name not allowed',
      ]);
    });
  });

  group('a success', () {
    test('gives the name the place gave and the counted size', () async {
      // The place may give the file another name than the app proposed.
      const placeName = 'pitak-backup-02Nov2026-134659 (1).pitabak';
      android((_) => saved(name: placeName));

      final result = await saver.saveCopy(path: file.path);

      final document = (result as DocumentSaved).document;
      expect(document.displayName, placeName);
      expect(document.sizeBytes, 700);
    });

    test('the name is cleaned on the way in, and may be empty', () async {
      android((_) => saved(name: 'my\nbackup\u0000${'x' * 1000}'));
      final long = await saver.saveCopy(path: file.path);
      final name = (long as DocumentSaved).document.displayName;
      expect(name.length, 255);
      expect(name, startsWith('mybackupxxx'));

      android((_) => saved(name: ''));
      final unnamed = await saver.saveCopy(path: file.path);
      expect((unnamed as DocumentSaved).document.displayName, '');
    });

    test('is "left behind" when it is not the expected map', () async {
      final answers = <Object?>[
        null,
        'saved',
        7,
        <Object?>[backupName, 700],
        <String, Object?>{},
        {'name': backupName},
        {'size': 700},
        {'name': 7, 'size': 700},
        {'name': backupName, 'size': '700'},
        {'name': backupName, 'size': 700.0},
      ];
      for (final answer in answers) {
        android((_) => answer);

        expect(
          await saver.saveCopy(path: file.path),
          isA<DocumentSaveLeftBehind>(),
          reason: 'answer $answer',
        );
      }
    });

    test('is "left behind" when the size is not the length of the file that '
        'was sent', () async {
      for (final size in [699, 701, 0, -1]) {
        android((_) => saved(size: size));

        expect(
          await saver.saveCopy(path: file.path),
          isA<DocumentSaveLeftBehind>(),
          reason: 'size $size',
        );
      }
    });

    test('toString shows the size and never the name', () async {
      android((_) => saved(name: 'Meera-private.pitabak'));

      final result = await saver.saveCopy(path: file.path);
      final document = (result as DocumentSaved).document;

      expect(document.toString(), 'SavedDocument(700 bytes)');
    });
  });

  group('a name a file may be saved under', () {
    test('is plain letters, digits and hyphens with one of four endings', () {
      for (final name in [
        backupName,
        'pitak-export-20261122.json',
        'pitak-library-20261122.csv',
        'pitak-donated-ram-sharma-20261122.pdf',
        'A-9.csv',
        '${'a' * 120}.pdf',
      ]) {
        expect(isSavableFileName(name), isTrue, reason: name);
      }
      for (final name in [
        '',
        'library.db',
        'notes.txt',
        'backup',
        'pitak.PDF',
        'pitak.pdf.exe',
        'pitak.tar.pdf',
        'my backup.pitabak',
        'my_backup.pitabak',
        '.pdf',
        'pitak.pdfx',
        'pitak.pitabak ',
        'pitak.pitabak\n',
        '../pitak.pdf',
        'run-a/pitak.pdf',
        '\u092A\u093F\u091F\u0915.pdf',
        '${'a' * 121}.pdf',
      ]) {
        expect(isSavableFileName(name), isFalse, reason: name);
      }
    });
  });

  group('the provider', () {
    test('gives the saver that talks to Android', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(documentSaverProvider),
        isA<ChannelDocumentSaver>(),
      );
    });
  });
}
