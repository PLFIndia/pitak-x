// Adapted from synchronized's BasicLock.
// MIT License — Copyright (c) 2016, Alexandre Roux Tekartik.
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import 'dart:async';

/// Serializes import and cleanup, including the janitor's reference snapshot.
/// A shared FIFO prevents a sweep from deleting not-yet-committed images.
/// Adapted from synchronized 3.4.0+1 BasicLock (Tekartik, MIT), without
/// timeouts/reentrancy or a new dependency. Owned by DI, never a global lock.
final class CoverFileCoordinator {
  Future<void>? _tail;

  /// Runs one complete operation; callers must not recursively acquire this.
  Future<T> run<T>(Future<T> Function() action) async {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    try {
      if (previous != null) await previous;
      return await action();
    } finally {
      if (identical(_tail, released.future)) _tail = null;
      released.complete();
    }
  }
}
