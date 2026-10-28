/// GitHub connection screen state + orchestration (application layer,
/// AGENTS.md §4/§7, presentation stays render-only, AGENTS §7).
///
/// Why a controller: the sign-in flow, token persistence, one-tap repo setup,
/// repo listing/adoption are business decisions. Widgets may
/// only RENDER state and forward intents — this class is the single place
/// those decisions live (and get unit-tested). It replaces the orchestration
/// that used to live in `_ConnectionTabState` (26 `setState` calls, direct
/// credential-store writes from a widget callback, free-text `_status`).
///
/// Security (AGENTS §6.2): the GitHub access token NEVER enters
/// [GitHubConnectionUi]. On `DeviceFlowSuccess` the controller hands the token
/// straight to `PublishCredentialStore.setToken` and records only the boolean
/// "signed in". Status messages are a fixed, safe set — raw transport/API text
/// never reaches the UI verbatim (AGENTS §5).
library;

import 'dart:async';

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/application/github_connection_ui.dart';
import 'package:pitaka/features/publish/application/github_device_flow.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'github_connection_ui.dart';

part 'github_connection_controller.g.dart';

/// Owns the GitHub connection tab's state machine (application layer).
///
/// The page watches this provider and only renders the state + forwards
/// intents (sign-in tapped → [signIn], repo picked → [selectRepo], …).
@riverpod
class GitHubConnectionController extends _$GitHubConnectionController {
  /// True once the provider has been torn down (mirrors `ExportController`'s
  /// `_disposed` flag): after disposal, state writes are refused so a late
  /// async completion can never emit into a dead element.
  bool _disposed = false;

  /// Initial suggestion for the one-tap repo name prompt.
  static const String defaultRepoSuggestion = 'my-library';

  /// Fixed, safe messages (AGENTS §5). The shared "connected" line is a
  /// function because it names the adopted repo.
  static String _connected(String fullName) =>
      'Connected to your existing $fullName — ready to publish!';
  static const String _setupFailed =
      'Could not set up the repository. Check your connection and try again.';
  static const String _connectFailed =
      'Could not connect that repository. Check your connection and try '
      'again.';
  static const String _signInFailed =
      'Sign-in failed. Check your connection and try again.';

  @override
  FutureOr<GitHubConnectionUi> build() async {
    ref.onDispose(() => _disposed = true);
    // Only the BOOLEAN "signed in" enters the state — never the token
    // (AGENTS §6.2).
    final creds = ref.watch(publishCredentialStoreProvider);
    final token = await creds.token();
    final repo = await creds.targetRepo();
    return GitHubConnectionUi(signedIn: token != null, targetRepo: repo);
  }

  /// The current UI state, or null while the first [build] is still loading.
  /// All intents no-op before that — fail closed (AGENTS §2.7).
  GitHubConnectionUi? get _current => state.valueOrNull;

  /// Applies [update] to the current state; refuses after disposal.
  void _emit(GitHubConnectionUi Function(GitHubConnectionUi current) update) {
    if (_disposed) return;
    final current = _current;
    if (current == null) return;
    state = AsyncData(update(current));
  }

  /// Runs [op] with the autoDispose element pinned for its duration.
  ///
  /// Why keepAlive: this provider is autoDispose and the page may stop
  /// listening mid-flow (e.g. tab disposed) — Riverpod would then dispose +
  /// rebuild the element mid-operation and the trailing `state =` would hit
  /// the rebuilt element ("Bad state: Future already completed"). The link
  /// pins the element until [op] finishes. Same pattern as
  /// `PublishController.publish` (AGENTS §4 — justified non-default lifetime).
  Future<void> _runExclusive(Future<void> Function() op) async {
    if (_disposed) return;
    final link = ref.keepAlive();
    try {
      await op();
    } finally {
      link.close();
    }
  }

  /// The repo-ADMIN role view of the shared GitHub client (S5, ISP): the
  /// repo picker needs `userRepos` and nothing else, so the narrow role type
  /// is named HERE at the boundary instead of depending on the aggregate.
  GitHubRepoAdminApi get _repoAdminApi => ref.read(gitHubApiProvider);

