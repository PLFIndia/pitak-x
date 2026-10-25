import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/library/application/form_cover_controller.dart';
import 'package:pitaka/features/library/presentation/widgets/form_cover_field.dart';

import '../../support/cover_capture_fakes.dart';

void main() {
  Widget app(
    CoverCaptureFakes fakes,
    List<String?> changes, {
    List<bool>? busyChanges,
  }) {
    return ProviderScope(
      overrides: [
        coversDirProvider.overrideWith((ref) async => '.'),
        formCoverControllerProvider.overrideWith(() => fakes.controller),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Cover')),
                    body: FormCoverField(
                      title: 'Chess set',
                      coverRef: null,
                      onChanged: changes.add,
                      onBusyChanged: busyChanges?.add ?? (_) {},
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openField(
    WidgetTester tester,
    CoverCaptureFakes fakes,
    List<String?> changes, {
    List<bool>? busyChanges,
  }) async {
    await tester.pumpWidget(app(fakes, changes, busyChanges: busyChanges));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('popping while the picker is pending stops before crop and a '
      'disposed provider read', (tester) async {
    final fakes = installCoverCaptureFakes();
    final changes = <String?>[];
    final busyChanges = <bool>[];
    await openField(tester, fakes, changes, busyChanges: busyChanges);
    await tester.tap(find.text('Add cover'));
    await tester.pump();
    await fakes.pickerGate.entered;

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    fakes
      ..finishCropper()
      ..finishPicker();
    await tester.pump();
    await tester.pump();

    expect(fakes.cropper.calls, 0);
    expect(fakes.controller.calls, 0);
    expect(changes, isEmpty);
    expect(busyChanges, [true], reason: 'no late busy callback after disposal');
    expect(tester.takeException(), isNull);
  });

  testWidgets('popping while storage is pending drops the late result', (
    tester,
  ) async {
    final fakes = installCoverCaptureFakes();
    final changes = <String?>[];
    final busyChanges = <bool>[];
    await openField(tester, fakes, changes, busyChanges: busyChanges);
    await tester.tap(find.text('Add cover'));
    await tester.pump();
    await fakes.pickerGate.entered;
    fakes.finishPicker();
    await tester.pump();
    await fakes.cropperGate.entered;
    fakes.finishCropper();
    await tester.pump();
    await fakes.storeGate.entered;

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    fakes.finishStore('covers/late.jpg');
    await tester.pumpAndSettle();

    expect(fakes.controller.calls, 1);
    expect(changes, isEmpty);
    expect(busyChanges, [true], reason: 'no late busy callback after disposal');
    expect(tester.takeException(), isNull);
  });
}
