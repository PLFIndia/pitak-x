import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/vault/domain/availability.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';

void main() {
  Loan loan(int bookId, {int? returnedDate}) => Loan(
    bookId: bookId,
    borrowerId: 1,
    lentDate: 1000,
    returnedDate: returnedDate,
  );

  group('activeLoanCountsByBook', () {
    test('counts only not-yet-returned loans, grouped by book', () {
      final counts = activeLoanCountsByBook([
        loan(1),
        loan(1),
        loan(2),
        loan(2, returnedDate: 2000), // returned → not counted
      ]);
      expect(counts[1], 2);
      expect(counts[2], 1);
    });

    test('empty input yields an empty map', () {
      expect(activeLoanCountsByBook(const []), isEmpty);
    });
  });

  group('isBookUnavailable', () {
    test('unavailable when active loans reach copyCount', () {
      expect(
        isBookUnavailable(bookId: 1, copyCount: 2, activeCounts: {1: 2}),
        isTrue,
      );
    });

    test('available when fewer copies are out than copyCount', () {
      expect(
        isBookUnavailable(bookId: 1, copyCount: 3, activeCounts: {1: 2}),
        isFalse,
      );
    });

    test('available when the book has no active loans', () {
      expect(
        isBookUnavailable(bookId: 9, copyCount: 1, activeCounts: const {}),
        isFalse,
      );
    });

    test('copyCount below 1 is clamped to 1', () {
      // 1 copy out, copyCount 0 → clamped to 1 → unavailable.
      expect(
        isBookUnavailable(bookId: 1, copyCount: 0, activeCounts: {1: 1}),
        isTrue,
      );
    });
  });
}
