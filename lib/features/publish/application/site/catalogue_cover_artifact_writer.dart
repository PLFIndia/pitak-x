/// Immediate, byte-releasing consumption of catalogue cover decisions.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/publish_cover_decider.dart';
import 'package:pitaka/features/publish/application/site/publish_artifact_writer.dart';
import 'package:pitaka/features/publish/domain/site/previous_publication.dart';
import 'package:pitaka/features/publish/domain/site/publish_artifact_sink.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';

/// Writes each produced cover before the next one is read, retaining metadata
/// only. With no sink, decisions keep their original in-memory bytes.
final class CatalogueCoverArtifactWriter {
  /// Creates one build-scoped writer over the previous publication record.
  CatalogueCoverArtifactWriter({
    required PublishArtifactSink? sink,
    required PreviousPublication previous,
  }) : _sink = sink,
       _previous = previous;

  final PublishArtifactSink? _sink;
  final PreviousPublication _previous;
  final _consumed = <String, PublishFile>{};
  var _coversRead = 0;
  var _coversReused = 0;

  /// Produced covers counted before their bytes were released.
  int get coversRead => _coversRead;

  /// Reused covers counted from their original decisions.
  int get coversReused => _coversReused;

  /// Metadata already written for [path], used during final assembly.
  PublishFile? operator [](String path) => _consumed[path];

  /// Releases assembly metadata after the section has been built.
  void clear() => _consumed.clear();

  /// Counts and consumes one decision, returning its byte-less successor.
  Future<Either<Failure, CoverDecision>> write(CoverDecision decision) async {
    if (decision.bytes != null) _coversRead++;
    if (decision.reuseSha != null) _coversReused++;
    final sink = _sink;
    if (sink == null || decision.bytes == null) return Right(decision);

    final path = decision.publishPath;
    final sha = decision.gitSha;
    final bytes = decision.bytes!;
    if (path != null && sha != null) {
      final file = PublishFile(
        path: path,
        bytes: bytes,
        gitSha: sha,
        upload: _previous.shaFor(path) != sha,
      );
      final written = await writePublishArtifact(sink: sink, file: file);
      if (written case Left(value: final failure)) return Left(failure);
      _consumed[path] = written.toNullable()!;
    }
    return Right(
      CoverDecision(
        publishPath: decision.publishPath,
        gitSha: decision.gitSha,
        reuseSha: decision.reuseSha,
        publishedCoverUrl: decision.publishedCoverUrl,
        source: decision.source,
      ),
    );
  }
}
