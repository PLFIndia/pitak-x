import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/app_settings_opener.dart';

/// Review finding P4-M8, decision D131: the Dart side of the channel that
/// opens Pitak's page of the phone's settings. Android is played by a mock
/// handler on the method channel.
///
/// What these tests guard:
///  - Dart sends nothing: which page is opened is decided on the Android
///    side alone;
///  - only a plain `true` counts as "opened"; a missing or failing Android
///    side, and any other answer, is "not opened", never an error;
///  - where the app does not run on Android the way is "not available",
///    and nothing is sent at all;
///  - nothing but an error CODE is ever logged.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.khoj.pitaka/app_settings');
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

  const onAndroid = MethodChannelAppSettingsOpener(onAndroid: true);
  const elsewhere = MethodChannelAppSettingsOpener(onAndroid: false);

  group('on Android', () {
    test('the way is available', () {
      expect(onAndroid.isAvailable, isTrue);
    });

    test('calls "open" once and sends nothing', () async {
      android((_) => true);

      await onAndroid.open();

      expect(calls, hasLength(1));
      expect(calls.single.method, 'open');
      expect(calls.single.arguments, isNull);
    });

    test('Android says it opened the page: opened', () async {
      android((_) => true);

      expect(await onAndroid.open(), isTrue);
      expect(printed, isEmpty);
    });

    test('Android says it could not: not opened', () async {
      android((_) => false);

      expect(await onAndroid.open(), isFalse);
      expect(printed, isEmpty);
    });

    test('an answer that is not a plain true: not opened', () async {
      for (final answer in <Object?>[
        null,
        'true',
        1,
        [true],
        {'opened': true},
      ]) {
        android((_) => answer);

        expect(await onAndroid.open(), isFalse, reason: '$answer');
      }
    });

    test('no handler on the Android side: not opened, nothing '
        'logged', () async {
      // No handler is set: the call ends in a MissingPluginException.
      expect(await onAndroid.open(), isFalse);
      expect(printed, isEmpty);
    });

    test('an Android side that fails: not opened, and only the error '
        'code is logged', () async {
      android(
        (_) => throw PlatformException(
          code: 'boom',
          message: 'no activity for package:dev.khoj.pitaka',
          details: '/data/user/0/dev.khoj.pitaka',
        ),
      );

      expect(await onAndroid.open(), isFalse);
      expect(printed, ['app_settings: open failed: boom']);
    });
  });

  group('where the app does not run on Android', () {
    test('the way is not available', () {
      expect(elsewhere.isAvailable, isFalse);
    });

    test('open answers "not opened" and sends nothing, even if something '
        'would answer', () async {
      android((_) => true);

      expect(await elsewhere.open(), isFalse);
      expect(calls, isEmpty);
    });
  });

  group('the provider', () {
    test('hands out the channel-backed port', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(appSettingsOpenerProvider),
        isA<MethodChannelAppSettingsOpener>(),
      );
    });

    test('on a machine that is not an Android phone (this test run) the '
        'way is not available', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(appSettingsOpenerProvider).isAvailable, isFalse);
    });

    test('on Android the way is available', () {
      final container = ProviderContainer(
        overrides: [runsOnAndroidProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);

      expect(container.read(appSettingsOpenerProvider).isAvailable, isTrue);
    });
  });
}
