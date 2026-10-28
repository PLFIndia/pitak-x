import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architecture fitness functions beyond domain purity (docs/ARCHITECTURE.md §2.1)
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

  test('application imports no infrastructure', () {
    // AGENTS §3.1: application depends on domain only — never on concrete
    // repositories/data sources. Wiring happens in the composition root
    // (core/di), which is the one place allowed to see both.
    final forbidden = RegExp(
      "^import 'package:pitaka/features/[^']+/infrastructure/",
    );
    final violations = <String>[
      for (final file in featureFiles('/application/'))
        for (final line in importLines(file))
          if (forbidden.hasMatch(line.trim())) '${file.path}: ${line.trim()}',
    ];
    expect(
      violations,
      isEmpty,
      reason:
          'application must not import infrastructure (AGENTS §3.1). '
          'Violations:\n${violations.join('\n')}',
    );
  });

  test('application and core/di import no Flutter UI libraries', () {
    // State orchestration and DI wiring never touch widgets; UI-only code
    // lives in presentation (AGENTS §3.1). flutter_map is on the list too
    // (review M4): its TileLayer/NetworkTileProvider own an HTTP-client
    // lifecycle, so they may only be constructed in presentation, per mount —
    // never cached in a DI or application provider.
    final uiImport = RegExp(
      r"^import 'package:(flutter/(material|widgets|cupertino)\.dart|"
      "flutter_map/)'",
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
          'application/core-di must not import Flutter UI libraries or '
          'flutter_map (AGENTS §3.1, review M4). Violations:\n'
          '${violations.join('\n')}',
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
          'print/debugPrint directly (logging policy: nothing in release builds). Violations:\n'
          '${violations.join('\n')}',
    );
  });

  test('a bare catch must carry a // comment on its line or the next two', () {
    // AGENTS §14: no silent swallowing. Two shapes count as "bare":
    //  (a) the error is discarded — `catch (_)`, `catch (_, __)`, …;
    //  (b) the body is empty — `catch (e) {}` or `catch (e) {` + `}`.
    // Either is acceptable only with an adjacent comment explaining the
    // fail-closed reasoning (the single existing site:
    // github_connection_controller.dart).
    final discardsError = RegExp(r'catch \(_(, _+)?\)\s*\{');
    final emptyOneLiner = RegExp(r'catch \([^)]*\)\s*\{\s*\}');
    final opensBlock = RegExp(r'catch \([^)]*\)\s*\{\s*$');
    bool isComment(String l) => l.trimLeft().startsWith('//');
    final violations = <String>[];
    for (final file in libFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final next = i + 1 < lines.length ? lines[i + 1] : '';
        final emptyMultiLine = opensBlock.hasMatch(line) && next.trim() == '}';
        final bare =
            discardsError.hasMatch(line) ||
            emptyOneLiner.hasMatch(line) ||
            emptyMultiLine;
        if (!bare) continue;
        final sameLineComment = line.contains('//');
        final window = lines.skip(i + 1).take(2);
        if (!sameLineComment && !window.any(isComment)) {
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
    // same bar as the CatalogueItem.validate allow-list.
    const allowList = <String, int>{
      'lib/features/vault/application/vault_session_controller.dart': 836,
      // library_merge_engine.dart left this list on 2026-10-23 (plan S19):
      // the fuzzy index moved to fuzzy_index.dart and the field specs to
      // merge_fields.dart (721 → <500). merge_page.dart left it the same day:
      // the review cards moved to widgets/merge_review_section.dart when the
      // periodical counts landed (538 → <500).
      // 2026-10 (plan F7 rename sessions): `CatalogueItem`,
      // `CatalogueItemRepository` etc. are longer identifiers, so dart format
      // wrapped signatures and the 80-column lint forced doc-comment reflows:
      // add_book_page +2, merge_library_use_case +2. No logic was added.
      // catalogue_item_detail_page left this list on 2026-10-23 (plan S14):
      // its actions moved to widgets/catalogue_item_actions.dart (681 → <500).
      // add_book_page shrank on 2026-10-23 (plan S16): the Session-33
      // language field moved to widgets/language_field.dart (640 → 526) so
      // the periodical form could share it.
      'lib/features/library/presentation/pages/add_book_page.dart': 526,
      'lib/features/import_export/infrastructure/pdf_library_renderer.dart':
          605,
      'lib/features/publish/infrastructure/http_github_api.dart': 600,
      // drift_catalogue_item_repository.dart left this list on 2026-10-22 (plan
      // S8): its SQL helpers moved to drift_catalogue_sql.dart (599 → <500).
      // restore_backup.dart left this list on 2026-10-23 (plan S21): the W2
      // kinds/details apply moved to restore_item_details.dart and the legacy
      // DB read phase to restore_legacy_read.dart (553 → <500).
      // merge_library_use_case.dart left this list on 2026-10-24 (magazine
      // remediation S4): the per-row resolution apply moved to
      // merge_resolution_applier.dart (516 → <500).
      'lib/features/import_export/domain/bounded_zip_extractor.dart': 521,
      // setup_cloudflare_site.dart entered on 2026-10-28 (S9): the pending-move
      // target guard is shared, but its two activation checks still belong
      // beside the setup transitions. Splitting the orchestrator would expose
      // a partial setup API; the file stays a reviewed 509-line size.
      'lib/features/publish/application/cloudflare/setup_cloudflare_site.dart':
          509,
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
              '(file-size ratchet, docs/ARCHITECTURE.md §2.1). Split it, or add an allow-list entry in '
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
            '(file-size ratchet, docs/ARCHITECTURE.md §2.1). Violations:\n${violations.join('\n')}',
      );
    });
  });
}
