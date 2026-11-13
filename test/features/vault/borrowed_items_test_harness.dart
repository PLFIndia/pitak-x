import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/local_cover_reader.dart';
import 'package:pitaka/features/vault/application/prepare_loan_reminder_use_case.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/borrowed_items.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/loan_status.dart';
import 'package:pitaka/features/vault/presentation/pages/borrowed_items_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

final testNow = DateTime(2026, 11, 6, 12).millisecondsSinceEpoch;

class TestVaultSession extends VaultSessionController {
  TestVaultSession(this._initial);
  final VaultSessionState _initial;

  @override
  Future<VaultSessionState> build() async => _initial;

  void show(VaultSessionState next) {
    state = AsyncData(next);
  }

  void showLoadingWithPrevious() {
    state = const AsyncLoading<VaultSessionState>().copyWithPrevious(state);
  }

  void showErrorWithPrevious() {
    state = AsyncError<VaultSessionState>(
      StateError('session unavailable'),
      StackTrace.current,
    ).copyWithPrevious(state);
  }
}

BorrowedLoan testEntry({
  int loanId = 1,
  int itemId = 2,
  String title = 'Godaan',
  String author = 'Premchand',
  int borrowerId = 3,
  String borrowerName = 'Asha',
  String? contact = 'Phone: +91 98123 45678',
  bool hasPhone = true,
  int? due,
  String? coverUrl,
}) {
  final loan = Loan(
    id: loanId,
    itemId: itemId,
    borrowerId: borrowerId,
    lentDate: 0,
    dueDate: due,
  );
  return BorrowedLoan(
    item: CatalogueItem(id: itemId, title: title, author: author),
    loan: loan,
    borrower: Borrower(
      id: borrowerId,
      name: borrowerName,
      contact: hasPhone ? contact : null,
    ),
    urgency: loanUrgency(loan, testNow),
    coverUrl: coverUrl,
  );
}

class TestCoverReader {
  TestCoverReader([LocalCoverReadResult? result])
    : result =
          result ?? LocalCoverReadSuccess(Uint8List.fromList([0xFF, 0xD8, 7]));
  LocalCoverReadResult result;
  final calls = <String>[];
  Completer<void>? gate;

  Future<LocalCoverReadResult> call(String coverUrl) async {
    calls.add(coverUrl);
    await gate?.future;
    return result;
  }
}

class ShareBytesCall {
  ShareBytesCall({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.text,
    required this.origin,
  });
  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final String? text;
  final Rect? origin;
}

class TestShare implements FileShareService {
  // This screen never shares a file by path (only the backup does, BR4).
  @override
  Future<ShareOutcome> shareFile({
    required String path,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) => throw UnimplementedError();

  final byteCalls = <ShareBytesCall>[];
  final textCalls = <({String text, Rect? origin})>[];
  ShareOutcome outcome = ShareOutcome.success;
  Exception? error;
  Completer<void>? nextBytesGate;

  @override
  Future<ShareOutcome> shareBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? text,
    Rect? sharePositionOrigin,
  }) async {
    byteCalls.add(
      ShareBytesCall(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        text: text,
        origin: sharePositionOrigin,
      ),
    );
    final error = this.error;
    if (error != null) throw error;
    await nextBytesGate?.future;
    nextBytesGate = null;
    return outcome;
  }

  @override
  Future<ShareOutcome> shareText(
    String text, {
    Rect? sharePositionOrigin,
  }) async {
    textCalls.add((text: text, origin: sharePositionOrigin));
    final error = this.error;
    if (error != null) throw error;
    return outcome;
  }
}

Future<({TestVaultSession session, TestCoverReader reader, TestShare share})>
pumpBorrowedItems(
  WidgetTester tester, {
  required BorrowedItemsSnapshot snapshot,
  TestVaultSession? session,
  TestCoverReader? reader,
  TestShare? share,
  Completer<void>? prepareGate,
  List<Override> extraOverrides = const [],
  ThemeData? theme,
  TextScaler? textScaler,
  Map<String, Object>? preferences,
  Size viewport = const Size(800, 1200),
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(preferences ?? {});
  final effectiveSession =
      session ?? TestVaultSession(const VaultUnlocked(VaultData.empty));
  final effectiveReader = reader ?? TestCoverReader();
  final effectiveShare = share ?? TestShare();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        vaultSessionControllerProvider.overrideWith(() => effectiveSession),
        borrowedItemsSnapshotProvider.overrideWith((ref) async => snapshot),
        prepareLoanReminderUseCaseProvider.overrideWith((ref) async {
          await prepareGate?.future;
          return PrepareLoanReminderUseCase(
            coverReader: effectiveReader.call,
            clock: () => testNow,
          );
        }),
        fileShareServiceProvider.overrideWithValue(effectiveShare),
        coversDirProvider.overrideWith((ref) async => '.'),
        ...extraOverrides,
      ],
      child: MaterialApp(
        theme: theme,
        home: const BorrowedItemsPage(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: textScaler ?? TextScaler.noScaling),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    session: effectiveSession,
    reader: effectiveReader,
    share: effectiveShare,
  );
}
