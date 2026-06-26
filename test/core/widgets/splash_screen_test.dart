import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/widgets/splash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(VoidCallback onDone, {Duration? hold}) => ProviderScope(
    child: MaterialApp(
      home: SplashScreen(
        onDone: onDone,
        holdDuration: hold ?? const Duration(seconds: 1),
      ),
    ),
  );

  testWidgets('shows the Brahmi brand text', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(host(() {}));
    await tester.pump();
    expect(find.text(kPitakBrahmi), findsOneWidget);
  });

  testWidgets('calls onDone after the hold elapses', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var done = false;
    await tester.pumpWidget(
      host(() => done = true, hold: const Duration(milliseconds: 500)),
    );

    await tester.pump();
    expect(done, isFalse); // not yet

    await tester.pump(const Duration(milliseconds: 500));
    expect(done, isTrue); // fired after the hold
  });
}
