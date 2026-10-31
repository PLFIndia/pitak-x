/// Secure whole-record storage for the Cloudflare connection (R18).
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';

/// Persists the token and its optional setup/target fields as ONE record.
///
/// There are no partial setters: replacing a token or target cannot leave a
/// second key behind to be paired with stale state. Corrupt data and platform
/// failures are typed failures, never a silent signed-out result.
abstract interface class CloudflareCredentialStore {
  /// Reads the record, or null when no record exists.
  Future<Either<Failure, CloudflareConnection?>> read();

  /// Replaces the complete record in one secure-storage write.
  Future<Either<Failure, Unit>> save(CloudflareConnection connection);

  /// Forgets the complete connection. Public manifests and the host journal are
  /// deliberately outside this port and are not cleared by disconnect.
  Future<Either<Failure, Unit>> clear();
}
