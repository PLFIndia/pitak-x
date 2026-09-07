import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/lookup/domain/isbn_format.dart';

/// Pure replacement planning: preserve verified local identities rather than
/// rewriting encrypted loan rows in another database (M03, policy C).
abstract final class CatalogueReplacementPlan {
  /// Maps incoming rows onto local IDs, or refuses before any write. New rows
  /// use [Book.emptyId]; SQLite AUTOINCREMENT must allocate their IDs without
  /// resetting sqlite_sequence. Thus old, deleted IDs are never recycled.
  ///
  /// Exact nonblank UIDs are authoritative. A valid normalized ISBN is a
  /// fallback only if a UID is absent, never if two UIDs disagree. No fuzzy
  /// matching. Duplicate/contradictory keys are refused, not first-match-wins.
  static Either<Failure, List<Book>> build({
    required List<Book> local,
    required List<Book> incoming,
    required Set<int> loanBookIds,
  }) {
    final localIds = <int>{};
    for (final book in local) {
      if (book.id <= 0 || !localIds.add(book.id)) return left(_unsafe);
    }
    if (!localIds.containsAll(loanBookIds)) return left(_unsafe);
    final localKeys = _IdentityIndex();
    final incomingKeys = _IdentityIndex();
    for (final book in local) {
      if (!localKeys.add(book)) return left(_unsafe);
    }
    for (final book in incoming) {
      if (!incomingKeys.add(book)) return left(_unsafe);
    }
    final claimed = <int>{};
    final planned = <Book>[];
    for (final book in incoming) {
      final uid = _uid(book);
      final isbn = _isbn(book);
      final byUid = uid == null ? null : localKeys.uids[uid];
      final byIsbn = isbn == null ? null : localKeys.isbns[isbn];
      if (byUid != null && byIsbn != null && byUid.id != byIsbn.id) {
        return left(_unsafe);
      }
      final match = byUid ?? byIsbn;
      if (match == null) {
        planned.add(book.copyWith(id: Book.emptyId));
        continue;
      }
      final localUid = _uid(match);
      if (uid != null && localUid != null && uid != localUid) {
        return left(_unsafe);
      }
      if (!claimed.add(match.id)) return left(_unsafe);
      // Keep the established UID when a legacy file provides only an ISBN.
      planned.add(book.copyWith(id: match.id, bookUid: localUid ?? uid));
    }
    if (!claimed.containsAll(loanBookIds)) return left(_unsafe);
    return right(List.unmodifiable(planned));
  }

  static const _unsafe = ValidationFailure(
    'Cannot safely match this catalogue to existing book identities and '
    'loan history. No books were replaced. Use a matching catalogue or Join '
    'instead; missing or conflicting identities must be resolved first.',
  );

  static String? _uid(Book book) {
    final value = book.bookUid?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String? _isbn(Book book) {
    final value = IsbnFormat.normalize(book.isbn ?? '');
    if (!IsbnFormat.isValid(value)) return null;
    return value.length == 10 ? IsbnFormat.toIsbn13(value) : value;
  }
}

/// Indexes exact keys, refusing ambiguity instead of selecting the first row.
final class _IdentityIndex {
  final uids = <String, Book>{};
  final isbns = <String, Book>{};

  bool add(Book book) {
    final uid = CatalogueReplacementPlan._uid(book);
    final isbn = CatalogueReplacementPlan._isbn(book);
    if (uid != null && uids.containsKey(uid)) return false;
    if (isbn != null && isbns.containsKey(isbn)) return false;
    if (uid != null) uids[uid] = book;
    if (isbn != null) isbns[isbn] = book;
    return true;
  }
}
