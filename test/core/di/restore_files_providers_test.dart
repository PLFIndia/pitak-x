import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/document_picker.dart';

import '../../support/fake_document_picker.dart';

/// The wiring of a restore's temporary files (backup rework BR6): where a
/// restore stages its databases, and the one-time clean-up per app start
/// of what a killed restore left behind: the private copy of a chosen
/// backup file, and the databases unpacked from it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.khoj.pitaka/picked_document');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory temp;
  late Directory docs;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pitaka_restore_di_temp_');
    docs = Directory.systemTemp.createTempSync('pitaka_restore_di_docs_');
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    for (final dir in [temp, docs]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  ProviderContainer container({List<Override> extra = const []}) {
    final created = ProviderContainer(
      overrides: [
        appTempDirProvider.overrideWith((ref) async => temp),
        appDocsDirProvider.overrideWith((ref) async => docs),
        ...extra,
      ],
    );
    addTearDown(created.dispose);
    return created;
  }

  Directory staleRun() =>
      Directory(p.join(temp.path, 'restore_work', 'run-stale'))
        ..createSync(recursive: true);

  /// A picked copy the way the Android side leaves it.
  Directory pickedCopy(String folderName) {
    final folder = Directory(p.join(temp.path, 'picked_documents', folderName))
      ..createSync(recursive: true);
    File(p.join(folder.path, 'document')).writeAsBytesSync([1, 2, 3]);
    return folder;
  }

  Directory oldDocumentsFolder() =>
      Directory(p.join(docs.path, 'restore_work'))..createSync(recursive: true);

  test('a restore stages its files under the temporary folder, never under '
      'Documents', () async {
    final folders = await container().read(restoreWorkFoldersProvider.future);

    final run = await folders.create();

    expect(run, isNotNull);
    expect(p.isWithin(p.join(temp.path, 'restore_work'), run!), isTrue);
    expect(p.basename(run), startsWith('run-'));
    expect(docs.listSync(), isEmpty);
  });

  test('one keeper of the work folders per app session: it has to remember '
      'what is in use', () async {
    final c = container();
    final first = await c.read(restoreWorkFoldersProvider.future);
    // Let auto-dispose run, if the provider were auto-disposed.
    await Future<void>.delayed(Duration.zero);
    final second = await c.read(restoreWorkFoldersProvider.future);

    expect(identical(first, second), isTrue);
  });

  test('the start-up sweep removes a stale picked copy, a stale run and '
      'the work folder older versions left under Documents', () async {
    final copy = pickedCopy('pick-stale');
    final run = staleRun();
    File(p.join(run.path, 'books.db')).writeAsBytesSync([1]);
    final old = oldDocumentsFolder();
    File(p.join(old.path, 'borrowers.db')).writeAsBytesSync([1]);
    // Things that are not ours, next to them, stay.
    final foreign = File(p.join(temp.path, 'restore_work', 'notes.txt'))
      ..writeAsBytesSync([7]);

    await container().read(staleRestoreFilesSweepProvider.future);

    expect(copy.existsSync(), isFalse);
    expect(run.existsSync(), isFalse);
    expect(old.existsSync(), isFalse);
    expect(foreign.existsSync(), isTrue);
    expect(docs.existsSync(), isTrue);
  });

  test('the sweep leaves the files of a restore that is running', () async {
    final c = container();
    final folders = await c.read(restoreWorkFoldersProvider.future);
    final run = (await folders.create())!;
    final staged = File(p.join(run, 'books.db'))..writeAsBytesSync([1, 2, 3]);
    // The copy that restore reads: picked through the app's picker, so the
    // picker knows it is in use.
    final copy = pickedCopy('pick-inuse');
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {
        'path': p.join(copy.path, 'document'),
        'name': 'backup.pitabak',
        'size': 3,
      },
    );
    final picker = await c.read(documentPickerProvider.future);
    expect(await picker.pickCopy(maxBytes: 1000), isA<DocumentPicked>());

    await c.read(staleRestoreFilesSweepProvider.future);

    expect(staged.existsSync(), isTrue);
    expect(File(p.join(copy.path, 'document')).existsSync(), isTrue);
  });

  test('the sweep runs once per app session', () async {
    final picker = FakeDocumentPicker(Directory(p.join(temp.path, 'fake')));
    final c = container(
      extra: [documentPickerProvider.overrideWith((ref) async => picker)],
    );
    await c.read(staleRestoreFilesSweepProvider.future);
    // Something appears later in the same session.
    final later = staleRun();

    await Future<void>.delayed(Duration.zero);
    await c.read(staleRestoreFilesSweepProvider.future);

    expect(picker.sweeps, 1);
    expect(later.existsSync(), isTrue, reason: 'no second sweep this session');
  });

  test('a restore sweeps what an earlier one left before it makes its own '
      'folder', () async {
    final stale = staleRun();
    final folders = await container().read(restoreWorkFoldersProvider.future);

    final run = await folders.create(sweepFirst: true);

    expect(stale.existsSync(), isFalse);
    expect(Directory(run!).existsSync(), isTrue);
  });
}
