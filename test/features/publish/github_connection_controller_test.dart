import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/publish/application/github_connection_controller.dart';
import 'package:pitaka/features/publish/application/github_device_flow.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/publish_credential_store.dart';

/// In-memory credential store that COUNTS writes, so tests can assert the
/// token landed in the store exactly once (and never in the UI state).
class _FakeCreds implements PublishCredentialStore {
  _FakeCreds({String? token, String? targetRepo, this.throwOnSetTargetRepo})
    : _token = token,
      _target = targetRepo;

  String? _token;
  String? _target;
  final List<String> setTokenCalls = [];

  /// When set, [setTargetRepo] throws it — models a secure-storage write
  /// failure (e.g. a Keystore PlatformException) that escapes the use case's
  /// own GitHubApiException→Either mapping.
  final Exception? throwOnSetTargetRepo;

  @override
  Future<String?> token() async => _token;
  @override
  Future<String?> targetRepo() async => _target;
  @override
  Future<void> setToken(String token) async {
    setTokenCalls.add(token);
    _token = token;
  }

  @override
  Future<void> clearToken() async {
    _token = null;
  }

  @override
  Future<void> setTargetRepo(String target) async {
    final failure = throwOnSetTargetRepo;
    if (failure != null) throw failure;
    _target = target;
  }

  @override
  Future<void> clearTargetRepo() async {
    _target = null;
  }
}

/// Scriptable GitHubApi (same pattern as `github_device_flow_test.dart`).
///
/// Each poll-script entry is either a [PollResult] (returned) or a
/// [GitHubApiException] (thrown). An optional [gate] completer holds the first
/// poll open so tests can observe mid-flow states (and disposal) safely.
class _FakeGitHubApi implements GitHubApi {
  _FakeGitHubApi({
    List<Object> polls = const [PollAuthorized('tok-123', 'public_repo')],
    this.gate,
    this.listing = const RepoListing(repos: [], truncated: false),
    this.throwOnUserRepos = false,
    this.details,
    this.throwOnLogin = false,
  }) : _polls = polls;

  final List<Object> _polls;
  int _pollIndex = 0;

  /// When set, the FIRST poll awaits this completer (mid-flow observation).
  final Completer<void>? gate;

  final RepoListing listing;
  final bool throwOnUserRepos;
  final GitHubRepoDetails? details;
  final bool throwOnLogin;

  int deviceCodeRequests = 0;
  String? createdRepoName;
  bool pagesEnabled = false;

  @override
  Future<DeviceCodeGrant> requestDeviceCode({
    required String clientId,
    required String scope,
  }) async {
    deviceCodeRequests++;
    return const DeviceCodeGrant(
      deviceCode: 'dev-code',
      userCode: 'ABCD-1234',
      verificationUri: 'https://github.com/login/device',
      expiresInSeconds: 900,
      intervalSeconds: 0,
    );
  }

  @override
  Future<PollResult> pollAccessToken({
    required String clientId,
    required String deviceCode,
  }) async {
    final gate = this.gate;
    if (gate != null && _pollIndex == 0) await gate.future;
    final entry = _polls[_pollIndex++];
    if (entry is GitHubApiException) throw entry;
    return entry as PollResult;
  }

  @override
  Future<String> currentUserLogin(String token) async {
    if (throwOnLogin) throw const GitHubApiException('boom');
    return 'user';
  }

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
  }) async => details;

  @override
  Future<PagesSite?> pagesSite({
    required String owner,
    required String repo,
    required String token,
  }) async =>
      // Pages off → the adopt/setup paths under test must enable it.
      null;

  @override
  Future<GitHubTreeSnapshot> headTree({
    required String owner,
    required String repo,
    required String branch,
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
    required List<DesiredFile> files,
    required String commitMessage,
    required String expectedHead,
    List<String> deletePaths = const [],
  }) async => const PublishCommitSuccess('sha', []);
}

