import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/paced_body.dart';
import '../support/slow_loopback_server.dart';

void main() {
  group('SlowLoopbackServer', () {
    test(
      'readSlowly stops at the byte limit and leaves the rest unread',
      () async {
        final server = await SlowLoopbackServer.start();
        addTearDown(server.close);
        final read = Completer<int>();
        server.handle((request) async {
          read.complete(
            await SlowLoopbackServer.readSlowly(request, stopAfterBytes: 8192),
          );
          // Deliberately no response: the client must see a stalled upload.
        });

        final client = HttpClient();
        addTearDown(client.close);
        final request = await client.postUrl(server.apiBase.resolve('/upload'))
          ..contentLength = 256 * 1024
          ..add(List<int>.filled(256 * 1024, 1));
        // Never await close(): the server never answers, which is the point.
        unawaited(request.close().then((_) {}, onError: (Object _) {}));

        expect(await read.future.timeout(const Duration(seconds: 5)), 8192);
      },
    );

    test('readSlowly drains the whole body when no limit is set', () async {
      final server = await SlowLoopbackServer.start();
      addTearDown(server.close);
      final read = Completer<int>();
      server.handle((request) async {
        read.complete(await SlowLoopbackServer.readSlowly(request));
        await SlowLoopbackServer.replyJson(request, result: const {'ok': true});
      });

      final client = HttpClient();
      addTearDown(client.close);
      const total = 1024 * 1024;
      final request = await client.postUrl(server.apiBase.resolve('/upload'))
        ..contentLength = total
        ..add(List<int>.filled(total, 1));
      final response = await request.close();
      expect(response.statusCode, 200);
      await response.drain<void>();
      expect(await read.future.timeout(const Duration(seconds: 5)), total);
    });
  });

  group('pacedBody', () {
    test('emits one chunk per tick under a fake clock', () {
      fakeAsync((async) {
        final received = <int>[];
        final subscription = pacedBody(
          totalBytes: 12,
          chunkBytes: 4,
          pause: const Duration(seconds: 1),
        ).listen(received.addAll);
        async.elapse(const Duration(milliseconds: 3500));
        expect(received.length, 12);
        expect(received, everyElement(0x41));
        subscription.cancel();
      });
    });

    test('no bytes arrive before the first tick', () {
      fakeAsync((async) {
        var bytes = 0;
        final subscription = pacedBody(
          totalBytes: 8,
          chunkBytes: 8,
          pause: const Duration(seconds: 1),
        ).listen((chunk) => bytes += chunk.length);
        async.flushMicrotasks();
        expect(bytes, 0);
        async.elapse(const Duration(seconds: 1));
        expect(bytes, 8);
        subscription.cancel();
      });
    });

    test('refuses a meaningless pause or chunk size', () {
      expect(
        () => pacedBody(totalBytes: 1, pause: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => pacedBody(
          totalBytes: 1,
          chunkBytes: 0,
          pause: const Duration(seconds: 1),
        ),
        throwsArgumentError,
      );
    });
  });
}
