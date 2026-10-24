import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/database/app_database.dart';

import 'generated/schema.dart';
import 'generated/schema_v4.dart' as v4;

/// The v5 upgrade drops and rebuilds the FTS5 index so `notes` becomes
/// searchable (ADR 0013 D10). That rebuild is the only part of the migration
/// whose cost grows with the catalogue, and it runs once, on the first open
/// after the update, before the Library screen can paint. This test pins the
/// cost at a size well beyond a personal library (5 000 rows) with a bound
/// generous enough for a slow CI runner — a regression that made the rebuild
/// quadratic or per-row would blow through it; normal jitter will not.
void main() {
  const rows = 5000;
  const bound = Duration(seconds: 20);

  test('v4 → v5 with $rows rows rebuilds FTS within $bound', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(4);
    final oldDb = v4.DatabaseAtV4(schema.newConnection());
    await oldDb.batch((b) {
      for (var i = 0; i < rows; i++) {
        b.insert(
          oldDb.books,
          v4.BooksCompanion.insert(
            bookUid: Value('uid-$i'),
            title: 'Title number $i',
            author: Value('Author ${i % 97}'),
            notes: Value('note-word-$i for row $i'),
            addedDate: 1700000000000 + i,
          ),
        );
      }
    });
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);
    final clock = Stopwatch()..start();
    await verifier.migrateAndValidate(db, db.schemaVersion);
    clock.stop();
    expect(
      clock.elapsed,
      lessThan(bound),
      reason: 'migration + FTS rebuild took ${clock.elapsed}',
    );

    // The rebuilt index covers every pre-upgrade row, notes included.
    Future<int> hits(String word) async =>
        (await db
                .customSelect(
                  'SELECT rowid FROM books_fts WHERE books_fts MATCH ?',
                  variables: [Variable(word)],
                )
                .get())
            .length;
    expect(await hits('"note-word-4999"'), 1);
    expect(await hits('Title'), rows);
    final count = await db
        .customSelect('SELECT COUNT(*) AS n FROM books')
        .map((r) => r.read<int>('n'))
        .getSingle();
    expect(count, rows);
  });

  test('an explicit rebuildFts over $rows rows stays within $bound', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.batch((b) {
      for (var i = 0; i < rows; i++) {
        b.insert(
          db.books,
          BooksCompanion.insert(
            title: 'Title number $i',
            notes: Value('note-word-$i'),
            addedDate: 1700000000000 + i,
          ),
        );
      }
    });
    final clock = Stopwatch()..start();
    await db.rebuildFts();
    clock.stop();
    expect(
      clock.elapsed,
      lessThan(bound),
      reason: 'rebuild took ${clock.elapsed}',
    );
  });
}
