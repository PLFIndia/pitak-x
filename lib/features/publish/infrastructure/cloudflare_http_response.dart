/// Bounded Cloudflare response value and its fixed failure mapping.
///
/// Extracted from `cloudflare_http_transport.dart` (fix-plan Phase 0.6) so the
/// transport can grow its upload timing profiles while the response contract
/// stays small and reviewable. No raw envelope, message or URL is retained:
/// only the status, the whitelisted `result`, and numeric error codes.
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_json.dart';

/// A bounded Cloudflare response reduced to safe, whitelisted fields.
final class CloudflareHttpResponse {
  /// Creates a parsed response.
  CloudflareHttpResponse({
    required this.statusCode,
    required Map<String, dynamic> envelope,
  }) : _success = envelope['success'] == true,
       result = envelope['success'] == true ? envelope['result'] : null,
       errorCodes = cloudflareErrorCodes(envelope);

  /// Creates a status-only Worker-existence response.
  CloudflareHttpResponse.statusOnly(this.statusCode)
    : _success = false,
      result = null,
      errorCodes = const [];

  /// HTTP status, retained as a number only.
  final int statusCode;

  final bool _success;

  /// The `result` field of a successful envelope. Error results, raw `errors`
  /// messages and top-level `messages` are discarded immediately.
  final Object? result;

  /// Numeric Cloudflare error codes only; never raw error messages.
  final List<int> errorCodes;

  /// True only for 2xx plus an explicit `success: true` envelope.
  bool get isSuccess => statusCode >= 200 && statusCode < 300 && _success;
}

/// Converts a non-success response into a fixed, redacted adapter failure.
CloudflareApiException cloudflareFailure(
  CloudflareHttpResponse response, {
  bool uncertain = false,
}) {
  final status = response.statusCode;
  final kind = switch (status) {
    401 => CloudflareApiExceptionKind.unauthorized,
    403 => CloudflareApiExceptionKind.forbidden,
    404 => CloudflareApiExceptionKind.notFound,
    429 => CloudflareApiExceptionKind.rateLimited,
    >= 500 => CloudflareApiExceptionKind.server,
    _ => CloudflareApiExceptionKind.requestRejected,
  };
  return CloudflareApiException(
    kind,
    statusCode: status,
    errorCodes: response.errorCodes,
    uncertain: uncertain || status >= 500,
  );
}

/// Returns [response] after requiring 2xx and `success: true`.
CloudflareHttpResponse requireCloudflareSuccess(
  CloudflareHttpResponse response, {
  bool uncertain = false,
}) {
  if (!response.isSuccess) {
    throw cloudflareFailure(response, uncertain: uncertain);
  }
  return response;
}
