import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architecture boundary gate (AGENTS.md §3.1), strengthened by review
/// finding N14 ("architecture and CI gates do not enforce several stated
/// guarantees").
///
/// The old gate was a DENYLIST of known-bad imports, which is exactly why a
/// `package:pdf` renderer and JSON codecs could live in `domain/` unnoticed:
/// anything not on the list slipped through. This version is an ALLOWLIST —
/// domain files may import only:
///
///  - pure `dart:` core libraries (never `dart:io` / `dart:isolate` /
///    `dart:ui` / `dart:ffi`);
///  - the explicitly-vetted pure third-party packages (`allowedPackages`
///    below);
///  - other domain code (or the pure cross-cutting core files listed in
///    `allowedCorePitaka` below).
///
/// Approach borrowed from Clean-Architecture "import lint" gates (e.g.
/// very_good_cli templates enforce the same rule with dart_code_metrics;
/// this is the dependency-free equivalent).
void main() {
  List<File> layerFiles(String pathFilter) => Directory('lib/features')
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (f) =>
            f.path.contains(pathFilter) &&
            f.path.endsWith('.dart') &&
            !f.path.endsWith('.g.dart') &&
            !f.path.endsWith('.freezed.dart'),
      )
      .toList();

  List<String> importsOf(File file) => file
      .readAsLinesSync()
      .where((l) => l.trimLeft().startsWith('import '))
      .toList();

  test('domain files import only pure Dart (allowlist, N14)', () {
    /// Pure `dart:` libraries allowed in domain. `dart:io`, `dart:isolate`,
    /// `dart:ui` and `dart:ffi` are the platform-facing ones and are NOT on
    /// this list.
    const allowedDart = {
      'dart:async',
      'dart:collection',
      'dart:convert',
      'dart:core',
      'dart:developer',
      'dart:math',
      'dart:typed_data',
    };

    /// Third-party packages verified PURE (no IO, no platform channels) and
    /// therefore acceptable in domain:
    ///  - `fpdart` — functional result types;
    ///  - `crypto` — hashing (the Git blob SHA-1 is domain protocol logic);
    ///  - `archive` — used by `bounded_zip_extractor`, whose decode LIMITS
    ///    (byte caps, entry counts) are the domain's defensive policy. M05
    ///    kept it here on purpose: the extractor uses the package's pure-Dart
    ///    `Inflate.stream` (not the `dart:io` native inflater) so the
    ///    budgeted decode stays platform-free. Since `archive` 4 the
    ///    package's main library ALSO exports `dart:io` classes, so "the
    ///    package is pure" is no longer true by itself: the next test
    ///    limits the domain to the five pure names it needs (ADR 0009,
    ///    amendment of 2026-11-10).
    /// Rendering engines (`pdf`), path contexts (`path`), plugins and
    /// frameworks are all forbidden here (N14).
    const allowedPackages = {'fpdart', 'crypto', 'archive'};

    /// pitaka imports allowed from domain: other features' domain layers and
    /// the few pure cross-cutting core files domain code actually needs
    /// (`core/text/` holds plain-Dart string helpers such as the file-name
    /// slug shared by the publish card and the export file names;
    /// `core/network/workers_dev_url.dart` is the shared, pure
    /// `<worker>.<subdomain>.workers.dev` grammar the reader's `BookmarkUrl`
    /// uses — it exists in core precisely so the network domain never has to
    /// import the publish feature, and it imports nothing but `dart:core`
    /// string logic).
    final allowedCorePitaka = RegExp(
      "^import 'package:pitaka/(features/[^']+/domain/|"
      'core/error/|'
      'core/text/|'
      r'core/crypto/secret_bytes\.dart|'
      r'core/network/workers_dev_url\.dart)',
    );

    final importUri = RegExp(r"^import\s+'([^']+)'");
    final violations = <String>[];
    for (final file in layerFiles('/domain/')) {
      for (final line in importsOf(file)) {
        final match = importUri.firstMatch(line.trim());
        if (match == null) continue; // relative imports stay inside the layer
        final uri = match.group(1)!;
        final ok = uri.startsWith('dart:')
            ? allowedDart.contains(uri)
            : uri.startsWith('package:pitaka/')
            ? allowedCorePitaka.hasMatch("import '$uri'")
            : uri.startsWith('package:') &&
                  allowedPackages.contains(
                    uri.substring('package:'.length).split('/').first,
                  );
        if (!ok) violations.add('${file.path}: $line');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Domain must stay pure Dart (AGENTS.md §3.1, N14 allowlist). '
          'Violations:\n${violations.join('\n')}',
    );
  });

  test('domain takes only the inflater and the CRC from package:archive', () {
    // ADR 0009, amendment of 2026-11-10 (backup rework BR2). The domain
    // reads the ZIP container itself (`zip_container.dart`); from the
    // package it may use the pure-Dart inflater with its in-memory streams
    // and the CRC function, nothing else. `archive` 4 exports file-backed
    // classes (`dart:io`) and a ZIP reader whose verdicts change between
    // versions from the same library, so the import must NAME what it
    // takes.
    const allowedNames = {
      'Inflate',
      'InputMemoryStream',
      'InputStream',
      'OutputMemoryStream',
      'getCrc32',
    };
    final archiveImport = RegExp(
      r"import\s+'package:archive/([^']*)'\s*([^;]*);",
    );
    final violations = <String>[];
    var imports = 0;
    for (final file in layerFiles('/domain/')) {
      for (final match in archiveImport.allMatches(file.readAsStringSync())) {
        imports++;
        final library = match.group(1)!;
        final rest = match.group(2)!.trim();
        if (library != 'archive.dart') {
          violations.add('${file.path}: imports package:archive/$library');
          continue;
        }
        if (!rest.startsWith('show ')) {
          violations.add('${file.path}: import without a show list');
          continue;
        }
        final names = rest
            .substring('show '.length)
            .split(',')
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty);
        for (final name in names) {
          if (!allowedNames.contains(name)) {
            violations.add('${file.path}: takes $name from package:archive');
          }
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Domain may take only $allowedNames from package:archive '
          '(ADR 0009). Violations:\n${violations.join('\n')}',
    );
    // The rule is about a real import: if the extractor stops importing
    // the package, drop `archive` from the allow-list above instead.
    expect(imports, 1, reason: 'expected exactly one domain import');
  });

  test('application and presentation import no infrastructure', () {
    // §3.1: application depends on domain only; presentation on application
    // + domain. Concrete infrastructure is wired exclusively by the
    // composition root (core/di/providers.dart).
    final infraImport = RegExp(
      "import 'package:pitaka/features/[^']*/infrastructure/",
    );

    final violations = <String>[];
    for (final file in layerFiles('/application/')) {
      for (final line in importsOf(file)) {
        if (infraImport.hasMatch(line)) {
          violations.add('${file.path}: ${line.trim()}');
        }
      }
    }
    for (final file in layerFiles('/presentation/')) {
      for (final line in importsOf(file)) {
        if (infraImport.hasMatch(line)) {
          violations.add('${file.path}: ${line.trim()}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Application/presentation must not import infrastructure '
          '(AGENTS.md §3.1); inject via core/di providers. Violations:\n'
          '${violations.join('\n')}',
    );
  });

  test('application files perform no platform IO (N14)', () {
    // The publish controller used to read cover files with dart:io itself.
    // Application code orchestrates; IO crosses a port injected from the
    // composition root.
    const forbidden = [
      "import 'dart:io'",
      "import 'dart:isolate'",
      "import 'package:path/",
      "import 'package:http/",
      "import 'package:drift/",
      "import 'package:shared_preferences/",
      "import 'package:flutter_secure_storage/",
    ];

    final violations = <String>[];
    for (final file in layerFiles('/application/')) {
      final content = file.readAsStringSync();
      for (final pattern in forbidden) {
        if (content.contains(pattern)) {
          violations.add('${file.path}: $pattern');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Application must stay free of platform IO/plugins (N14); inject '
          'ports instead. Violations:\n${violations.join('\n')}',
    );
  });
}