  /// Starts the GitHub device-flow sign-in.
  ///
  /// The flow is an async GENERATOR: it is suspended at `yield` until this
  /// loop asks for the next state. Because the loop lives here (not in the
  /// widget), showing the user-code dialog can never pause token polling.
  /// On success the token goes straight into the secure store; with no stored
  /// target, the one-tap setup prompt is signalled via
  /// [GitHubConnectionUi.repoPromptInitialName].
  Future<void> signIn() async {
    final current = _current;
    // Guard: refuse a second flow while one runs (fail closed).
    if (current == null || current.phase != GitHubConnectionPhase.idle) {
      return;
    }
    final flow = ref.read(gitHubDeviceFlowProvider);
    final creds = ref.read(publishCredentialStoreProvider);
    await _runExclusive(() async {
      _emit(
        (c) => c.copyWith(
          phase: GitHubConnectionPhase.signingIn,
          statusMessage: 'Starting…',
        ),
      );
      try {
        await for (final s in flow.start()) {
          switch (s) {
            case DeviceFlowStarting():
              _emit(
                (c) => c.copyWith(
                  phase: GitHubConnectionPhase.signingIn,
                  statusMessage: 'Starting…',
                ),
              );
            case DeviceFlowAwaitingUser(
              :final userCode,
              :final verificationUri,
            ):
              _emit(
                (c) => c.copyWith(
                  phase: GitHubConnectionPhase.awaitingUser,
                  awaitingUserCode: userCode,
                  awaitingVerificationUri: verificationUri,
                  // Both values are display data (the code exists to be typed
                  // by the user) — safe to surface (§5).
                  statusMessage: 'Enter code $userCode at $verificationUri',
                ),
              );
            case DeviceFlowSuccess(:final accessToken):
              // SECURITY (AGENTS §6.2): the token goes directly into the
              // secure credential store — it never enters GitHubConnectionUi,
              // a status message, or a log.
              // Browser authorization stays OUTSIDE the publish queue; only
              // the credential-write critical section enters it (R11).
              await ref
                  .read(publishOperationQueueProvider)
                  .enqueue(() => creds.setToken(accessToken));
              final repo = await creds.targetRepo();
              _emit(
                (c) => c.copyWith(
                  phase: GitHubConnectionPhase.idle,
                  signedIn: true,
                  targetRepo: repo,
                  awaitingUserCode: null,
                  awaitingVerificationUri: null,
                  statusMessage: 'Signed in.',
                ),
              );
              // One-tap setup (mirrors Localcart Orange): brand-new users get
              // a publish-ready repo right away. Existing users keep their
              // stored target untouched — the prompt only fires when none is
              // set.
              if (repo == null) {
                _emit(
                  (c) =>
                      c.copyWith(repoPromptInitialName: defaultRepoSuggestion),
                );
              }
            case DeviceFlowDenied():
              _emit(
                (c) => c.copyWith(
                  phase: GitHubConnectionPhase.idle,
                  awaitingUserCode: null,
                  awaitingVerificationUri: null,
                  statusMessage: 'Authorization denied.',
                ),
              );
            case DeviceFlowExpired():
              _emit(
                (c) => c.copyWith(
                  phase: GitHubConnectionPhase.idle,
                  awaitingUserCode: null,
                  awaitingVerificationUri: null,
                  statusMessage: 'The code expired. Please try again.',
                ),
              );
            case DeviceFlowFailed():
              // Fixed message (§5): the reason can carry transport/API text
              // that must not reach the UI verbatim.
              _emit(
                (c) => c.copyWith(
                  phase: GitHubConnectionPhase.idle,
                  awaitingUserCode: null,
                  awaitingVerificationUri: null,
                  statusMessage: _signInFailed,
                ),
              );
          }
        }
      } catch (_) {
        // Fail closed (AGENTS §2.7): the flow maps every EXPECTED failure to a
        // DeviceFlowState, so reaching here means something unexpected. Rather
        // than letting the tab freeze mid-sign-in (buttons disabled forever)
        // or leaking raw error text, end on a safe terminal state.
        _emit(
          (c) => c.copyWith(
            phase: GitHubConnectionPhase.idle,
            awaitingUserCode: null,
            awaitingVerificationUri: null,
            statusMessage: _signInFailed,
          ),
        );
      }
    });
  }

