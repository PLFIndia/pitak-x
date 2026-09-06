import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';

/// Creates operation-owned cover batches, isolated from existing images.
// Named domain port, matching Importer: infrastructure and test doubles must
// explicitly implement the same resource-ownership contract across DI.
// ignore: one_member_abstracts
abstract interface class BundleCoverFiles {
  /// Starts an in-memory ownership record; this does not write files.
  BundleCoverBatch begin();
}

/// A batch owns only newly created files; it cannot delete pre-existing covers.
/// This scoped resource keeps filesystem cleanup tied to the database result.
abstract interface class BundleCoverBatch {
  /// Fully writes new bytes under a fresh name, failing rather than clobbering.
  Future<Either<Failure, String>> stage(String sourceLeaf, Uint8List bytes);

  /// Removes staged files superseded by later rows, BEFORE the DB commits.
  Future<Either<Failure, Unit>> retainOnly(Set<String> references);

  /// Deletes only this batch's files after the database rolls back.
  Future<Either<Failure, Unit>> rollback();

  /// Relinquishes ownership after the OUTERMOST database commit. No file IO.
  void commit();
}
