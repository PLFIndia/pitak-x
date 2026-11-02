import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/widgets/local_time_text.dart';

/// The one "when" wording shared by the publish status row and the viewer's
/// availability summary: today → the time only; another day → the short date
/// in front.
void main() {
  Future<String> format(WidgetTester tester, DateTime at, DateTime now) async {
    late String text;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            text = formatLocalMoment(
              context,
              at.millisecondsSinceEpoch,
              nowMillis: now.millisecondsSinceEpoch,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return text;
  }

  testWidgets('a time from today shows only the time', (tester) async {
    final text = await format(
      tester,
      DateTime(2026, 11, 2, 14, 5),
      DateTime(2026, 11, 2, 18),
    );
    expect(text, '2:05 PM');
  });

  testWidgets('an earlier day also shows its short date', (tester) async {
    final text = await format(
      tester,
      DateTime(2026, 11, 1, 9, 30),
      DateTime(2026, 11, 2, 8),
    );
    expect(text, 'Nov 1, 9:30 AM');
  });
}
