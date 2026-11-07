import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/domain/borrower_limit_policy.dart';
import 'package:pitaka/features/vault/domain/borrower_limit_policy_store.dart';
import 'package:pitaka/features/vault/infrastructure/prefs_borrower_limit_policy_store.dart';
import 'package:pitaka/features/vault/presentation/pages/lending_rules_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/a11y.dart';

class _Store implements BorrowerLimitPolicyStore {
  _Store({this.failWrites = false});

  BorrowerLimitPolicy? stored;
  final bool failWrites;
  Completer<void>? writeGate;

  @override
  Either<Failure, BorrowerLimitPolicy?> load() => Right(stored);

  @override
  Future<Either<Failure, Unit>> save(BorrowerLimitPolicy policy) async {
    await writeGate?.future;
    if (failWrites) return left(const StorageFailure('write refused'));
    stored = policy;
    return right(unit);
  }
}

Future<void> _pump(WidgetTester tester, {_Store? store}) async {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (store != null)
          borrowerLimitPolicyStoreProvider.overrideWith((ref) async => store),
      ],
      child: const MaterialApp(home: LendingRulesPage()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enable(WidgetTester tester) async {
  await tester.tap(find.byType(SwitchListTile));
  await tester.pumpAndSettle();
}

Future<PrefsBorrowerLimitPolicyStore> _realStore() async =>
    PrefsBorrowerLimitPolicyStore(await SharedPreferences.getInstance());

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('valid save persists the limit and Refuse selection', (
    tester,
  ) async {
    await _pump(tester);
    await _enable(tester);
    await tester.enterText(
      find.byKey(const ValueKey('borrower-limit-field')),
      '3',
    );

    var segmented = tester.widget<SegmentedButton<BorrowerLimitAction>>(
      find.byType(SegmentedButton<BorrowerLimitAction>),
    );
    expect(segmented.selected, {BorrowerLimitAction.warn});
    await tester.tap(find.text('Refuse'));
    await tester.pump();
    segmented = tester.widget<SegmentedButton<BorrowerLimitAction>>(
      find.byType(SegmentedButton<BorrowerLimitAction>),
    );
    expect(segmented.selected, {BorrowerLimitAction.refuse});

    await tester.tap(find.byKey(const ValueKey('lending-rules-save')));
    await tester.pumpAndSettle();

    final saved = (await _realStore()).load().toNullable()!;
    expect(saved.maxActiveLoans, 3);
    expect(saved.action, BorrowerLimitAction.refuse);
  });

  testWidgets('0 and 100 fail inline validation without a write', (
    tester,
  ) async {
    await _pump(tester);
    await _enable(tester);
    final fieldFinder = find.byKey(const ValueKey('borrower-limit-field'));
    await tester.enterText(fieldFinder, '0');
    await tester.tap(find.byKey(const ValueKey('lending-rules-save')));
    await tester.pump();

    expect(find.text('Enter a whole number from 1 to 99.'), findsOneWidget);
    final field = tester.widget<TextFormField>(fieldFinder);
    expect(field.validator!('100'), 'Enter a whole number from 1 to 99.');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.get(PrefsBorrowerLimitPolicyStore.key), isNull);
  });

  testWidgets('Save is disabled while a write is pending', (tester) async {
    final store = _Store()..writeGate = Completer<void>();
    await _pump(tester, store: store);
    await _enable(tester);

    await tester.tap(find.byKey(const ValueKey('lending-rules-save')));
    await tester.pump();
    var button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('lending-rules-save')),
    );
    expect(button.onPressed, isNull);

    store.writeGate!.complete();
    await tester.pumpAndSettle();
    button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('lending-rules-save')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('unreadable document renders an editable recovery form', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      PrefsBorrowerLimitPolicyStore.key: true,
    });
    await _pump(tester);

    expect(
      find.text('Lending rules could not be read. Save to set them again.'),
      findsOneWidget,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );

    await _enable(tester);
    await tester.enterText(
      find.byKey(const ValueKey('borrower-limit-field')),
      '2',
    );
    await tester.tap(find.byKey(const ValueKey('lending-rules-save')));
    await tester.pumpAndSettle();

    expect(
      find.text('Lending rules could not be read. Save to set them again.'),
      findsNothing,
    );
    final repaired = (await _realStore()).load().toNullable()!;
    expect(repaired.maxActiveLoans, 2);
    expect(repaired.action, BorrowerLimitAction.warn);
  });

  testWidgets('failed save shows safe copy and preserves entered values', (
    tester,
  ) async {
    await _pump(tester, store: _Store(failWrites: true));
    await _enable(tester);
    const fieldKey = ValueKey('borrower-limit-field');
    await tester.enterText(find.byKey(fieldKey), '7');

    await tester.tap(find.byKey(const ValueKey('lending-rules-save')));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not save lending rules. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('write refused'), findsNothing);
    expect(
      tester.widget<TextFormField>(find.byKey(fieldKey)).controller!.text,
      '7',
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    await _pump(tester);
    await _enable(tester);
    await expectMeetsA11yGuidelines(tester);
  });
}
