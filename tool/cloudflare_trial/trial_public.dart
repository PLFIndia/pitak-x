/// Unauthenticated public-site checks for the trial (Cloudflare plan T8/T10/
/// T11/T12/R16).
///
/// This client is deliberately separate from the API client: it never sends a
/// token, it never follows a redirect (a redirect is a RESULT to record, not
/// something to chase), and it caps the body. That is the same shape the
/// production read-back verifier has, so the trial measures the contract the
/// app will rely on.
library;

import 'dart:async';
import 'dart:io';

/// One public response, reduced to what the report may show.
final class PublicResponse {
  /// Creates a response.
  const PublicResponse({
    required this.status,
    required this.headers,
    required this.bytes,
    this.body = const [],
    this.errorLabel,
  });

  /// HTTP status (0 when the request never completed).
  final int status;

  /// Whitelisted headers, lower-case names.
  final Map<String, String> headers;

  /// Bytes read.
  final int bytes;

  /// The body, up to the caller's cap. Used ONLY to parse a small public file
  /// (the marker); never printed.
  final List<int> body;

  /// A fixed label for a transport failure.
  final String? errorLabel;

  /// True for a 2xx status.
  bool get ok => status >= 200 && status < 300;

  /// The `location` header of a redirect, when present.
  String? get location => headers['location'];

  /// A short, safe description for the report.
  String get label {
    final parts = <String>['status=$status'];
    final type = headers['content-type'];
    if (type != null) parts.add('type=$type');
    final cache = headers['cache-control'];
    if (cache != null) parts.add('cache=$cache');
    final cors = headers['access-control-allow-origin'];
    if (cors != null) parts.add('cors=$cors');
    if (errorLabel != null) parts.add('error=$errorLabel');
    return parts.join(' ');
  }
}

/// Fetches public URLs without credentials.
abstract final class TrialPublic {
  /// Fetches [uri] with a byte cap and an abortable deadline.
  static Future<PublicResponse> get(
    Uri uri, {
    int cap = 64 * 1024,
    Duration deadline = const Duration(seconds: 20),
  }) async {
    final client = HttpClient()..connectionTimeout = deadline;
    try {
      final request = await client.getUrl(uri).timeout(deadline);
      request
        ..followRedirects = false
        ..headers.set(HttpHeaders.userAgentHeader, 'pitak-trial');
      final response = await request.close().timeout(deadline);
      final body = <int>[];
      var overCap = false;
      await for (final chunk in response.timeout(deadline)) {
        body.addAll(chunk);
        if (body.length > cap) {
          overCap = true;
          break; // cancels the subscription
        }
      }
      return PublicResponse(
        status: response.statusCode,
        headers: _whitelisted(response.headers),
        bytes: body.length,
        body: overCap ? const [] : body,
      );
    } on TimeoutException {
      return const PublicResponse(
        status: 0,
        headers: {},
        bytes: 0,
        errorLabel: 'timeout',
      );
    } on SocketException {
      return const PublicResponse(
        status: 0,
        headers: {},
        bytes: 0,
        errorLabel: 'network',
      );
    } on HttpException {
      return const PublicResponse(
        status: 0,
        headers: {},
        bytes: 0,
        errorLabel: 'http',
      );
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, String> _whitelisted(HttpHeaders headers) {
    const names = <String>[
      'content-type',
      'cache-control',
      'access-control-allow-origin',
      'content-security-policy',
      'x-content-type-options',
      'referrer-policy',
      'location',
      'cf-cache-status',
    ];
    final kept = <String, String>{};
    for (final name in names) {
      final value = headers.value(name);
      if (value != null) kept[name] = value;
    }
    return kept;
  }
}
