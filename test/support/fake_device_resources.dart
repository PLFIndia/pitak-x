import 'package:pitaka/core/platform/device_resources.dart';

/// A [DeviceResources] for tests: answers [facts], or throws [failure]
/// when one is set. Counts how often it was asked.
///
/// The default is a phone with plenty of everything, so that a test which
/// is not about the notice gets the verdict "enough".
final class FakeDeviceResources implements DeviceResources {
  /// Creates the fake.
  FakeDeviceResources({this.facts = plenty, this.failure});

  /// 64 GB of free storage, 4 GB of memory, a low mark of 256 MB.
  static const DeviceResourceFacts plenty = DeviceResourceFacts(
    freeStorageBytes: 64 * 1024 * 1024 * 1024,
    availableMemoryBytes: 4 * 1024 * 1024 * 1024,
    lowMemoryThresholdBytes: 256 * 1024 * 1024,
    lowMemory: false,
  );

  /// What [read] answers.
  DeviceResourceFacts facts;

  /// When set, [read] throws this instead of answering.
  Object? failure;

  /// How many times [read] was called.
  int reads = 0;

  @override
  Future<DeviceResourceFacts> read() async {
    reads++;
    final failure = this.failure;
    // A test fake throws whatever the test asks for.
    // ignore: only_throw_errors
    if (failure != null) throw failure;
    return facts;
  }
}
