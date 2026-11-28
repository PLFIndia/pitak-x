import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/widgets/bring_into_view.dart';

/// Decision D177: a page says what came of a tap under the button, and that
/// can lie below the screen. `bringResultIntoView` scrolls just far enough
/// for it to be read.
void main() {
  const screen = Size(400, 400);
  final resultKey = GlobalKey();
  final firstLineKey = GlobalKey();

  /// A page of [above] pixels of other things, then a result of
  /// [resultHeight] pixels whose first line is 20 pixels high.
  Future<void> pumpPage(
    WidgetTester tester, {
    required double above,
    required double resultHeight,
    bool noAnimations = false,
  }) async {
    tester.view
      ..physicalSize = screen
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: screen, disableAnimations: noAnimations),
          child: Scaffold(
            body: ListView(
              children: [
                SizedBox(height: above),
                Column(
                  key: resultKey,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(key: firstLineKey, height: 20),
                    SizedBox(height: resultHeight - 20),
                  ],
                ),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Rect rectOf(WidgetTester tester, GlobalKey key) =>
      tester.getRect(find.byKey(key));

  testWidgets('a result below the screen: its end comes onto the screen, and '
      'no further', (tester) async {
    await pumpPage(tester, above: 380, resultHeight: 100);
    expect(rectOf(tester, resultKey).bottom, greaterThan(screen.height));

    bringResultIntoView(result: resultKey, firstLine: firstLineKey);
    await tester.pump();
    await tester.pumpAndSettle();

    // Just far enough: the end of the result sits at the bottom edge.
    expect(rectOf(tester, resultKey).bottom, screen.height);
    expect(rectOf(tester, firstLineKey).top, greaterThanOrEqualTo(0));
  });

  testWidgets('a result taller than the screen: its first line wins', (
    tester,
  ) async {
    await pumpPage(tester, above: 380, resultHeight: 700);

    bringResultIntoView(result: resultKey, firstLine: firstLineKey);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(rectOf(tester, firstLineKey).top, 0);
  });

  testWidgets('a result that is in view already: nothing moves', (
    tester,
  ) async {
    await pumpPage(tester, above: 100, resultHeight: 100);
    final before = rectOf(tester, resultKey);

    bringResultIntoView(result: resultKey, firstLine: firstLineKey);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(rectOf(tester, resultKey), before);
  });

  testWidgets('the list moves over a moment, and at once on a phone that is '
      'set to show no animations', (tester) async {
    await pumpPage(tester, above: 380, resultHeight: 100);
    bringResultIntoView(result: resultKey, firstLine: firstLineKey);
    await tester.pump();
    // The first frame after the call starts the clock of the movement; the
    // second is 50 ms into it.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    // On its way: not where it began, and not there yet.
    final onTheWay = rectOf(tester, resultKey).bottom;
    expect(onTheWay, lessThan(480));
    expect(onTheWay, greaterThan(screen.height));
    await tester.pumpAndSettle();

    await pumpPage(tester, above: 381, resultHeight: 100, noAnimations: true);
    bringResultIntoView(result: resultKey, firstLine: firstLineKey);
    await tester.pump();
    await tester.pump();
    expect(rectOf(tester, resultKey).bottom, screen.height);
  });

  testWidgets('a result that is gone by the next frame: nothing happens', (
    tester,
  ) async {
    await pumpPage(tester, above: 380, resultHeight: 100);
    bringResultIntoView(result: resultKey, firstLine: firstLineKey);
    // The page is replaced before the frame.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
