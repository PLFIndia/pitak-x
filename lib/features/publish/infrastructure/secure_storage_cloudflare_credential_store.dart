/// `flutter_secure_storage`-backed Cloudflare whole-connection store (R18).
///
/// The single `cf_connection` value is treated as secret in full. JSON is
/// bounded and validated before a record is rebuilt from value objects; no
/// stored URL is accepted as an independent publish target.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/security/hardened_secure_storage.dart';
import 'package:pitaka/core/text/json_nesting_depth.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_token.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_connection.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_credential_store.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';

/// Production hardened secure-storage adapter.
final class SecureStorageCloudflareCredentialStore
    implements CloudflareCredentialStore {
  /// Uses the same hardened options as every other credential store.
  SecureStorageCloudflareCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? hardenedSecureStorage();

  final FlutterSecureStorage _storage;

  /// The only key read or written by this adapter.
  static const String key = 'cf_connection';
  static const int _schema = 1;
  static const int _maxRecordLength = 16 * 1024;

  @override
  Future<Either<Failure, CloudflareConnection?>> read() async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null) return right(null);
      if (raw.isEmpty || raw.length > _maxRecordLength) {
        return left(const StorageFailure('cloudflare connection record'));
      }
      if (JsonNestingDepth.maxDepthOf(raw) > CloudflareLimits.maxJsonDepth) {
        return left(const StorageFailure('cloudflare connection record'));
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded.length > 16 ||
          decoded['schema'] != _schema) {
        return left(const StorageFailure('cloudflare connection record'));
      }
      final expiresText = _optionalString(decoded['expiresOn'], 64);
      final expires = expiresText == null
          ? null
          : DateTime.tryParse(expiresText)?.toUtc();
      if (expiresText != null && expires == null) {
        return left(const StorageFailure('cloudflare connection record'));
      }
      final connection = CloudflareConnection.tryCreate(
        token: CloudflareApiToken.tryParse(
          _optionalString(decoded['token'], CloudflareApiToken.maxLength),
        ),
        tokenExpiresOn: expires,
        accountId: CloudflareAccountId.tryParse(
          _optionalString(decoded['accountId'], CloudflareAccountId.length),
        ),
        accountName: _optionalString(decoded['accountName'], 256),
        accountSubdomain: CloudflareSubdomain.tryParse(
          _optionalString(
            decoded['accountSubdomain'],
            CloudflareSubdomain.maxLength,
          ),
        ),
        workerName: CloudflareWorkerName.tryParse(
          _optionalString(
            decoded['workerName'],
            CloudflareWorkerName.maxLength,
          ),
        ),
        verifiedWorkerName: CloudflareWorkerName.tryParse(
          _optionalString(
            decoded['verifiedWorkerName'],
            CloudflareWorkerName.maxLength,
          ),
        ),
        addressConfirmed: decoded['addressConfirmed'] == true,
        workersWriteConfirmed: decoded['workersWriteConfirmed'] == true,
      );
      if (connection == null ||
          decoded['addressConfirmed'] is! bool ||
          decoded['workersWriteConfirmed'] is! bool) {
        return left(const StorageFailure('cloudflare connection record'));
      }
      return right(connection);
    } on Exception {
      // Never copy the secure value or platform error into a failure.
      return left(const StorageFailure('cloudflare connection read'));
    }
  }

  @override
  Future<Either<Failure, Unit>> save(CloudflareConnection connection) async {
    try {
      final encoded = connection.useToken(
        (token) => token.use(
          (secret) => jsonEncode({
            'schema': _schema,
            'token': secret,
            if (connection.tokenExpiresOn case final expiry?)
              'expiresOn': expiry.toUtc().toIso8601String(),
            if (connection.accountId case final account?)
              'accountId': account.value,
            if (connection.accountName case final name?) 'accountName': name,
            if (connection.accountSubdomain case final subdomain?)
              'accountSubdomain': subdomain.value,
            if (connection.workerName case final worker?)
              'workerName': worker.value,
            if (connection.verifiedWorkerName case final worker?)
              'verifiedWorkerName': worker.value,
            'addressConfirmed': connection.addressConfirmed,
            'workersWriteConfirmed': connection.workersWriteConfirmed,
          }),
        ),
      );
      await _storage.write(key: key, value: encoded);
      return right(unit);
    } on Exception {
      return left(const StorageFailure('cloudflare connection write'));
    }
  }

  @override
  Future<Either<Failure, Unit>> clear() async {
    try {
      await _storage.delete(key: key);
      return right(unit);
    } on Exception {
      return left(const StorageFailure('cloudflare connection clear'));
    }
  }

  static String? _optionalString(Object? value, int maxLength) {
    if (value == null) return null;
    if (value is! String || value.isEmpty || value.length > maxLength) {
      throw const FormatException('invalid Cloudflare connection field');
    }
    return value;
  }
}
