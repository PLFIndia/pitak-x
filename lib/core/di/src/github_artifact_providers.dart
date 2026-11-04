/// GitHub operation-artifact DI, separate from the shared publish module so
/// each composition-root file stays below the architecture size ratchet.
library;

import 'package:pitaka/core/di/src/platform_providers.dart';
import 'package:pitaka/features/publish/application/github_artifact_store.dart';
import 'package:pitaka/features/publish/infrastructure/file_github_artifact_store.dart';
import 'package:pitaka/features/publish/infrastructure/publish_artifact_spool_root.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'github_artifact_providers.g.dart';

/// Fresh operation-scoped GitHub artifact spools (never shared between runs).
///
/// The spool root does NO file work here. Its sweep and run folder happen on
/// the first `write`, inside a queued operation (review finding 6).
@riverpod
Future<GitHubArtifactStoreFactory> gitHubArtifactStores(
  GitHubArtifactStoresRef ref,
) async {
  final spoolRoot = PublishArtifactSpoolRoot(
    tempRoot: await ref.watch(appTempDirProvider.future),
    legacyRoot: await ref.watch(appDocsDirProvider.future),
  );
  return () => FileGitHubArtifactStore(spoolRoot: spoolRoot);
}
