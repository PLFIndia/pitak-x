import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/site/availability_section_builder.dart';
import 'package:pitaka/features/publish/domain/availability/availability_document.dart';
import 'package:pitaka/features/publish/domain/availability/availability_request.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/section_merge.dart';
import '../support/key_set_fixtures.dart';

/// The availability section (ADR 0019 Decisions 2 and 6, plan C.2 item 2).
void main() {
  AvailabilitySnapshot snapshot(
    List<String> keys, {
    int asOf = 1761984345678,
  }) => AvailabilitySnapshot.tryCreate(
    keySet: testKeySetId,
    keys: keys,
    asOfMillis: asOf,
  )!;

  const keyA = '3f2c7a1b9e4d8051';
  const keyB = '9a0b44c1d2e3f405';

  group('the one compact encoder', () {
    test('writes the exact ADR 0019 bytes: compact, sorted, minute asOf', () {
      final bytes = encodeAvailabilityJsonBytes(
        AvailabilityDocument(snapshot([keyB, keyA, keyB])),
      );
      expect(
        utf8.decode(bytes),
        '{"schemaVersion":1,"keySet":"5e0c1d2b3a497f68",'
        '"asOf":1761984300000,'
        '"out":["3f2c7a1b9e4d8051","9a0b44c1d2e3f405"]}',
      );
    });

    test('the same set always gives the same bytes, whatever the order', () {
      expect(
        encodeAvailabilityJsonBytes(
          AvailabilityDocument(snapshot([keyA, keyB])),
        ),
        encodeAvailabilityJsonBytes(
          AvailabilityDocument(snapshot([keyB, keyA])),
        ),
      );
    });

    test('an empty set is a real, publishable answer', () {
      expect(
        utf8.decode(
          encodeAvailabilityJsonBytes(
            AvailabilityDocument(snapshot(const [], asOf: 120000)),
          ),
        ),
        '{"schemaVersion":1,"keySet":"5e0c1d2b3a497f68",'
        '"asOf":120000,"out":[]}',
      );
    });
  });

  group('write', () {
    test('one file, owned by the availability section, marked for upload', () {
      final section = AvailabilitySectionBuilder.write(
        snapshot: snapshot([keyA]),
        previous: PublishManifest.empty,
      );
      expect(section.section, SiteSection.availability);
      expect(section.paths, [AvailabilityDocument.path]);
      expect(section.deletePaths, isEmpty);
      final file = section.files.single;
      expect(file.upload, isTrue);
      expect(file.gitSha, GitBlobSha.of(file.bytes));
      expect(SiteSection.availability.owns(file.path), isTrue);
    });

    test('an unchanged set is never uploaded again', () {
      final first = AvailabilitySectionBuilder.write(
        snapshot: snapshot([keyA]),
        previous: PublishManifest.empty,
      );
      final record = PublishManifest(
        repo: 'me/lib',
        fileShas: {AvailabilityDocument.path: first.files.single.gitSha},
      );
      final again = AvailabilitySectionBuilder.write(
        snapshot: snapshot([keyA]),
        previous: record,
      );
      expect(again.files.single.upload, isFalse);

      final changed = AvailabilitySectionBuilder.write(
        snapshot: snapshot([keyA, keyB]),
        previous: record,
      );
      expect(changed.files.single.upload, isTrue);
    });
  });

  group('removal', () {
    test('nothing to do when the record does not show the file', () {
      expect(
        AvailabilitySectionBuilder.removal(previous: PublishManifest.empty),
        isNull,
      );
    });

    test('a recorded file becomes one exact deletion and nothing else', () {
      const record = PublishManifest(
        repo: 'me/lib',
        fileShas: {
          AvailabilityDocument.path: 'sha-a',
          'books.json': 'sha-b',
          'events.json': 'sha-e',
        },
      );
      final section = AvailabilitySectionBuilder.removal(previous: record)!;
      expect(section.section, SiteSection.availability);
      expect(section.files, isEmpty);
      expect(section.deletePaths, [AvailabilityDocument.path]);

      final merge = mergeSection(previous: record, section: section);
      expect(merge.deletePaths, [AvailabilityDocument.path]);
      expect(merge.fileShas, {'books.json': 'sha-b', 'events.json': 'sha-e'});
    });
  });

  group('withoutFreshSet (plan S6, J9)', () {
    const recorded = PublishManifest(
      repo: 'me/lib',
      fileShas: {'books.json': 'b1', 'availability.json': 'a1'},
      catalogueKeyed: true,
    );
    final unvouched = recorded.withoutCatalogueKeys();
    const nothingRecorded = PublishManifest(
      repo: 'me/lib',
      fileShas: {'books.json': 'b1'},
    );

    test('lane off: the recorded file is deleted, keyed or not', () {
      for (final previous in [recorded, unvouched]) {
        final section = AvailabilitySectionBuilder.withoutFreshSet(
          request: const AvailabilityRemoval(),
          previous: previous,
        );
        expect(section!.deletePaths, [AvailabilityDocument.path]);
        expect(section.files, isEmpty);
      }
    });

    test('lane on: a file the keyed catalogue vouches for is left alone', () {
      expect(
        AvailabilitySectionBuilder.withoutFreshSet(
          request: const AvailabilityFromLoanCounts(),
          previous: recorded,
        ),
        isNull,
      );
    });

    test('lane on: an unvouched file is deleted (keys may name others)', () {
      final section = AvailabilitySectionBuilder.withoutFreshSet(
        request: const AvailabilityFromLoanCounts(),
        previous: unvouched,
      );
      expect(section!.section, SiteSection.availability);
      expect(section.deletePaths, [AvailabilityDocument.path]);
    });

    test('nothing recorded: nothing to do either way (R13)', () {
      for (final request in const [
        AvailabilityRemoval(),
        AvailabilityFromLoanCounts(),
      ]) {
        expect(
          AvailabilitySectionBuilder.withoutFreshSet(
            request: request,
            previous: nothingRecorded,
          ),
          isNull,
        );
      }
    });
  });
}
