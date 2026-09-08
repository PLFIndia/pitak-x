import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architecture boundary gate (AGENTS.md §3.1), strengthened by N14
/// (astra-review.md).
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
    ///  - `archive` — pure-Dart zip codec used by `bounded_zip_extractor`,
    ///    whose decode LIMITS (byte caps, entry counts) are the domain's
    ///    defensive policy. M05 kept it here on purpose: the extractor uses
    ///    the package's pure-Dart `Inflate.stream` (not the `dart:io` native
    ///    inflater) so the budgeted decode stays platform-free.
    /// Rendering engines (`pdf`), path contexts (`path`), plugins and
    /// frameworks are all forbidden here (N14).
    const allowedPackages = {'fpdart', 'crypto', 'archive'};

    /// pitaka imports allowed from domain: other features' domain layers and
    /// the two pure cross-cutting core files domain code actually needs.
    final allowedCorePitaka = RegExp(
      "^import 'package:pitaka/(features/[^']+/domain/|"
      'core/error/|'
      r'core/crypto/secret_bytes\.dart)',
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
