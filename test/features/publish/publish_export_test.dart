import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/publish_export.dart';

/// JSON shapes of the world-facing payload (ADR 0014 W3). The viewer reads
/// these keys; the additive additions (`kind`, `issue{}`, `periodicals[]`)
/// must not disturb what older viewers read.
void main() {
  test('schema stays 1 and periodicals[] is omitted when empty', () {
    const export = PublishExport(
      exportedAt: 1000,
      books: [PublishItem(title: 'The Odyssey', kind: 'book')],
    );
    final json = export.toJson();
    expect(json['schemaVersion'], 1);
    expect(json['exportedAt'], 1000);
    expect((json['books'] as List<dynamic>).single, {
      'title': 'The Odyssey',
      'kind': 'book',
    });
    expect(json.containsKey('periodicals'), isFalse);
  });

  test('periodicals[] serialises when present, nulls omitted', () {
    const export = PublishExport(
      exportedAt: 1000,
      books: [],
      periodicals: [
        PublishPeriodical(
          periodicalUid: 'uid-1',
          title: 'Chandamama',
          issn: '0577-6058',
          frequency: 'monthly',
        ),
      ],
    );
    final periodicals = export.toJson()['periodicals'] as List<dynamic>;
    expect(periodicals.single, {
      'periodicalUid': 'uid-1',
      'title': 'Chandamama',
      'issn': '0577-6058',
      'frequency': 'monthly',
    });
  });

  test('an issue entry nests issue{} with nulls omitted', () {
    const item = PublishItem(
      title: 'Chandamama — Vol 249 No 10 (Oct 2026)',
      kind: 'magazine-issue',
      issue: PublishIssue(periodicalUid: 'uid-1', volume: 249, issueNumber: 10),
    );
    expect(item.toJson(), {
      'title': 'Chandamama — Vol 249 No 10 (Oct 2026)',
      'kind': 'magazine-issue',
      'issue': {'periodicalUid': 'uid-1', 'volume': 249, 'issueNumber': 10},
    });
  });
}
