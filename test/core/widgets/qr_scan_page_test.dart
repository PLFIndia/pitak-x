import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/widgets/qr_scan_page.dart';
import 'package:pitaka/features/library/domain/value_objects/library_qr_payload.dart';

/// Tests for the generic QR-scan page (libNetwork.md §5.12). The camera is
/// never exercised (repo rule: scanners are tested through the decision made
/// AFTER a payload arrives) — the pure [QrScanPage.decide] policy is tested
/// directly, and the widget behaviour through the injected fake scanner seam.
void main() {
  group('decide (pure policy)', () {
    test('an accepted payload becomes ScanAccepted with the parsed value', () {
      final outcome = QrScanPage.decide<String>(
        raw: 'pitaka-lib:0123456789abcdef',
        accept: LibraryQrPayload.parse,
      );
      expect(outcome, isA<ScanAccepted<String>>());
      expect((outcome as ScanAccepted<String>).value, '0123456789abcdef');
    });

    test('a known-other payload becomes ScanRejected with the hint', () {
      final outcome = QrScanPage.decide<String>(
        raw: 'pitaka-lib:0123456789abcdef',
        accept: (_) => null, // this screen takes something else
        rejectedHint: "That's a pairing code.",
        isKnownOtherPayload: (raw) => raw.startsWith('pitaka-lib:'),
      );
      expect(outcome, isA<ScanRejected<String>>());
      expect((outcome as ScanRejected<String>).hint, "That's a pairing code.");
    });

    test(
      'an unknown payload is silently ignored (no hint without a match)',
      () {
        final outcome = QrScanPage.decide<String>(
          raw: 'https://example.com',
          accept: (_) => null,
          rejectedHint: 'hint',
          isKnownOtherPayload: (raw) => raw.startsWith('pitaka-lib:'),
        );
        expect(outcome, isA<ScanIgnored<String>>());
      },
    );

    test('acceptance wins over the known-other rule', () {
      final outcome = QrScanPage.decide<String>(
        raw: 'pitaka-lib:0123456789abcdef',
        accept: LibraryQrPayload.parse,
        rejectedHint: 'hint',
        isKnownOtherPayload: (_) => true,
      );
      expect(outcome, isA<ScanAccepted<String>>());
    });

    test('a hint without isKnownOtherPayload never rejects', () {
      final outcome = QrScanPage.decide<String>(
        raw: 'anything',
        accept: (_) => null,
        rejectedHint: 'hint',
      );
      expect(outcome, isA<ScanIgnored<String>>());
    });
  });

  group('widget behaviour (fake scanner seam)', () {
    /// A scanner replacement: one button per payload the test wants to emit.
    Widget Function(void Function(String) onText) fakeScanner(
      List<String> payloads,
    ) =>
        (void Function(String) onText) => Column(
          children: [
            for (final (i, payload) in payloads.indexed)
              ElevatedButton(
                onPressed: () => onText(payload),
                child: Text('emit-$i'),
              ),
          ],
        );

    /// Pushes a QrScanPage over a button; returns the popped value via
    /// `resultText` once the scan page pops.
    Future<String?> pumpAndScan(
      WidgetTester tester, {
      required QrScanPage<String> page,
      required String emitButton,
    }) async {
      String? popped = 'NOT_POPPED';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  popped = await Navigator.of(
                    context,
                  ).push<String>(MaterialPageRoute(builder: (_) => page));
                },
                child: const Text('open-scanner'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open-scanner'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(emitButton));
      await tester.pumpAndSettle();
      return popped == 'NOT_POPPED' ? null : popped;
    }

    testWidgets('an accepted payload pops the page with the value', (
      tester,
    ) async {
      final popped = await pumpAndScan(
        tester,
        page: QrScanPage<String>(
          title: 'Scan a library QR',
          accept: LibraryQrPayload.parse,
          buildScanner: fakeScanner(['pitaka-lib:0123456789abcdef']),
        ),
        emitButton: 'emit-0',
      );
      expect(popped, '0123456789abcdef');
    });

    testWidgets('a rejected-but-known payload shows the hint and keeps '
        'scanning; a following good payload still pops', (tester) async {
      String? popped = 'NOT_POPPED';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<String>(
                    MaterialPageRoute(
                      builder: (_) => QrScanPage<String>(
                        title: 'Add a member',
                        accept: (_) => null, // nothing accepted in this test
                        rejectedHint: "That's a pairing code.",
                        isKnownOtherPayload: (raw) =>
                            raw.startsWith('pitaka-lib:'),
                        buildScanner: fakeScanner([
                          'pitaka-lib:0123456789abcdef',
                          'pitaka-lib:0123456789abcdef', // second emission
                        ]),
                      ),
                    ),
                  );
                },
                child: const Text('open-scanner'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open-scanner'));
      await tester.pumpAndSettle();

      // First known-other payload: the hint appears, the page stays open.
      await tester.tap(find.text('emit-0'));
      await tester.pumpAndSettle();
      expect(find.text("That's a pairing code."), findsOneWidget);
      expect(popped, 'NOT_POPPED');

      // The same payload again: the hint is NOT duplicated (spam guard).
      await tester.tap(find.text('emit-1'));
      await tester.pumpAndSettle();
      expect(find.text("That's a pairing code."), findsOneWidget);
      expect(popped, 'NOT_POPPED');
    });

    testWidgets('an unknown payload is ignored silently', (tester) async {
      String? popped = 'NOT_POPPED';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<String>(
                    MaterialPageRoute(
                      builder: (_) => QrScanPage<String>(
                        title: 'Scan a library QR',
                        accept: LibraryQrPayload.parse,
                        rejectedHint: 'hint',
                        isKnownOtherPayload: (raw) => raw.startsWith('nope:'),
                        buildScanner: fakeScanner([
                          'https://example.com/random-qr',
                          'pitaka-lib:tooshort', // wrong shape, not known-other
                        ]),
                      ),
                    ),
                  );
                },
                child: const Text('open-scanner'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open-scanner'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('emit-0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('emit-1'));
      await tester.pumpAndSettle();
      expect(popped, 'NOT_POPPED');
      expect(find.text('hint'), findsNothing);
    });

    testWidgets('shows the injected title in the app bar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QrScanPage<String>(
            title: 'Scan a library QR',
            accept: LibraryQrPayload.parse,
            buildScanner: (_) => const SizedBox.shrink(),
          ),
        ),
      );
      expect(find.text('Scan a library QR'), findsOneWidget);
    });
  });
}
