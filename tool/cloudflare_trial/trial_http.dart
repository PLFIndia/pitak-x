/// The trial's Cloudflare API client (Cloudflare plan Part L.1/R20/R21).
///
/// Deliberately small and strict, because the trial's job is to prove the
/// contract, not to be convenient:
///  - one fixed origin (`https://api.cloudflare.com/client/v4`);
///  - redirects are NEVER followed (a 3xx is recorded, not chased);
///  - the response body is streamed with a hard byte cap and cancelled past it;
///  - only whitelisted headers are kept, and no raw body text is ever exposed
///    to the report;
///  - a 429 honours `retry-after` once, a 5xx is retried a bounded number of
///    times, and nothing else is retried.
///
/// The token lives in this object for the process lifetime (ADR 0007's accepted
/// `String` exception) and is never printed, logged or put in an exception.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';

/// One API response, reduced to what the trial may look at.
final class TrialResponse {
  /// Creates a response.
  const TrialResponse({
    required this.status,
    required this.bytes,
    required this.headers,
    required this.elapsed,
    this.json,
    this.overCap = false,
    this.errorLabel,
  });

  /// HTTP status (0 when the request never completed).
  final int status;

  /// Bytes read from the body.
  final int bytes;

  /// Whitelisted response headers, lower-case names.
  final Map<String, String> headers;

  /// Wall-clock time for the request.
  final Duration elapsed;

  /// The decoded JSON envelope, or null when the body was not JSON.
  final Map<String, Object?>? json;

  /// True when the body exceeded the cap and was cancelled.
  final bool overCap;

  /// A fixed label for a transport failure (`network`, `timeout`, `http`).
  final String? errorLabel;

  /// True when the request completed with a 2xx status.
  bool get ok => status >= 200 && status < 300;

  /// The `success` flag of a Cloudflare envelope, when present.
  bool? get success {
    final value = json?['success'];
    return value is bool ? value : null;
  }

  /// The `result` object of a Cloudflare envelope, when present.
  Map<String, Object?>? get result {
    final value = json?['result'];
    return value is Map<String, Object?> ? value : null;
  }

  /// The `result` LIST of a Cloudflare envelope (the accounts endpoint), when
  /// present.
  List<Object?>? get resultList {
    final value = json?['result'];
    return value is List ? value : null;
  }

  /// The `result_info` object (pagination), when present.
  Map<String, Object?>? get resultInfo {
    final value = json?['result_info'];
    return value is Map<String, Object?> ? value : null;
  }

  /// The numeric error codes of a Cloudflare envelope (never the messages).
  List<int> get errorCodes {
    final errors = json?['errors'];
    if (errors is! List) return const [];
    return [
      for (final error in errors)
        if (error is Map && error['code'] is int) error['code'] as int,
    ];
  }

  /// A short, safe description for the report.
  String get label {
    final parts = <String>['status=$status'];
    if (overCap) parts.add('over-cap');
    if (errorLabel != null) parts.add('error=$errorLabel');
    if (errorCodes.isNotEmpty) parts.add('codes=${errorCodes.join(',')}');
    return parts.join(' ');
  }
}

/// The trial's API client.
final class TrialHttp {
  /// Creates a client over [token].
  TrialHttp({
    required String token,
    required String userAgent,
    Future<HttpClientRequest> Function(String method, Uri uri)? openUrl,
  }) : _token = token,
       _userAgent = userAgent,
       _openUrl = openUrl {
    _client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  }

  final String _token;
  final String _userAgent;

  /// Test seam for transport failures; production always uses [_client].
  final Future<HttpClientRequest> Function(String method, Uri uri)? _openUrl;
  late final HttpClient _client;

  /// Sends one request to the fixed API origin.
  ///
  /// [path] is appended to [CloudflareLimits.apiBase] and must start with `/`.
  /// [bearer] overrides the API token (the bucket upload uses the upload JWT).
  Future<TrialResponse> send({
    required String method,
    required String path,
    Object? jsonBody,
    List<int>? body,
    String? contentType,
    String? bearer,
    Duration deadline = CloudflareLimits.apiDeadline,
    bool retry = false,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      final response = await _attempt(
        method: method,
        path: path,
        jsonBody: jsonBody,
        body: body,
        contentType: contentType,
        bearer: bearer,
        deadline: deadline,
      );
      if (!retry || attempt >= CloudflareLimits.maxAttempts) return response;
      final wait = _retryDelay(response, attempt);
      if (wait == null) return response;
      await Future<void>.delayed(wait);
    }
  }

