import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/catalogue_replacement_plan.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';

const _local = CatalogueItem(id: 7, itemUid: 'stable', title: 'Local');
const _isbn = '9780306406157';

void main() {
  test(
    'UID match keeps local ID and incoming metadata, ignoring incoming ID',
    () {
      const incoming = CatalogueItem(
        id: 99,
        itemUid: 'stable',
        title: 'Updated',
      );
      final result = CatalogueReplacementPlan.build(
        local: [_local],
        incoming: [incoming],
        loanBookIds: {7},
      ).getOrElse((f) => fail('$f'));
      expect(result.single.id, 7);
      expect(result.single.title, 'Updated');
      expect(result.single.itemUid, 'stable');
      expect(incoming.id, 99);
      expect(() => result.add(incoming), throwsUnsupportedError);
    },
  );

  test('new rows never adopt file IDs; unrelated unloaned books may go', () {
    final result = CatalogueReplacementPlan.build(
      local: [_local],
      incoming: [const CatalogueItem(id: 7, title: 'New')],
      loanBookIds: {},
    ).getOrElse((f) => fail('$f'));
    expect(result.single.id, CatalogueItem.emptyId);
  });

  test('valid ISBN-10 matches ISBN-13 when UID absent, keeping local UID', () {
    final result = CatalogueReplacementPlan.build(
      local: [
        const CatalogueItem(id: 7, itemUid: 'stable', title: 'A', isbn: _isbn),
      ],
      incoming: [const CatalogueItem(title: 'B', isbn: '0-306-40615-2')],
      loanBookIds: {7},
    ).getOrElse((f) => fail('$f'));
    expect(result.single.id, 7);
    expect(result.single.itemUid, 'stable');
  });

  test('legacy local ISBN can acquire an incoming UID', () {
    final result = CatalogueReplacementPlan.build(
      local: [const CatalogueItem(id: 7, title: 'A', isbn: _isbn)],
      incoming: [
        const CatalogueItem(itemUid: 'new-uid', title: 'B', isbn: _isbn),
      ],
      loanBookIds: {7},
    ).getOrElse((f) => fail('$f'));
    expect(result.single.id, 7);
    expect(result.single.itemUid, 'new-uid');
  });

  void rejects(
    String name, {
    required List<CatalogueItem> incoming,
    List<CatalogueItem> local = const [_local],
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
    incoming: [const CatalogueItem(id: 7, itemUid: 'other', title: 'Other')],
  );
  rejects(
    'same title is not identity',
    incoming: [const CatalogueItem(title: 'Local')],
  );
  rejects('pre-existing dangling loan', incoming: [_local], loans: {99});
  rejects(
    'nonpositive local ID',
    local: [const CatalogueItem(title: 'A')],
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
    local: [const CatalogueItem(id: 7, title: 'A', itemUid: ' ')],
    incoming: [const CatalogueItem(title: 'A', itemUid: '')],
  );
  rejects(
    'invalid ISBN cannot prove identity',
    local: [const CatalogueItem(id: 7, title: 'A', isbn: '123')],
    incoming: [const CatalogueItem(title: 'A', isbn: '123')],
  );
  rejects(
    'conflicting UIDs cannot fall back to matching ISBN',
    local: [
      const CatalogueItem(id: 7, title: 'A', itemUid: 'one', isbn: _isbn),
    ],
    incoming: [const CatalogueItem(title: 'A', itemUid: 'two', isbn: _isbn)],
  );
  rejects(
    'UID and ISBN resolve to different local books',
    local: [
      _local,
      const CatalogueItem(id: 8, itemUid: 'other', title: 'B', isbn: _isbn),
    ],
    incoming: [const CatalogueItem(itemUid: 'stable', title: 'A', isbn: _isbn)],
  );
  rejects(
    'two incoming books claim the same local row',
    local: [
      const CatalogueItem(id: 7, itemUid: 'stable', title: 'A', isbn: _isbn),
    ],
    incoming: [
      _local,
      const CatalogueItem(title: 'Legacy', isbn: _isbn),
    ],
  );
  rejects(
    'duplicate normalized incoming ISBN',
    incoming: [
      _local,
      const CatalogueItem(title: 'B', isbn: _isbn),
      const CatalogueItem(title: 'C', isbn: '0-306-40615-2'),
    ],
  );
  rejects(
    'duplicate normalized local ISBN',
    local: [
      _local,
      const CatalogueItem(id: 8, title: 'B', isbn: _isbn),
      const CatalogueItem(id: 9, title: 'C', isbn: '0-306-40615-2'),
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
