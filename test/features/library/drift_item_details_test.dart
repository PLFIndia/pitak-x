import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/database/app_database.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/infrastructure/drift_item_details.dart';

/// The per-kind detail seam on its own (ADR 0013 F4/F6).
void main() {
  late AppDatabase db;
  late DriftItemDetails seam;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    seam = DriftItemDetails(db);
  });

  tearDown(() => db.close());

  const row = MagazineIssueRow(
    itemId: 1,
    periodicalUid: 'p',
    volume: 2,
    issueNumber: 3,
    issueDate: 4,
    boundUntil: 5,
    issueLabel: 'l',
  );

  group('read', () {
    test('book → null, other → marker, magazine-issue → IssueOf', () {
      expect(seam.read('book', null), isNull);
      expect(seam.read('book', row), isNull, reason: 'kind wins');
      expect(seam.read('other', null), isA<OtherItemOf>());
      final issue = seam.read('magazine-issue', row)! as IssueOf;
      expect(issue.periodicalUid, 'p');
      expect(issue.volume, 2);
      expect(issue.issueNumber, 3);
      expect(issue.issueDate, 4);
      expect(issue.boundUntil, 5);
      expect(issue.label, 'l');
    });

    test('unknown token or missing detail row reads as a book', () {
      expect(seam.read('hologram', null), isNull);
      expect(seam.read('hologram', row), isNull);
      expect(seam.read('magazine-issue', null), isNull);
      expect(seam.read('', null), isNull);
    });

    test('isSupported mirrors ItemKind.fromToken', () {
      expect(DriftItemDetails.isSupported('book'), isTrue);
      expect(DriftItemDetails.isSupported('Magazine-Issue'), isTrue);
      expect(DriftItemDetails.isSupported('hologram'), isFalse);
    });
  });

  group('write / delete', () {
    Future<int> base(String title) => db
        .into(db.books)
        .insert(BooksCompanion.insert(title: title, addedDate: 1));

    test('an issue is upserted; a book/other removes a stale row', () async {
      final id = await base('x');
      await seam.write(id, const IssueOf(periodicalUid: 'p', issueNumber: 1));
      await seam.write(id, const IssueOf(periodicalUid: 'p', issueNumber: 2));
      final rows = await db.select(db.magazineIssues).get();
      expect(rows.single.issueNumber, 2);

      await seam.write(id, null);
      expect(await db.select(db.magazineIssues).get(), isEmpty);

      await seam.write(id, const IssueOf(periodicalUid: 'p', issueNumber: 3));
      await seam.write(id, const OtherItemOf());
      expect(await db.select(db.magazineIssues).get(), isEmpty);
    });

    test('delete is idempotent', () async {
      final id = await base('x');
      await seam.delete(id);
      await seam.write(id, const IssueOf(periodicalUid: 'p', issueNumber: 1));
      await seam.delete(id);
      await seam.delete(id);
      expect(await db.select(db.magazineIssues).get(), isEmpty);
    });

    test('a detail row cannot exist without its base row (FK)', () async {
      await expectLater(
        seam.write(4242, const IssueOf(periodicalUid: 'p', issueNumber: 1)),
        throwsA(isA<Object>()),
      );
    });
  });
}
