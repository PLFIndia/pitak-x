/// Book ingress-gate fitness function (SOLID-PLAN S7, AGENTS §3.3).
///
/// Why a source-scanning test exists (beginner note): `Book` deliberately
/// keeps a PLAIN constructor for trusted data (the DB mapper, `copyWith` on
/// a persisted row) plus a static gate — `Book.validate` — that every
/// INGRESS path (add/edit forms, JSON/CSV import, merge, backup restore,
/// wishlist move) must pass a row through BEFORE persistence. Dart cannot
/// force "call validate first" at the type level without churning every
/// construction site, so the design is pinned here instead: any scanned file
/// that CONSTRUCTS a `Book(` must reference `Book.validate`, unless it is in
/// the commented allow-list of trusted constructors below. A future ingress
/// path that forgets the gate fails this test, not production.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Directories whose sources are ingress-adjacent (SOLID-PLAN S7 scope):
  /// import/export, backup (restore + legacy reader), the library
  /// application layer, and the merge engine.
  const scanDirs = [
    'lib/features/import_export',
    'lib/features/backup',
    'lib/features/library/application',
    'lib/features/library/domain/merge',
  ];

  /// Single files scanned on top of [scanDirs].
  const scanFiles = [
    // The DB mapper constructs Books from stored rows — trusted, but
    // SCANNED so its allow-list entry below stays honest.
    'lib/features/library/infrastructure/book_mapper.dart',
    // Wishlist move-to-library constructs a library Book (S34/D2).
    'lib/features/wishlist/application/wishlist_use_cases.dart',
  ];

  /// Trusted constructors — files allowed to build a `Book(` WITHOUT
  /// referencing the gate, each with its justification. Adding an entry is
  /// a deliberate, reviewed change (AGENTS.md footer).
  const trustedConstructors = <String, String>{
    // The entity itself: defines the plain constructor, copyWith, and the
    // gate; the gate cannot meaningfully reference itself.
    'lib/features/library/domain/entities/book.dart': 'the entity itself',
    // DB mapper: rows it reads were validated on WRITE by the use cases;
    // re-validating on every read would double the gate (and break nothing —
    // but the constructor is intentionally the trusted fast path, see
    // book.dart's "plain constructor" doc).
    'lib/features/library/infrastructure/book_mapper.dart':
        'DB mapper (rows validated on write)',
  };

  /// Matches a `Book(` construction that is NOT a `WishlistBook(`,
  /// `BookMapper(`, etc. — a non-letter immediately before `Book(`.
  final constructsBook = RegExp(r'(?<![a-zA-Z])Book\(');

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

  test('every Book-constructing ingress file passes through Book.validate '
      'or is an explicitly trusted constructor', () {
    final offenders = <String>[];
    var constructing = 0;

    final files = <File>[
      for (final dir in scanDirs) ...dartFiles(dir),
      for (final path in scanFiles) File(path),
    ];

    for (final file in files) {
      final src = file.readAsStringSync();
      if (!constructsBook.hasMatch(src)) continue;
      constructing++;
      if (trustedConstructors.containsKey(file.path)) continue;
      if (!src.contains('Book.validate')) offenders.add(file.path);
    }

    // Sanity: the census must be non-trivial so a renamed regex or a moved
    // tree cannot silently make this test vacuously green.
    expect(
      constructing,
      greaterThanOrEqualTo(6),
      reason: 'expected the known Book construction sites to be scanned',
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'these files construct a Book without referencing '
          'Book.validate — route them through the gate, or add them to '
          'trustedConstructors with a justification comment',
    );
  });

  test('the known ingress gates are present (spot-check census)', () {
    const gated = [
      'lib/features/import_export/application/import_library_use_case.dart',
      'lib/features/import_export/application/merge_library_use_case.dart',
      'lib/features/import_export/domain/goodreads_csv_importer.dart',
      'lib/features/import_export/infrastructure/pitaka_json_importer.dart',
      'lib/features/backup/infrastructure/legacy_db_reader.dart',
      'lib/features/library/application/add_book_use_case.dart',
      'lib/features/library/application/update_book_use_case.dart',
      'lib/features/wishlist/application/wishlist_use_cases.dart',
    ];
    for (final path in gated) {
      expect(
        File(path).readAsStringSync(),
        contains('Book.validate'),
        reason: '$path is a known ingress and must keep calling the gate',
      );
    }
  });

  test('the allow-list stays exactly as reviewed (no silent growth)', () {
    // If you ADD an entry here, the PR must say why the constructor is
    // trusted (AGENTS.md footer: deliberate, reviewed changes only).
    expect(
      trustedConstructors.keys,
      unorderedEquals([
        'lib/features/library/domain/entities/book.dart',
        'lib/features/library/infrastructure/book_mapper.dart',
      ]),
    );
  });
}
