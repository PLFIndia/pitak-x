/// Immutable, secret-free UI state for the GitHub connection tab.
library;

import 'package:pitaka/features/publish/domain/github_models.dart';

/// What the GitHub connection tab is doing right now.
enum GitHubConnectionPhase {
  /// Nothing running; action buttons enabled.
  idle,

  /// The device flow is starting or polling.
  signingIn,

  /// Waiting for the user to enter the device code in their browser.
  awaitingUser,

  /// Any other operation (repo setup, listing, adoption, publish) is running.
  busy,
}

/// Immutable screen state for the GitHub connection tab.
///
/// Nothing in this class is secret, by construction: the token never enters
/// the state, so no field needs redaction.
final class GitHubConnectionUi {
  /// Creates the screen state.
  const GitHubConnectionUi({
    this.phase = GitHubConnectionPhase.idle,
    this.signedIn = false,
    this.targetRepo,
    this.repos = const [],
    this.reposTruncated = false,
    this.awaitingUserCode,
    this.awaitingVerificationUri,
    this.repoPromptInitialName,
    this.statusMessage,
  });

  /// Anything other than idle disables action buttons.
  final GitHubConnectionPhase phase;

  /// Only the boolean "signed in" enters state — never the token.
  final bool signedIn;

  /// Selected owner/repository target, or null before setup.
  final String? targetRepo;

  /// Bounded repository choices shown by the advanced picker.
  final List<GitHubRepo> repos;

  /// Whether the bounded listing may be incomplete.
  final bool reposTruncated;

  /// Device-flow code that is safe to display to the user.
  final String? awaitingUserCode;

  /// Validated-by-the-domain device authorization address.
  final String? awaitingVerificationUri;

  /// Initial repository name for a controller-requested prompt.
  final String? repoPromptInitialName;

  /// Fixed, safe messages only; never raw exception or API text.
  final String? statusMessage;

  /// A copy with the given fields replaced. The [_keep] sentinel distinguishes
  /// an omitted nullable field from an explicit request to clear it.
  GitHubConnectionUi copyWith({
    GitHubConnectionPhase? phase,
    bool? signedIn,
    Object? targetRepo = _keep,
    List<GitHubRepo>? repos,
    bool? reposTruncated,
    Object? awaitingUserCode = _keep,
    Object? awaitingVerificationUri = _keep,
    Object? repoPromptInitialName = _keep,
    Object? statusMessage = _keep,
  }) {
    return GitHubConnectionUi(
      phase: phase ?? this.phase,
      signedIn: signedIn ?? this.signedIn,
      targetRepo: identical(targetRepo, _keep)
          ? this.targetRepo
          : targetRepo as String?,
      repos: repos ?? this.repos,
      reposTruncated: reposTruncated ?? this.reposTruncated,
      awaitingUserCode: identical(awaitingUserCode, _keep)
          ? this.awaitingUserCode
          : awaitingUserCode as String?,
      awaitingVerificationUri: identical(awaitingVerificationUri, _keep)
          ? this.awaitingVerificationUri
          : awaitingVerificationUri as String?,
      repoPromptInitialName: identical(repoPromptInitialName, _keep)
          ? this.repoPromptInitialName
          : repoPromptInitialName as String?,
      statusMessage: identical(statusMessage, _keep)
          ? this.statusMessage
          : statusMessage as String?,
    );
  }
}

/// "Leave this field alone" marker for [GitHubConnectionUi.copyWith].
const Object _keep = Object();
