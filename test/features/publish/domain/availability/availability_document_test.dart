import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/availability/availability_document.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import '../../support/key_set_fixtures.dart';

/// SPECIFICATION of the public `availability.json` (ADR 0019 Decisions 2 and
/// 4, plan C.1).
void main() {
  AvailabilityDocument document(List<String> keys, int asOf) =>
      AvailabilityDocument(
        AvailabilitySnapshot.tryCreate(
          keySet: testKeySetId,
          keys: keys,
          asOfMillis: asOf,
        )!,
      );

  test('compact JSON of the map is exactly the ADR 0019 example', () {
    // The example as clarified in S7 (plan A.6 #68): the key-set id sits
    // right after the schema version.
    final doc = document(const [
      '9a0b44c1d2e3f405',
      '3f2c7a1b9e4d8051',
    ], 1761984300000);
    expect(
      jsonEncode(doc.toJson()),
      '{"schemaVersion":1,"keySet":"5e0c1d2b3a497f68","asOf":1761984300000,'
      '"out":["3f2c7a1b9e4d8051","9a0b44c1d2e3f405"]}',
    );
  });

  test('the same set gives identical bytes whatever the input order', () {
    final first = document(const ['bbbbbbbbbbbbbbbb', 'aaaaaaaaaaaaaaaa'], 0);
    final second = document(const [
      'aaaaaaaaaaaaaaaa',
      'bbbbbbbbbbbbbbbb',
      'aaaaaaaaaaaaaaaa',
    ], 0);
    expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
  });

  test('an empty set still writes an explicit empty list', () {
    expect(
      jsonEncode(document(const [], 60000).toJson()),
      '{"schemaVersion":1,"keySet":"5e0c1d2b3a497f68","asOf":60000,'
      '"out":[]}',
    );
  });

  test('the field order is fixed: schemaVersion, keySet, asOf, out', () {
    expect(document(const [], 0).toJson().keys, [
      'schemaVersion',
      'keySet',
      'asOf',
      'out',
    ]);
  });

  test('the availability section owns the document path', () {
    expect(AvailabilityDocument.path, 'availability.json');
    expect(SiteSection.availability.owns(AvailabilityDocument.path), isTrue);
  });

  test('anything the writer can produce, every reader accepts (AV15)', () {
    // The largest set the writer allows, with the largest plausible asOf.
    final keys = [
      for (var i = 0; i < AvailabilitySnapshot.maxKeys; i++)
        i.toRadixString(16).padLeft(16, 'f'),
    ];
    final doc = document(keys, 9999999999999);
    final bytes = utf8.encode(jsonEncode(doc.toJson()));

    expect(
      bytes.length,
      lessThanOrEqualTo(AvailabilityDocument.readerMaxBytes),
    );
    expect(
      AvailabilitySnapshot.maxKeys,
      lessThanOrEqualTo(AvailabilityDocument.readerMaxKeys),
    );
  });

  test('the file carries no internal id, count or loan detail', () {
    final json = document(const ['3f2c7a1b9e4d8051'], 0).toJson();
    expect(json.keys.toSet(), {'schemaVersion', 'keySet', 'asOf', 'out'});
  });

  test('toString names counts only, never keys', () {
    expect(
      document(const ['3f2c7a1b9e4d8051'], 60000).toString(),
      'AvailabilityDocument(AvailabilitySnapshot(1 out, asOf 60000))',
    );
  });
}
