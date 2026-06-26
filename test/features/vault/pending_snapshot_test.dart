import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/pending_snapshot.dart';

void main() {
  const day = 1000 * 60 * 60 * 24;
  const now = 100 * day;

  Loan loan({
    required int id,
    int? dueDate,
    int? returnedDate,
    int bookId = 1,
  }) => Loan(
    id: id,
    bookId: bookId,
    borrowerId: 1,
    lentDate: 0,
    dueDate: dueDate,
    returnedDate: returnedDate,
  );

  test('empty inputs → empty snapshot', () {
    final s = buildPendingSnapshot(loans: const [], books: const [], now: now);
    expect(s.isEmpty, isTrue);
    expect(s.count, 0);
  });

  test('classifies overdue vs due-soon vs neither', () {
    final s = buildPendingSnapshot(
      loans: [
        loan(id: 1, dueDate: now - day), // overdue
        loan(id: 2, dueDate: now + day), // due soon (within 3d)
        loan(id: 3, dueDate: now + 10 * day), // far future → neither
      ],
      books: const [],
      now: now,
    );
    expect(s.overdue.map((l) => l.id), [1]);
    expect(s.dueSoon.map((l) => l.id), [2]);
  });

  test('returned and no-due-date loans are excluded', () {
    final s = buildPendingSnapshot(
      loans: [
        loan(id: 1, dueDate: now - day, returnedDate: now), // returned
        loan(id: 2), // no due date
      ],
      books: const [],
      now: now,
    );
    expect(s.overdue, isEmpty);
    expect(s.dueSoon, isEmpty);
  });

  test('overdue and due-soon are each sorted by due date ascending', () {
    final s = buildPendingSnapshot(
      loans: [
        loan(id: 1, dueDate: now - day),
        loan(id: 2, dueDate: now - 5 * day),
        loan(id: 3, dueDate: now + 2 * day),
        loan(id: 4, dueDate: now + 1 * day),
      ],
      books: const [],
      now: now,
    );
    expect(s.overdue.map((l) => l.id), [2, 1]); // -5d before -1d
    expect(s.dueSoon.map((l) => l.id), [4, 3]); // +1d before +2d
  });

  test('respects a custom due-soon window', () {
    final s = buildPendingSnapshot(
      loans: [loan(id: 1, dueDate: now + 5 * day)],
      books: const [],
      now: now,
      dueSoonWithinDays: 7,
    );
    expect(s.dueSoon.map((l) => l.id), [1]);
  });

  test('needsMetadata books are surfaced; removed ones excluded', () {
    final s = buildPendingSnapshot(
      loans: const [],
      books: const [
        Book(id: 1, title: 'Needs', needsMetadata: true),
        Book(id: 2, title: 'Fine'),
        Book(id: 3, title: 'Gone', needsMetadata: true, removed: true),
      ],
      now: now,
    );
    expect(s.staleMetadataBooks.map((b) => b.id), [1]);
  });

  test('count sums all buckets', () {
    final s = buildPendingSnapshot(
      loans: [
        loan(id: 1, dueDate: now - day),
        loan(id: 2, dueDate: now + day),
      ],
      books: const [Book(id: 9, title: 'X', needsMetadata: true)],
      now: now,
    );
    expect(s.count, 3);
    expect(s.isEmpty, isFalse);
  });
}
