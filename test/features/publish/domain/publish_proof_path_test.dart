import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';

/// SPECIFICATION of the proof path (ADR 0019 Decision 10, plan AV12, A.6 #21).
void main() {
  test('the four rows of the ADR 0019 table', () {
    expect(PublishProofPath.booksJson.path, 'books.json');
    expect(PublishProofPath.booksJson.expectsAbsent, isFalse);
    expect(PublishProofPath.eventsJson.path, 'events.json');
    expect(PublishProofPath.eventsJson.expectsAbsent, isFalse);
    expect(PublishProofPath.availabilityJson.path, 'availability.json');
    expect(PublishProofPath.availabilityJson.expectsAbsent, isFalse);
    expect(PublishProofPath.availabilityJsonAbsent.path, 'availability.json');
    expect(PublishProofPath.availabilityJsonAbsent.expectsAbsent, isTrue);
  });

  test('every proof file is an app-owned path', () {
    for (final proof in PublishProofPath.values) {
      expect(SiteSection.anyOwns(proof.path), isTrue, reason: proof.name);
    }
  });

  test('tryParse reads stored names only', () {
    for (final proof in PublishProofPath.values) {
      expect(PublishProofPath.tryParse(proof.name), proof);
    }
    for (final bad in [null, '', 'books.json', 'BooksJson', 3, true]) {
      expect(PublishProofPath.tryParse(bad), isNull, reason: '$bad');
    }
  });

  group('agreesWith the record files', () {
    test('an expected file must be recorded', () {
      expect(
        PublishProofPath.booksJson.agreesWith({'books.json': 'b'}),
        isTrue,
      );
      expect(
        PublishProofPath.booksJson.agreesWith({'events.json': 'e'}),
        isFalse,
      );
    });

    test('an expected absence must NOT be recorded', () {
      expect(
        PublishProofPath.availabilityJsonAbsent.agreesWith({'books.json': 'b'}),
        isTrue,
      );
      expect(
        PublishProofPath.availabilityJsonAbsent.agreesWith({
          'availability.json': 'a',
        }),
        isFalse,
      );
    });
  });
}
