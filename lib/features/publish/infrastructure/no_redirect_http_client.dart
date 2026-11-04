/// Redirect-refusing HTTP client policy for fixed-origin APIs.
library;

import 'package:http/http.dart' as http;
import 'package:pitaka/core/platform/app_log.dart';

/// Refuses every redirect instead of forwarding credentials to another host.
final class NoRedirectHttpClient extends http.BaseClient {
  /// Wraps one inner client; every request inherits the same policy.
  NoRedirectHttpClient(this._inner);

  final http.Client _inner;

  /// Fixed refusal text; it never names a URL or response detail.
  static const String refusal = 'GitHub answered with a redirect';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Some clients honor only one of these two switches, so set both.
    request
      ..followRedirects = false
      ..maxRedirects = 0;
    final response = await _inner.send(request);
    if (response.statusCode >= 300 && response.statusCode <= 399) {
      // Abandon the body unread. Cancelling closes the connection instead of
      // buffering a hostile payload; the fixed refusal below is the answer.
      try {
        await response.stream.listen(null).cancel();
      } on Object catch (error) {
        appLog('GitHub redirect body not cancelled: ${error.runtimeType}');
      }
      throw http.ClientException(refusal);
    }
    return response;
  }

  @override
  void close() => _inner.close();
}
