import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/events/domain/repositories/events_repository.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/presentation/pages/publish_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A signed-out credential store (no token, no repo) so the Connection tab
/// renders its "Sign in" state without any network.
class _FakeCreds implements PublishCredentialStore {
  @override
  Future<String?> token() async => null;
  @override
  Future<String?> targetRepo() async => null;
  @override
  Future<String?> clientId() async => null;
  @override
  Future<void> clearToken() async {}
  @override
  Future<void> setClientId(String id) async {}
  @override
  Future<void> setTargetRepo(String target) async {}
  @override
  Future<void> setToken(String token) async {}
}

class _EmptyEventsRepo implements EventsRepository {
  @override
  Future<EventsContent> load() async => EventsContent.empty;
  @override
  Future<Either<Failure, EventsContent>> save(EventsContent c) async =>
      right(c);
  @override
  Future<Either<Failure, String>> savePosterImage(Uint8List b) async =>
      right('posters/x.jpg');
}

Future<Widget> _app({PublishTab initialTab = PublishTab.connection}) async {
  SharedPreferences.setMockInitialValues({'library_name': 'My Shelf'});
  return ProviderScope(
    overrides: [
      publishCredentialStoreProvider.overrideWithValue(_FakeCreds()),
      eventsRepositoryProvider.overrideWith((ref) async => _EmptyEventsRepo()),
    ],
    child: MaterialApp(home: PublishPage(initialTab: initialTab)),
  );
}

void main() {
  testWidgets('renders the three tabs', (tester) async {
    await tester.pumpWidget(await _app());
    await tester.pumpAndSettle();

    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('Basic info'), findsOneWidget);
    expect(find.text('Events'), findsWidgets); // tab label
  });

  testWidgets('Connection tab shows sign-in + a disabled Cloudflare card', (
    tester,
  ) async {
    await tester.pumpWidget(await _app());
    await tester.pumpAndSettle();

    expect(find.text('Sign in to GitHub'), findsOneWidget);
    expect(find.text('Cloudflare Pages'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
  });

  testWidgets('Basic info starts read-only, then Edit reveals fields', (
    tester,
  ) async {
    // Tall surface so all five fields lay out on-screen.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await _app(initialTab: PublishTab.basicInfo));
    await tester.pumpAndSettle();

    // View mode: the seeded value shows as text, no editable TextFields, and a
    // single Edit button drives the whole screen.
    expect(find.text('My Shelf'), findsOneWidget); // seeded library name value
    expect(find.byType(TextField), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Edit'), findsOneWidget);
    // Optional blank fields collapse to a greyed "Not set".
    expect(find.text('Not set'), findsWidgets);

    // Tap Edit -> all five fields become editable, Save replaces Edit.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Library name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Library address'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'GPS location'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Phone'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);

    // Edit a field and Save -> collapses back to read-only with the new value.
    await tester.enterText(
      find.widgetWithText(TextField, 'Library address'),
      '14 Banyan Road',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('14 Banyan Road'), findsOneWidget);
  });

  testWidgets('initialTab opens directly on the Events editor', (tester) async {
    await tester.pumpWidget(await _app(initialTab: PublishTab.events));
    await tester.pumpAndSettle();

    // The Events editor body is shown (its empty-state copy).
    expect(find.text('No posters yet.'), findsOneWidget);
    expect(find.text('Add poster'), findsOneWidget);
  });
}
