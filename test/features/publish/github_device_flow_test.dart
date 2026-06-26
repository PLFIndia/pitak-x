import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/github_device_flow.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';

/// Scriptable GitHubApi for the device-flow state machine.
class _ScriptedApi implements GitHubApi {
  _ScriptedApi(this._polls);
  final List<PollResult> _polls;
  int _i = 0;

  @override
  Future<DeviceCodeGrant> requestDeviceCode({
    required String clientId,
    required String scope,
  }) async => const DeviceCodeGrant(
    deviceCode: 'DC',
    userCode: 'WXYZ-1234',
    verificationUri: 'https://github.test/login/device',
    expiresInSeconds: 900,
    intervalSeconds: 1,
  );

  @override
  Future<PollResult> pollAccessToken({
    required String clientId,
    required String deviceCode,
  }) async => _polls[_i++];

  // Unused in these tests.
  @override
  Future<PublishCommitResult> commitFiles({
    required String owner,
    required String repo,
    required String branch,
    required String token,
    required List<DesiredFile> files,
    required String commitMessage,
  }) => throw UnimplementedError();
  @override
  Future<String?> defaultBranch({
    required String owner,
    required String repo,
    required String token,
  }) => throw UnimplementedError();
  @override
  Future<Map<String, String>> headTreeShas({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) => throw UnimplementedError();
  @override
  Future<bool?> latestPagesBuildStatus({
    required String owner,
    required String repo,
    required String token,
  }) => throw UnimplementedError();
  @override
  Future<String> currentUserLogin(String token) => throw UnimplementedError();
  @override
  Future<List<GitHubRepo>> userRepos(String token) =>
      throw UnimplementedError();
}

void main() {
  Future<void> noSleep(Duration _) async {}

  test('emits Starting, AwaitingUser, then Success', () async {
    final flow = GitHubDeviceFlow(
      _ScriptedApi([
        const PollPending(),
        const PollAuthorized('TOKEN', 'public_repo'),
      ]),
      sleep: noSleep,
    );
    final states = await flow.start('client-id').toList();
    expect(states[0], isA<DeviceFlowStarting>());
    expect(states[1], isA<DeviceFlowAwaitingUser>());
    expect((states[1] as DeviceFlowAwaitingUser).userCode, 'WXYZ-1234');
    expect(states.last, isA<DeviceFlowSuccess>());
    expect((states.last as DeviceFlowSuccess).accessToken, 'TOKEN');
  });

  test('denied short-circuits to Denied', () async {
    final flow = GitHubDeviceFlow(
      _ScriptedApi([const PollDenied()]),
      sleep: noSleep,
    );
    final states = await flow.start('cid').toList();
    expect(states.last, isA<DeviceFlowDenied>());
  });

  test('slow_down keeps polling until success', () async {
    final flow = GitHubDeviceFlow(
      _ScriptedApi([
        const PollPending(slowDown: true),
        const PollPending(),
        const PollAuthorized('T', ''),
      ]),
      sleep: noSleep,
    );
    final states = await flow.start('cid').toList();
    expect(states.last, isA<DeviceFlowSuccess>());
  });
}
