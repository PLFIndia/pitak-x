/// How much free storage and available memory this device has
/// (core/platform, backup rework BR9).
///
/// Why this exists (beginner note): before a backup and before a restore
/// the app says what the run needs and what the phone has (decision D5).
/// Only the native side can ask the phone, so a one-method [MethodChannel]
/// passes the answer on. The app only SHOWS these figures; it never refuses
/// to start because of them.
///
/// Same seam pattern as `app_info.dart`: an injectable interface, a
/// channel-backed implementation, and fail-safe degradation. When the
/// native side is absent (tests, desktop, iOS) or fails, the answer is
/// "unknown", and the notice says that it could not read the figure.
///
/// What crosses the channel is treated as untrusted, like every other
/// boundary (AGENTS.md §6.5): each value is checked on its own, and a value
/// of the wrong kind makes THAT figure unknown, not the others.
///
/// Privacy: the figures are read on the device, shown once, and never
/// stored, logged or sent. Dart sends nothing over the channel.
library;

import 'package:flutter/services.dart';
import 'package:pitaka/core/platform/app_log.dart';

/// What the device said about its storage and memory. Every field is null
/// when it could not be read.
final class DeviceResourceFacts {
  /// Creates the facts; a field that is left out is unknown.
  const DeviceResourceFacts({
    this.freeStorageBytes,
    this.availableMemoryBytes,
    this.lowMemoryThresholdBytes,
    this.lowMemory,
  });

  /// Nothing could be read.
  static const DeviceResourceFacts unknown = DeviceResourceFacts();

  /// Bytes that are free for apps on the file system the app's own files
  /// are on (Android: `StatFs.getAvailableBytes()`).
  final int? freeStorageBytes;

  /// Memory the system has available (Android:
  /// `ActivityManager.MemoryInfo.availMem`).
  final int? availableMemoryBytes;

  /// The mark of available memory below which the system calls memory low
  /// (Android: `MemoryInfo.threshold`).
  final int? lowMemoryThresholdBytes;

  /// Whether the system says it is low on memory right now (Android:
  /// `MemoryInfo.lowMemory`).
  final bool? lowMemory;
}

/// Reads the device's free storage and available memory.
// One method on purpose: the port has one job.
// ignore: one_member_abstracts
abstract interface class DeviceResources {
  /// The figures, each null when it could not be read. An implementation
  /// answers [DeviceResourceFacts.unknown] instead of failing.
  Future<DeviceResourceFacts> read();
}

/// [DeviceResources] backed by the narrow `dev.khoj.pitaka/device_resources`
/// channel (`DeviceResourcesChannel.kt`).
final class MethodChannelDeviceResources implements DeviceResources {
  /// Creates the channel-backed implementation.
  const MethodChannelDeviceResources();

  /// The single method-channel name shared with the native side.
  static const MethodChannel _channel = MethodChannel(
    'dev.khoj.pitaka/device_resources',
  );

  @override
  Future<DeviceResourceFacts> read() async {
    final Object? answer;
    try {
      // No argument on purpose: the native side decides what it reads.
      answer = await _channel.invokeMethod<Object?>('read');
    } on MissingPluginException {
      // No native handler (non-Android/tests): expected, means "unknown".
      return DeviceResourceFacts.unknown;
    } on PlatformException catch (e) {
      // A handler exists but failed. Debug builds log the error CODE only
      // (release builds log nothing); the notice then says "could not be
      // read", which is always safe: it never blocks anything.
      appLog('device_resources: read failed: ${e.code}');
      return DeviceResourceFacts.unknown;
    }
    if (answer is! Map) return DeviceResourceFacts.unknown;
    final lowMemory = answer['lowMemory'];
    return DeviceResourceFacts(
      freeStorageBytes: _size(answer['freeStorageBytes']),
      availableMemoryBytes: _size(answer['availableMemoryBytes']),
      lowMemoryThresholdBytes: _size(answer['lowMemoryThresholdBytes']),
      lowMemory: lowMemory is bool ? lowMemory : null,
    );
  }

  /// A size as the channel may send it: a whole number that is not
  /// negative. Anything else is "unknown".
  static int? _size(Object? value) => value is int && value >= 0 ? value : null;
}
