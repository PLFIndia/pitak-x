/// Fixed-origin, bounded and retrying HTTP transport for Cloudflare adapters.
///
/// One transport serves both role adapters. Tokens arrive per call and are
/// never fields. Every attempt gets a fresh request and a fresh
/// [TimeoutHttpClient] decorator configured with the request's
/// [CloudflareRequestTiming] and a 1 MiB response cap.
///
/// Uploads are bounded by progress, not by one wall-clock number (fix-plan
/// H2): the request body has an idle timer, the total follows the body size,
/// and an attempt that already sent more than
/// [CloudflareLimits.blindResendMaxBytes] is never blindly re-sent.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:pitaka/core/network/app_user_agent.dart';
import 'package:pitaka/core/network/timeout_http_client.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_http_response.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_json.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_request_timing.dart';

export 'package:pitaka/features/publish/infrastructure/cloudflare_http_response.dart';
export 'package:pitaka/features/publish/infrastructure/cloudflare_request_timing.dart';

/// Builds a fresh request for one attempt. Multipart bodies are single-use, so
/// retries must invoke this factory again rather than re-sending a request.
typedef CloudflareRequestBuilder = http.BaseRequest Function(Uri uri);

/// The shared Cloudflare HTTP transport.
final class CloudflareHttpTransport {
  /// Creates a transport. [apiBase] is a test seam; the production facade uses
  /// the fixed [CloudflareLimits.apiBase] and exposes no origin parameter.
  CloudflareHttpTransport({
    http.Client? client,
    Uri? apiBase,
    Future<void> Function(Duration delay)? sleep,
  }) : _injectedClient = client,
       _apiBase = apiBase ?? Uri.parse(CloudflareLimits.apiBase),
       _sleep = sleep ?? Future<void>.delayed;

  final http.Client? _injectedClient;
  final Uri _apiBase;
  final Future<void> Function(Duration delay) _sleep;
  http.Client? _nativeClient;

  /// The fixed connect timeout for the one native client.
  ///
  /// Keyed by a CONSTANT, never by the operation deadline (fix-plan N14):
  /// size-derived upload deadlines would otherwise create one connection pool
  /// per distinct value, each with a connect timeout of minutes. 30 s is the
  /// ordinary API deadline, which is the only phase this timeout bounds.
  static const Duration _connectTimeout = CloudflareLimits.apiDeadline;

  /// Returns THE client whose NATIVE connect timeout bounds `openUrl`.
  ///
  /// package:http installs its Abortable listener only AFTER openUrl completes.
  /// HttpClient.connectionTimeout therefore provides the missing pre-request
  /// bound; TimeoutHttpClient still aborts the later request/body phases.
  ///
  /// One client is enough because the key is the fixed [_connectTimeout], not
  /// the operation deadline (fix-plan N14): a per-deadline pool would grow
  /// with every size-derived upload deadline and hold connections open.
  http.Client _client() =>
      _injectedClient ??
      (_nativeClient ??= IOClient(
        HttpClient()..connectionTimeout = _connectTimeout,
      ));

  /// Closes every native client and any injected shared client. Per-attempt
  /// decorators are not closed separately because they own no connections.
  void close() {
    _injectedClient?.close();
    _nativeClient?.close();
    _nativeClient = null;
  }

