/// CatalogueItem ingress-gate fitness function (ADR 0004, AGENTS §3.3).
///
/// `Book` was renamed `CatalogueItem` in 2026-10 (plan F7): the entity is the
/// base row of EVERY catalogue item kind, not only books. The gate is
/// unchanged.
///
/// Why a source-scanning test exists (beginner note): `CatalogueItem`
/// deliberately keeps a PLAIN constructor for trusted data (the DB mapper,
/// `copyWith` on a persisted row) plus a static gate — `CatalogueItem.validate`
/// — that every INGRESS path (add/edit forms, JSON/CSV import, merge, backup
/// restore, wishlist move) must pass a row through BEFORE persistence. Dart
/// cannot force "call validate first" at the type level without churning
/// every construction site, so the design is pinned here instead: ANY file
/// under `lib/` that CONSTRUCTS a `CatalogueItem(` must reference
/// `CatalogueItem.validate`, unless it is in the commented allow-list of
/// trusted constructors below. A future ingress path that forgets the gate
/// fails this test, not production.
///
/// Why the whole of `lib/` and not a hand-picked list of directories: a
/// scope list is itself something a future contributor must remember to
/// extend — the exact "human memory" failure this test exists to remove.
/// Scanning everything costs ~500 small file reads and cannot go stale.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Everything under `lib/` is scanned (see the file header for why no
  /// narrower scope list is used).
  const scanRoot = 'lib';

  /// Trusted constructors — files allowed to build a `CatalogueItem(` WITHOUT
  /// referencing the gate, each with its justification. Adding an entry is
  /// a deliberate, reviewed change (AGENTS.md footer).
  const trustedConstructors = <String, String>{
    // The entity itself: defines the plain constructor, copyWith, and the
    // gate; the gate cannot meaningfully reference itself.
    'lib/features/library/domain/entities/catalogue_item.dart':
        'the entity itself',
    // DB mapper: rows it reads were validated on WRITE by the use cases;
    // re-validating on every read would double the gate (and break nothing —
    // but the constructor is intentionally the trusted fast path, see
    // catalogue_item.dart's "plain constructor" doc).
    'lib/features/library/infrastructure/catalogue_item_mapper.dart':
        'DB mapper (rows validated on write)',
    // The add/edit form ASSEMBLES a CatalogueItem from its text fields and
    // hands it to AddCatalogueItemUseCase / UpdateCatalogueItemUseCase, which ARE the gate (both
    // call CatalogueItem.validate — pinned by the spot-check test below). The
    // widget may not validate itself (AGENTS §7: no business logic in
    // widgets), so the construction is trusted here and the gate is one hop
    // downstream.
    'lib/features/library/presentation/pages/add_book_page.dart':
        'form assembly; gate is Add/UpdateCatalogueItemUseCase',
    // ADR 0013 D1/D3: the add/edit-issue form assembles the row from its
    // fields (blank title — the projection composes it) and hands it to
    // AddIssueUseCase / UpdateIssueUseCase, which ARE the gate (the projected
    // row passes CatalogueItem.validate before any store access). Same
    // one-hop reasoning as the book form above.
    'lib/features/periodicals/presentation/pages/add_issue_page.dart':
        'form assembly; gate is Add/UpdateIssueUseCase',
    // ADR 0013 O3: the Others form assembles its row (details always the
    // field-less `OtherItemOf` marker) and hands it to the GENERIC
    // AddCatalogueItemUseCase / UpdateCatalogueItemUseCase — the same gate
    // the book form uses, one hop downstream.
    'lib/features/library/presentation/pages/other_item_form_page.dart':
        'form assembly; gate is Add/UpdateCatalogueItemUseCase',
    // ADR 0013 D3: rebuilds an issue row from an already-validated row and
    // a validated periodical (a pure field copy — `copyWith` cannot null a
    // field, so the row is rebuilt). The issue use cases validate the
    // projected row before persisting, so the gate is one hop downstream.
    'lib/features/periodicals/domain/issue_projection.dart':
        'series → issue projection; gate is the issue use cases',
    // ADR 0013 W1/D8 (plan S19): the merge planner's orphan rule — an
    // incoming issue no series claims degrades to a plain book (`copyWith`
    // cannot null `details`, so the base row is rebuilt field by field).
    // The row was validated at parse time and the merge apply writes through
    // the repository, whose write path is gated downstream.
    'lib/features/library/domain/merge/periodical_merge.dart':
        'merge orphan rule (W1 twin); rows validated at parse, gated on write',
  };

  /// Matches a `CatalogueItem(` construction and NOT a longer identifier that
  /// merely ends in it: a non-letter must immediately precede `CatalogueItem(`.
  final constructsItem = RegExp(r'(?<![a-zA-Z])CatalogueItem\(');

  List<File> dartFiles(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (f) =>
            f.path.endsWith('.dart') &&
            !f.path.endsWith('.g.dart') &&
            !f.path.endsWith('.freezed.dart'),
      )
      .toList();

  test('every CatalogueItem-constructing file under lib/ passes through '
      'CatalogueItem.validate or is an explicitly trusted constructor', () {
    final offenders = <String>[];
    final constructing = <String>[];

    for (final file in dartFiles(scanRoot)) {
      final src = file.readAsStringSync();
      if (!constructsItem.hasMatch(src)) continue;
      constructing.add(file.path);
      if (trustedConstructors.containsKey(file.path)) continue;
      if (!src.contains('CatalogueItem.validate')) offenders.add(file.path);
    }

    // Sanity: the census must be non-trivial so a renamed regex or a moved
    // tree cannot silently make this test vacuously green. 13 = the sites
    // known at S19: 7 trusted (allow-list above — S19 added the merge
    // planner's orphan rule) + 6 gated ingress paths that reference the gate
    // themselves.
    expect(
      constructing,
      hasLength(greaterThanOrEqualTo(13)),
      reason:
          'expected the known CatalogueItem construction sites to be scanned',
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'these files construct a CatalogueItem without referencing '
          'CatalogueItem.validate — route them through the gate, or add them '
          'to trustedConstructors with a justification comment',
    );
  });

  test('every allow-list entry is a real, scanned, CatalogueItem-constructing '
      'file (no dead entries)', () {
    // A dead entry would let the "stays exactly as reviewed" test below pin
    // a path that is never consulted — the allow-list must stay honest.
    for (final path in trustedConstructors.keys) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path no longer exists');
      expect(
        constructsItem.hasMatch(file.readAsStringSync()),
        isTrue,
        reason:
            '$path no longer constructs a CatalogueItem — drop it from the '
            'list',
      );
    }
  });

  test('the known ingress gates are present (spot-check census)', () {
    const gated = [
      'lib/features/import_export/application/import_library_use_case.dart',
      // Moved here on 2026-10-24 (magazine remediation S4) when the per-row
      // resolution apply left the merge use case for its own file.
      'lib/features/import_export/application/merge_resolution_applier.dart',
      'lib/features/import_export/domain/goodreads_csv_importer.dart',
      'lib/features/import_export/infrastructure/pitaka_json_importer.dart',
      'lib/features/backup/infrastructure/legacy_db_reader.dart',
      'lib/features/library/application/add_catalogue_item_use_case.dart',
      'lib/features/library/application/update_catalogue_item_use_case.dart',
      'lib/features/wishlist/application/wishlist_use_cases.dart',
    ];
    for (final path in gated) {
      expect(
        File(path).readAsStringSync(),
        contains('CatalogueItem.validate'),
        reason: '$path is a known ingress and must keep calling the gate',
      );
    }
  });

  // ADR 0013: `Periodical` follows the same gate pattern
  // (`Periodical.validate`, AGENTS §3.3). Separate regex and allow-list so
  // the two censuses cannot mask each other; the reasoning for each trusted
  // site is the same as above.
  group('Periodical gate', () {
    const trustedPeriodicalConstructors = <String, String>{
      // The entity itself: plain constructor, copyWith and the gate.
      'lib/features/periodicals/domain/entities/periodical.dart':
          'the entity itself',
      // DB mapper: rows it reads were validated on WRITE by the use cases —
      // the same reasoning as the catalogue item mapper above.
      'lib/features/periodicals/infrastructure/periodical_mapper.dart':
          'DB mapper (rows validated on write)',
      // The add/edit-series form assembles the entity from its fields and
      // hands it to AddPeriodicalUseCase / UpdatePeriodicalUseCase, which ARE
      // the gate (PeriodicalIngress.prepare = Periodical.validate + the ISSN
      // pre-check). Same one-hop reasoning as the book form.
      'lib/features/periodicals/presentation/pages/periodical_form_page.dart':
          'form assembly; gate is Add/UpdatePeriodicalUseCase',
    };
    final constructsPeriodical = RegExp(r'(?<![a-zA-Z])Periodical\(');

    test('every Periodical-constructing file under lib/ passes through '
        'Periodical.validate or is an explicitly trusted constructor', () {
      final offenders = <String>[];
      final constructing = <String>[];
      for (final file in dartFiles(scanRoot)) {
        final src = file.readAsStringSync();
        if (!constructsPeriodical.hasMatch(src)) continue;
        constructing.add(file.path);
        if (trustedPeriodicalConstructors.containsKey(file.path)) continue;
        if (!src.contains('Periodical.validate')) offenders.add(file.path);
      }
      expect(
        constructing,
        hasLength(greaterThanOrEqualTo(1)),
        reason: 'expected at least the entity file to be scanned',
      );
      expect(
        offenders,
        isEmpty,
        reason:
            'these files construct a Periodical without referencing '
            'Periodical.validate — route them through the gate, or add them '
            'to trustedPeriodicalConstructors with a justification comment',
      );
    });

    test('every allow-list entry is a real, scanned, Periodical-constructing '
        'file (no dead entries)', () {
      for (final path in trustedPeriodicalConstructors.keys) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path no longer exists');
        expect(
          constructsPeriodical.hasMatch(file.readAsStringSync()),
          isTrue,
          reason: '$path no longer constructs a Periodical — drop it',
        );
      }
    });

    test('the allow-list stays exactly as reviewed (no silent growth)', () {
      expect(
        trustedPeriodicalConstructors.keys,
        unorderedEquals([
          'lib/features/periodicals/domain/entities/periodical.dart',
          'lib/features/periodicals/infrastructure/periodical_mapper.dart',
          'lib/features/periodicals/presentation/pages/periodical_form_page.dart',
        ]),
      );
    });
  });

  test('the allow-list stays exactly as reviewed (no silent growth)', () {
    // If you ADD an entry here, the PR must say why the constructor is
    // trusted (AGENTS.md footer: deliberate, reviewed changes only).
    expect(
      trustedConstructors.keys,
      unorderedEquals([
        'lib/features/library/domain/entities/catalogue_item.dart',
        'lib/features/library/domain/merge/periodical_merge.dart',
        'lib/features/library/infrastructure/catalogue_item_mapper.dart',
        'lib/features/library/presentation/pages/add_book_page.dart',
        'lib/features/library/presentation/pages/other_item_form_page.dart',
        'lib/features/periodicals/domain/issue_projection.dart',
        'lib/features/periodicals/presentation/pages/add_issue_page.dart',
      ]),
    );
  });
}
