import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/domain/bundle_cover_files.dart';

/// Deterministic file-boundary failures/pauses over the real file store.
final class ControlledBundleFiles implements BundleCoverFiles {
  ControlledBundleFiles(this.delegate);
  final BundleCoverFiles delegate;
  final Set<String> failures = {};
  Future<void> Function()? afterStage;
  int stages = 0;
  bool committed = false;
  bool rolledBack = false;
  late BundleCoverBatch batch;

  @override
  BundleCoverBatch begin() => batch = _Batch(this, delegate.begin());
}

class _Batch implements BundleCoverBatch {
  _Batch(this.owner, this.delegate);
  final ControlledBundleFiles owner;
  final BundleCoverBatch delegate;
  static const failure = StorageFailure('synthetic file failure');

  @override
  Future<Either<Failure, String>> stage(
    String sourceLeaf,
    Uint8List bytes,
  ) async {
    owner.stages++;
    final result = await delegate.stage(sourceLeaf, bytes);
    await owner.afterStage?.call();
    if (owner.failures.contains('throw')) throw StateError('synthetic error');
    return owner.failures.contains('stage') ? left(failure) : result;
  }

  @override
  Future<Either<Failure, Unit>> retainOnly(Set<String> refs) async =>
      owner.failures.contains('retain')
      ? left(failure)
      : delegate.retainOnly(refs);

  @override
  Future<Either<Failure, Unit>> rollback() async {
    owner.rolledBack = true;
    return owner.failures.contains('rollback')
        ? left(failure)
        : delegate.rollback();
  }

  @override
  void commit() {
    owner.committed = true;
    delegate.commit();
  }
}
