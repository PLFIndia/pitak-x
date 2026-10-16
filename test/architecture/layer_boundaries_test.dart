import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architecture fitness functions beyond domain purity (architecture.md B4)
/// plus the file-size ratchet (B8). Same style as
/// `domain_purity_test.dart`: dependency-free source scanning, so the rules
/// are enforced by `flutter test` with no extra tooling to supply-chain.
///
/// All five gates landed GREEN on 2026-10-16 (0 boundary violations; the one
/// bare catch already carries a justification comment). They exist to keep
/// it that way — a violation means a deliberate, reviewed change, not drift.
void main() {
  List<File> libFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (f) =>
            f.path.endsWith('.dart') &&
            !f.path.endsWith('.g.dart') &&
            !f.path.endsWith('.freezed.dart') &&
            // Generated flutter_rust_bridge bindings are not hand-maintained.
            !f.path.contains('lib/src/rust/'),
      )
      .toList();

  List<File> featureFiles(String layer) => libFiles()
      .where((f) => f.path.contains('/features/') && f.path.contains(layer))
      .toList();

  List<String> importLines(File file) => file
      .readAsLinesSync()
      .where((l) => l.trimLeft().startsWith('import '))
      .toList();

  test('presentation imports no infrastructure, drift, or core/database', () {
    // AGENTS §3.1: presentation talks to application/domain only; the
    // composition root (core/di) wires concrete infrastructure.
    final forbidden = RegExp(
      "import 'package:(pitaka/features/[^']+/infrastructure/|"
      'drift|'
      'pitaka/core/database)',
    );
    final violations = <String>[
      for (final file in featureFiles('/presentation/'))
        for (final line in importLines(file))
          if (forbidden.hasMatch(line)) '${file.path}: ${line.trim()}',
    ];
    expect(
      violations,
      isEmpty,
      reason:
          'presentation must not import infrastructure/drift/database '
          '(AGENTS §3.1). Violations:\n${violations.join('\n')}',
    );
  });

  test('application and core/di import no Flutter UI libraries', () {
    // State orchestration and DI wiring never touch widgets; UI-only code
    // lives in presentation (AGENTS §3.1).
    final uiImport = RegExp(
      r"^import 'package:flutter/(material|widgets|cupertino)\.dart'",
    );
    final targets = <File>[
      ...featureFiles('/application/'),
      ...libFiles().where((f) => f.path.contains('lib/core/di/')),
    ];
    final violations = <String>[
      for (final file in targets)
        for (final line in importLines(file))
          if (uiImport.hasMatch(line.trim())) '${file.path}: ${line.trim()}',
    ];
    expect(
      violations,
      isEmpty,
      reason:
          'application/core-di must not import Flutter UI libraries '
          '(AGENTS §3.1). Violations:\n${violations.join('\n')}',
    );
  });

  test('print/debugPrint appear only in lib/core/platform/app_log.dart', () {
    // B5: release logs reach logcat, so diagnostics exist only through the
    // debug-only `appLog` wrapper — and only there.
    final call = RegExp(r'\b(print|debugPrint)\(');
    final violations = <String>[];
    for (final file in libFiles()) {
      if (file.path.endsWith('lib/core/platform/app_log.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (call.hasMatch(lines[i])) {
          violations.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Use appLog() (lib/core/platform/app_log.dart), never '
          'print/debugPrint directly (architecture.md B5). Violations:\n'
          '${violations.join('\n')}',
    );
  });

  test('a bare catch must be followed within two lines by a // comment', () {
    // AGENTS §14: no silent swallowing. A bare `catch (_)` or `catch (e) {}`
    // is acceptable only with an adjacent comment explaining the fail-closed
    // reasoning (the single existing site: github_connection_controller.dart).
    final bareCatch = RegExp(r'catch \(_\)\s*\{|catch \(e\)\s*\{\s*\}');
    final violations = <String>[];
    for (final file in libFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!bareCatch.hasMatch(lines[i])) continue;
        final window = lines.skip(i + 1).take(2);
        final hasComment = window.any((l) => l.trimLeft().startsWith('//'));
        if (!hasComment) {
          violations.add('${file.path}:${i + 1}: uncommented bare catch');
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Bare catches need an adjacent justification comment '
          '(AGENTS §14). Violations:\n${violations.join('\n')}',
    );
  });

  group('file-size ratchet (B8)', () {
    // B8/D9: growth is a decision, not drift — mirrors the CI coverage-floor
    // pattern. Every non-generated file over 500 lines is listed here with
    // its recorded size (measured 2026-10-16). An allow-listed file may
    // SHRINK but never exceed its recorded size; when it drops under 500,
    // delete its entry. Adding a new entry is a deliberate, reviewed change —
    // same bar as the Book.validate allow-list.
    const allowList = <String, int>{
      'lib/features/vault/application/vault_session_controller.dart': 836,
      'lib/features/library/domain/merge/library_merge_engine.dart': 721,
      'lib/features/settings/presentation/pages/settings_page.dart': 682,
      'lib/features/library/presentation/pages/book_detail_page.dart': 676,
      'lib/features/publish/application/github_connection_controller.dart': 670,
      'lib/features/library/presentation/pages/add_book_page.dart': 638,
      'lib/features/import_export/infrastructure/pdf_library_renderer.dart':
          605,
      'lib/features/publish/infrastructure/http_github_api.dart': 600,
      'lib/features/library/infrastructure/drift_book_repository.dart': 597,
      'lib/features/backup/infrastructure/restore_backup.dart': 553,
      'lib/features/import_export/application/merge_library_use_case.dart': 543,
      'lib/features/import_export/presentation/pages/merge_page.dart': 538,
      'lib/features/import_export/domain/bounded_zip_extractor.dart': 521,
    };

    int lineCount(File f) => f.readAsLinesSync().length;

    test(
      'no non-generated file exceeds 500 lines without an allow-list entry',
      () {
        final violations = <String>[];
        for (final file in libFiles()) {
          final lines = lineCount(file);
          if (lines <= 500) continue;
          final allowed = allowList[file.path];
          if (allowed == null) {
            violations.add(
              '${file.path}: $lines lines (>500, no allow-list entry)',
            );
          }
        }
        expect(
          violations,
          isEmpty,
          reason:
              'A file over 500 lines is a deliberate, reviewed size '
              '(architecture.md B8). Split it, or add an allow-list entry in '
              'layer_boundaries_test.dart with the reasoning. Violations:\n'
              '${violations.join('\n')}',
        );
      },
    );

    test('allow-listed files may shrink but never grow past their record', () {
      final violations = <String>[];
      for (final entry in allowList.entries) {
        final file = File(entry.key);
        if (!file.existsSync()) {
          violations.add(
            '${entry.key}: listed but no longer exists — '
            'delete the entry',
          );
          continue;
        }
        final lines = lineCount(file);
        if (lines > entry.value) {
          violations.add(
            '${entry.key}: $lines lines exceeds recorded ${entry.value}',
          );
        } else if (lines <= 500) {
          violations.add(
            '${entry.key}: now $lines lines (≤500) — delete the entry',
          );
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'File-size ratchet: allowed files may only shrink '
            '(architecture.md B8/D9). Violations:\n${violations.join('\n')}',
      );
    });
  });
}
