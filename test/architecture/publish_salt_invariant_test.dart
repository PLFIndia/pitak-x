import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// INVARIANT (ADR 0019 Decision 3): a public item key means something only
/// while the cover salt and the internal ids stay the same, so any flow that
/// replaces the salt must clear `catalogueKeyed` in both publish records.
///
/// Why a source scan (beginner note): today the salt is never replaced — it
/// is generated once, on first use, when none exists, and then only read
/// (`SecureStorageCoverSaltStore`; Android backup is off and secure storage
/// throws instead of silently resetting). So "every salt replacement clears
/// the flag" holds because there is no replacement. This test keeps it that
/// way: the moment new code writes or deletes the salt — for example the
/// backup restore of plan S11 (CV6/CV7) — it fails, and whoever changes it
/// must make that flow clear `catalogueKeyed` and then update this test.
/// Same technique as the plan's cover-file invariant (CV1).
void main() {
  const saltStorePath =
      'lib/features/publish/infrastructure/secure_storage_cover_salt_store.dart';
  const saltKey = 'publish_cover_salt_v1';

  List<File> libFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (file) =>
            file.path.endsWith('.dart') &&
            !file.path.endsWith('.g.dart') &&
            !file.path.endsWith('.freezed.dart'),
      )
      .toList();

  String path(File file) => file.path.replaceAll(Platform.pathSeparator, '/');

  test('only the secure-storage salt store knows the salt storage key', () {
    final offenders = [
      for (final file in libFiles())
        if (path(file) != saltStorePath &&
            file.readAsStringSync().contains(saltKey))
          path(file),
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'The cover salt is written only by first-use generation. A new '
          'reader or writer of its storage key must keep ADR 0019 Decision '
          '3: a flow that replaces the salt clears catalogueKeyed in both '
          'publish records.',
    );
  });

  test('the salt store writes only on first use and never deletes', () {
    final source = File(saltStorePath).readAsStringSync();

    expect(
      '.write('.allMatches(source).length,
      1,
      reason: 'exactly one write: the first-use generation',
    );
    expect(source, isNot(contains('.delete(')));
    expect(source, isNot(contains('.deleteAll(')));
    // The one write sits after the "a salt already exists" early return, so
    // an existing salt is never overwritten.
    final existingReturn = source.indexOf('return base64Decode(existing)');
    final write = source.indexOf('.write(');
    expect(existingReturn, greaterThan(0));
    expect(write, greaterThan(existingReturn));
  });

  test('no other production class implements the salt store port', () {
    final implementer = RegExp(r'implements\s+PublishCoverSaltStore\b');
    final implementations = [
      for (final file in libFiles())
        if (implementer.hasMatch(file.readAsStringSync())) path(file),
    ]..sort();
    expect(implementations, [
      // The dev-only memory harness: a fixed in-memory salt, never stored,
      // never reachable from the shipping entry point
      // (shipping_entry_point_test.dart).
      'lib/dev/cloudflare_memory_scenario.dart',
      saltStorePath,
    ]);
  });
}