  /// Sends one logical operation.
  ///
  /// Reads and idempotent hash uploads retry network failures, 429 and 5xx at
  /// most three times. A non-idempotent write repeats only after [recover]
  /// re-reads remote state and returns false ("retry"). True means the desired
  /// state already exists and returns null; null means stop without repeating.
  Future<CloudflareHttpResponse?> send({
    required String path,
    required String bearer,
    required CloudflareRequestBuilder requestBuilder,
    Map<String, String>? queryParameters,
    CloudflareRequestTiming timing = CloudflareRequestTiming.api,
    bool idempotent = true,
    bool statusOnly = false,
    Future<bool?> Function()? recover,
  }) async {
    var attempt = 0;
    var retriedRateLimit = false;
    // One resend is allowed after a large body hit a 5xx/429 (H2 step 4).
    var largeBodyResends = 0;
    while (true) {
      attempt++;
      var bytesSent = 0;
      try {
        final response = await _open(
          path: path,
          bearer: bearer,
          requestBuilder: requestBuilder,
          queryParameters: queryParameters,
          timing: timing,
          onBodyProgress: (sent) => bytesSent = sent,
        );
        final status = response.statusCode;
        if (status >= 300 && status < 400) {
          _discard(response);
          throw CloudflareApiException(
            CloudflareApiExceptionKind.redirect,
            statusCode: status,
            uncertain: !idempotent,
          );
        }
        if (statusOnly && ((status >= 200 && status < 300) || status == 404)) {
          _discard(response);
          return CloudflareHttpResponse.statusOnly(status);
        }

        final largeBodySent =
            timing.observesRequestBody &&
            bytesSent > CloudflareLimits.blindResendMaxBytes;
        final retryableStatus = status == 429 || status >= 500;
        final mayRetryStatus =
            retryableStatus &&
            attempt < CloudflareLimits.maxAttempts &&
            (status != 429 || !retriedRateLimit) &&
            (!largeBodySent || largeBodyResends < 1) &&
            (idempotent || recover != null);
        if (mayRetryStatus) {
          _discard(response);
          if (status == 429) retriedRateLimit = true;
          if (largeBodySent) largeBodyResends++;
          if (idempotent) {
            await _sleep(_retryDelay(response, attempt));
            continue;
          }
          final decision = await recover!();
          if (decision != null) {
            if (decision) return null;
            await _sleep(_retryDelay(response, attempt));
            continue;
          }
          throw CloudflareApiException(
            status == 429
                ? CloudflareApiExceptionKind.rateLimited
                : CloudflareApiExceptionKind.server,
            statusCode: status,
            uncertain: true,
          );
        }
        return await _parse(response, uncertain: !idempotent);
      } on CloudflareApiException catch (error) {
        // These are never retried: the bytes changed locally, the session is
        // out of time, or re-sending a large body is worse than asking.
        if (_neverRetried(error.kind)) rethrow;
        // A failed large upload is not re-sent from byte 0 (H2 step 4): the
        // user would spend the data twice with no better chance.
        if (timing.observesRequestBody &&
            bytesSent > CloudflareLimits.blindResendMaxBytes &&
            error.kind == CloudflareApiExceptionKind.timeout) {
          throw CloudflareApiException(
            CloudflareApiExceptionKind.uploadStalled,
            statusCode: error.statusCode,
          );
        }
        final retryableError =
            error.kind == CloudflareApiExceptionKind.network ||
            error.kind == CloudflareApiExceptionKind.timeout ||
            error.uncertain;
        if (!retryableError ||
            attempt >= CloudflareLimits.maxAttempts ||
            (!idempotent && recover == null)) {
          rethrow;
        }
        if (idempotent) {
          // Parsing/size/redirect refusals are deterministic, not transient.
          if (error.kind != CloudflareApiExceptionKind.network &&
              error.kind != CloudflareApiExceptionKind.timeout) {
            rethrow;
          }
          await _sleep(Duration(seconds: attempt));
          continue;
        }
        final decision = await recover!();
        if (decision != null) {
          if (decision) return null;
          await _sleep(Duration(seconds: attempt));
          continue;
        }
        rethrow;
      }
    }
  }

  Future<http.StreamedResponse> _open({
    required String path,
    required String bearer,
    required CloudflareRequestBuilder requestBuilder,
    required Map<String, String>? queryParameters,
    required CloudflareRequestTiming timing,
    required void Function(int sent) onBodyProgress,
  }) async {
    final uri = _apiBase.replace(
      path: '${_apiBase.path}$path',
      queryParameters: queryParameters,
    );
    final http.BaseRequest request;
    try {
      request = requestBuilder(uri)
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers.addAll({
          'Authorization': 'Bearer $bearer',
          'Accept': 'application/json',
          'User-Agent': AppUserAgent.value,
        });
    } on CloudflareJsonException {
      throw CloudflareApiException(CloudflareApiExceptionKind.invalidRequest);
    }
    // N13: any body over 256 KiB — including a ~1.6 MB upload-session
    // manifest — uses the upload profile. Without this the derived total
    // would not apply to an ordinary JSON call that still moves real bytes.
    final contentLength = request.contentLength;
    final effective =
        !timing.observesRequestBody &&
            contentLength != null &&
            contentLength > CloudflareLimits.largeBodyBytes
        ? const CloudflareRequestTiming.upload()
        : timing;
    final bounded = TimeoutHttpClient(
      _client(),
      timeout: effective.connect,
      totalDeadline: effective.resolveTotal(contentLength),
      requestBodyIdleTimeout: effective.idle,
      responseHeadersTimeout: effective.responseWait,
      onRequestBodyProgress: effective.observesRequestBody
          ? onBodyProgress
          : null,
      maxResponseBytes: CloudflareLimits.maxApiBodyBytes,
    );
    try {
      return await bounded.send(request);
    } on http.ClientException catch (error) {
      throw _transportException(
        error,
        uncertain: request.method != 'GET',
        upload: effective.observesRequestBody,
      );
    } on CloudflareByteSourceException {
      // A spool file vanished or changed while it streamed (fix-plan L8).
      throw CloudflareApiException(CloudflareApiExceptionKind.artifactChanged);
    } on CloudflareAssetHashException {
      // The bytes on this device no longer hash to what Cloudflare accepted,
      // so another attempt would send different content (fix-plan L8).
      throw CloudflareApiException(CloudflareApiExceptionKind.artifactChanged);
    } on CloudflareJsonException {
      // The upload stream re-checks each hash and the base64 chunk cap.
      throw CloudflareApiException(CloudflareApiExceptionKind.artifactChanged);
    } on Exception {
      throw CloudflareApiException(
        CloudflareApiExceptionKind.network,
        uncertain: request.method != 'GET',
      );
    }
  }