/// Owns a container + the collected UI states for one test.
class _Harness {
  _Harness({_FakeCreds? creds, _FakeGitHubApi? api})
    : creds = creds ?? _FakeCreds(),
      api = api ?? _FakeGitHubApi() {
    container = ProviderContainer(
      overrides: [
        publishCredentialStoreProvider.overrideWithValue(this.creds),
        gitHubApiProvider.overrideWithValue(this.api),
        // Real device flow, but with an instant sleep so tests never wait on
        // real timers.
        gitHubDeviceFlowProvider.overrideWith(
          (ref) => GitHubDeviceFlow(
            ref.watch(gitHubApiProvider),
            sleep: (_) async {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    subscription = container.listen(gitHubConnectionControllerProvider, (
      _,
      next,
    ) {
      final value = next.valueOrNull;
      if (value != null) states.add(value);
    }, fireImmediately: true);
  }

  late final ProviderContainer container;
  final _FakeCreds creds;
  final _FakeGitHubApi api;
  late final ProviderSubscription<AsyncValue<GitHubConnectionUi>> subscription;

  /// Every emitted (non-loading) UI state, in order.
  final List<GitHubConnectionUi> states = [];

  GitHubConnectionController get notifier =>
      container.read(gitHubConnectionControllerProvider.notifier);

  /// Completes the initial build() and returns the first state.
  Future<GitHubConnectionUi> settle() =>
      container.read(gitHubConnectionControllerProvider.future);

  GitHubConnectionUi get last => states.last;
}

void main() {
  test('build() loads signed-in flag + target repo; the token itself never '
      'enters the state', () async {
    final h = _Harness(
      creds: _FakeCreds(token: 'SECRET-TOKEN', targetRepo: 'me/lib'),
    );
    final first = await h.settle();

    expect(first.signedIn, isTrue);
    expect(first.targetRepo, 'me/lib');
    expect(first.phase, GitHubConnectionPhase.idle);
    // SECURITY (AGENTS §6.2): only the boolean crosses — assert every
    // rendered field is free of the token value.
    final rendered = h.states
        .map(
          (s) =>
              '${s.phase}|${s.signedIn}|${s.targetRepo}|${s.repos}|'
              '${s.awaitingUserCode}|${s.awaitingVerificationUri}|'
              '${s.repoPromptInitialName}|${s.statusMessage}',
        )
        .join('\n');
    expect(rendered, isNot(contains('SECRET-TOKEN')));
  });

  test('build() with empty store starts signed out with no target', () async {
    final h = _Harness();
    final first = await h.settle();
    expect(first.signedIn, isFalse);
    expect(first.targetRepo, isNull);
  });

  group('signIn()', () {
    test('success passes through awaitingUser, stores the token once, and — '
        'with no stored target — signals the one-tap setup prompt', () async {
      final h = _Harness();
      await h.settle();

      await h.notifier.signIn();

      // The flow passed through the awaiting-user phase with the code +
      // verification URI the dialog needs.
      final awaiting = h.states.where(
        (s) => s.phase == GitHubConnectionPhase.awaitingUser,
      );
      expect(awaiting, isNotEmpty);
      expect(awaiting.last.awaitingUserCode, 'ABCD-1234');
      expect(
        awaiting.last.awaitingVerificationUri,
        'https://github.com/login/device',
      );

      // Terminal state: signed in, dialog state cleared, fixed message.
      expect(h.last.phase, GitHubConnectionPhase.idle);
      expect(h.last.signedIn, isTrue);
      expect(h.last.awaitingUserCode, isNull);
      expect(h.last.awaitingVerificationUri, isNull);
      expect(h.last.statusMessage, 'Signed in.');

      // The token went to the store exactly once…
      expect(h.creds.setTokenCalls, ['tok-123']);
      // …and never into any emitted state (AGENTS §6.2).
      final rendered = h.states
          .map(
            (s) =>
                '${s.statusMessage}|${s.awaitingUserCode}|'
                '${s.awaitingVerificationUri}|${s.targetRepo}',
          )
          .join('\n');
      expect(rendered, isNot(contains('tok-123')));

      // No stored target ⇒ the one-tap setup prompt is signalled.
      expect(h.last.repoPromptInitialName, 'my-library');
    });

    test('one-tap path: answering the prompt runs setup and stores the '
        'target', () async {
      final h = _Harness();
      await h.settle();
      await h.notifier.signIn();
      expect(h.last.repoPromptInitialName, 'my-library');

      await h.notifier.createRepo(h.last.repoPromptInitialName!);

      // SetupGitHubRepo ran against the fake api: repo created, Pages
      // enabled, target stored (ready to publish, N09).
      expect(h.api.createdRepoName, 'my-library');
      expect(h.api.pagesEnabled, isTrue);
      expect(await h.creds.targetRepo(), 'user/my-library');
      expect(h.last.targetRepo, 'user/my-library');
      expect(h.last.repoPromptInitialName, isNull);
      expect(
        h.last.statusMessage,
        'Repository user/my-library created — ready to publish!',
      );
    });

    test(
      'with a stored target, sign-in does NOT signal the setup prompt',
      () async {
        final h = _Harness(
          creds: _FakeCreds(targetRepo: 'user/old-repo'),
          api: _FakeGitHubApi(),
        );
        await h.settle();

        await h.notifier.signIn();

        expect(h.last.signedIn, isTrue);
        expect(h.last.targetRepo, 'user/old-repo');
        expect(h.last.repoPromptInitialName, isNull);
        expect(h.api.createdRepoName, isNull);
      },
    );

    test(
      'denied ends with the fixed message and clears the dialog state',
      () async {
        final h = _Harness(api: _FakeGitHubApi(polls: [const PollDenied()]));
        await h.settle();
        await h.notifier.signIn();

        expect(h.last.phase, GitHubConnectionPhase.idle);
        expect(h.last.signedIn, isFalse);
        expect(h.last.statusMessage, 'Authorization denied.');
        expect(h.last.awaitingUserCode, isNull);
        expect(h.creds.setTokenCalls, isEmpty);
      },
    );

    test(
      'expired ends with the fixed message and clears the dialog state',
      () async {
        final h = _Harness(api: _FakeGitHubApi(polls: [const PollExpired()]));
        await h.settle();
        await h.notifier.signIn();

        expect(h.last.statusMessage, 'The code expired. Please try again.');
        expect(h.last.awaitingUserCode, isNull);
      },
    );

    test('failed (fatal poll error) maps to the safe fixed message — '
        'transport detail never reaches the UI', () async {
      final h = _Harness(
        api: _FakeGitHubApi(
          polls: [const PollFatal('device_flow_disabled for client X')],
        ),
      );
      await h.settle();
      await h.notifier.signIn();

      expect(
        h.last.statusMessage,
        'Sign-in failed. Check your connection and try again.',
      );
      expect(h.last.statusMessage, isNot(contains('device_flow_disabled')));
      expect(h.last.awaitingUserCode, isNull);
    });

    test('a transport failure when requesting the device code also ends on '
        'the fixed message', () async {
      final api = _ThrowingRequestApi();
      final h = _Harness(api: api);
      await h.settle();
      await h.notifier.signIn();

      expect(
        h.last.statusMessage,
        'Sign-in failed. Check your connection and try again.',
      );
      expect(h.last.phase, GitHubConnectionPhase.idle);
    });

    test(
      'a second signIn() while one is running is refused (fail closed)',
      () async {
        final gate = Completer<void>();
        final h = _Harness(api: _FakeGitHubApi(gate: gate));
        await h.settle();

        final first = h.notifier.signIn();
        // Let the flow reach the pending poll.
        await Future<void>.delayed(Duration.zero);
        expect(h.last.phase, GitHubConnectionPhase.awaitingUser);

        await h.notifier.signIn(); // must be a no-op
        expect(h.api.deviceCodeRequests, 1);

        gate.complete();
        await first;
        expect(h.last.signedIn, isTrue);
      },
    );

    test('provider disposal mid-flow: keepAlive holds the element, the link '
        'is released on the terminal state, and nothing emits into a '
        'disposed provider', () async {
      final gate = Completer<void>();
      final creds = _FakeCreds();
      final api = _FakeGitHubApi(gate: gate);
      final container = ProviderContainer(
        overrides: [
          publishCredentialStoreProvider.overrideWithValue(creds),
          gitHubApiProvider.overrideWithValue(api),
          gitHubDeviceFlowProvider.overrideWith(
            (ref) => GitHubDeviceFlow(
              ref.watch(gitHubApiProvider),
              sleep: (_) async {},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final states = <GitHubConnectionUi>[];
      final sub = container.listen(gitHubConnectionControllerProvider, (
        _,
        next,
      ) {
        final v = next.valueOrNull;
        if (v != null) states.add(v);
      }, fireImmediately: true);
      await container.read(gitHubConnectionControllerProvider.future);

      final pending = container
          .read(gitHubConnectionControllerProvider.notifier)
          .signIn();
      await Future<void>.delayed(Duration.zero);
      expect(states.last.phase, GitHubConnectionPhase.awaitingUser);

      // Drop the listener mid-flow: the keepAlive link (taken by signIn)
      // must keep the element alive — same pattern as PublishController.
      sub.close();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(
        container.exists(gitHubConnectionControllerProvider),
        isTrue,
        reason: 'keepAlive must pin the element while sign-in runs',
      );

      // Finish the flow: token stored, link released…
      gate.complete();
      await pending;
      expect(creds.setTokenCalls, ['tok-123']);

      // …and with no listeners left, autoDispose reclaims the element.
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(container.exists(gitHubConnectionControllerProvider), isFalse);
    });
  });

  group('signOut()', () {
    test(
      'clears token AND target repo (D3-a) and returns to signed-out',
      () async {
        final h = _Harness(
          creds: _FakeCreds(token: 'TKN', targetRepo: 'user/old'),
        );
        await h.settle();
        expect(h.last.signedIn, isTrue);

        await h.notifier.signOut();

        expect(await h.creds.token(), isNull);
        expect(await h.creds.targetRepo(), isNull);
        expect(h.last.signedIn, isFalse);
        expect(h.last.targetRepo, isNull);
        expect(h.last.repos, isEmpty);
        expect(h.last.statusMessage, 'Signed out.');
      },
    );
  });

  group('loadRepos()', () {
    test('stores the listing in state', () async {
      final h = _Harness(
        creds: _FakeCreds(token: 'TKN'),
        api: _FakeGitHubApi(
          listing: const RepoListing(
            repos: [GitHubRepo(fullName: 'user/shelf', isPrivate: false)],
            truncated: true,
          ),
        ),
      );
      await h.settle();

      await h.notifier.loadRepos();

      expect(h.last.repos.single.fullName, 'user/shelf');
      expect(h.last.reposTruncated, isTrue);
      expect(h.last.phase, GitHubConnectionPhase.idle);
    });

    test(
      'a failed load shows a safe fixed message (no raw exception text)',
      () async {
        final h = _Harness(
          creds: _FakeCreds(token: 'TKN'),
          api: _FakeGitHubApi(throwOnUserRepos: true),
        );
        await h.settle();

        await h.notifier.loadRepos();

        expect(
          h.last.statusMessage,
          'Could not list your repositories. Try again.',
        );
        expect(h.last.statusMessage, isNot(contains('boom')));
        expect(h.last.phase, GitHubConnectionPhase.idle);
      },
    );
  });

  group('createRepo()', () {
    test('a validation failure re-arms the prompt with the rejected name and '
        'shows the actionable message', () async {
      final h = _Harness(creds: _FakeCreds(token: 'TKN'));
      await h.settle();

      await h.notifier.createRepo('bad name!');

      expect(h.last.phase, GitHubConnectionPhase.idle);
      expect(h.last.repoPromptInitialName, 'bad name!');
      expect(h.last.statusMessage, contains('Repository names can use'));
      expect(h.api.createdRepoName, isNull);
    });

    test('a transport failure ends with the safe fixed message and no '
        're-prompt', () async {
      final h = _Harness(
        creds: _FakeCreds(token: 'TKN'),
        api: _FakeGitHubApi(throwOnLogin: true),
      );
      await h.settle();

      await h.notifier.createRepo('good-name');

      expect(
        h.last.statusMessage,
        'Could not set up the repository. Check your connection and try '
        'again.',
      );
      expect(h.last.repoPromptInitialName, isNull);
      expect(await h.creds.targetRepo(), isNull);
    });

    test("a secure-storage write failure (past the use case's Either "
        'mapping) still unfreezes the tab and shows the fixed message — '
        'fail closed, no raw platform text', () async {
      final h = _Harness(
        creds: _FakeCreds(
          token: 'TKN',
          throwOnSetTargetRepo: Exception('Keystore: key invalidated'),
        ),
      );
      await h.settle();

      // Must not throw out to the caller (the widget's onPressed).
      await h.notifier.createRepo('good-name');

      expect(h.last.phase, GitHubConnectionPhase.idle);
      expect(
        h.last.statusMessage,
        'Could not set up the repository. Check your connection and try '
        'again.',
      );
      expect(h.last.statusMessage, isNot(contains('Keystore')));
      // The target was never stored; state must not claim otherwise.
      expect(h.last.targetRepo, isNull);
      // Buttons unfrozen ⇒ a retry is accepted (not refused as "busy").
      h.notifier.requestRepoSetup();
      expect(h.last.repoPromptInitialName, 'my-library');
    });

    test('skipRepoSetup: no target yet → nudge message; with target → '
        'message cleared', () async {
      final h = _Harness(creds: _FakeCreds(token: 'TKN'));
      await h.settle();

      h.notifier.requestRepoSetup();
      expect(h.last.repoPromptInitialName, 'my-library');

      h.notifier.skipRepoSetup();
      expect(h.last.repoPromptInitialName, isNull);
      expect(
        h.last.statusMessage,
        'Signed in. Set up a repository to publish.',
      );

      // With a target already stored, backing out changes nothing.
      final h2 = _Harness(
        creds: _FakeCreds(token: 'TKN', targetRepo: 'user/kept'),
      );
      await h2.settle();
      h2.notifier.requestRepoSetup();
      h2.notifier.skipRepoSetup();
      expect(h2.last.repoPromptInitialName, isNull);
      expect(h2.last.statusMessage, isNull);
      expect(h2.last.targetRepo, 'user/kept');
    });
  });

  group('selectRepo()', () {
    GitHubRepoDetails owned({String owner = 'user'}) => GitHubRepoDetails(
      fullName: '$owner/shelf',
      ownerLogin: owner,
      isPrivate: false,
      isArchived: false,
      defaultBranch: 'main',
      canPush: true,
      canAdmin: true,
    );

    test(
      'adopts the repo through the full N09 rules and stores the target',
      () async {
        final h = _Harness(
          creds: _FakeCreds(token: 'TKN'),
          api: _FakeGitHubApi(details: owned()),
        );
        await h.settle();

        await h.notifier.selectRepo('user/shelf');

        expect(h.api.pagesEnabled, isTrue);
        expect(await h.creds.targetRepo(), 'user/shelf');
        expect(h.last.targetRepo, 'user/shelf');
        expect(
          h.last.statusMessage,
          'Connected to your existing user/shelf — ready to publish!',
        );
      },
    );

    test('a repo owned by someone else is refused and NOT stored', () async {
      final h = _Harness(
        creds: _FakeCreds(token: 'TKN'),
        api: _FakeGitHubApi(details: owned(owner: 'someone-else')),
      );
      await h.settle();

      await h.notifier.selectRepo('user/shelf');

      expect(await h.creds.targetRepo(), isNull);
      expect(h.last.targetRepo, isNull);
      expect(h.last.statusMessage, contains('owned by the GitHub account'));
      expect(h.api.pagesEnabled, isFalse);
    });

    test('a secure-storage write failure during adopt still unfreezes the '
        'tab and shows the fixed message (fail closed)', () async {
      final h = _Harness(
        creds: _FakeCreds(
          token: 'TKN',
          throwOnSetTargetRepo: Exception('Keystore: key invalidated'),
        ),
        api: _FakeGitHubApi(details: owned()),
      );
      await h.settle();

      await h.notifier.selectRepo('user/shelf');

      expect(h.last.phase, GitHubConnectionPhase.idle);
      expect(
        h.last.statusMessage,
        'Could not connect that repository. Check your connection and try '
        'again.',
      );
      expect(h.last.statusMessage, isNot(contains('Keystore')));
      expect(h.last.targetRepo, isNull);
      // A follow-up intent is accepted: the phase guard is not stuck on busy.
      await h.notifier.loadRepos();
      expect(h.last.phase, GitHubConnectionPhase.idle);
    });
  });
}

/// requestDeviceCode itself throwing (transport down before the flow starts).
class _ThrowingRequestApi extends _FakeGitHubApi {
  @override
  Future<DeviceCodeGrant> requestDeviceCode({
    required String clientId,
    required String scope,
  }) => throw const GitHubApiException('no route to host');
}
