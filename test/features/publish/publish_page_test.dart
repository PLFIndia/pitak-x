import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/events/domain/repositories/events_repository.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/presentation/pages/publish_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An in-memory credential store, starting signed out, so the Connection tab
/// renders its "Sign in" state without any network.
class _FakeCreds implements PublishCredentialStore {
  String? _token;
  @override
  Future<String?> token() async => _token;
  @override
  Future<String?> targetRepo() async => null;
  @override
  Future<void> clearToken() async {
    _token = null;
  }

  @override
  Future<void> setTargetRepo(String target) async {}
  @override
  Future<void> setToken(String token) async {
    _token = token;
  }
}

/// Fake GitHub API for the device flow: instant grant, authorizes on the
/// first poll. No network, no real timers (interval 0).
class _FakeGitHubApi implements GitHubApi {
  int polls = 0;

  @override
  Future<DeviceCodeGrant> requestDeviceCode({
    required String clientId,
    required String scope,
  }) async => const DeviceCodeGrant(
    deviceCode: 'dev-code',
    userCode: 'ABCD-1234',
    verificationUri: 'https://github.com/login/device',
    expiresInSeconds: 900,
    intervalSeconds: 0,
  );

  @override
  Future<PollResult> pollAccessToken({
    required String clientId,
    required String deviceCode,
  }) async {
    polls++;
    return const PollAuthorized('tok-123', 'public_repo');
  }

  @override
  Future<String> currentUserLogin(String token) async => 'user';
  @override
  Future<List<GitHubRepo>> userRepos(String token) async => const [];
  @override
  Future<String?> defaultBranch({
    required String owner,
    required String repo,
    required String token,
  }) async => 'main';
  @override
  Future<Map<String, String>> headTreeShas({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async => const {};
  @override
  Future<PublishCommitResult> commitFiles({
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required List<DesiredFile> files,
    required String commitMessage,
  }) async => const PublishCommitSuccess('sha', []);
  @override
  Future<bool?> latestPagesBuildStatus({
    required String owner,
    required String repo,
    required String token,
  }) async => true;
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

  testWidgets(
    'device-flow sign-in completes WHILE the user-code dialog is open '
    '(regression: awaiting the dialog suspended token polling)',
    (tester) async {
      // Tall surface: the status line renders at the bottom of a lazy
      // ListView and would not be built in the default test viewport.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final creds = _FakeCreds();
      final api = _FakeGitHubApi();
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            publishCredentialStoreProvider.overrideWithValue(creds),
            gitHubApiProvider.overrideWithValue(api),
            eventsRepositoryProvider.overrideWith(
              (ref) async => _EmptyEventsRepo(),
            ),
          ],
          child: const MaterialApp(home: PublishPage()),
        ),
      );
      await tester.pumpAndSettle();

      // No client-id prompt anymore: Pitak ships its own public client id,
      // so tapping sign-in starts the device flow immediately.
      await tester.tap(find.text('Sign in to GitHub'));
      await tester.pumpAndSettle();

      // The flow must have polled and stored the token WITHOUT anyone
      // tapping "Done" on the authorize dialog — and the dialog must have
      // been dismissed by the success state.
      expect(api.polls, greaterThanOrEqualTo(1));
      expect(await creds.token(), 'tok-123');
      expect(find.text('Authorize in your browser'), findsNothing);
      expect(find.text('Signed in.'), findsOneWidget);
    },
  );

  testWidgets('initialTab opens directly on the Events editor', (tester) async {
    await tester.pumpWidget(await _app(initialTab: PublishTab.events));
    await tester.pumpAndSettle();

    // The Events editor body is shown (its empty-state copy).
    expect(find.text('No posters yet.'), findsOneWidget);
    expect(find.text('Add poster'), findsOneWidget);
  });
}
