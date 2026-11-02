/// Shared fixtures for the backup publishing record (plan S11, CV6/CV7):
/// a salt, one valid GitHub record and one valid Cloudflare record, both of
/// the shapes this build writes. No credentials anywhere.
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_cover_rendition.dart';
import 'package:pitaka/features/publish/domain/publish_manifest.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_proof_path.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';

/// The archive's salt (16 bytes, all different from [phoneSalt]).
final List<int> archiveSalt = List<int>.generate(16, (i) => 200 + i ~/ 2);

/// A salt a phone already had before the restore.
final List<int> phoneSalt = List<int>.generate(16, (i) => i);

/// The GitHub site the archive describes.
final GitHubPublishTarget archiveGitHub = GitHubPublishTarget.create(
  'degt3rt/my-library',
)!;

/// The Cloudflare site the archive describes.
final CloudflarePublishTarget archiveCloudflare =
    CloudflarePublishTarget.create(
      accountId: '0123456789abcdef0123456789abcdef',
      workerName: 'pitak-library',
      accountSubdomain: 'library',
    )!;

/// A 40-hex git sha made of [c].
String sha40(String c) => c * 40;

/// A live, keyed GitHub record with one local and one remote cover source.
PublishManifest gitHubRecord({
  Map<String, String>? covers,
  bool keyed = true,
  String repo = 'degt3rt/my-library',
}) => PublishManifest(
  repo: repo,
  branch: 'main',
  headSha: sha40('1'),
  ownershipConfirmed: true,
  state: PublishState.live,
  fileShas: {
    'books.json': sha40('a'),
    'index.html': sha40('b'),
    'covers/3f2c7a1b9e4d8051.jpg': sha40('c'),
    'covers/9a8b7c6d5e4f3021.jpg': sha40('d'),
  },
  coverUrlByBookId:
      covers ??
      const {
        '1': 'covers/0b1f-uuid.jpg',
        '2': 'https://covers.openlibrary.org/b/id/1-L.jpg',
      },
  proofPath: PublishProofPath.booksJson,
  catalogueKeyed: keyed,
  coverRendition: PublishCoverRendition.current,
);

CloudflareAssetEntry _entry(String sha, CloudflareContentType type) =>
    CloudflareAssetEntry(
      sha: sha,
      hash: CloudflareAssetHash.of(sha.codeUnits, type.extension),
      size: 10,
      type: type,
    );

/// A live, keyed Cloudflare record with one local cover source.
CloudflareSiteManifest cloudflareRecord({
  Map<String, String>? covers,
  bool keyed = true,
}) => CloudflareSiteManifest(
  target: archiveCloudflare,
  state: PublishState.live,
  publishId: 'a' * 32,
  hashScheme: CloudflareAssetHash.scheme,
  files: {
    'books.json': _entry(sha40('a'), CloudflareContentType.json),
    'index.html': _entry(sha40('b'), CloudflareContentType.html),
    'pitak-publish.json': _entry(sha40('e'), CloudflareContentType.json),
  },
  coverUrlByBookId: covers ?? const {'1': 'covers/0b1f-uuid.jpg'},
  catalogueKeyed: keyed,
  coverRendition: PublishCoverRendition.current,
);

/// A backup record of a library that publishes to GitHub (verified) and
/// once published to Cloudflare.
PublishStateBackup archivedState({
  PublishManifest? gitHub,
  CloudflareSiteManifest? cloudflare,
  PublishHost? activeHost = PublishHost.github,
  PublishTarget? verified,
  bool verifiedGitHub = true,
}) => PublishStateBackup.tryCreate(
  coverSalt: archiveSalt,
  gitHubRecord: gitHub ?? gitHubRecord(),
  cloudflareRecord: cloudflare ?? cloudflareRecord(),
  activeHost: activeHost,
  verifiedTarget: verified ?? (verifiedGitHub ? archiveGitHub : null),
)!;
