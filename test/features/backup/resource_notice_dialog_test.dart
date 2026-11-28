/// Widget tests of the notice before a backup and before a restore (backup
/// rework BR9, decisions D5, D49, D51).
///
/// The dialog is opened from a plain button and stands on the REAL
/// providers of the notice, with a fake device and a fake library size. So
/// what is proven here is the whole way from the figures to the screen.
///
/// What these tests guard:
///  - the dialog NEVER blocks: the button that starts the run is there and
///    works in every state (reading, read, unreadable) and for every
///    verdict;
///  - only an explicit tap on that button means "go on";
///  - the Restore dialog says that the library is replaced, the backup
///    dialog does not;
///  - nothing is printed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/device_resources.dart';
import 'package:pitaka/features/backup/application/resource_notice_providers.dart';
import 'package:pitaka/features/backup/domain/resource_notice.dart';
import 'package:pitaka/features/backup/presentation/resource_notice_messages.dart';
import 'package:pitaka/features/backup/presentation/widgets/resource_notice_dialog.dart';

import '../../support/a11y.dart';
import '../../support/fake_device_resources.dart';
import '../../support/fake_library_footprint_source.dart';

const int _mb = 1024 * 1024;
const int _gb = 1024 * _mb;

/// A device source whose answer waits until the test lets it go.
final class _HeldDeviceResources implements DeviceResources {
  final Completer<DeviceResourceFacts> answer = Completer();

  @override
  Future<DeviceResourceFacts> read() => answer.future;
}