  /// Releases the underlying connections.
  void close() => _client.close(force: true);

  Future<TrialResponse> _attempt({
    required String method,
    required String path,
    required Object? jsonBody,
    required List<int>? body,
    required String? contentType,
    required String? bearer,
    required Duration deadline,
  }) async {
    final watch = Stopwatch()..start();
    final uri = Uri.parse('${CloudflareLimits.apiBase}$path');
    HttpClientRequest? request;
    try {
      final opened =
          await (_openUrl?.call(method, uri) ?? _client.openUrl(method, uri))
              .timeout(deadline);
      request = opened
        ..followRedirects = false
        ..headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${bearer ?? _token}',
        )
        ..headers.set(HttpHeaders.userAgentHeader, _userAgent)
        ..headers.set(HttpHeaders.acceptHeader, 'application/json');
      final payload = jsonBody != null
          ? utf8.encode(jsonEncode(jsonBody))
          : body;
      if (payload != null) {
        opened
          ..headers.set(
            HttpHeaders.contentTypeHeader,
            contentType ?? 'application/json',
          )
          ..add(payload);
      }
      final response = await opened.close().timeout(deadline);
      final read = await _readCapped(response, deadline);
      watch.stop();
      return TrialResponse(
        status: response.statusCode,
        bytes: read.bytes,
        headers: _whitelisted(response.headers),
        elapsed: watch.elapsed,
        json: read.json,
        overCap: read.overCap,
      );
    } on TimeoutException {
      request?.abort();
      watch.stop();
      return TrialResponse(
        status: 0,
        bytes: 0,
        headers: const {},
        elapsed: watch.elapsed,
        errorLabel: 'timeout',
      );
    } on TlsException {
      request?.abort();
      watch.stop();
      return TrialResponse(
        status: 0,
        bytes: 0,
        headers: const {},
        elapsed: watch.elapsed,
        errorLabel: 'tls',
      );
    } on SocketException {
      watch.stop();
      return TrialResponse(
        status: 0,
        bytes: 0,
        headers: const {},
        elapsed: watch.elapsed,
        errorLabel: 'network',
      );
    } on HttpException {
      watch.stop();
      return TrialResponse(
        status: 0,
        bytes: 0,
        headers: const {},
        elapsed: watch.elapsed,
        errorLabel: 'http',
      );
    }
  }

  /// Reads the body with a hard cap; past it the stream is cancelled.
  Future<({int bytes, Map<String, Object?>? json, bool overCap})> _readCapped(
    HttpClientResponse response,
    Duration deadline,
  ) async {
    final buffer = <int>[];
    var overCap = false;
    await for (final chunk in response.timeout(deadline)) {
      buffer.addAll(chunk);
      if (buffer.length > CloudflareLimits.maxApiBodyBytes) {
        overCap = true;
        break; // cancels the subscription: the rest is never read
      }
    }
    if (overCap) {
      return (bytes: buffer.length, json: null, overCap: true);
    }
    Map<String, Object?>? decoded;
    try {
      final value = jsonDecode(utf8.decode(buffer));
      if (value is Map<String, Object?>) decoded = value;
    } on FormatException {
      // A non-JSON body is recorded as "no envelope", never echoed.
      decoded = null;
    }
    return (bytes: buffer.length, json: decoded, overCap: false);
  }

  /// The wait before a retry, or null when this response is final.
  static Duration? _retryDelay(TrialResponse response, int attempt) {
    if (response.status == 429) {
      final raw = response.headers['retry-after'];
      final seconds = int.tryParse(raw ?? '');
      if (seconds == null || seconds < 0) return const Duration(seconds: 1);
      final capped = seconds > CloudflareLimits.maxRetryAfter.inSeconds
          ? CloudflareLimits.maxRetryAfter.inSeconds
          : seconds;
      return Duration(seconds: capped);
    }
    if (response.status >= 500) return Duration(seconds: attempt);
    return null;
  }

  static Map<String, String> _whitelisted(HttpHeaders headers) {
    const names = <String>[
      'content-type',
      'cache-control',
      'access-control-allow-origin',
      'cf-cache-status',
      'location',
      'retry-after',
      'content-length',
    ];
    final kept = <String, String>{};
    for (final name in names) {
      final value = headers.value(name);
      if (value != null) kept[name] = value;
    }
    return kept;
  }
}
