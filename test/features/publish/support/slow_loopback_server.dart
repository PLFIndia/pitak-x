/// A real loopback HTTP server for socket-level upload tests.
///
/// The unit tests use fakes, but a fake socket cannot prove what happens when
/// the network stops draining. These tests bind a real server on 127.0.0.1 and
/// control exactly how much of a request body is read and how fast.
///
/// Nothing here touches a remote host: every address is loopback.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// One loopback server with explicit body-reading control.
final class SlowLoopbackServer {
  SlowLoopbackServer._(this._server);

  final HttpServer _server;

  /// Starts a server on an ephemeral loopback port.
  static Future<SlowLoopbackServer> start() async => SlowLoopbackServer._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
  );

  /// The ephemeral port actually bound.
  int get port => _server.port;

  /// The API base a `CloudflareHttpTransport` should target in a test.
  Uri get apiBase => Uri.parse('http://127.0.0.1:$port/client/v4');

  /// Serves every request with [handler]. A handler that throws because the
  /// client aborted is ignored: aborting is the behaviour under test.
  void handle(Future<void> Function(HttpRequest request) handler) {
    _server.listen((request) {
      unawaited(
        handler(request).catchError((Object _) {
          // The client closing mid-request is expected in these tests.
        }),
      );
    });
  }

  /// Stops the server and closes any connection it still holds.
  Future<void> close() => _server.close(force: true);

  /// Reads [request]'s body in [chunkBytes] pieces, pausing [pause] between
  /// pieces, and returns once [stopAfterBytes] were read.
  ///
  /// Returning early leaves the rest of the body unread on purpose: the socket
  /// stays open, the client's send buffer fills, and no progress is reported.
  /// That is how a stalled mobile upload is modelled without a real network.
  static Future<int> readSlowly(
    HttpRequest request, {
    int chunkBytes = 64 * 1024,
    Duration pause = Duration.zero,
    int? stopAfterBytes,
  }) async {
    var total = 0;
    await for (final chunk in request) {
      for (var offset = 0; offset < chunk.length; offset += chunkBytes) {
        // Never read past the exact limit: the caller asserts the byte count.
        final room = stopAfterBytes == null
            ? chunkBytes
            : math.min(chunkBytes, stopAfterBytes - total);
        final end = math.min(offset + room, chunk.length);
        if (end <= offset) return total;
        total += end - offset;
        if (stopAfterBytes != null && total >= stopAfterBytes) return total;
        if (pause > Duration.zero) await Future<void>.delayed(pause);
      }
    }
    return total;
  }

  /// Writes one minimal Cloudflare envelope and closes the response.
  static Future<void> replyJson(
    HttpRequest request, {
    int status = 200,
    Object? result,
  }) async {
    final succeeded = status >= 200 && status < 300;
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode({
          'success': succeeded,
          'errors': const <Object?>[],
          'messages': const <Object?>[],
          'result': result,
        }),
      );
    await request.response.close();
  }
}
