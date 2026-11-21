import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `flutter_secure_storage` stays on major version 9 until a release of
/// Pitak on version 10 has reached its users (decision D67 of `PLAN.md`).
///
/// Why this gate exists: on Android, version 11 of the package cannot read
/// what version 9 stored. Its changelog says so under 11.0.0: "Any data
/// saved using deprecated algorithms or features will be unusable after
/// this upgrade. If you used a version prior to v10, upgrade to v10 first
/// so existing data is migrated." Pitak keeps its secrets there, with an
/// option version 11 removed (`core/security/hardened_secure_storage.dart`):
/// the publish tokens, the lookup key, the cover salt and the record for
/// fingerprint unlock. A jump from 9 straight to 11 would leave every user
/// without them, and nothing in the app would say why.
///
/// `.github/dependabot.yml` tells Dependabot not to propose the jump. That
/// stops one way only: a grouped update or a `flutter pub upgrade
/// --major-versions` by hand can still bring it. This test reads what is
/// actually locked, however it got there.
///
/// How to move on: plan the release on version 10 first (what it has to
/// decide is in the review, finding P2-M3). The change that makes that
/// release moves `pinnedMajor` to 10 on purpose; the one after it, once
/// users have opened a build on 10, removes this file and the Dependabot
/// entry.
///
/// Same style as the other architecture tests: plain reading of a file, no
/// extra tooling.
void main() {
  const package = 'flutter_secure_storage';
  const pinnedMajor = 9;

  // The version `pubspec.lock` holds for [name], or null when it holds no
  // such package. A package's block starts with its name at two spaces and
  // goes on for as long as the lines are indented deeper.
  String? lockedVersion(List<String> lockLines, String name) {
    final start = lockLines.indexOf('  $name:');
    if (start < 0) return null;
    final version = RegExp(r'^    version: "([^"]+)"$');
    for (final line in lockLines.skip(start + 1)) {
      if (!line.startsWith('    ')) return null;
      if (version.firstMatch(line) case final match?) return match.group(1);
    }
    return null;
  }

  int? majorOf(String version) => int.tryParse(version.split('.').first);

  test('pubspec.lock holds flutter_secure_storage on major version 9', () {
    final locked = lockedVersion(
      File('pubspec.lock').readAsLinesSync(),
      package,
    );

    // Fail closed: a lock file this test cannot read the version from is a
    // failure, not a pass.
    expect(
      locked,
      isNotNull,
      reason: 'no version of $package found in pubspec.lock',
    );
    expect(
      majorOf(locked!),
      pinnedMajor,
      reason:
          '$package is locked at $locked. It must stay on $pinnedMajor.x: '
          'version 11 cannot read what version 9 stored, so a release on '
          'version 10 has to reach users first. See the comment at the top '
          'of this file before changing the number.',
    );
  });

  group('the reader of the lock file', () {
    // The real file with one line changed, so that these tests fail with
    // the real test above if the layout of the lock file ever changes.
    List<String> lockWithVersion(String version) {
      final lines = File('pubspec.lock').readAsLinesSync();
      final start = lines.indexOf('  $package:');
      final at = lines.indexWhere(
        (line) => line.startsWith('    version: '),
        start,
      );
      return [...lines]..[at] = '    version: "$version"';
    }

    test('sees a jump to version 10 or 11 in a lock file', () {
      expect(majorOf(lockedVersion(lockWithVersion('10.3.1'), package)!), 10);
      expect(majorOf(lockedVersion(lockWithVersion('11.2.0'), package)!), 11);
    });

    test('reads the package itself, not one of its platform parts', () {
      // `flutter_secure_storage_linux` and its kind have versions of
      // their own (1.x to 3.x today) and follow in the lock file.
      final lines = [
        '  flutter_secure_storage:',
        '    dependency: "direct main"',
        '    version: "9.2.4"',
        '  flutter_secure_storage_linux:',
        '    dependency: transitive',
        '    version: "1.2.3"',
      ];

      expect(lockedVersion(lines, package), '9.2.4');
      expect(lockedVersion(lines.sublist(3), package), isNull);
    });

    test('gives no version when the package block has none', () {
      final lines = [
        '  flutter_secure_storage:',
        '    dependency: "direct main"',
        '  flutter_secure_storage_linux:',
        '    version: "1.2.3"',
      ];

      expect(lockedVersion(lines, package), isNull);
    });
  });
}
