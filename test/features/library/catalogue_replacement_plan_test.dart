import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_plan.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';

const _local = Book(id: 7, bookUid: 'stable', title: 'Local');
const _isbn = '9780306406157';

void main() {
  test(
    'UID match keeps local ID and incoming metadata, ignoring incoming ID',
    () {
      const incoming = Book(id: 99, bookUid: 'stable', title: 'Updated');
      final result = CatalogueReplacementPlan.build(
        local: [_local],
        incoming: [incoming],
        loanBookIds: {7},
      ).getOrElse((f) => fail('$f'));
      expect(result.single.id, 7);
      expect(result.single.title, 'Updated');
      expect(result.single.bookUid, 'stable');
      expect(incoming.id, 99);
      expect(() => result.add(incoming), throwsUnsupportedError);
    },
  );

  test('new rows never adopt file IDs; unrelated unloaned books may go', () {
    final result = CatalogueReplacementPlan.build(
      local: [_local],
      incoming: [const Book(id: 7, title: 'New')],
      loanBookIds: {},
    ).getOrElse((f) => fail('$f'));
    expect(result.single.id, Book.emptyId);
  });

  test('valid ISBN-10 matches ISBN-13 when UID absent, keeping local UID', () {
    final result = CatalogueReplacementPlan.build(
      local: [const Book(id: 7, bookUid: 'stable', title: 'A', isbn: _isbn)],
      incoming: [const Book(title: 'B', isbn: '0-306-40615-2')],
      loanBookIds: {7},
    ).getOrElse((f) => fail('$f'));
    expect(result.single.id, 7);
    expect(result.single.bookUid, 'stable');
  });

  test('legacy local ISBN can acquire an incoming UID', () {
    final result = CatalogueReplacementPlan.build(
      local: [const Book(id: 7, title: 'A', isbn: _isbn)],
      incoming: [const Book(bookUid: 'new-uid', title: 'B', isbn: _isbn)],
      loanBookIds: {7},
    ).getOrElse((f) => fail('$f'));
    expect(result.single.id, 7);
    expect(result.single.bookUid, 'new-uid');
  });

  void rejects(
    String name, {
    required List<Book> incoming,
    List<Book> local = const [_local],
    Set<int> loans = const {7},
  }) {
    test(name, () {
      final failure = CatalogueReplacementPlan.build(
        local: local,
        incoming: incoming,
        loanBookIds: loans,
      ).getLeft().toNullable();
      expect(failure, isA<ValidationFailure>());
      expect((failure! as ValidationFailure).message, isNot(contains('Local')));
    });
  }

  rejects('missing loaned book', incoming: []);
  rejects(
    'same numeric ID is not identity',
    incoming: [const Book(id: 7, bookUid: 'other', title: 'Other')],
  );
  rejects('same title is not identity', incoming: [const Book(title: 'Local')]);
  rejects('pre-existing dangling loan', incoming: [_local], loans: {99});
  rejects(
    'nonpositive local ID',
    local: [const Book(title: 'A')],
    incoming: [_local],
  );
  rejects('duplicate local ID', local: [_local, _local], incoming: [_local]);
  rejects(
    'duplicate local UID',
    local: [_local, _local.copyWith(id: 8)],
    incoming: [_local],
  );
  rejects('duplicate incoming UID', incoming: [_local, _local.copyWith(id: 8)]);
  rejects(
    'blank UIDs cannot prove identity',
    local: [const Book(id: 7, title: 'A', bookUid: ' ')],
    incoming: [const Book(title: 'A', bookUid: '')],
  );
  rejects(
    'invalid ISBN cannot prove identity',
    local: [const Book(id: 7, title: 'A', isbn: '123')],
    incoming: [const Book(title: 'A', isbn: '123')],
  );
  rejects(
    'conflicting UIDs cannot fall back to matching ISBN',
    local: [const Book(id: 7, title: 'A', bookUid: 'one', isbn: _isbn)],
    incoming: [const Book(title: 'A', bookUid: 'two', isbn: _isbn)],
  );
  rejects(
    'UID and ISBN resolve to different local books',
    local: [
      _local,
      const Book(id: 8, bookUid: 'other', title: 'B', isbn: _isbn),
    ],
    incoming: [const Book(bookUid: 'stable', title: 'A', isbn: _isbn)],
  );
  rejects(
    'two incoming books claim the same local row',
    local: [const Book(id: 7, bookUid: 'stable', title: 'A', isbn: _isbn)],
    incoming: [
      _local,
      const Book(title: 'Legacy', isbn: _isbn),
    ],
  );
  rejects(
    'duplicate normalized incoming ISBN',
    incoming: [
      _local,
      const Book(title: 'B', isbn: _isbn),
      const Book(title: 'C', isbn: '0-306-40615-2'),
    ],
  );
  rejects(
    'duplicate normalized local ISBN',
    local: [
      _local,
      const Book(id: 8, title: 'B', isbn: _isbn),
      const Book(id: 9, title: 'C', isbn: '0-306-40615-2'),
    ],
    incoming: [_local],
  );

  test('empty catalogue can replace an empty unloaned catalogue', () {
    expect(
      CatalogueReplacementPlan.build(
        local: [],
        incoming: [],
        loanBookIds: {},
      ).toNullable(),
      isEmpty,
    );
  });
  test('same UID permits metadata edits including a corrected ISBN', () {
    expect(
      CatalogueReplacementPlan.build(
        local: [_local],
        incoming: [_local.copyWith(isbn: _isbn)],
        loanBookIds: {7},
      ).isRight(),
      isTrue,
    );
  });
}
