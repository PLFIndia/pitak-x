import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/widgets/app_drawer.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _app() async {
  // The drawer reads settings, which load from shared_preferences.
  return const ProviderScope(
    child: MaterialApp(
      home: Scaffold(drawer: AppDrawer(), body: SizedBox()),
    ),
  );
}

void main() {
  testWidgets('header shows the library name when one is set', (tester) async {
    SharedPreferences.setMockInitialValues({
      'library_name': 'Indiranagar Books',
    });
    await tester.pumpWidget(await _app());
    // Open the drawer.
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('Indiranagar Books'), findsOneWidget);
    expect(find.text('Pitak'), findsNothing);
  });

  testWidgets('header falls back to "Pitak" when no name is set', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(await _app());
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('Pitak'), findsOneWidget);
  });

  testWidgets('lists the Bookmarks destination below Wishlist', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(await _app());
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('Bookmarks'), findsOneWidget);
  });
}
