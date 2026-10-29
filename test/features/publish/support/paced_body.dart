/// A request/response body that emits on timers, so `fakeAsync` paces it.
///
/// Upload-progress rules are about time: "no bytes for 60 s" and "64 KiB/s
/// sustained". A real wait would make those tests slow and flaky, so the body
/// is emitted by one timer tick per chunk. Under `fakeAsync` the tick only
/// happens when the test advances the clock, which makes a stall and a slow
/// drain exact.
library;

import 'dart:async';
import 'dart:math' as math;

/// Emits [totalBytes] in [chunkBytes] pieces, one piece per [pause].
///
/// The first piece arrives on the first tick, not on listen. A negative or
/// zero [pause] would make the tick meaningless, so it is asserted here rather
/// than silently producing an empty stream.
Stream<List<int>> pacedBody({
  required int totalBytes,
  required Duration pause,
  int chunkBytes = 64 * 1024,
  int fillByte = 0x41,
}) {
  if (chunkBytes <= 0) {
    throw ArgumentError.value(chunkBytes, 'chunkBytes', 'must be positive');
  }
  if (pause <= Duration.zero) {
    throw ArgumentError.value(pause, 'pause', 'must be positive');
  }
  final controller = StreamController<List<int>>();
  Timer? timer;
  var sent = 0;
  controller
    ..onListen = () {
      timer = Timer.periodic(pause, (tick) {
        if (sent >= totalBytes) {
          tick.cancel();
          unawaited(controller.close());
          return;
        }
        final size = math.min(chunkBytes, totalBytes - sent);
        sent += size;
        controller.add(List<int>.filled(size, fillByte));
      });
    }
    ..onCancel = () {
      timer?.cancel();
    };
  return controller.stream;
}
