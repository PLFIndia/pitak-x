import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/platform/channel_document_saver.dart';
import 'package:pitaka/core/platform/document_saver.dart';
import 'package:pitaka/features/backup/infrastructure/file_backup_work_area.dart';
import 'package:pitaka/features/import_export/infrastructure/file_export_work_area.dart';

/// A file the app made leaves it in two ways only: through the one share
/// service, or through the app's OWN saver (review finding P4-M6;
/// decisions D168, D172 and D173).
///
/// Why this gate exists: saving a file where the user says is done by the
/// app's own Android code (`SavedDocumentChannel.kt`), behind the port
/// `core/platform/document_saver.dart`. The plugins that could do it were
/// read and not taken: they write paths to the device's log, pass on the
/// text of errors, and leave a broken file behind when a copy fails. These
/// tests keep them out, keep the share plugin in its one file, and hold the
/// two halves of the channel (Kotlin and Dart) to ONE text for every name
/// they must agree on. Until now such names agreed by comments only.
///
/// Same style as the other architecture tests: plain source scanning, no
/// extra tooling. This is the first of them that reads a Kotlin file.
void main() {
  const kotlinFolder = 'android/app/src/main/kotlin/dev/khoj/pitaka';

  List<File> dartFiles(String root) => Directory(root)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('the share plugin is imported by the one share service only', () {
    final import = RegExp(r'''^\s*import\s+['"]package:share_plus''');
    final importers = <String>{
      for (final root in ['lib', 'test', 'integration_test'])
        for (final file in dartFiles(root))
          if (file.readAsLinesSync().any(import.hasMatch)) file.path,
    };
    expect(
      importers,
      {'lib/core/platform/file_share.dart'},
      reason:
          'Share through FileShareService (core/platform/file_share.dart); '
          'save through DocumentSaver (core/platform/document_saver.dart).',
    );
  });

  group('a plugin that saves or picks files', () {
    // The packages that were read for the job, and the family of each.
    const plugins = [
      'file_picker',
      'flutter_file_dialog',
      'file_saver',
      'flutter_file_saver',
      'saf_stream',
    ];

    test('is imported by no file under lib/, test/ or integration_test/', () {
      final import = RegExp(
        '''^\\s*import\\s+['"]package:(${plugins.join('|')})\\w*/''',
      );
      final violations = <String>[
        for (final root in ['lib', 'test', 'integration_test'])
          for (final file in dartFiles(root))
            for (final line in file.readAsLinesSync())
              if (import.hasMatch(line)) '${file.path}: ${line.trim()}',
      ];
      expect(
        violations,
        isEmpty,
        reason:
            'Save a file through DocumentSaver (core/platform), which is '
            "the app's own code. Violations:\n${violations.join('\n')}",
      );
    });

    test('is not named by pubspec.yaml', () {
      final dependency = RegExp('^\\s+(${plugins.join('|')})\\w*\\s*:');
      final lines = File('pubspec.yaml').readAsLinesSync();
      expect(lines.where(dependency.hasMatch), isEmpty);

      // That this check can fail is shown HERE, on made-up lines, and not
      // by a trial on `pubspec.yaml` itself: a changed `pubspec.yaml`
      // makes the next `flutter test` ask pub.dev for packages.
      for (final plugin in plugins) {
        expect(dependency.hasMatch('  $plugin: ^1.0.0'), isTrue);
        expect(dependency.hasMatch('  ${plugin}_android: ^1.0.0'), isTrue);
      }
      expect(dependency.hasMatch('  share_plus: ^12.0.2'), isFalse);
      expect(dependency.hasMatch('  # file_saver: not taken'), isFalse);
    });
  });

  test('the export controller hands over a file, never bytes', () {
    // Decision D172: handing BYTES to the share service makes the share
    // plugin write them into a file of its own that nobody ever removes.
    // An export is put into ONE private file of the app's own instead, is
    // saved or shared by that file's path, and the file is removed when
    // the call returns.
    final controller = File(
      'lib/features/import_export/application/export_controller.dart',
    ).readAsStringSync();
    expect(controller, isNot(contains('shareBytes')));
    expect(controller, contains('.shareFile('));
    expect(controller, contains('.saveCopy('));
  });

  group('the two halves of the channel agree', () {
    final channel = File(
      '$kotlinFolder/SavedDocumentChannel.kt',
    ).readAsStringSync();
    final copyOut = File('$kotlinFolder/DocumentCopyOut.kt').readAsStringSync();
    final dartSaver = File(
      'lib/core/platform/channel_document_saver.dart',
    ).readAsStringSync();

    /// The text of `const val <name> = "<text>"` in a Kotlin source.
    String kotlinConst(String source, String name) {
      final found = RegExp(
        'const val $name(?:: \\w+)? = "([^"]*)"',
      ).allMatches(source).toList();
      expect(found, hasLength(1), reason: 'const val $name');
      return found.single.group(1)!;
    }

    /// The text of `static const String <name> = '<text>';` in a Dart source.
    String dartConst(String source, String name) {
      final found = RegExp(
        "static const String $name = '([^']*)';",
      ).allMatches(source).toList();
      expect(found, hasLength(1), reason: 'static const String $name');
      return found.single.group(1)!;
    }

    test('on the name of the channel and of its one method', () {
      expect(kotlinConst(channel, 'CHANNEL'), ChannelDocumentSaver.channelName);
      expect(
        kotlinConst(channel, 'METHOD_SAVE_COPY'),
        ChannelDocumentSaver.methodSaveCopy,
      );
    });

    test('on the argument and on the two fields of a success', () {
      expect(
        kotlinConst(channel, 'ARG_PATH'),
        dartConst(dartSaver, '_argumentPath'),
      );
      expect(
        kotlinConst(channel, 'KEY_NAME'),
        dartConst(dartSaver, '_keyName'),
      );
      expect(
        kotlinConst(channel, 'KEY_SIZE'),
        dartConst(dartSaver, '_keySize'),
      );
    });

    test('on the codes: Dart names every code a user can act on', () {
      final kotlinCodes = {
        for (final match in RegExp(
          r'const val CODE_\w+ = "([^"]*)"',
        ).allMatches(channel))
          match.group(1)!,
      };
      final dartCases = {
        for (final match in RegExp("case '([^']*)':").allMatches(dartSaver))
          match.group(1)!,
      };
      // The three that mean a mistake in code. Dart does not name them: it
      // turns them, and anything it does not know, into "failed".
      const mistakes = {'busy', 'invalid', 'failed'};

      expect(kotlinCodes, hasLength(10));
      expect(kotlinCodes.containsAll(mistakes), isTrue);
      expect(dartCases, kotlinCodes.difference(mistakes));
    });

    test('on the folder a backup is built in, and on the name of a run', () {
      expect(
        kotlinConst(copyOut, 'FOLDER_BACKUP'),
        FileBackupWorkArea.directoryName,
      );
      expect(
        '^${kotlinConst(copyOut, 'RUN_NAME')}\$',
        FileBackupWorkArea.runNamePattern.pattern,
      );
    });

    test('on the folder an export is put in, and on the name of its run', () {
      expect(
        kotlinConst(copyOut, 'FOLDER_EXPORT'),
        FileExportWorkArea.directoryName,
      );
      expect(
        '^${kotlinConst(copyOut, 'RUN_NAME')}\$',
        FileExportWorkArea.runNamePattern.pattern,
      );
    });

    test('on what a file that is saved may be called', () {
      expect(kotlinConst(copyOut, 'NAME_STEM'), savableFileNameStem);
      // The endings are the keys of Kotlin's table of types.
      final table = RegExp(
        r'val TYPES: Map<String, String> = mapOf\(([^)]*)\)',
      ).firstMatch(copyOut);
      expect(table, isNotNull, reason: 'the table TYPES in DocumentCopyOut.kt');
      final endings = [
        for (final match in RegExp(
          r'"(\w+)" to "[^"]+"',
        ).allMatches(table!.group(1)!))
          match.group(1)!,
      ];
      expect(endings, savableFileEndings);
    });
  });
}
