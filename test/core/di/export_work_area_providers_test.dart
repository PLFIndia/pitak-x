import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/providers.dart';

/// The wiring of the export work area (review finding P4-M6): where the
/// file of one export lies while it is saved or shared, and the one-time
/// clean-up per app start.
void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pitaka_export_di_temp_');
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  ProviderContainer container() {
    final created = ProviderContainer(
      overrides: [appTempDirProvider.overrideWith((ref) async => temp)],
    );
    addTearDown(created.dispose);
    return created;
  }

  Directory staleRun() =>
      Directory(p.join(temp.path, 'export_work', 'run-stale'))
        ..createSync(recursive: true);

  Future<String> put(ProviderContainer c) async {
    final workArea = await c.read(exportWorkAreaProvider.future);
    return (await workArea.put(
      fileName: 'pitak-export-20261122.json',
      bytes: Uint8List.fromList([1, 2, 3]),
    )).getOrElse((f) => fail('$f'));
  }

  test('an export file lies under the temporary folder', () async {
    final path = await put(container());

    expect(p.isWithin(p.join(temp.path, 'export_work'), path), isTrue);
    expect(File(path).readAsBytesSync(), [1, 2, 3]);
  });

  test('the start-up sweep removes what a killed export left', () async {
    final stale = staleRun();
    File(p.join(stale.path, 'pitak-export-old.json')).writeAsBytesSync([1]);

    await container().read(staleExportWorkSweepProvider.future);

    expect(stale.existsSync(), isFalse);
  });

  test('the sweep runs once per app session', () async {
    final c = container();
    await c.read(staleExportWorkSweepProvider.future);
    // Something appears later in the same session.
    final later = staleRun();

    await c.read(staleExportWorkSweepProvider.future);

    expect(later.existsSync(), isTrue, reason: 'no second sweep this session');
  });

  test('the sweep leaves an export that is being saved or shared', () async {
    final c = container();
    final path = await put(c);

    await c.read(staleExportWorkSweepProvider.future);

    expect(File(path).existsSync(), isTrue);
  });

  test('one work area per app session: it has to remember what is in '
      'use', () async {
    final c = container();
    final first = await c.read(exportWorkAreaProvider.future);
    // Let auto-dispose run, if the provider were auto-disposed.
    await Future<void>.delayed(Duration.zero);
    final second = await c.read(exportWorkAreaProvider.future);

    expect(identical(first, second), isTrue);
  });
}
