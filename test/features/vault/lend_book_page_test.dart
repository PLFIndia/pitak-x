/// Review finding N12 widget test: the lend screen's borrower dropdown
/// must constrain long names at narrow widths / large text instead of
/// overflowing (isExpanded + ellipsis).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/vault/application/lend_book_use_case.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/borrower_limit_policy.dart';
import 'package:pitaka/features/vault/domain/borrower_limit_policy_store.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';
import 'package:pitaka/features/vault/infrastructure/vault_store.dart';
import 'package:pitaka/features/vault/presentation/pages/lend_book_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/a11y.dart';
import '../../support/fake_vault_session.dart';
import '../../support/form_back_harness.dart';
import 'vault_repository_write_stub.dart';

class _ReadOnlyVault with VaultWriteUnsupported implements VaultRepository {
  _ReadOnlyVault(this.data);
  final VaultData data;

  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async => right(data);

  @override
  Future<Either<Failure, String>> createVault({
    required SecretBytes passphrase,
    required String dbPath,
  }) async => right('test-blob');
}

class _UnavailableItems implements CatalogueItemRepository {
  _UnavailableItems(this.result);

  final Either<Failure, CatalogueItem?> result;

  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async => result;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

class _UnusedLender implements VaultLender {
  @override
  List<Loan>? get currentLoans => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

class _UnusedPolicyStore implements BorrowerLimitPolicyStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

final class _UseCaseCall {
  const _UseCaseCall({
    required this.bookId,
    required this.target,
    required this.lentDate,
    required this.dueDate,
    required this.notes,
    required this.acknowledged,
  });

  final int bookId;
  final LendTarget target;
  final int lentDate;
  final int? dueDate;
  final String? notes;
  final bool acknowledged;
}

class _ScriptedUseCase extends LendBookUseCase {
  _ScriptedUseCase(this.results)
    : super(
        books: _UnavailableItems(right(null)),
        vault: _UnusedLender(),
        policyStore: _UnusedPolicyStore(),
      );

  final List<Either<Failure, LendOutcome>> results;
  final calls = <_UseCaseCall>[];

  /// While set, a call waits for it before it answers (P4-M1: "Back while
  /// the lend runs").
  Completer<void>? hold;

