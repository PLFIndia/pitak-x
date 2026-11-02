import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';

/// Plan S5 (ADR 0019 Decision 11): the snapshot of an availability-only
/// publish, and the one "would this change the site?" rule both hosts use.
void main() {
  PublishFile file({required bool upload}) {
    final bytes = utf8.encode('{"schemaVersion":1,"asOf":0,"out":[]}');
    return PublishFile(
      path: 'availability.json',
      bytes: bytes,
      gitSha: GitBlobSha.of(bytes),
      upload: upload,
    );
  }

  group('PublishSnapshot.availabilityOnly', () {
    final section = PublishSection(
      section: SiteSection.availability,
      files: [file(upload: true)],
    );

    test('carries exactly the availability section, incrementally', () {
      final snapshot = PublishSnapshot.availabilityOnly(section);

      expect(snapshot.sections, [section]);
      expect(snapshot.availability, same(section));
      expect(snapshot.catalogue, isNull);
      expect(snapshot.events, isNull);
      // The lane never builds a complete site, so it can never stand in for
      // a move or a replacement.
      expect(snapshot.mode, PublishMode.incremental);
    });

    test('writes no catalogue, so it never claims a keyed books.json', () {
      final snapshot = PublishSnapshot.availabilityOnly(section);

      // The Cloudflare record then keeps `catalogueKeyed` only because the
      // deploy carried the recorded books.json unchanged (A.6 #37).
      expect(snapshot.writesKeyedCatalogue, isFalse);
      expect(snapshot.catalogueItemCount, 0);
      expect(snapshot.posterCount, 0);
      expect(snapshot.availabilityOmitted, isFalse);
      expect(snapshot.eventsIsEmpty, isFalse);
    });

    test('a removal is a snapshot too', () {
      const removal = PublishSection(
        section: SiteSection.availability,
        files: [],
        deletePaths: ['availability.json'],
      );

      expect(const PublishSnapshot.availabilityOnly(removal).sections, [
        removal,
      ]);
    });
  });

  group('PublishSection.changesSite', () {
    test('a file to upload changes the site', () {
      expect(
        PublishSection(
          section: SiteSection.availability,
          files: [file(upload: true)],
        ).changesSite,
        isTrue,
      );
    });

    test('a path to delete changes the site', () {
      expect(
        const PublishSection(
          section: SiteSection.availability,
          files: [],
          deletePaths: ['availability.json'],
        ).changesSite,
        isTrue,
      );
    });

    test('an unchanged file carried by its sha does not', () {
      expect(
        PublishSection(
          section: SiteSection.availability,
          files: [file(upload: false)],
        ).changesSite,
        isFalse,
      );
      expect(
        const PublishSection(
          section: SiteSection.availability,
          files: [],
        ).changesSite,
        isFalse,
      );
    });
  });
}
