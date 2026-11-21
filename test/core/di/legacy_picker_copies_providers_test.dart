import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/storage/legacy_picker_copies.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Decision D33, the wiring: the clean-up of the old file picker's copies
/// runs on Android only, in the app's temporary folder, and ONCE: a flag in
/// the preferences is set when nothing is left. (Which folders count as a
/// copy is tested in `legacy_picker_copies_test.dart`.)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A folder name of the kind the plugin made (a version 3 UUID).
  const copyName = 'd41d8cd9-8f00-3204-a980-0998ecf8427e';

  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pitaka_legacy_copies_di_');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  /// A container over the test's own folder. [android] plays the answer to
  /// "does the app really run on Android"; null leaves the real answer.
  ProviderContainer container({bool? android = true}) {
    final created = ProviderContainer(
      overrides: [
        appTempDirProvider.overrideWith((ref) async => temp),
        if (android != null) runsOnAndroidProvider.overrideWithValue(android),
      ],
    );
    addTearDown(created.dispose);
    return created;
  }

  /// A copy the way the plugin left one.
  Directory leftCopy([String name = copyName]) {
    final folder = Directory(p.join(temp.path, name))..createSync();
    File(p.join(folder.path, 'Pitak-backup.pitabak')).writeAsBytesSync([1, 2]);
    return folder;
  }

  Future<Object?> flag() async => (await SharedPreferences.getInstance()).get(
    LegacyPickerCopies.removedFlagKey,
  );

  test('on Android the copies are removed and the flag is set', () async {
    final copy = leftCopy();
    // Something of another plugin, next to it, stays.
    final other = Directory(
      p.join(temp.path, '6f1c3b2a-9d4e-4a7b-8c1d-0123456789ab'),
    )..createSync();

    await container().read(legacyPickerCopiesSweepProvider.future);

    expect(copy.existsSync(), isFalse);
    expect(other.existsSync(), isTrue);
    expect(await flag(), isTrue);
  });

  test('with nothing to remove the flag is set all the same: it is '
      'done', () async {
    await container().read(legacyPickerCopiesSweepProvider.future);
    expect(await flag(), isTrue);
  });

  test('once the flag is set, a later app start looks at nothing', () async {
    SharedPreferences.setMockInitialValues({
      LegacyPickerCopies.removedFlagKey: true,
    });
    // Whatever made this folder after the clean-up, it is not ours.
    final later = leftCopy();

    await container().read(legacyPickerCopiesSweepProvider.future);

    expect(later.existsSync(), isTrue);
  });

  test('where the app does not run on Android nothing is looked at and no '
      'flag is set', () async {
    final copy = leftCopy();

    await container(
      android: false,
    ).read(legacyPickerCopiesSweepProvider.future);

    expect(copy.existsSync(), isTrue);
    expect(await flag(), isNull);
  });

  test('"on Android" is the REAL system, not the one a test pretends to '
      'be', () async {
    // flutter_test reports `defaultTargetPlatform` as Android on every
    // machine. The clean-up must not believe that: on the machine these
    // tests run on, nothing may be deleted by the shape of its name.
    expect(Platform.isAndroid, isFalse, reason: 'tests run on a computer');
    final c = container(android: null);
    expect(c.read(runsOnAndroidProvider), Platform.isAndroid);

    final copy = leftCopy();
    await c.read(legacyPickerCopiesSweepProvider.future);
    expect(copy.existsSync(), isTrue);
  });

  test('a copy that could not be removed: no flag, and the next app start '
      'tries again', () async {
    final stuck = leftCopy();
    Process.runSync('chmod', ['500', stuck.path]);
    addTearDown(() => Process.runSync('chmod', ['700', stuck.path]));
    var writable = true;
    try {
      File(p.join(stuck.path, 'probe')).writeAsBytesSync([1]);
    } on FileSystemException {
      writable = false;
    }
    if (writable) {
      // An administrator account may write anywhere, and Windows has no
      // `chmod`: the case cannot be made there.
      markTestSkipped('this account can write into a read-only folder');
      return;
    }

    await container().read(legacyPickerCopiesSweepProvider.future);
    expect(stuck.existsSync(), isTrue);
    expect(await flag(), isNull);

    // The next app start (a new container) finds the folder deletable.
    Process.runSync('chmod', ['700', stuck.path]);
    await container().read(legacyPickerCopiesSweepProvider.future);
    expect(stuck.existsSync(), isFalse);
    expect(await flag(), isTrue);
  });
}