  @override
  Future<Either<Failure, LendOutcome>> call({
    required int bookId,
    required LendTarget target,
    required int lentDate,
    int? dueDate,
    String? notes,
    bool limitWarningAcknowledged = false,
  }) {
    calls.add(
      _UseCaseCall(
        bookId: bookId,
        target: target,
        lentDate: lentDate,
        dueDate: dueDate,
        notes: notes,
        acknowledged: limitWarningAcknowledged,
      ),
    );
    if (calls.length > results.length) {
      throw StateError('Unexpected extra lend call ${calls.length}');
    }
    final result = results[calls.length - 1];
    final held = hold;
    if (held == null) return Future.value(result);
    return held.future.then((_) => result);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('lend_page_test');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> pumpScripted(
    WidgetTester tester,
    _ScriptedUseCase useCase, {
    VaultData? data,
  }) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = VaultStore(baseDir: '${tmp.path}/vault');
    final container = ProviderContainer(
      overrides: [
        lendBookUseCaseProvider.overrideWith((ref) async => useCase),
        vaultStoreProvider.overrideWith((ref) async => store),
        vaultRepositoryProvider.overrideWith(
          (ref) => _ReadOnlyVault(
            data ??
                const VaultData(
                  borrowers: [Borrower(id: 1, name: 'Asha')],
                  loans: [],
                ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(vaultSessionControllerProvider.future);
    final enabled = await container
        .read(vaultSessionControllerProvider.notifier)
        .enable(SecretBytes(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])));
    expect(enabled.isRight(), isTrue);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          initialRoute: '/lend',
          routes: {
            '/': (_) => const Scaffold(body: Text('Host')),
            '/lend': (_) => const LendBookPage(bookId: 7, bookTitle: 'Godaan'),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectAsha(WidgetTester tester) async {
    await tester.tap(find.byType(DropdownButtonFormField<int?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asha').last);
    await tester.pumpAndSettle();
  }

  testWidgets('N12: a very long borrower name does not overflow at 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final longName = 'A' * 120;
    final data = VaultData(
      borrowers: [Borrower(id: 1, name: longName)],
      loans: const [],
    );
    final store = VaultStore(baseDir: '${tmp.path}/vault');
    final container = ProviderContainer(
      overrides: [
        vaultStoreProvider.overrideWith((ref) async => store),
        vaultRepositoryProvider.overrideWith((ref) => _ReadOnlyVault(data)),
      ],
    );
    addTearDown(container.dispose);

    await container.read(vaultSessionControllerProvider.future);
    final enabled = await container
        .read(vaultSessionControllerProvider.notifier)
        .enable(SecretBytes(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])));
    expect(enabled.isRight(), isTrue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: LendBookPage(bookId: 7, bookTitle: 'Godaan'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lend item'), findsOneWidget);
    expect(find.text('Lend book'), findsNothing);
    expect(find.byType(DropdownButtonFormField<int?>), findsOneWidget);

    // Open the menu: the 120-char item must ellipsize, not overflow.
    await tester.tap(find.byType(DropdownButtonFormField<int?>));
    await tester.pumpAndSettle();
    expect(find.textContaining('AAAA'), findsWidgets);
    expect(tester.takeException(), isNull);

    // Select the long-named borrower: the closed field shows the name
    // ellipsized inside 320px (isExpanded), still no overflow.
    await tester.tap(find.textContaining('AAAA').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('S9: the locked lending screen uses neutral item copy', (
    tester,
  ) async {
    final store = VaultStore(baseDir: '${tmp.path}/vault');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultStoreProvider.overrideWith((ref) async => store),
          vaultRepositoryProvider.overrideWith(
            (ref) => _ReadOnlyVault(VaultData.empty),
          ),
        ],
        child: const MaterialApp(
          home: LendBookPage(bookId: 7, bookTitle: 'Chess set'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lend item'), findsOneWidget);
    expect(find.text('Unlock the vault to lend an item.'), findsOneWidget);
    expect(find.textContaining('book'), findsNothing);
  });

  Future<void> expectLendFailure(
    WidgetTester tester,
    _UnavailableItems items,
    String expected,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = VaultStore(baseDir: '${tmp.path}/vault');
    final container = ProviderContainer(
      overrides: [
        catalogueItemRepositoryProvider.overrideWith((ref) async => items),
        vaultStoreProvider.overrideWith((ref) async => store),
        vaultRepositoryProvider.overrideWith(
          (ref) => _ReadOnlyVault(VaultData.empty),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(vaultSessionControllerProvider.future);
    final enabled = await container
        .read(vaultSessionControllerProvider.notifier)
        .enable(SecretBytes(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])));
    expect(enabled.isRight(), isTrue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: LendBookPage(bookId: 7, bookTitle: 'Frontline — No 5'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Asha');
    await tester.tap(find.widgetWithText(FilledButton, 'Lend'));
    await tester.pumpAndSettle();

    expect(find.text('Lend item'), findsOneWidget);
    expect(find.text(expected), findsOneWidget);
    expect(find.textContaining('book'), findsNothing);
  }

  testWidgets('S9: a missing item uses neutral lending error copy', (
    tester,
  ) async {
    await expectLendFailure(
      tester,
      _UnavailableItems(right(null)),
      'That item or borrower no longer exists.',
    );
  });

  testWidgets('S9: a lending read failure uses neutral error copy', (
    tester,
  ) async {
    await expectLendFailure(
      tester,
      _UnavailableItems(left(const StorageFailure('private database detail'))),
      'Could not lend the item. Please try again.',
    );
    expect(find.textContaining('private database detail'), findsNothing);
  });

  testWidgets('Cancel clears busy without a second lend call', (tester) async {
    final useCase = _ScriptedUseCase([
      right(const LimitConfirmationNeeded(limit: 1, active: 1)),
    ]);
    await pumpScripted(tester, useCase);
    await selectAsha(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Lend'));
    // Busy stays on while the modal is open, so the spinner never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Borrower Asha has 1 item out; your limit is 1. Lend anyway?'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(useCase.calls, hasLength(1));
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Lend'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('barrier dismissal also clears busy without another call', (
    tester,
  ) async {
    final useCase = _ScriptedUseCase([
      right(const LimitConfirmationNeeded(limit: 1, active: 1)),
    ]);
    await pumpScripted(tester, useCase);
    await selectAsha(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Lend'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(useCase.calls, hasLength(1));
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Lend'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('confirm acknowledges and retries the identical submission', (
    tester,
  ) async {
    final useCase = _ScriptedUseCase([
      right(const LimitConfirmationNeeded(limit: 3, active: 4)),
      right(const LoanRecorded()),
    ]);
    await pumpScripted(tester, useCase);
    await selectAsha(tester);
    await tester.enterText(find.byType(TextField), 'Preserve notes');
    await tester.tap(find.widgetWithText(TextButton, 'Pick'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Lend'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Borrower Asha has 4 items out; your limit is 3. Lend anyway?'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<int?>>(
            find.byType(DropdownButtonFormField<int?>),
          )
          .onChanged,
      isNull,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Pick'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Lend anyway'));
    await tester.pumpAndSettle();

    expect(useCase.calls, hasLength(2));
    final first = useCase.calls.first;
    final second = useCase.calls.last;
    expect(first.acknowledged, isFalse);
    expect(second.acknowledged, isTrue);
    expect(second.target, same(first.target));
    expect((second.target as ExistingBorrower).id, 1);
    expect(second.bookId, first.bookId);
    expect(second.lentDate, first.lentDate);
    expect(second.dueDate, isNotNull);
    expect(second.dueDate, first.dueDate);
    expect(second.notes, 'Preserve notes');
    expect(find.byType(LendBookPage), findsNothing);
    expect(find.text('Host'), findsOneWidget);
  });

  testWidgets('confirmation uses generic copy when no name is available', (
    tester,
  ) async {
    final useCase = _ScriptedUseCase([
      right(const LimitConfirmationNeeded(limit: 1, active: 1)),
    ]);
    await pumpScripted(tester, useCase, data: VaultData.empty);
    await tester.enterText(find.byType(TextField).first, 'Asha');

    await tester.tap(find.widgetWithText(FilledButton, 'Lend'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('This borrower has 1 item out; your limit is 1. Lend anyway?'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(useCase.calls, hasLength(1));
  });

  testWidgets('borrower refusal shows its safe text inline', (tester) async {
    final message = borrowerLimitRefusalMessage(activeLoans: 4, limit: 3);
    final useCase = _ScriptedUseCase([left(ValidationFailure(message))]);
    await pumpScripted(tester, useCase);
    await selectAsha(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Lend'));
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(useCase.calls, hasLength(1));
  });

  // Review finding P4-M1: Back must not throw away what was entered without
  // asking. The form stands above the page 'Host' (see `pumpScripted`);
  // "the form is gone" means 'Host' shows again.
  group('leaving the form (P4-M1)', () {
    final page = find.byType(LendBookPage);
    final newName = find.widgetWithText(TextField, 'New borrower name');
    final notes = find.widgetWithText(TextField, 'Notes (optional)');
    final lend = find.widgetWithText(FilledButton, 'Lend');

    void expectGoneWithoutQuestion() {
      expect(findDiscardQuestion(), findsNothing);
      expect(page, findsNothing);
      expect(find.text('Host'), findsOneWidget);
    }

    void expectAsked() {
      expect(findDiscardQuestion(), findsOneWidget);
      expect(page, findsOneWidget);
    }

    testWidgets('untouched, Back: the form leaves at once', (tester) async {
      await pumpScripted(tester, _ScriptedUseCase([]));
      await pressSystemBack(tester);

      expectGoneWithoutQuestion();
    });

    testWidgets('the screen "Unlock the vault to lend an item." has nothing '
        'to lose: Back leaves, no question', (tester) async {
      await pumpFormAboveHome(
        tester,
        const LendBookPage(bookId: 7, bookTitle: 'Godaan'),
        overrides: [
          vaultSessionControllerProvider.overrideWith(
            () => FixedVaultSession(const VaultLocked()),
          ),
        ],
      );
      expect(find.text('Unlock the vault to lend an item.'), findsOneWidget);
      await pressSystemBack(tester);

      expect(findDiscardQuestion(), findsNothing);
      expect(page, findsNothing);
      expect(findFormBackHome(), findsOneWidget);
    });

    testWidgets('a new name typed, Back: the question. "Keep editing" keeps '
        'the form and the text; Back again and "Discard" leaves', (
      tester,
    ) async {
      final useCase = _ScriptedUseCase([]);
      await pumpScripted(tester, useCase);
      await tester.enterText(newName, 'Meera');
      await pressSystemBack(tester);
      expectAsked();
      expect(
        find.text('What you entered on this page has not been saved.'),
        findsOneWidget,
      );

      await tester.tap(findKeepEditing());
      await tester.pumpAndSettle();
      expect(findDiscardQuestion(), findsNothing);
      expect(find.widgetWithText(TextField, 'Meera'), findsOneWidget);

      await pressSystemBack(tester);
      await tester.tap(findDiscard());
      await tester.pumpAndSettle();
      expectGoneWithoutQuestion();
      expect(useCase.calls, isEmpty, reason: 'discarded, nothing lent');
    });

    testWidgets('the question shows nothing that was typed', (tester) async {
      await pumpScripted(tester, _ScriptedUseCase([]));
      await tester.enterText(newName, 'Meera Private');
      await pressSystemBack(tester);
      expectAsked();

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('Meera'),
        ),
        findsNothing,
      );
    });

    testWidgets('the form shows exactly the two text fields these tests '
        'know', (tester) async {
      await pumpScripted(tester, _ScriptedUseCase([]));

      expect(find.byType(TextField), findsNWidgets(2));
      expect(newName, findsOneWidget);
      expect(notes, findsOneWidget);
    });

    testWidgets('notes typed, Back: the question', (tester) async {
      await pumpScripted(tester, _ScriptedUseCase([]));
      await tester.enterText(notes, 'Back by Friday');
      await pressSystemBack(tester);

      expectAsked();
    });

    testWidgets('an existing borrower picked, Back: the question', (
      tester,
    ) async {
      await pumpScripted(tester, _ScriptedUseCase([]));
      await selectAsha(tester);
      await pressSystemBack(tester);

      expectAsked();
    });

    testWidgets('a due date picked, Back: the question', (tester) async {
      await pumpScripted(tester, _ScriptedUseCase([]));
      await tester.tap(find.widgetWithText(TextButton, 'Pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('No due date'), findsNothing);
      await pressSystemBack(tester);

      expectAsked();
    });

    testWidgets('the arrow of the app bar asks as well', (tester) async {
      await pumpScripted(tester, _ScriptedUseCase([]));
      await tester.enterText(newName, 'Meera');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expectAsked();
    });

    testWidgets('typed and put back, Back: leaves', (tester) async {
      await pumpScripted(tester, _ScriptedUseCase([]));
      await tester.enterText(newName, 'Meera');
      await tester.enterText(newName, '');
      await pressSystemBack(tester);

      expectGoneWithoutQuestion();
    });

    testWidgets('Back while the lend runs does nothing; the form then '
        'leaves by itself, with no question (D95)', (tester) async {
      final useCase = _ScriptedUseCase([right(const LoanRecorded())])
        ..hold = Completer<void>();
      await pumpScripted(tester, useCase);
      await selectAsha(tester);
      await tester.tap(lend);
      // No waiting for rest: the button shows a spinner while held.
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await pressSystemBack(tester, settle: false);
      expect(findDiscardQuestion(), findsNothing);
      expect(page, findsOneWidget, reason: 'Back waits for the lend');

      useCase.hold!.complete();
      await tester.pumpAndSettle();
      expectGoneWithoutQuestion();
      expect(useCase.calls, hasLength(1));
    });

    testWidgets('after a lend that was refused, Back asks', (tester) async {
      final useCase = _ScriptedUseCase([
        left(const ValidationFailure('This item is not available.')),
      ]);
      await pumpScripted(tester, useCase);
      await selectAsha(tester);
      await tester.tap(lend);
      await tester.pumpAndSettle();
      expect(find.text('This item is not available.'), findsOneWidget);
      await pressSystemBack(tester);

      expectAsked();
    });

    testWidgets('the limit dialog is open, Back: that dialog closes, no '
        '"Discard changes?" on top of it, the form stays; Back again asks', (
      tester,
    ) async {
      final useCase = _ScriptedUseCase([
        right(const LimitConfirmationNeeded(limit: 1, active: 1)),
      ]);
      await pumpScripted(tester, useCase);
      await selectAsha(tester);
      await tester.tap(lend);
      // Busy stays on while the dialog is open: the spinner never rests.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Borrower limit reached'), findsOneWidget);

      await pressSystemBack(tester);
      expect(find.text('Borrower limit reached'), findsNothing);
      expect(findDiscardQuestion(), findsNothing);
      expect(page, findsOneWidget);
      expect(useCase.calls, hasLength(1), reason: 'not lent anyway');

      await pressSystemBack(tester);
      expectAsked();
    });
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    const data = VaultData(
      borrowers: [Borrower(id: 1, name: 'Asha')],
      loans: [],
    );
    final store = VaultStore(baseDir: '${tmp.path}/vault');
    final container = ProviderContainer(
      overrides: [
        vaultStoreProvider.overrideWith((ref) async => store),
        vaultRepositoryProvider.overrideWith((ref) => _ReadOnlyVault(data)),
      ],
    );
    addTearDown(container.dispose);

    await container.read(vaultSessionControllerProvider.future);
    final enabled = await container
        .read(vaultSessionControllerProvider.notifier)
        .enable(SecretBytes(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])));
    expect(enabled.isRight(), isTrue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: LendBookPage(bookId: 7, bookTitle: 'Godaan'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectMeetsA11yGuidelines(tester);
  });
}
