/// Fixed-origin, bounded and retrying HTTP transport for Cloudflare adapters.
///
/// One transport serves both role adapters. Tokens arrive per call and are
/// never fields. Every attempt gets a fresh request and a fresh
/// [TimeoutHttpClient]
/// decorator configured with Cloudflare's own deadline and 1 MiB response cap.
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
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_http_response.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_json.dart';

export 'package:pitaka/features/publish/infrastructure/cloudflare_http_response.dart';

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
    Duration deadline = CloudflareLimits.apiDeadline,
    bool idempotent = true,
    bool statusOnly = false,
    Future<bool?> Function()? recover,
  }) async {
    var attempt = 0;
    var retriedRateLimit = false;
    while (true) {
      attempt++;
      try {
        final response = await _open(
          path: path,
          bearer: bearer,
          requestBuilder: requestBuilder,
          queryParameters: queryParameters,
          deadline: deadline,
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

        final retryableStatus = status == 429 || status >= 500;
        final mayRetryStatus =
            retryableStatus &&
            attempt < CloudflareLimits.maxAttempts &&
            (status != 429 || !retriedRateLimit) &&
            (idempotent || recover != null);
        if (mayRetryStatus) {
          _discard(response);
          if (status == 429) retriedRateLimit = true;
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
    required Duration deadline,
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
    final bounded = TimeoutHttpClient(
      _client(),
      timeout: deadline,
      totalDeadline: deadline,
      maxResponseBytes: CloudflareLimits.maxApiBodyBytes,
    );
    try {
      return await bounded.send(request);
    } on http.ClientException catch (error) {
      throw _transportException(error, uncertain: request.method != 'GET');
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
        throw CloudflareApiException(
          CloudflareApiExceptionKind.malformedResponse,
          statusCode: response.statusCode,
          uncertain: uncertain,
        );
      }
    } on http.ClientException catch (error) {
      throw _transportException(error, uncertain: uncertain);
    }
  }

  static CloudflareApiException _transportException(
    http.ClientException error, {
    required bool uncertain,
  }) {
    // Inspect only our own fixed wrapper messages to classify the failure. The
    // original text and URI are never copied into the public exception.
    final message = error.message;
    final kind = message.startsWith('Response exceeded')
        ? CloudflareApiExceptionKind.responseTooLarge
        : message.startsWith('Request timed out') ||
              message.startsWith('Request exceeded') ||
              message.startsWith('Response stalled')
        ? CloudflareApiExceptionKind.timeout
        : CloudflareApiExceptionKind.network;
    return CloudflareApiException(kind, uncertain: uncertain);
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
