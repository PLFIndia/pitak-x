import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_account_flow.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_connection_ui.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_error_messages.dart';

import '../../support/cloudflare_fakes.dart';

/// L1/D7: the legacy-token explanation must reach the user, and the account
/// verification flag must reach `selectAccount`.
void main() {
  CloudflareAccountFlow flowFor(
    CloudflareSetupHarness h, {
    required void Function(String? message) onPrompt,
    bool manual = false,
  }) => CloudflareAccountFlow(
    awaitInput:
        <T>(prompt, {accounts = const [], initialValue, message}) async {
          onPrompt(message);
          if (prompt == CloudflareSetupPrompt.manualAccount) {
            return cloudflareTestAccountId as T;
          }
          if (manual) return const CloudflareAccountChoice(manual: true) as T;
          return CloudflareAccountChoice(
                account: CloudflareAccount(
                  id: cloudflareTestAccount(),
                  name: 'Library account',
                ),
              )
              as T;
        },
    enqueue: <T>(command) => command(h.setup),
    unwrap: <T>(result) async => result.toNullable(),
    reload: ({String? message}) async {},
    continueFrom: (_) async => true,
  );

  test(
    'the fallback explanation reaches the picker and the account verify',
    () async {
      final h = CloudflareSetupHarness();
      h.api.userVerifyError = CloudflareApiException(
        CloudflareApiExceptionKind.unauthorized,
      );
      final token = cloudflareLegacyTestToken();
      final discovery = (await h.setup.begin(token)).toNullable()!;
      expect(discovery.accountVerificationPending, isTrue);

      String? shown;
      await flowFor(
        h,
        onPrompt: (message) => shown = message,
      ).run(right(discovery), pendingToken: token);

      expect(shown, CloudflareErrorMessages.legacyTokenAccountCheck);
      expect(h.api.accountVerifyCalls, 1);
      expect(
        h.credentials.record?.status.accountId?.value,
        cloudflareTestAccountId,
      );
    },
  );

  test('the manual Account ID path also carries the explanation', () async {
    final h = CloudflareSetupHarness();
    h.api
      ..userVerifyError = CloudflareApiException(
        CloudflareApiExceptionKind.unauthorized,
      )
      ..listError = CloudflareApiException(
        CloudflareApiExceptionKind.unauthorized,
      );
    final token = cloudflareLegacyTestToken();
    final discovery = (await h.setup.begin(token)).toNullable()!;
    expect(discovery.manualRequired, isTrue);

    final shown = <String?>[];
    await flowFor(
      h,
      onPrompt: shown.add,
    ).run(right(discovery), pendingToken: token);

    expect(shown, contains(CloudflareErrorMessages.legacyTokenAccountCheck));
    expect(h.api.accountVerifyCalls, 1);
    expect(
      h.credentials.record?.status.accountId?.value,
      cloudflareTestAccountId,
    );
  });

  test('an ordinary user token shows no legacy explanation', () async {
    final h = CloudflareSetupHarness();
    final token = cloudflareTestToken();
    final discovery = (await h.setup.begin(token)).toNullable()!;

    String? shown;
    await flowFor(
      h,
      onPrompt: (message) => shown = message,
    ).run(right(discovery), pendingToken: token);

    expect(shown, isNull);
    expect(
      h.api.accountVerifyCalls,
      0,
      reason: 'a cfut_ token was already verified as a user token',
    );
  });
}
