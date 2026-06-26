/// GitHub Device Flow orchestrator (application layer, AGENTS.md §4, #32).
///
/// Port of Kotlin `GitHubDeviceFlow`. Emits a [DeviceFlowState] stream: request
/// a device+user code, surface it for the user to enter in their browser, then
/// poll until the user authorizes (Success), denies, lets it expire, or it
/// fails. The user registers their OWN OAuth App and supplies the client id —
/// zero developer infrastructure (§1.1).
library;

import 'package:pitaka/features/publish/domain/github_api.dart';

/// States emitted while running the device flow.
sealed class DeviceFlowState {
  const DeviceFlowState();
}

/// Requesting the device code.
final class DeviceFlowStarting extends DeviceFlowState {
  /// Creates the starting state.
  const DeviceFlowStarting();
}

/// Waiting for the user to authorize in their browser.
final class DeviceFlowAwaitingUser extends DeviceFlowState {
  /// Creates the awaiting state.
  const DeviceFlowAwaitingUser({
    required this.userCode,
    required this.verificationUri,
  });

  /// The short code the user types.
  final String userCode;

  /// Where the user enters [userCode].
  final String verificationUri;
}

/// The user authorized; carries the access token + granted scope.
final class DeviceFlowSuccess extends DeviceFlowState {
  /// Creates the success state.
  const DeviceFlowSuccess(this.accessToken, this.scope);

  /// The OAuth access token.
  final String accessToken;

  /// Granted scope.
  final String scope;
}

/// The user denied the request.
final class DeviceFlowDenied extends DeviceFlowState {
  /// Creates the denied state.
  const DeviceFlowDenied();
}

/// The device code expired before authorization.
final class DeviceFlowExpired extends DeviceFlowState {
  /// Creates the expired state.
  const DeviceFlowExpired();
}

/// The flow failed (transport/config); [reason] is a short diagnostic.
final class DeviceFlowFailed extends DeviceFlowState {
  /// Creates the failed state.
  const DeviceFlowFailed(this.reason);

  /// Diagnostic (safe to show as a generic hint).
  final String reason;
}

/// Runs GitHub Device Flow against a [GitHubApi].
final class GitHubDeviceFlow {
  /// Creates the flow. [sleep] is injectable so tests don't wait in real time.
  GitHubDeviceFlow(this._api, {Future<void> Function(Duration)? sleep})
    : _sleep = sleep ?? Future<void>.delayed;

  final GitHubApi _api;
  final Future<void> Function(Duration) _sleep;

  /// `public_repo` suffices for publishing to a user-owned public repo (§1.1).
  static const String defaultScope = 'public_repo';

  /// Drives the flow for [clientId], emitting states until a terminal one.
  Stream<DeviceFlowState> start(
    String clientId, {
    String scope = defaultScope,
  }) async* {
    yield const DeviceFlowStarting();

    final DeviceCodeGrant grant;
    try {
      grant = await _api.requestDeviceCode(clientId: clientId, scope: scope);
    } on GitHubApiException catch (e) {
      yield DeviceFlowFailed(e.message);
      return;
    }

    yield DeviceFlowAwaitingUser(
      userCode: grant.userCode,
      verificationUri: grant.verificationUri,
    );

    var intervalMs = grant.intervalSeconds * 1000;
    final deadline = DateTime.now().add(
      Duration(seconds: grant.expiresInSeconds),
    );

    while (DateTime.now().isBefore(deadline)) {
      await _sleep(Duration(milliseconds: intervalMs));
      final PollResult r;
      try {
        r = await _api.pollAccessToken(
          clientId: clientId,
          deviceCode: grant.deviceCode,
        );
      } on GitHubApiException catch (e) {
        yield DeviceFlowFailed(e.message);
        return;
      }
      switch (r) {
        case PollAuthorized(:final accessToken, :final scope):
          yield DeviceFlowSuccess(accessToken, scope);
          return;
        case PollPending(:final slowDown):
          if (slowDown) intervalMs += 5000;
        case PollDenied():
          yield const DeviceFlowDenied();
          return;
        case PollExpired():
          yield const DeviceFlowExpired();
          return;
      }
    }
    yield const DeviceFlowExpired();
  }
}
