import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/github_artifact_store.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';

/// In-memory [GitHubArtifactStore] for focused tests (review finding 6).
///
/// It keeps each written file's bytes in a map, so the commit writer's
/// per-file resolver and the move digest work exactly as they do over the
/// real temp-file spool, without any file IO.
final class MemoryGitHubArtifactStore implements GitHubArtifactStore {
  /// Every path written, in order (a repeated path appears again).
  final List<String> writes = [];

  /// How many times [dispose] ran.
  int disposals = 0;

  /// When set, [write] answers it and stores nothing.
  Failure? writeFailure;

  /// When set, [write] waits for it before answering (observes one-at-a-time
  /// consumption).
  Future<void> Function()? beforeWrite;

  /// When true, [write] throws instead of answering (the use case must still
  /// dispose the store).
  bool throwOnWrite = false;

  final Map<String, List<int>> _byPath = {};

  @override
  Future<Either<Failure, Unit>> write(PublishFile file) async {
    await beforeWrite?.call();
    if (throwOnWrite) throw StateError('synthetic spool failure');
    final failure = writeFailure;
    if (failure != null) return Left(failure);
    writes.add(file.path);
    _byPath[file.path] = List.of(file.bytes);
    return right(unit);
  }

  @override
  Future<List<int>?> read(String path) async {
    final bytes = _byPath[path];
    return bytes == null ? null : List.of(bytes);
  }

  @override
  Future<void> dispose() async {
    disposals++;
    _byPath.clear();
  }
}
