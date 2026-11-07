import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/vault/domain/borrower_limit_policy.dart';
import 'package:pitaka/features/vault/infrastructure/prefs_borrower_limit_policy_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<PrefsBorrowerLimitPolicyStore> _store() async =>
    PrefsBorrowerLimitPolicyStore(await SharedPreferences.getInstance());

BorrowerLimitPolicy _policy(int? limit, BorrowerLimitAction action) =>
    BorrowerLimitPolicy.validate(
      maxActiveLoans: limit,
      action: action,
    ).toNullable()!;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('absent is null; enabled and disabled policies round trip', () async {
    expect((await _store()).load().toNullable(), isNull);

    final enabled = _policy(3, BorrowerLimitAction.refuse);
    expect((await (await _store()).save(enabled)).isRight(), isTrue);
    final loadedEnabled = (await _store()).load().toNullable()!;
    expect(loadedEnabled.maxActiveLoans, 3);
    expect(loadedEnabled.action, BorrowerLimitAction.refuse);

    expect(
      (await (await _store()).save(BorrowerLimitPolicy.off)).isRight(),
      isTrue,
    );
    final loadedOff = (await _store()).load().toNullable()!;
    expect(loadedOff.isOn, isFalse);
    expect(loadedOff.action, BorrowerLimitAction.warn);
  });

  test(
    'wrong preference type, malformed JSON and bad versions are unreadable',
    () async {
      final values = <Object>[
        true,
        '{"version":1,',
        jsonEncode({'version': 2}),
        jsonEncode({'version': 1.0}),
        jsonEncode({'version': '1'}),
      ];
      for (final value in values) {
        SharedPreferences.setMockInitialValues({
          PrefsBorrowerLimitPolicyStore.key: value,
        });
        expect((await _store()).load().isLeft(), isTrue, reason: '$value');
      }
    },
  );

  test(
    'wrong field types, bad limits and unknown actions are unreadable',
    () async {
      final documents = <Map<String, Object?>>[
        {'version': 1, 'maxActiveLoans': '3', 'action': 'warn'},
        {'version': 1, 'maxActiveLoans': 3.0, 'action': 'warn'},
        {'version': 1, 'maxActiveLoans': 0, 'action': 'warn'},
        {'version': 1, 'maxActiveLoans': 100, 'action': 'warn'},
        {'version': 1, 'maxActiveLoans': -1, 'action': 'warn'},
        {'version': 1, 'maxActiveLoans': 3, 'action': 'unknown'},
        {'version': 1, 'maxActiveLoans': 3, 'action': 1},
        {'version': 1, 'maxActiveLoans': 3},
      ];
      for (final document in documents) {
        SharedPreferences.setMockInitialValues({
          PrefsBorrowerLimitPolicyStore.key: jsonEncode(document),
        });
        expect((await _store()).load().isLeft(), isTrue, reason: '$document');
      }
    },
  );

  test('oversized input is rejected before decoding', () async {
    SharedPreferences.setMockInitialValues({
      PrefsBorrowerLimitPolicyStore.key: 'x' * 257,
    });
    expect((await _store()).load().isLeft(), isTrue);
  });

  test('saving replaces a wrong-typed corrupt preference', () async {
    SharedPreferences.setMockInitialValues({
      PrefsBorrowerLimitPolicyStore.key: true,
    });
    final result = await (await _store()).save(BorrowerLimitPolicy.off);
    expect(result.isRight(), isTrue);
    expect((await _store()).load().toNullable(), isNotNull);
  });
}