  /// Sign-out forgets BOTH the token and the target repo (N09, D3-a). The
  /// target belongs to the account that chose it; a different account signing
  /// in next must never inherit a repository it may not own. The publish
  /// manifest is kept: the last published site still exists, so the journal's
  /// verified share address remains available after sign-out.
  Future<void> signOut() async {
    if (_current == null) return;
    await _runExclusive(() async {
      final creds = ref.read(publishCredentialStoreProvider);
      await ref.read(publishOperationQueueProvider).enqueue(() async {
        await creds.clearToken();
        await creds.clearTargetRepo();
      });
      _emit(
        (c) => c.copyWith(
          phase: GitHubConnectionPhase.idle,
          signedIn: false,
          targetRepo: null,
          repos: const [],
          reposTruncated: false,
          statusMessage: 'Signed out.',
        ),
      );
    });
  }

  /// Loads the signed-in account's repositories for the picker (N09).
  Future<void> loadRepos() async {
    final current = _current;
    if (current == null || current.phase != GitHubConnectionPhase.idle) {
      return;
    }
    await _runExclusive(() async {
      final creds = ref.read(publishCredentialStoreProvider);
      final token = await creds.token();
      if (token == null) return;
      _emit((c) => c.copyWith(phase: GitHubConnectionPhase.busy));
      try {
        final listing = await _repoAdminApi.userRepos(token);
        _emit(
          (c) => c.copyWith(
            repos: listing.repos,
            reposTruncated: listing.truncated,
          ),
        );
      } on GitHubApiException {
        // Fixed message (§5): exception text can carry transport/API detail.
        _emit(
          (c) => c.copyWith(
            statusMessage: 'Could not list your repositories. Try again.',
          ),
        );
      } finally {
        // Fail closed: whatever happened above, the buttons unfreeze.
        _emit((c) => c.copyWith(phase: GitHubConnectionPhase.idle));
      }
    });
  }

  /// Signals the page to show the "name your repository" prompt (the Create /
  /// Set-up button). The dialog itself stays UI; its answer comes back through
  /// [createRepo] or [skipRepoSetup].
  void requestRepoSetup() {
    final current = _current;
    if (current == null ||
        !current.signedIn ||
        current.phase != GitHubConnectionPhase.idle) {
      return;
    }
    _emit((c) => c.copyWith(repoPromptInitialName: defaultRepoSuggestion));
  }

  /// The user backed out of the repo-name prompt. With a target already
  /// stored nothing changes; otherwise nudge — the advanced picker can also
  /// set one.
  void skipRepoSetup() {
    _emit(
      (c) => c.copyWith(
        repoPromptInitialName: null,
        statusMessage: c.targetRepo == null
            ? 'Signed in. Set up a repository to publish.'
            : null,
      ),
    );
  }

