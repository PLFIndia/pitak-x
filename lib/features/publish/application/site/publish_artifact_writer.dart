/// Shared artifact-sink consumption with exact metadata preservation.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/site/publish_artifact_sink.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';

/// Hands [file] to [sink], or returns it unchanged when no sink is installed.
///
/// A consumed file keeps no bytes, but its exact size remains available for
/// upload accounting and bounded read-back. Every section uses this one rule
/// so a byte-less spooled file cannot be mistaken for an in-memory empty file.
Future<Either<Failure, PublishFile>> writePublishArtifact({
  required PublishArtifactSink? sink,
  required PublishFile file,
}) async {
  if (sink == null) return Right(file);
  final result = await sink.write(file);
  if (result case Left(value: final failure)) return Left(failure);
  return Right(
    PublishFile(
      path: file.path,
      bytes: const [],
      gitSha: file.gitSha,
      upload: file.upload,
      storedSize: file.size,
    ),
  );
}
