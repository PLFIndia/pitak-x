import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architecture boundary gate (AGENTS.md §3.1): the domain layer is pure
/// Dart. It must never import Flutter, Riverpod, or IO/plugin packages —
/// approach borrowed from the "import lint" checks common in Clean
/// Architecture repos (e.g. very_good_cli templates enforce the same rule
/// with dart_code_metrics; this is the dependency-free equivalent).
void main() {
  test('domain files import no Flutter/Riverpod/IO packages', () {
    final domainFiles = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.contains('/domain/') &&
              f.path.endsWith('.dart') &&
              !f.path.endsWith('.g.dart') &&
              !f.path.endsWith('.freezed.dart'),
        );

    const forbidden = [
      "import 'package:flutter/",
      "import 'package:flutter_riverpod/",
      "import 'package:riverpod_annotation/",
      "import 'package:hooks_riverpod/",
      "import 'dart:io'",
      "import 'dart:ui'",
      "import 'package:http/",
      "import 'package:drift/",
      "import 'package:shared_preferences/",
      "import 'package:flutter_secure_storage/",
    ];

    final violations = <String>[];
    for (final file in domainFiles) {
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
          'Domain must stay pure Dart (AGENTS.md §3.1). Violations:\n'
          '${violations.join('\n')}',
    );
  });

  test('application and presentation import no infrastructure', () {
    // §3.1: application depends on domain only; presentation on application
    // + domain. Concrete infrastructure is wired exclusively by the
    // composition root (core/di/providers.dart).
    final files = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              (f.path.contains('/application/') ||
                  f.path.contains('/presentation/')) &&
              f.path.endsWith('.dart') &&
              !f.path.endsWith('.g.dart') &&
              !f.path.endsWith('.freezed.dart'),
        );

    final infraImport = RegExp(
      "import 'package:pitaka/features/[^']*/infrastructure/",
    );

    final violations = <String>[];
    for (final file in files) {
      for (final line in file.readAsLinesSync()) {
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
}