  /// Creates (or adopts) a repo named [name] and enables Pages in one go
  /// (SetupGitHubRepo). A validation failure re-arms the prompt with the
  /// rejected name so a typo doesn't dead-end the flow; anything else ends
  /// the attempt with a safe, fixed message.
  Future<void> createRepo(String name) async {
    final current = _current;
    if (current == null || current.phase != GitHubConnectionPhase.idle) {
      return;
    }
    await _runExclusive(() async {
      final creds = ref.read(publishCredentialStoreProvider);
      final token = await creds.token();
      if (token == null) {
        _emit((c) => c.copyWith(repoPromptInitialName: null));
        return;
      }
      _emit(
        (c) => c.copyWith(
          phase: GitHubConnectionPhase.busy,
          repoPromptInitialName: null,
          statusMessage: 'Setting up "$name" on GitHub…',
        ),
      );
      // The use-case call sits INSIDE the try: it maps GitHub transport
      // errors to Either, but its final step writes the target to secure
      // storage, which can still throw (e.g. a Keystore failure). The
      // finally below must run for that path too, or the tab stays frozen.
      try {
        // .match maps Either→outcome (codebase convention, §5).
        final result = await ref
            .read(publishOperationQueueProvider)
            .enqueue(
              () => ref
                  .read(setupGitHubRepoProvider)
                  .call(token: token, repoName: name),
            );
        await result.match<Future<void>>(
          (failure) async {
            if (failure is ValidationFailure) {
              // Our own fixed, actionable copy; re-prompt so the user can
              // fix the name.
              _emit(
                (c) => c.copyWith(
                  phase: GitHubConnectionPhase.idle,
                  statusMessage: failure.message,
                  repoPromptInitialName: name,
                ),
              );
              return;
            }
            _emit(
              (c) => c.copyWith(
                phase: GitHubConnectionPhase.idle,
                statusMessage: _setupFailed,
              ),
            );
          },
          (r) async {
            // Setup stores the target LAST (only after every check passed).
            final repo = await creds.targetRepo();
            _emit(
              (c) => c.copyWith(
                phase: GitHubConnectionPhase.idle,
                targetRepo: repo,
                statusMessage: r.created
                    ? 'Repository ${r.fullName} created — ready to publish!'
                    : _connected(r.fullName),
              ),
            );
          },
        );
      } on Exception {
        // Same convention as publish()/signIn(): an exception past the use
        // case's own Either mapping ends on the fixed message — its text can
        // carry platform/storage detail that must not reach the UI (§5).
        _emit(
          (c) => c.copyWith(
            phase: GitHubConnectionPhase.idle,
            statusMessage: _setupFailed,
          ),
        );
      } finally {
        // Fail closed: whatever escaped above (even a non-Exception Error),
        // the buttons unfreeze.
        _emit(
          (c) => c.phase == GitHubConnectionPhase.busy
              ? c.copyWith(phase: GitHubConnectionPhase.idle)
              : c,
        );
      }
    });
  }

  /// Adopts an existing repo through the SAME rules as the one-tap setup
  /// (N09): ownership, push rights, and a Pages layout the app can publish to
  /// are verified — and Pages is enabled when off — before the target is
  /// stored. "Connected" therefore always means "ready to publish".
  Future<void> selectRepo(String fullName) async {
    final current = _current;
    if (current == null || current.phase != GitHubConnectionPhase.idle) {
      return;
    }
    await _runExclusive(() async {
      final creds = ref.read(publishCredentialStoreProvider);
      final token = await creds.token();
      if (token == null) return;
      _emit(
        (c) => c.copyWith(
          phase: GitHubConnectionPhase.busy,
          statusMessage: 'Checking $fullName…',
        ),
      );
      // The adopt call sits INSIDE the try (see createRepo): its final
      // secure-storage write of the target can throw past the Either mapping.
      try {
        final result = await ref
            .read(publishOperationQueueProvider)
            .enqueue(
              () => ref
                  .read(setupGitHubRepoProvider)
                  .adopt(token: token, fullName: fullName),
            );
        await result.match<Future<void>>(
          (failure) async {
            // A ValidationFailure carries our own fixed, actionable copy;
            // every other failure ends with a safe generic line (§5).
            _emit(
              (c) => c.copyWith(
                phase: GitHubConnectionPhase.idle,
                statusMessage: failure is ValidationFailure
                    ? failure.message
                    : _connectFailed,
              ),
            );
          },
          (r) async {
            _emit(
              (c) => c.copyWith(
                phase: GitHubConnectionPhase.idle,
                statusMessage: _connected(r.fullName),
              ),
            );
          },
        );
        // Mirrors the old widget's `_refresh()`: re-read the stored target
        // (adopt stores it on success; unchanged on failure).
        final repo = await creds.targetRepo();
        _emit((c) => c.copyWith(targetRepo: repo));
      } on Exception {
        // Fixed message (§5) — see createRepo for why this branch exists.
        _emit(
          (c) => c.copyWith(
            phase: GitHubConnectionPhase.idle,
            statusMessage: _connectFailed,
          ),
        );
      } finally {
        // Fail closed: the buttons unfreeze on every path.
        _emit(
          (c) => c.phase == GitHubConnectionPhase.busy
              ? c.copyWith(phase: GitHubConnectionPhase.idle)
              : c,
        );
      }
    });
  }
}
