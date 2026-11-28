import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:pitaka/features/events/domain/repositories/events_repository.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status.dart';
import 'package:pitaka/features/publish/application/site/publish_site_status_controller.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_commit_plan.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';
import 'package:pitaka/features/publish/presentation/pages/publish_page.dart';
import 'package:pitaka/features/publish/presentation/widgets/basic_info_tab.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/domain/settings_repository.dart';
import 'package:pitaka/features/settings/presentation/settings_write.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/a11y.dart';
import '../../support/form_back_harness.dart';
import 'support/cloudflare_fakes.dart';

/// An in-memory credential store, starting signed out, so the Connection tab
/// renders its "Sign in" state without any network.
class _FakeCreds implements PublishCredentialStore {
  _FakeCreds({String? targetRepo, String? token})
    : _target = targetRepo,
      _token = token;
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
  Future<void> clearTargetRepo() async {
    _target = null;
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
    this.listing = const RepoListing(repos: [], truncated: false),
    this.details,
    this.pages,
    this.throwOnUserRepos = false,
  });

  PollResult pollResult;
  final int intervalSeconds;
  int polls = 0;

  /// What `userRepos` answers (N09).
  final RepoListing listing;
  final bool throwOnUserRepos;

  /// What `repository()` answers for any owner/repo (null = 404).
  final GitHubRepoDetails? details;

  /// What `pagesSite()` answers (null = Pages off).
  final PagesSite? pages;
  int repositoryCalls = 0;

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
  Future<RepoListing> userRepos(String token) async {
    if (throwOnUserRepos) throw const GitHubApiException('boom');
    return listing;
  }

  @override
  Future<GitHubRepoDetails?> repository({
    required String owner,
    required String repo,
    required String token,
  }) async {
    repositoryCalls++;
    return details;
  }

  @override
  Future<PagesSite?> pagesSite({
    required String owner,
    required String repo,
    required String token,
  }) async => pages;
  @override
  Future<String> branchHead({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async => 'sha';

  @override
  Future<GitHubTreeSnapshot> treeAt({
    required String owner,
    required String repo,
    required String branch,
    required String headSha,
    required String token,
  }) async => const GitHubTreeSnapshot(
    repo: 'me/lib',
    branch: 'main',
    headSha: 'sha',
    files: {},
    truncated: false,
  );
  @override
  Future<PublishCommitResult> commitFiles({
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required GitHubCommitPlan plan,
    required String commitMessage,
    required String expectedHead,
    List<String> deletePaths = const [],
    Future<void> Function(String gitSha)? onBlobStored,
  }) async => const PublishCommitSuccess('sha', []);
}

class _EmptyEventsRepo implements EventsRepository {
  /// Records deletions so tests can assert orphan cleanup (decision Q12).
  final List<String> deletedPosters = [];

  @override
  Future<void> deletePosterImage(String imageRef) async {
    deletedPosters.add(imageRef);
  }

  @override
  Future<EventsContent> loadForEditor() async => EventsContent.empty;

  @override
  Future<Either<Failure, EventsContent>> loadStrict() async =>
      right(EventsContent.empty);
  @override
  Future<Either<Failure, EventsContent>> save(EventsContent c) async =>
      right(c);
  @override
  Future<Either<Failure, String>> savePosterImage(Uint8List b) async =>
      right('posters/x.jpg');
}

/// A settings store in memory for the tests of leaving "Basic info" (review
/// finding P4-M1). Each of the three writes of the tab's Save can be held
/// open, and the contact write can be refused. Any other write is not
/// expected on the Publish page and fails the test that causes it.
final class _HeldSettings implements SettingsRepository {
  AppSettings stored = AppSettings.defaults.copyWith(libraryName: 'My Shelf');

  /// While a write's name is in here ('name', 'contact' or 'sharing'), that
  /// write waits for the completer before it stores anything.
  final Map<String, Completer<void>> holds = {};

  /// When true, the contact write answers a failure and stores nothing.
  bool refuseContact = false;

  /// How many writes stored something.
  int writes = 0;

  @override
  Future<AppSettings> load() async => stored;

  @override
  Future<Either<Failure, Unit>> setLibraryName(String name) async {
    await holds['name']?.future;
    stored = stored.copyWith(libraryName: name);
    writes++;
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> setPublishContact({
    required String address,
    required String gps,
    required String email,
    required String phone,
  }) async {
    await holds['contact']?.future;
    if (refuseContact) return left(const StorageFailure('synthetic'));
    stored = stored.copyWith(
      publishContactAddress: address,
      publishContactGps: gps,
      publishContactEmail: email,
      publishContactPhone: phone,
    );
    writes++;
    return right(unit);
  }

  @override
  Future<Either<Failure, Unit>> setPublishLocationSharing(
    LocationSharing sharing,
  ) async {
    await holds['sharing']?.future;
    stored = stored.copyWith(publishLocationSharing: sharing);
    writes++;
    return right(unit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

List<Override> _cloudflareOverrides() {
  final graph = CloudflareSetupHarness();
  final documents = Directory.systemTemp.createTempSync('pitaka_publish_page_');
  addTearDown(() {
    if (documents.existsSync()) documents.deleteSync(recursive: true);
  });
  return [
    setupCloudflareSiteProvider.overrideWith((ref) async => graph.setup),
    cloudflareCredentialStoreProvider.overrideWithValue(graph.credentials),
    appDocsDirProvider.overrideWith((ref) async => documents),
    // Review finding 6: a GitHub publish spools into the temporary directory;
    // the page fixture points it at the same temporary folder.
    appTempDirProvider.overrideWith((ref) async => documents),
  ];
}

Future<Widget> _app({PublishTab initialTab = PublishTab.connection}) async {
  SharedPreferences.setMockInitialValues({'library_name': 'My Shelf'});
  return ProviderScope(
    overrides: [
      ..._cloudflareOverrides(),
      publishCredentialStoreProvider.overrideWithValue(_FakeCreds()),
      eventsRepositoryProvider.overrideWith((ref) async => _EmptyEventsRepo()),
    ],
    child: MaterialApp(home: PublishPage(initialTab: initialTab)),
  );
}

void main() {
  test(
    'publishSiteStatus completes with a bounded number of evaluations',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          ..._cloudflareOverrides(),
          publishCredentialStoreProvider.overrideWithValue(_FakeCreds()),
        ],
      );
      addTearDown(container.dispose);
      final states = <AsyncValue<PublishSiteStatus>>[];
      final subscription = container.listen(
        publishSiteStatusProvider,
        (_, next) => states.add(next),
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final status = await container
          .read(publishSiteStatusProvider.future)
          .timeout(const Duration(seconds: 2));

      expect(status.activeHost, isNull);
      await Future<void>.delayed(Duration.zero);
      expect(states.length, lessThan(5));
    },
  );

  testWidgets('renders the three tabs', (tester) async {
    await tester.pumpWidget(await _app());
    await tester.pumpAndSettle();

    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('Basic info'), findsOneWidget);
    expect(find.text('Events'), findsWidgets); // tab label
  });

  testWidgets('Connection tab shows sign-in + a Cloudflare connection card', (
    tester,
  ) async {
    await tester.pumpWidget(await _app());
    await tester.pumpAndSettle();

    expect(find.text('Sign in to GitHub'), findsOneWidget);
    expect(find.text('Cloudflare Workers'), findsOneWidget);
    expect(find.text('Coming soon'), findsNothing);
    expect(find.text('Not configured'), findsNWidgets(2));
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
            ..._cloudflareOverrides(),
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
            ..._cloudflareOverrides(),
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
            ..._cloudflareOverrides(),
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

  // N12 regression: the signed-in account row used to be a fixed
  // spaceBetween Row that overflowed at 320px / large text.
  testWidgets('N12: signed-in row survives a 320px width', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'library_name': 'My Shelf'});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._cloudflareOverrides(),
          publishCredentialStoreProvider.overrideWithValue(
            _FakeCreds(token: 'TKN', targetRepo: 'me/lib'),
          ),
          eventsRepositoryProvider.overrideWith(
            (ref) async => _EmptyEventsRepo(),
          ),
        ],
        child: const MaterialApp(home: PublishPage()),
      ),
    );
    await tester.pumpAndSettle();

    // S35: signed in + repo set = green = tile starts COLLAPSED (D4); open
    // it to reach the account row. The header itself must also survive 320px.
    await tester.tap(find.text('GitHub Pages'));
    await tester.pumpAndSettle();

    expect(find.text('Signed in'), findsOneWidget);
    // A RenderFlex overflow would fail the test via the binding; reaching
    // here with the row built is the assertion.
    expect(tester.takeException(), isNull);
  });

  group('N09 — existing-repository setup', () {
    GitHubRepoDetails owned({
      String owner = 'user',
      String repo = 'shelf',
      bool canAdmin = true,
    }) => GitHubRepoDetails(
      fullName: '$owner/$repo',
      ownerLogin: owner,
      isPrivate: false,
      isArchived: false,
      defaultBranch: 'main',
      canPush: true,
      canAdmin: canAdmin,
    );

    Future<void> pumpSignedIn(
      WidgetTester tester, {
      required _FakeCreds creds,
      required _FakeGitHubApi api,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._cloudflareOverrides(),
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
    }

    Future<void> openList(WidgetTester tester) async {
      await tester.tap(find.text('Choose an existing repo (advanced)'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'picking a repo verifies it and enables Pages before storing it',
      (tester) async {
        final creds = _FakeCreds(token: 'TKN');
        final api = _FakeGitHubApi(
          listing: const RepoListing(
            repos: [GitHubRepo(fullName: 'user/shelf', isPrivate: false)],
            truncated: false,
          ),
          details: owned(),
          // `pages` left null: Pages off → the adopt path must turn it on.
        );
        await pumpSignedIn(tester, creds: creds, api: api);
        await openList(tester);
        expect(find.text('user/shelf'), findsOneWidget);

        await tester.tap(find.text('user/shelf'));
        await tester.pumpAndSettle();

        expect(api.repositoryCalls, 1);
        expect(api.pagesEnabled, isTrue);
        expect(await creds.targetRepo(), 'user/shelf');
        expect(find.text('Current: user/shelf'), findsOneWidget);
        expect(
          find.text(
            'Connected to your existing user/shelf — ready to publish!',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('a repo the account does not own is refused and NOT stored', (
      tester,
    ) async {
      final creds = _FakeCreds(token: 'TKN');
      final api = _FakeGitHubApi(
        // The list can only contain owned repos (affiliation=owner), but
        // the server's answer is what counts: it says another owner.
        listing: const RepoListing(
          repos: [GitHubRepo(fullName: 'user/shelf', isPrivate: false)],
          truncated: false,
        ),
        details: owned(owner: 'someone-else'),
      );
      await pumpSignedIn(tester, creds: creds, api: api);
      await openList(tester);
      await tester.tap(find.text('user/shelf'));
      await tester.pumpAndSettle();

      expect(await creds.targetRepo(), isNull);
      expect(api.pagesEnabled, isFalse);
      expect(find.textContaining('Current:'), findsNothing);
      expect(
        find.textContaining('owned by the GitHub account'),
        findsOneWidget,
      );
    });

    testWidgets(
      'a Pages layout the app cannot publish to is refused with guidance',
      (tester) async {
        final creds = _FakeCreds(token: 'TKN');
        final api = _FakeGitHubApi(
          listing: const RepoListing(
            repos: [GitHubRepo(fullName: 'user/shelf', isPrivate: false)],
            truncated: false,
          ),
          details: owned(),
          pages: const PagesSite(
            sourceBranch: 'main',
            sourcePath: '/docs',
            isWorkflowBuild: false,
          ),
        );
        await pumpSignedIn(tester, creds: creds, api: api);
        await openList(tester);
        await tester.tap(find.text('user/shelf'));
        await tester.pumpAndSettle();

        expect(await creds.targetRepo(), isNull);
        expect(find.textContaining('Deploy from a branch'), findsOneWidget);
      },
    );

    testWidgets('sign-out clears the target repo too (D3-a)', (tester) async {
      final creds = _FakeCreds(token: 'TKN', targetRepo: 'user/old');
      final api = _FakeGitHubApi();
      await pumpSignedIn(tester, creds: creds, api: api);
      // S35: green state (signed in + repo) starts collapsed — expand first.
      await tester.tap(find.text('GitHub Pages'));
      await tester.pumpAndSettle();
      expect(find.text('Current: user/old'), findsOneWidget);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(await creds.token(), isNull);
      expect(await creds.targetRepo(), isNull);
      expect(find.text('Signed out.'), findsOneWidget);
      // Signing back in as a fresh account now prompts for a repo (no
      // inherited target).
      await tester.tap(find.text('Sign in to GitHub'));
      await tester.pumpAndSettle();
      expect(find.text('Name your library repository'), findsOneWidget);
    });

    testWidgets(
      'a truncated list says so instead of pretending to be complete (D4-a)',
      (tester) async {
        final creds = _FakeCreds(token: 'TKN');
        final api = _FakeGitHubApi(
          listing: RepoListing(
            repos: [
              for (var i = 0; i < 3; i++)
                GitHubRepo(fullName: 'user/r$i', isPrivate: false),
            ],
            truncated: true,
          ),
        );
        await pumpSignedIn(tester, creds: creds, api: api);
        await openList(tester);
        expect(find.text('user/r0'), findsOneWidget);
        expect(
          find.textContaining('most recently updated repositories'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a complete list shows no truncation notice', (tester) async {
      final creds = _FakeCreds(token: 'TKN');
      final api = _FakeGitHubApi(
        listing: const RepoListing(
          repos: [GitHubRepo(fullName: 'user/r0', isPrivate: false)],
          truncated: false,
        ),
      );
      await pumpSignedIn(tester, creds: creds, api: api);
      await openList(tester);
      expect(
        find.textContaining('most recently updated repositories'),
        findsNothing,
      );
    });

    testWidgets('a failed list load shows a safe message', (tester) async {
      final creds = _FakeCreds(token: 'TKN');
      final api = _FakeGitHubApi(throwOnUserRepos: true);
      await pumpSignedIn(tester, creds: creds, api: api);
      await openList(tester);
      expect(
        find.text('Could not list your repositories. Try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('boom'), findsNothing);
    });
  });

  // S35: providers are collapsible tiles with a three-state status badge
  // (D3) and auto-expand unless fully configured (D4), so the tab fits one
  // screen and nothing actionable hides behind a tap.
  group('S35 — provider tiles', () {
    Future<void> pumpCreds(WidgetTester tester, _FakeCreds creds) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._cloudflareOverrides(),
            publishCredentialStoreProvider.overrideWithValue(creds),
            eventsRepositoryProvider.overrideWith(
              (ref) async => _EmptyEventsRepo(),
            ),
          ],
          child: const MaterialApp(home: PublishPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'not signed in: red status on both tiles, GitHub auto-expanded',
      (tester) async {
        await pumpCreds(tester, _FakeCreds());

        // Both providers are unconfigured (GitHub red + Cloudflare red).
        expect(find.text('Not configured'), findsNWidgets(2));
        // D4: not green → the GitHub body is open WITHOUT a tap.
        expect(find.text('Sign in to GitHub'), findsOneWidget);
      },
    );

    testWidgets(
      'signed in, no repo: amber Partially configured, auto-expanded',
      (tester) async {
        await pumpCreds(tester, _FakeCreds(token: 'TKN'));

        expect(find.text('Partially configured'), findsOneWidget);
        expect(find.text('Set up a repository'), findsOneWidget);
      },
    );

    testWidgets('signed in + repo: green, collapsed, Publish stays visible', (
      tester,
    ) async {
      await pumpCreds(tester, _FakeCreds(token: 'TKN', targetRepo: 'me/lib'));

      expect(find.text('Configured'), findsOneWidget);
      // D4: green → collapsed; the body is not built…
      expect(find.text('Signed in'), findsNothing);
      expect(find.text('Current: me/lib'), findsNothing);
      // …but the ACTION stays visible without expanding (no-scroll goal).
      expect(find.text('Publish catalogue now'), findsOneWidget);

      // Expanding reveals the account + target sections.
      await tester.tap(find.text('GitHub Pages'));
      await tester.pumpAndSettle();
      expect(find.text('Signed in'), findsOneWidget);
      expect(find.text('Current: me/lib'), findsOneWidget);
    });

    testWidgets(
      'Cloudflare tile: collapsed setup, real connect action on expand',
      (tester) async {
        await pumpCreds(tester, _FakeCreds());

        expect(find.text('Cloudflare Workers'), findsOneWidget);
        expect(find.text('Coming soon'), findsNothing);
        expect(find.text('Connect Cloudflare'), findsNothing);

        await tester.tap(find.text('Cloudflare Workers'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Worker dedicated to Pitak'),
          findsOneWidget,
        );
        expect(find.text('Connect Cloudflare'), findsOneWidget);
        expect(find.text('Cloudflare API token'), findsNothing);
      },
    );
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    await tester.pumpWidget(await _app());
    await tester.pumpAndSettle();
    await expectMeetsA11yGuidelines(tester);
  });

  testWidgets('the GitHub device code reappears after a tab switch (M6)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final creds = _FakeCreds();
    // The flow stays awaiting the user, so the code is still in state. A
    // one-second poll interval keeps the fake from spinning forever.
    final api = _FakeGitHubApi(
      pollResult: const PollPending(),
      intervalSeconds: 1,
    );
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._cloudflareOverrides(),
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
    // The flow polls forever, so settle by hand instead of pumpAndSettle.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Authorize in your browser'), findsOneWidget);

    // Dismiss the dialog without answering: the flow keeps waiting.
    await tester.tapAt(const Offset(10, 10));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Authorize in your browser'), findsNothing);

    // Leaving and returning to the tab must show it again, not strand the
    // user with a disabled tile and no dialog.
    await tester.tap(find.text('Basic info'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Connection'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Authorize in your browser'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // End the flow so no poll timer outlives the test.
    api.pollResult = const PollDenied();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  });

  // What the Publish page does when the user leaves it while "Basic info"
  // holds unsaved edits (review finding P4-M1). The page stands ABOVE a home
  // page here, as in the app; "the page is gone" means the home page shows
  // again. Two things are special about this form: it is a TAB, so a change
  // of tab must not throw the edits away, and the question must come from
  // every tab of the page.
  group('leaving with unsaved "Basic info" (P4-M1)', () {
    late _HeldSettings settings;

    /// When a test sets this and has the provider built again, the settings
    /// store itself can no longer be had, and a write THROWS instead of
    /// answering a failure.
    late bool storeBroken;

    setUp(() {
      settings = _HeldSettings();
      storeBroken = false;
    });

    final page = find.byType(PublishPage);
    final editButton = find.widgetWithText(OutlinedButton, 'Edit');
    final saveButton = find.widgetWithText(FilledButton, 'Save');
    Finder field(String label) => find.widgetWithText(TextField, label);
    Finder tab(String label) => find.widgetWithText(Tab, label);

    // Written out here, not taken from the app's code: a changed word has
    // to fail the tests (decision D96 of PLAN.md).
    const tabSentence = 'Your changes under "Basic info" have not been saved.';

    Future<void> openPublish(
      WidgetTester tester, {
      PublishTab initialTab = PublishTab.basicInfo,
    }) async {
      // Tall enough to have every field and the Save button on the screen.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      await pumpFormAboveHome(
        tester,
        PublishPage(initialTab: initialTab),
        overrides: [
          ..._cloudflareOverrides(),
          publishCredentialStoreProvider.overrideWithValue(_FakeCreds()),
          eventsRepositoryProvider.overrideWith(
            (ref) async => _EmptyEventsRepo(),
          ),
          settingsRepositoryProvider.overrideWith((ref) async {
            if (storeBroken) throw StateError('synthetic');
            return settings;
          }),
        ],
      );
    }

    Future<void> tapEdit(WidgetTester tester) async {
      await tester.tap(editButton);
      await tester.pumpAndSettle();
    }

    Future<void> tapSave(WidgetTester tester) async {
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
    }

    Future<void> goToTab(WidgetTester tester, String label) async {
      await tester.tap(tab(label));
      await tester.pumpAndSettle();
    }

    /// Takes the focus out of the text field that has it, as the keyboard's
    /// Done key does. A text field keeps its tab alive while it has the
    /// focus; without this step a test of "the tab keeps its edits" would
    /// pass on a tab that throws them away.
    Future<void> giveUpFocus(WidgetTester tester) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
    }

    /// The number of the tab on the screen (0 Connection, 1 Basic info,
    /// 2 Events).
    int shownTab(WidgetTester tester) =>
        DefaultTabController.of(tester.element(find.byType(TabBarView))).index;

    void expectGoneWithoutQuestion() {
      expect(findDiscardQuestion(), findsNothing);
      expect(page, findsNothing);
      expect(findFormBackHome(), findsOneWidget);
    }

    void expectAsked() {
      expect(findDiscardQuestion(), findsOneWidget);
      expect(find.text(tabSentence), findsOneWidget);
      expect(page, findsOneWidget);
    }

    testWidgets('opened on Connection, "Basic info" never shown: Back '
        'leaves at once', (tester) async {
      await openPublish(tester, initialTab: PublishTab.connection);
      expect(find.byType(BasicInfoTab, skipOffstage: false), findsNothing);
      await pressSystemBack(tester);

      expectGoneWithoutQuestion();
    });

    testWidgets('"Basic info" in view mode, a name stored: Back leaves', (
      tester,
    ) async {
      await openPublish(tester);
      expect(find.text('My Shelf'), findsOneWidget);
      expect(editButton, findsOneWidget);
      await pressSystemBack(tester);

      expectGoneWithoutQuestion();
    });

    testWidgets('"Basic info" looked at, then to Connection: Back leaves', (
      tester,
    ) async {
      await openPublish(tester);
      await goToTab(tester, 'Connection');
      await pressSystemBack(tester);

      expectGoneWithoutQuestion();
    });

    testWidgets('"Edit" and nothing more: Back leaves', (tester) async {
      await openPublish(tester);
      await tapEdit(tester);
      expect(saveButton, findsOneWidget);
      await pressSystemBack(tester);

      expectGoneWithoutQuestion();
    });

    testWidgets('a name typed, Back: the question with the sentence of the '
        'tab. "Keep editing" keeps edit mode and the text; Back again '
        'and "Discard" leaves, and nothing is stored', (tester) async {
      await openPublish(tester);
      await tapEdit(tester);
      await tester.enterText(field('Library name'), 'Typed name');
      await pressSystemBack(tester);
      expectAsked();

      await tester.tap(findKeepEditing());
      await tester.pumpAndSettle();
      expect(findDiscardQuestion(), findsNothing);
      expect(saveButton, findsOneWidget);
      expect(find.widgetWithText(TextField, 'Typed name'), findsOneWidget);

      await pressSystemBack(tester);
      await tester.tap(findDiscard());
      await tester.pumpAndSettle();
      expectGoneWithoutQuestion();
      expect(settings.writes, 0, reason: 'discarded, not saved');
      expect(settings.stored.libraryName, 'My Shelf');
    });

    testWidgets('the arrow of the app bar asks as well', (tester) async {
      await openPublish(tester);
      await tapEdit(tester);
      await tester.enterText(field('Library name'), 'Typed name');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expectAsked();
    });

    // Every text field the tab shows in edit mode, by its label. A field
    // that is added to the tab has to be added here (the count below fails
    // otherwise), and then its own test says whether the guard knows of it.
    const textFields = [
      'Library name',
      'Library address',
      'GPS location',
      'Email',
      'Phone',
    ];

    testWidgets('edit mode shows exactly the text fields these tests know', (
      tester,
    ) async {
      await openPublish(tester);
      await tapEdit(tester);

      expect(find.byType(TextField), findsNWidgets(textFields.length));
      for (final label in textFields) {
        expect(field(label), findsOneWidget);
      }
    });

    for (final label in textFields) {
      testWidgets('"$label" changed, Back: the question', (tester) async {
        await openPublish(tester);
        await tapEdit(tester);
        await tester.enterText(field(label), '7');
        await pressSystemBack(tester);

        expectAsked();
      });
    }

    testWidgets('only the location choice changed, Back: the question', (
      tester,
    ) async {
      await openPublish(tester);
      await tapEdit(tester);
      await tester.tap(find.text('Exact'));
      await tester.pumpAndSettle();
      await pressSystemBack(tester);

      expectAsked();
    });

    testWidgets('typed and put back, Back: leaves', (tester) async {
      await openPublish(tester);
      await tapEdit(tester);
      await tester.enterText(field('Library name'), 'Typed name');
      await tester.enterText(field('Library name'), 'My Shelf');
      await pressSystemBack(tester);

      expectGoneWithoutQuestion();
    });

    testWidgets('the location choice changed and put back, Back: leaves', (
      tester,
    ) async {
      await openPublish(tester);
      await tapEdit(tester);
      await tester.tap(find.text('Exact'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not shared'));
      await tester.pumpAndSettle();
      await pressSystemBack(tester);

      expectGoneWithoutQuestion();
    });

    // The two neighbours of "Basic info", with their place among the tabs.
    const neighbours = {'Connection': 0, 'Events': 2};

    for (final neighbour in neighbours.entries) {
      final other = neighbour.key;

      testWidgets('a name typed, then to $other, Back there: the question. '
          '"Keep editing" stays on $other, and the text is still under '
          '"Basic info"', (tester) async {
        await openPublish(tester);
        await tapEdit(tester);
        await tester.enterText(field('Library name'), 'Typed name');
        await giveUpFocus(tester);
        await goToTab(tester, other);
        await pressSystemBack(tester);
        expectAsked();

        await tester.tap(findKeepEditing());
        await tester.pumpAndSettle();
        expect(page, findsOneWidget);
        expect(shownTab(tester), neighbour.value);

        await goToTab(tester, 'Basic info');
        expect(saveButton, findsOneWidget);
        expect(find.widgetWithText(TextField, 'Typed name'), findsOneWidget);
      });

      testWidgets('a name typed, the focus given up, to $other and back: '
          'still in edit mode, with the text', (tester) async {
        await openPublish(tester);
        await tapEdit(tester);
        await tester.enterText(field('Library name'), 'Typed name');
        await giveUpFocus(tester);
        await goToTab(tester, other);
        expect(shownTab(tester), neighbour.value);
        await goToTab(tester, 'Basic info');

        expect(saveButton, findsOneWidget);
        expect(find.widgetWithText(TextField, 'Typed name'), findsOneWidget);
      });

      testWidgets('only the location choice changed, to $other and back: '
          'the choice is kept', (tester) async {
        await openPublish(tester);
        await tapEdit(tester);
        await tester.tap(find.text('Exact'));
        await tester.pumpAndSettle();
        await goToTab(tester, other);
        expect(shownTab(tester), neighbour.value);
        await goToTab(tester, 'Basic info');

        expect(saveButton, findsOneWidget);
        expect(
          tester
              .widget<SegmentedButton<LocationSharing>>(
                find.byType(SegmentedButton<LocationSharing>),
              )
              .selected,
          {LocationSharing.exact},
        );
      });
    }

    // A Save of this tab is three writes, one after the other. Back has to
    // wait through all three (D95), so each is held open once.
    for (final write in ['name', 'contact', 'sharing']) {
      testWidgets('Back while the save runs (its "$write" write held open) '
          'does nothing; then the tab shows the saved name, the page stays, '
          'and Back leaves with no question', (tester) async {
        final hold = Completer<void>();
        addTearDown(() {
          if (!hold.isCompleted) hold.complete();
        });
        await openPublish(tester);
        await tapEdit(tester);
        await tester.enterText(field('Library name'), 'New name');
        await giveUpFocus(tester);
        settings.holds[write] = hold;
        await tapSave(tester);

        await pressSystemBack(tester);
        expect(findDiscardQuestion(), findsNothing);
        expect(page, findsOneWidget, reason: 'Back waits for the save');

        hold.complete();
        await tester.pumpAndSettle();
        expect(page, findsOneWidget, reason: 'this form stays after a save');
        expect(editButton, findsOneWidget);
        expect(find.text('New name'), findsOneWidget);
        expect(settings.stored.libraryName, 'New name');

        await pressSystemBack(tester);
        expectGoneWithoutQuestion();
      });
    }

    testWidgets('after a save the store refused, Back asks', (tester) async {
      settings.refuseContact = true;
      await openPublish(tester);
      await tapEdit(tester);
      await tester.enterText(field('Library address'), '14 Banyan Road');
      await giveUpFocus(tester);
      await tapSave(tester);
      expect(find.text(settingsSaveFailedMessage), findsOneWidget);
      expect(saveButton, findsOneWidget, reason: 'still in edit mode');
      await pressSystemBack(tester);

      expectAsked();
    });

    testWidgets('after a save that threw, Back is not left dead: it asks', (
      tester,
    ) async {
      await openPublish(tester);
      await tapEdit(tester);
      await tester.enterText(field('Library name'), 'New name');
      await giveUpFocus(tester);
      storeBroken = true;
      ProviderScope.containerOf(
        tester.element(page),
      ).invalidate(settingsRepositoryProvider);
      // The Save button's handler is not awaited by anybody, so what it
      // throws is an error nobody catches, and such an error fails a test at
      // once. A zone of its own around the tap catches it here instead.
      Object? thrown;
      await runZonedGuarded(
        () => tapSave(tester),
        (error, _) => thrown = error,
      );
      expect(thrown, isStateError);
      expect(saveButton, findsOneWidget, reason: 'still in edit mode');
      await pressSystemBack(tester);

      expectAsked();
    });

    testWidgets('after "Save", Back: leaves', (tester) async {
      await openPublish(tester);
      await tapEdit(tester);
      await tester.enterText(field('Library name'), 'New name');
      await giveUpFocus(tester);
      await tapSave(tester);
      expect(settings.stored.libraryName, 'New name');
      await pressSystemBack(tester);

      expectGoneWithoutQuestion();
    });

    testWidgets('after "Save", "Edit" again and nothing changed: Back '
        'leaves', (tester) async {
      await openPublish(tester);
      await tapEdit(tester);
      await tester.enterText(field('Library name'), 'New name');
      await giveUpFocus(tester);
      await tapSave(tester);
      await tapEdit(tester);
      expect(saveButton, findsOneWidget);
      await pressSystemBack(tester);

      expectGoneWithoutQuestion();
    });

    testWidgets('after "Save", "Edit" again and a field changed: Back asks', (
      tester,
    ) async {
      await openPublish(tester);
      await tapEdit(tester);
      await tester.enterText(field('Library name'), 'New name');
      await giveUpFocus(tester);
      await tapSave(tester);
      await tapEdit(tester);
      await tester.enterText(field('Phone'), '7');
      await pressSystemBack(tester);

      expectAsked();
    });

    testWidgets('the question shows nothing that was typed', (tester) async {
      await openPublish(tester);
      await tapEdit(tester);
      await tester.enterText(field('Phone'), '98450 12345');
      await giveUpFocus(tester);
      await goToTab(tester, 'Connection');
      await pressSystemBack(tester);
      expectAsked();

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('98450'),
        ),
        findsNothing,
      );
    });
  });
}
