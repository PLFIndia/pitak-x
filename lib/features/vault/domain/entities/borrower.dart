/// Vault domain models. Mirror of Kotlin `Borrower` / `Loan` / `BorrowerStats`
/// (source app). Pure Dart (AGENTS.md §3.1). These live in the encrypted vault;
/// the data crosses the FFI boundary as rows out of the Rust core, never with
/// the key.
library;

/// A person who can borrow books. `id == emptyId` means "not yet persisted".
class Borrower {
  /// Creates a borrower. Only [name] is required.
  const Borrower({
    required this.name,
    this.id = emptyId,
    this.contact,
    this.notes,
  });

  /// Sentinel meaning "not yet persisted".
  static const int emptyId = 0;

  /// Per-device autoincrement id.
  final int id;

  /// Required display name.
  final String name;

  /// Optional contact (phone/email/free-form).
  final String? contact;

  /// Optional free-form notes.
  final String? notes;

  /// Returns a copy with the given fields replaced.
  Borrower copyWith({int? id, String? name, String? contact, String? notes}) {
    return Borrower(
      id: id ?? this.id,
      name: name ?? this.name,
      contact: contact ?? this.contact,
      notes: notes ?? this.notes,
    );
  }
}

/// A lending record tying a book to a borrower. Dates are epoch millis.
///
/// `bookId` is a logical cross-DB reference to a library book (no DB-level FK,
/// since books live in Drift and loans in the Rust vault). Integrity is
/// enforced in the application layer (AGENTS.md / PLAN.md cross-DB rule).
class Loan {
  /// Creates a loan. [bookId], [borrowerId] and [lentDate] are required.
  const Loan({
    required this.bookId,
    required this.borrowerId,
    required this.lentDate,
    this.id = emptyId,
    this.dueDate,
    this.returnedDate,
    this.notes,
  });

  /// Sentinel meaning "not yet persisted".
  static const int emptyId = 0;

  /// Per-device autoincrement id.
  final int id;

  /// Logical reference to the borrowed book (library `book.id`).
  final int bookId;

  /// Logical reference to the borrower.
  final int borrowerId;

  /// Epoch millis when the book was lent.
  final int lentDate;

  /// Epoch millis the loan is due back; null if open-ended.
  final int? dueDate;

  /// Epoch millis when returned; null while still out.
  final int? returnedDate;

  /// Optional free-form notes.
  final String? notes;

  /// True once the book has been returned.
  bool get isReturned => returnedDate != null;

  /// True if not returned and past [dueDate] at [now] (epoch millis).
  bool isOverdue(int now) => !isReturned && dueDate != null && now > dueDate!;

  /// Returns a copy with the given fields replaced.
  Loan copyWith({
    int? id,
    int? bookId,
    int? borrowerId,
    int? lentDate,
    int? dueDate,
    int? returnedDate,
    String? notes,
  }) {
    return Loan(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      borrowerId: borrowerId ?? this.borrowerId,
      lentDate: lentDate ?? this.lentDate,
      dueDate: dueDate ?? this.dueDate,
      returnedDate: returnedDate ?? this.returnedDate,
      notes: notes ?? this.notes,
    );
  }
}

/// Live-computed borrower statistics (Kotlin `BorrowerStats`).
class BorrowerStats {
  /// Creates a stats snapshot.
  const BorrowerStats({
    required this.totalLoans,
    required this.averageReturnDays,
    required this.overdueRate,
  });

  /// Total number of loans for the borrower.
  final int totalLoans;

  /// Average days to return, or null if no returns yet.
  final double? averageReturnDays;

  /// Fraction of loans that went overdue (0.0–1.0).
  final double overdueRate;
}
