import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_digest.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';
import 'package:pitaka/features/publish/domain/site/publish_mode.dart';
import 'package:pitaka/features/publish/domain/site/publish_section.dart';
import 'package:pitaka/features/publish/domain/site/publish_snapshot.dart';

PublishFile _jsonFile(String path, Map<String, Object?> value) {
  final bytes = utf8.encode(jsonEncode(value));
  return PublishFile(
    path: path,
    bytes: bytes,
    gitSha: GitBlobSha.of(bytes),
    upload: true,
  );
}

PublishSnapshot _snapshot({
  int exportedAt = 1000,
  int updatedAt = 2000,
  String title = 'The Odyssey',
  String coverSha = 'cover-content-sha',
  bool reverse = false,
}) {
  final files = <PublishFile>[
    _jsonFile('books.json', {
      'schemaVersion': 1,
      'exportedAt': exportedAt,
      'books': [
        {'title': title, 'author': 'Homer'},
      ],
    }),
    _jsonFile('library.json', {
      'siteUrl': 'https://worker.library.workers.dev/',
      'updatedAt': updatedAt,
      'fingerprint': 'library-fingerprint',
    }),
    PublishFile(
      path: 'index.html',
      bytes: utf8.encode('<html>$title</html>'),
      gitSha: GitBlobSha.of(utf8.encode('<html>$title</html>')),
      upload: true,
    ),
    PublishFile(
      path: 'covers/a.jpg',
      bytes: const [],
      gitSha: coverSha,
      upload: false,
    ),
  ];
  return PublishSnapshot(
    mode: PublishMode.complete,
    catalogue: PublishSection(
      section: SiteSection.catalogue,
      files: reverse ? files.reversed.toList() : files,
    ),
    catalogueItemCount: 1,
    posterCount: 0,
    availabilityOmitted: false,
  );
}

void main() {
  test('operation timestamps do not change the canonical digest', () async {
    final first = await PublishSnapshotDigest.of(_snapshot());
    final second = await PublishSnapshotDigest.of(
      _snapshot(exportedAt: 999999, updatedAt: 888888),
    );

    expect(first.isRight(), isTrue);
    expect(second.isRight(), isTrue);
    expect(first.toNullable(), second.toNullable());
    expect(
      _snapshot().catalogue!.files.first.gitSha,
      isNot(_snapshot(exportedAt: 999999).catalogue!.files.first.gitSha),
      reason: 'the raw books.json bytes really did change',
    );
  });

  test('file ordering does not change the digest', () async {
    final first = await PublishSnapshotDigest.of(_snapshot());
    final second = await PublishSnapshotDigest.of(_snapshot(reverse: true));

    expect(first.toNullable(), second.toNullable());
  });

  test('real catalogue content changes require renewed confirmation', () async {
    final first = await PublishSnapshotDigest.of(_snapshot());
    final second = await PublishSnapshotDigest.of(_snapshot(title: 'Ulysses'));

    expect(first.toNullable(), isNot(second.toNullable()));
  });

  test('an asset content-hash change requires renewed confirmation', () async {
    final first = await PublishSnapshotDigest.of(_snapshot());
    final second = await PublishSnapshotDigest.of(
      _snapshot(coverSha: 'new-sha'),
    );

    expect(first.toNullable(), isNot(second.toNullable()));
  });

  test(
    'malformed volatile JSON fails closed instead of hashing timestamps',
    () async {
      final snapshot = _snapshot();
      final broken = PublishSnapshot(
        mode: snapshot.mode,
        catalogue: PublishSection(
          section: SiteSection.catalogue,
          files: [
            PublishFile(
              path: 'books.json',
              bytes: utf8.encode('{broken'),
              gitSha: 'broken',
              upload: true,
            ),
          ],
        ),
        catalogueItemCount: 0,
        posterCount: 0,
        availabilityOmitted: false,
      );

      expect((await PublishSnapshotDigest.of(broken)).isLeft(), isTrue);
    },
  );
}
