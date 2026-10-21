import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/presentation/catalogue_save_messages.dart';

// The one failure → sentence mapping every catalogue form shares. The book
// wording is pinned exactly (AddBookPage tests assert it on screen); the new
// ADR 0013 failures get plain, non-technical sentences with no raw text.
void main() {
  group('catalogueSaveMessage', () {
    test('validation messages pass through verbatim', () {
      expect(
        catalogueSaveMessage(const ValidationFailure('A title is required.')),
        'A title is required.',
      );
    });

    test('duplicate ISBN: book wording unchanged (S34)', () {
      expect(
        catalogueSaveMessage(const DuplicateIsbnFailure()),
        'This book is already in your library.',
      );
      expect(
        catalogueSaveMessage(
          const DuplicateIsbnFailure(existingTitle: ' Dune '),
        ),
        "'Dune' is already in your library.",
      );
      expect(
        catalogueSaveMessage(
          const DuplicateIsbnFailure(
            existingTitle: 'Dune',
            existingIsRemoved: true,
          ),
        ),
        "'Dune' is already in your library. It is marked as removed — open "
        'it from the library list to restore it.',
      );
    });

    test('the noun changes the generic sentences only', () {
      expect(
        catalogueSaveMessage(const NotFoundFailure(), noun: 'issue'),
        'This issue no longer exists and could not be saved.',
      );
      expect(
        catalogueSaveMessage(const StorageFailure('disk'), noun: 'item'),
        'Could not save the item. Please try again.',
      );
      expect(
        catalogueSaveMessage(const StorageFailure('disk')),
        'Could not save the book. Please try again.',
      );
    });

    test('duplicate ISSN names the existing title when known', () {
      expect(
        catalogueSaveMessage(const DuplicateIssnFailure()),
        'A magazine title with this ISSN is already in your library.',
      );
      expect(
        catalogueSaveMessage(
          const DuplicateIssnFailure(existingTitle: 'Chandamama'),
        ),
        "'Chandamama' already has this ISSN.",
      );
    });

    test('duplicate issue names the existing row when known', () {
      expect(
        catalogueSaveMessage(const DuplicateIssueFailure()),
        'This issue is already in your library.',
      );
      expect(
        catalogueSaveMessage(
          const DuplicateIssueFailure(existingTitle: 'Chandamama — No 10'),
        ),
        "'Chandamama — No 10' is already in your library.",
      );
    });

    test('a periodical with issues cannot be deleted: counts are worded', () {
      expect(
        catalogueSaveMessage(const PeriodicalHasIssuesFailure(1)),
        'This magazine title still has 1 issue. Remove them first, or mark '
        'the title as removed instead.',
      );
      expect(
        catalogueSaveMessage(const PeriodicalHasIssuesFailure(12)),
        contains('still has 12 issues'),
      );
    });

    test('an unsupported kind asks for an update and echoes no raw text', () {
      final msg = catalogueSaveMessage(
        const UnsupportedItemKindFailure('hologram'),
        noun: 'item',
      );
      expect(msg, contains('newer version of Pitak'));
      expect(msg, isNot(contains('hologram')));
    });

    test('anything else is the generic retry sentence', () {
      expect(
        catalogueSaveMessage(StateError('boom')),
        'Could not save the book. Please try again.',
      );
    });
  });
}
