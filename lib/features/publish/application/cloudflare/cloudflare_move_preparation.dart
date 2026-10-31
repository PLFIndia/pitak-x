/// Cloudflare move preparation backed by one operation's artifact spool.
library;

import 'dart:typed_data';

import 'package:pitaka/features/publish/application/cloudflare/cloudflare_artifact_store.dart';
import 'package:pitaka/features/publish/application/site/move_snapshot_preparation.dart';
import 'package:pitaka/features/publish/application/site/publish_snapshot_builder.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_site_manifest.dart';

/// Wires the shared move builder to immediate spooling and digest reads.
MoveSnapshotPreparation cloudflareMovePreparation({
  required PublishSnapshotBuilder builder,
  required CloudflareArtifactStore store,
  required int Function() clock,
}) => MoveSnapshotPreparation(
  builder: builder.withArtifactSink(CloudflareArtifactSink(store)),
  emptyPrevious: CloudflareSiteManifest.empty,
  clock: clock,
  readBytes: (path) async {
    final asset = store.assetForPath(path);
    if (asset == null) return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in asset.bucketAsset.openValidated()) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  },
);
