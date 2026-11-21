import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/device_resources.dart';

/// BR9: the Dart side of the channel that says how much free storage and
/// available memory the device has. Android is played by a mock handler on
/// the method channel.
///
/// What these tests guard:
///  - Dart sends nothing;
///  - a missing or failing Android side is "unknown", never an error;
///  - every value of the answer is checked on its own: a value of the wrong
///    kind makes that one figure unknown and leaves the others;
///  - no figure is ever logged.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.khoj.pitaka/device_resources');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late List<String> printed;
  late DebugPrintCallback originalDebugPrint;

  setUp(() {
    calls = <MethodCall>[];
    printed = <String>[];
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      printed.add(message ?? '');
    };
  });

  tearDown(() {
    debugPrint = originalDebugPrint;
    messenger.setMockMethodCallHandler(channel, null);
  });

  /// Android answers every call with [answer] (a value, or it throws).
  void android(Object? Function(MethodCall call) answer) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return answer(call);
    });
  }

  const resources = MethodChannelDeviceResources();

  const good = <String, Object?>{
    'freeStorageBytes': 12345678901,
    'availableMemoryBytes': 2000000000,
    'lowMemoryThresholdBytes': 300000000,
    'lowMemory': true,
  };

  void expectUnknown(DeviceResourceFacts facts) {
    expect(facts.freeStorageBytes, isNull);
    expect(facts.availableMemoryBytes, isNull);
    expect(facts.lowMemoryThresholdBytes, isNull);
    expect(facts.lowMemory, isNull);
  }

  test('calls "read" once and sends nothing', () async {
    android((_) => good);

    await resources.read();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'read');
    expect(calls.single.arguments, isNull);
  });

  test('a full answer is passed on, figure by figure', () async {
    android((_) => good);

    final facts = await resources.read();

    expect(facts.freeStorageBytes, 12345678901);
    expect(facts.availableMemoryBytes, 2000000000);
    expect(facts.lowMemoryThresholdBytes, 300000000);
    expect(facts.lowMemory, isTrue);
  });

  test('a size of 0 is a reading, not "unknown"', () async {
    android((_) => {...good, 'freeStorageBytes': 0});

    expect((await resources.read()).freeStorageBytes, 0);
  });

  test('no Android side (desktop, tests): everything unknown', () async {
    // No handler is set: the call ends in a MissingPluginException.
    expectUnknown(await resources.read());
    expect(printed, isEmpty);
  });

  test('an Android side that fails: everything unknown, and only the '
      'error code is logged', () async {
    android(
      (_) => throw PlatformException(
        code: 'boom',
        message: 'free 12345678901 at /data/user/0/dev.khoj.pitaka',
        details: '/data/user/0/dev.khoj.pitaka/files',
      ),
    );

    expectUnknown(await resources.read());

    expect(printed, ['device_resources: read failed: boom']);
  });

  test('an answer that is not a map: everything unknown', () async {
    for (final answer in <Object?>[
      null,
      12345,
      'plenty',
      [1, 2, 3],
      true,
    ]) {
      android((_) => answer);

      expectUnknown(await resources.read());
    }
  });

  test('an empty map: everything unknown', () async {
    android((_) => <String, Object?>{});

    expectUnknown(await resources.read());
  });

  // Each figure is checked on its own.
  for (final key in [
    'freeStorageBytes',
    'availableMemoryBytes',
    'lowMemoryThresholdBytes',
  ]) {
    int? sizeOf(DeviceResourceFacts facts) => switch (key) {
      'freeStorageBytes' => facts.freeStorageBytes,
      'availableMemoryBytes' => facts.availableMemoryBytes,
      _ => facts.lowMemoryThresholdBytes,
    };

    for (final (label, bad) in <(String, Object?)>[
      ('missing', null),
      ('negative', -1),
      ('a text', '12345'),
      ('a fraction', 123.0),
      ('a flag', true),
      ('a list', [1]),
    ]) {
      test('$key is $label: that figure is unknown, the others stay', () async {
        final answer = {...good}..remove(key);
        if (bad != null) answer[key] = bad;
        android((_) => answer);

        final facts = await resources.read();

        expect(sizeOf(facts), isNull);
        // The flag is always among "the others".
        expect(facts.lowMemory, isTrue);
        final others = [
          facts.freeStorageBytes,
          facts.availableMemoryBytes,
          facts.lowMemoryThresholdBytes,
        ].whereType<int>();
        expect(others, hasLength(2));
      });
    }
  }

  for (final (label, bad) in <(String, Object?)>[
    ('missing', null),
    ('a number', 1),
    ('a text', 'true'),
  ]) {
    test('lowMemory is $label: the flag is unknown, the sizes stay', () async {
      final answer = {...good}..remove('lowMemory');
      if (bad != null) answer['lowMemory'] = bad;
      android((_) => answer);

      final facts = await resources.read();

      expect(facts.lowMemory, isNull);
      expect(facts.freeStorageBytes, 12345678901);
      expect(facts.availableMemoryBytes, 2000000000);
      expect(facts.lowMemoryThresholdBytes, 300000000);
    });
  }

  test('a good answer logs nothing', () async {
    android((_) => good);

    await resources.read();

    expect(printed, isEmpty);
  });

  test('the provider hands out the channel-backed port', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(deviceResourcesProvider),
      isA<MethodChannelDeviceResources>(),
    );
  });
}