  Future<CloudflareHttpResponse> _parse(
    http.StreamedResponse response, {
    required bool uncertain,
  }) async {
    try {
      final declared = response.contentLength;
      if (declared != null && declared > CloudflareLimits.maxApiBodyBytes) {
        _discard(response);
        throw CloudflareApiException(
          CloudflareApiExceptionKind.responseTooLarge,
          statusCode: response.statusCode,
          uncertain: uncertain,
        );
      }
      final bytes = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in response.stream) {
        total += chunk.length;
        if (total > CloudflareLimits.maxApiBodyBytes) {
          throw CloudflareApiException(
            CloudflareApiExceptionKind.responseTooLarge,
            statusCode: response.statusCode,
            uncertain: uncertain,
          );
        }
        bytes.add(chunk);
      }
      try {
        return CloudflareHttpResponse(
          statusCode: response.statusCode,
          envelope: decodeCloudflareEnvelope(bytes.takeBytes()),
        );
      } on CloudflareJsonException {
        // L8: classify by STATUS first. Cloudflare's edge serves an HTML page
        // for a 5xx or a second 429, so a non-JSON body there is a server /
        // rate-limit answer, not "unreadable". A non-JSON 4xx stays
        // malformed, because setup's 403 branch must not act on an HTML page.
        final status = response.statusCode;
        if (status == 429 || status >= 500) {
          return CloudflareHttpResponse.statusOnly(status);
        }
        throw CloudflareApiException(
          CloudflareApiExceptionKind.malformedResponse,
          statusCode: status,
          uncertain: uncertain,
        );
      }
    } on http.ClientException catch (error) {
      throw _transportException(error, uncertain: uncertain, upload: false);
    }
  }

  /// True for failure kinds that must never be attempted again.
  static bool _neverRetried(CloudflareApiExceptionKind kind) =>
      kind == CloudflareApiExceptionKind.uploadStalled ||
      kind == CloudflareApiExceptionKind.uploadTooSlow ||
      kind == CloudflareApiExceptionKind.artifactChanged;

  static CloudflareApiException _transportException(
    http.ClientException error, {
    required bool uncertain,
    required bool upload,
  }) {
    // Inspect only our own fixed wrapper messages to classify the failure. The
    // original text and URI are never copied into the public exception.
    final message = error.message;
    if (message.startsWith('Response exceeded')) {
      return CloudflareApiException(
        CloudflareApiExceptionKind.responseTooLarge,
        uncertain: uncertain,
      );
    }
    if (message.startsWith('Upload stalled')) {
      return CloudflareApiException(
        CloudflareApiExceptionKind.timeout,
        uncertain: uncertain,
      );
    }
    if (message.startsWith('Request exceeded')) {
      // An upload that ran out of its size-derived total is too slow, not
      // "dead": retrying would spend the same data again (fix-plan H2).
      return CloudflareApiException(
        upload
            ? CloudflareApiExceptionKind.uploadTooSlow
            : CloudflareApiExceptionKind.timeout,
        uncertain: uncertain,
      );
    }
    if (message.startsWith('Request timed out') ||
        message.startsWith('Response stalled') ||
        message.startsWith('Response headers timed out')) {
      return CloudflareApiException(
        CloudflareApiExceptionKind.timeout,
        uncertain: uncertain,
      );
    }
    return CloudflareApiException(
      CloudflareApiExceptionKind.network,
      uncertain: uncertain,
    );
  }

  static Duration _retryDelay(http.StreamedResponse response, int attempt) {
    if (response.statusCode == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '');
      if (seconds == null || seconds < 0) return const Duration(seconds: 1);
      return Duration(
        seconds: seconds > CloudflareLimits.maxRetryAfter.inSeconds
            ? CloudflareLimits.maxRetryAfter.inSeconds
            : seconds,
      );
    }
    return Duration(seconds: attempt);
  }

  static void _discard(http.StreamedResponse response) {
    // Cancelling closes the socket; draining would read an untrusted body.
    unawaited(response.stream.listen(null).cancel().catchError((_) {}));
  }
}

/// Builds a JSON request. A null [body] sends no body and no JSON content type.
CloudflareRequestBuilder cloudflareJsonRequest(String method, Object? body) =>
    (uri) {
      final request = http.Request(method, uri);
      if (body != null) {
        request
          ..headers['Content-Type'] = 'application/json'
          ..bodyBytes = utf8.encode(jsonEncode(body));
      }
      return request;
    };

/// Runs local request validation and redacts any rejected value.
T parseCloudflareInput<T>(T Function() parse) {
  try {
    return parse();
  } on CloudflareJsonException {
    throw CloudflareApiException(CloudflareApiExceptionKind.invalidRequest);
  }
}

/// Async counterpart of [parseCloudflareInput] for streamed source validation.
Future<T> parseCloudflareInputAsync<T>(Future<T> Function() parse) async {
  try {
    return await parse();
  } on CloudflareJsonException {
    throw CloudflareApiException(CloudflareApiExceptionKind.invalidRequest);
  }
}

/// Runs an endpoint-specific bounded parser and redacts any shape refusal.
T parseCloudflareResponse<T>(T Function() parse) {
  try {
    return parse();
  } on CloudflareJsonException {
    throw CloudflareApiException(CloudflareApiExceptionKind.malformedResponse);
  }
}
