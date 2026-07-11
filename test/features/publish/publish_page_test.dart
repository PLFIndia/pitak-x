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
  _FakeCreds({String? targetRepo}) : _target = targetRepo;
  String? _token;
  String? _target;
  @override
  Future<String?> token() async => _token;
  @override
  Future<String?> targetRepo() async => _target;
  @override
  Future<void> clearToken() async {
    _token = null;
  }

  @override
  Future<void> setTargetRepo(String target) async {
    _target = target;
  }

  @override
  Future<void> setToken(String token) async {
    _token = token;
  }
}

/// Fake GitHub API for the device flow: instant grant; poll outcome and
/// interval are configurable. No network.
class _FakeGitHubApi implements GitHubApi {
  _FakeGitHubApi({
    this.pollResult = const PollAuthorized('tok-123', 'public_repo'),
    this.intervalSeconds = 0,
  });

  final PollResult pollResult;
  final int intervalSeconds;
  int polls = 0;

  @override
  Future<DeviceCodeGrant> requestDeviceCode({
    required String clientId,
    required String scope,
  }) async => DeviceCodeGrant(
    deviceCode: 'dev-code',
    userCode: 'ABCD-1234',
    verificationUri: 'https://github.com/login/device',
    expiresInSeconds: 900,
    intervalSeconds: intervalSeconds,
  );

  @override
  Future<PollResult> pollAccessToken({
    required String clientId,
    required String deviceCode,
  }) async {
    polls++;
    return pollResult;
  }

  @override
  Future<String> currentUserLogin(String token) async => 'user';
  String? createdRepoName;
  bool pagesEnabled = false;
  @override
  Future<RepoCreateResult> createUserRepo({
    required String name,
    required String token,
  }) async {
    createdRepoName = name;
    return const RepoCreated('main');
  }

  @override
  Future<void> enablePages({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {
    pagesEnabled = true;
  }

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

      // Fresh user (no stored target) → the one-tap setup prompt appears.
      expect(find.text('Name your library repository'), findsOneWidget);

      // Accept the suggested name → repo created + Pages enabled + target
      // stored, with zero dashboard trips (mirrors Localcart Orange).
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(api.createdRepoName, 'my-library');
      expect(api.pagesEnabled, isTrue);
      expect(await creds.targetRepo(), 'user/my-library');
      expect(
        find.text('Repository user/my-library created — ready to publish!'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'existing users keep their stored target: sign-in does NOT prompt for '
    'a repo name or touch the target',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final creds = _FakeCreds(targetRepo: 'user/old-repo');
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

      await tester.tap(find.text('Sign in to GitHub'));
      await tester.pumpAndSettle();

      expect(find.text('Name your library repository'), findsNothing);
      expect(api.createdRepoName, isNull);
      expect(await creds.targetRepo(), 'user/old-repo');
      expect(find.text('Current: user/old-repo'), findsOneWidget);

      // The create option stays available even with a target set — tapping
      // it prompts for a name and switches the target to the new repo.
      final createBtn = find.text('Create a new repository');
      expect(createBtn, findsOneWidget);
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();
      expect(find.text('Name your library repository'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Repository name'),
        'second-shelf',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(api.createdRepoName, 'second-shelf');
      expect(api.pagesEnabled, isTrue);
      expect(await creds.targetRepo(), 'user/second-shelf');
      expect(find.text('Current: user/second-shelf'), findsOneWidget);

      // Backing out of the prompt leaves the target untouched.
      await tester.tap(find.text('Create a new repository'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(await creds.targetRepo(), 'user/second-shelf');
    },
  );

  testWidgets(
    'authorize dialog offers a tappable "open in browser" button for a '
    'validated github.com verification URL',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Poll is DENIED after a 5 s interval, so the dialog stays open long
      // enough to inspect, then closes deterministically (no pending timers).
      final api = _FakeGitHubApi(
        pollResult: const PollDenied(),
        intervalSeconds: 5,
      );
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            publishCredentialStoreProvider.overrideWithValue(_FakeCreds()),
            gitHubApiProvider.overrideWithValue(api),
            eventsRepositoryProvider.overrideWith(
              (ref) async => _EmptyEventsRepo(),
            ),
          ],
          child: const MaterialApp(home: PublishPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign in to GitHub'));
      await tester.pump(); // start flow
      await tester.pump(); // dialog frame

      // The URL renders as a real button (not a text link), labelled with
      // the host+path of the VALIDATED https github.com URL.
      expect(
        find.widgetWithText(FilledButton, 'github.com/login/device'),
        findsOneWidget,
      );
      // The raw URL string is no longer shown as selectable text.
      expect(find.text('https://github.com/login/device'), findsNothing);

      // Let the poll fire (denied) so the dialog closes and timers drain.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('Authorize in your browser'), findsNothing);
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