void main() {
  late FakeDeviceResources device;
  late FakeLibraryFootprintSource library;

  /// What each closed dialog answered, in order.
  late List<bool> answers;

  setUp(() {
    device = FakeDeviceResources(
      facts: const DeviceResourceFacts(
        freeStorageBytes: 12 * _gb,
        availableMemoryBytes: 2355 * _mb,
        lowMemoryThresholdBytes: 300 * _mb,
        lowMemory: false,
      ),
    );
    // The fake's small library: a catalogue of 1 MB and covers of 8 MB.
    // 9 MB on disk, so a backup needs 18 MB.
    library = FakeLibraryFootprintSource();
    answers = <bool>[];
  });

  const archive = (
    takenBytes: 30 * _mb,
    databaseBytes: 2 * _mb,
    hasCovers: true,
    hasVault: true,
  );

  /// A page with one button that opens the dialog for [run].
  Widget host(
    ResourceNoticeRun run, {
    DeviceResources? deviceResources,
    List<Override> more = const [],
  }) => ProviderScope(
    overrides: [
      deviceResourcesProvider.overrideWithValue(deviceResources ?? device),
      libraryFootprintSourceProvider.overrideWithValue(library),
      ...more,
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                answers.add(
                  await ResourceNoticeDialog.ask(
                    context,
                    notice: switch (run) {
                      ResourceNoticeRun.backup => backupResourceNoticeProvider,
                      ResourceNoticeRun.restore =>
                        restoreResourceNoticeProvider(archive),
                    },
                    run: run,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder confirm() => find.byKey(ResourceNoticeDialog.confirmKey);
  Finder cancel() => find.byKey(ResourceNoticeDialog.cancelKey);

  bool confirmEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(confirm()).enabled;

  group('what it shows', () {
    testWidgets('a backup with plenty of room: both lines, "enough", and '
        'nothing about replacing', (tester) async {
      await tester.pumpWidget(host(ResourceNoticeRun.backup));
      await open(tester);

      expect(find.text('Before you create the backup'), findsOneWidget);
      expect(
        find.text(
          'Storage: this needs about 18.0 MB. This phone has 12.0 GB free.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Memory: this needs about 100.0 MB. 2.3 GB are available right '
          'now.',
        ),
        findsOneWidget,
      );
      expect(find.text('That is enough.'), findsOneWidget);
      expect(find.text(resourceNoticeReplacesLibraryMessage), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Go on'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('a restore: says that the library is replaced, and its '
        'button says "Restore" (D49, D51)', (tester) async {
      await tester.pumpWidget(host(ResourceNoticeRun.restore));
      await open(tester);

      expect(find.text('Restore this backup?'), findsOneWidget);
      expect(find.text(resourceNoticeReplacesLibraryMessage), findsOneWidget);
      // 30 MB taken, 2 MB of databases once more, 1 MB of catalogue.
      expect(
        find.text(
          'Storage: this needs about 33.0 MB. This phone has 12.0 GB free.',
        ),
        findsOneWidget,
      );
      expect(find.text('That is enough.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Restore'), findsOneWidget);
      expect(find.text('Go on'), findsNothing);
    });

    testWidgets('the sentence about replacing comes before the figures', (
      tester,
    ) async {
      await tester.pumpWidget(host(ResourceNoticeRun.restore));
      await open(tester);

      final replaces = tester.getTopLeft(
        find.text(resourceNoticeReplacesLibraryMessage),
      );
      final storage = tester.getTopLeft(find.textContaining('Storage:'));
      expect(replaces.dy, lessThan(storage.dy));
    });
  });

  group('it never blocks (D5)', () {
    // With the fakes above a backup needs 18 MB and a restore 33 MB. The
    // free storage that gives each verdict for a need:
    int? freeFor(ResourceVerdict verdict, int need) => switch (verdict) {
      ResourceVerdict.enough => 12 * _gb,
      ResourceVerdict.tight => need,
      ResourceVerdict.notEnough => need - 1,
      ResourceVerdict.unknown => null,
    };
    const sentenceFor = <ResourceVerdict, String>{
      ResourceVerdict.enough: 'That is enough.',
      ResourceVerdict.tight: 'Storage is tight.',
      ResourceVerdict.notEnough: 'does not have enough free storage',
      ResourceVerdict.unknown: 'Pitak could not read this on this device',
    };

    for (final run in ResourceNoticeRun.values) {
      for (final verdict in ResourceVerdict.values) {
        testWidgets('${run.name}, storage ${verdict.name}: the verdict is '
            'said, and the run can be started', (tester) async {
          final need = run == ResourceNoticeRun.backup ? 18 * _mb : 33 * _mb;
          device.facts = DeviceResourceFacts(
            freeStorageBytes: freeFor(verdict, need),
            availableMemoryBytes: 2355 * _mb,
            lowMemoryThresholdBytes: 300 * _mb,
            lowMemory: false,
          );
          await tester.pumpWidget(host(run));
          await open(tester);

          expect(find.textContaining(sentenceFor[verdict]!), findsOneWidget);
          expect(confirmEnabled(tester), isTrue);

          await tester.tap(confirm());
          await tester.pumpAndSettle();
          expect(answers, [true]);
        });
      }
    }

    testWidgets('memory that is short is said too, and still does not '
        'block', (tester) async {
      device.facts = const DeviceResourceFacts(
        freeStorageBytes: 12 * _gb,
        availableMemoryBytes: 50 * _mb,
        lowMemoryThresholdBytes: 300 * _mb,
        lowMemory: true,
      );
      await tester.pumpWidget(host(ResourceNoticeRun.backup));
      await open(tester);

      expect(
        find.textContaining('very little memory available right now'),
        findsOneWidget,
      );
      expect(
        find.text('If it fails, nothing is changed and no backup is made.'),
        findsOneWidget,
      );
      expect(confirmEnabled(tester), isTrue);
    });

    testWidgets('while the figures are still being read: "Checking…", and '
        'the run can already be started', (tester) async {
      final held = _HeldDeviceResources();
      await tester.pumpWidget(
        host(ResourceNoticeRun.backup, deviceResources: held),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Checking this phone…'), findsOneWidget);
      expect(find.textContaining('Storage:'), findsNothing);
      expect(confirmEnabled(tester), isTrue);

      await tester.tap(confirm());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(answers, [true]);

      // The read ends after the dialog is gone: nobody listens, no error.
      held.answer.complete(DeviceResourceFacts.unknown);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the figures arrive while the dialog is open: it fills in', (
      tester,
    ) async {
      final held = _HeldDeviceResources();
      await tester.pumpWidget(
        host(ResourceNoticeRun.backup, deviceResources: held),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      expect(find.text('Checking this phone…'), findsOneWidget);

      held.answer.complete(FakeDeviceResources.plenty);
      await tester.pumpAndSettle();

      expect(find.text('Checking this phone…'), findsNothing);
      expect(find.text('That is enough.'), findsOneWidget);
    });

    testWidgets('a notice that fails altogether: says it could not read, '
        'and the run can be started', (tester) async {
      await tester.pumpWidget(
        host(
          ResourceNoticeRun.restore,
          more: [
            restoreResourceNoticeProvider(archive).overrideWith(
              (ref) async => throw StateError('free 123 at /data/user/0/x'),
            ),
          ],
        ),
      );
      await open(tester);

      expect(find.text(resourceNoticeUnknownMessage), findsOneWidget);
      expect(
        find.text('If it fails, your library stays exactly as it is.'),
        findsOneWidget,
      );
      // Nothing of the error reaches the screen.
      expect(find.textContaining('/data/'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
      expect(confirmEnabled(tester), isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('the answer', () {
    testWidgets('the button that starts the run answers yes', (tester) async {
      await tester.pumpWidget(host(ResourceNoticeRun.backup));
      await open(tester);
      await tester.tap(confirm());
      await tester.pumpAndSettle();

      expect(answers, [true]);
      expect(find.byType(ResourceNoticeDialog), findsNothing);
    });

    testWidgets('Cancel answers no', (tester) async {
      await tester.pumpWidget(host(ResourceNoticeRun.restore));
      await open(tester);
      await tester.tap(cancel());
      await tester.pumpAndSettle();

      expect(answers, [false]);
    });

    testWidgets('a tap outside the dialog answers no', (tester) async {
      await tester.pumpWidget(host(ResourceNoticeRun.restore));
      await open(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(answers, [false]);
    });

    testWidgets('the Back key answers no', (tester) async {
      await tester.pumpWidget(host(ResourceNoticeRun.restore));
      await open(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(answers, [false]);
    });
  });

  testWidgets('the figures are read anew each time the dialog opens', (
    tester,
  ) async {
    await tester.pumpWidget(host(ResourceNoticeRun.backup));
    await open(tester);
    await tester.tap(cancel());
    await tester.pumpAndSettle();
    expect(device.reads, 1);

    device.facts = const DeviceResourceFacts(
      freeStorageBytes: 17 * _mb,
      availableMemoryBytes: 2355 * _mb,
      lowMemoryThresholdBytes: 300 * _mb,
      lowMemory: false,
    );
    await open(tester);

    expect(device.reads, 2);
    expect(library.reads, 2);
    expect(
      find.textContaining('does not have enough free storage'),
      findsOneWidget,
    );
  });

  testWidgets('with a very large font the buttons stay on the screen', (
    tester,
  ) async {
    // A small phone and the largest font setting and more: the sentences
    // are then far taller than the screen.
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    device.facts = const DeviceResourceFacts(
      freeStorageBytes: 17 * _mb,
      availableMemoryBytes: 50 * _mb,
      lowMemoryThresholdBytes: 300 * _mb,
      lowMemory: true,
    );

    await tester.pumpWidget(host(ResourceNoticeRun.restore));
    await open(tester);

    expect(tester.takeException(), isNull, reason: 'no overflow');
    // Both buttons can be hit where they are drawn.
    expect(confirm().hitTestable(), findsOneWidget);
    expect(cancel().hitTestable(), findsOneWidget);
    await tester.tap(confirm());
    await tester.pumpAndSettle();
    expect(answers, [true]);
  });

  testWidgets('nothing is printed, whatever the dialog shows', (tester) async {
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      printed.add(message ?? '');
    };
    addTearDown(() => debugPrint = original);
    device.failure = StateError('free 12345 at /data/user/0/x');

    await tester.pumpWidget(host(ResourceNoticeRun.restore));
    await open(tester);
    await tester.tap(confirm());
    await tester.pumpAndSettle();
    debugPrint = original;

    expect(printed, isEmpty);
    expect(answers, [true]);
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    await tester.pumpWidget(host(ResourceNoticeRun.restore));
    await open(tester);

    await expectMeetsA11yGuidelines(tester);
  });
}
