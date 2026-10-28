/// Host-specific artifact consumption during section building (R24).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/site/publish_file.dart';

/// Receives each built file immediately instead of retaining a whole-site copy.
///
/// GitHub keeps the original in-memory `PublishFile.bytes`. Cloudflare installs
/// a spool sink: after a successful write the builder returns only path/hash/
/// upload metadata, so covers and posters are not all retained in heap at once.
// A one-method injected seam for host-specific artifact consumption.
// ignore: one_member_abstracts
abstract interface class PublishArtifactSink {
  /// Persists or otherwise consumes one built public artifact.
  Future<Either<Failure, Unit>> write(PublishFile file);
}
