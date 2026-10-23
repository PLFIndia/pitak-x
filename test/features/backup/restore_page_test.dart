/// Review finding N13 widget tests: the Restore screen must inspect the
/// archive's bounded manifest FIRST and only ask for a passphrase when the
/// backup actually carries an encrypted vault. A vault-free backup used to
/// demand a password the user never created.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
// Transitive dependency of file_selector; imported only for the picker seam
// below (it also re-exports XFile). Deliberately NOT added to pubspec so the
// dependency surface stays unchanged.
// ignore: depend_on_referenced_packages
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/application/restore_controller.dart';
import 'package:pitaka/features/backup/domain/restore_summary.dart';
import 'package:pitaka/features/backup/presentation/pages/restore_page.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/repositories/vault_repository.dart';

import '../../support/a11y.dart';
import '../library/replacement_test_guard.dart';
import '../vault/vault_repository_write_stub.dart';
import 'generation_fixture.dart';

class _RetainedRestoreController extends RestoreController {
  @override
  RestoreSummary? build() => const RestoreSummary(
    booksRestored: 1,
    wishlistRestored: 0,
    borrowersRestored: 0,
    loansRestored: 0,
    existingVaultKept: true,
  );
}

/// §5.10 outcome-copy fixture: identity adopted + 2 network rows restored.
class _AdoptedRestoreController extends RestoreController {
  @override
  RestoreSummary? build() => const RestoreSummary(
    booksRestored: 1,
    wishlistRestored: 0,
    borrowersRestored: 0,
    loansRestored: 0,
    restoredIdentity: (id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', name: 'M'),
    restoredNetwork: [],
    identityAdopted: true,
    networkApplied: true,
    networkRestored: 2,
  );
}

/// M9 fixture: the restore applied, but the archive dropped unreadable rows.
class _DroppedRowsRestoreController extends RestoreController {
  @override
  RestoreSummary? build() => const RestoreSummary(
    booksRestored: 1,
    wishlistRestored: 0,
    borrowersRestored: 0,
    loansRestored: 0,
    restoredNetwork: [],
    networkApplied: true,
    networkRestored: 1,
    networkRowsDropped: 2,
  );
}

/// §5.10 outcome-copy fixture: identity present but not adoptable, network
/// list unreadable — the two failure sentences.
class _FailedExtrasRestoreController extends RestoreController {
  @override
  RestoreSummary? build() => const RestoreSummary(
    booksRestored: 1,
    wishlistRestored: 0,
    borrowersRestored: 0,
    loansRestored: 0,
    restoredIdentity: (id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', name: 'M'),
    networkInvalid: true,
  );
}

/// W2 outcome-copy fixture (ADR 0014): a series restored, one issue link
/// detached, one kinds row skipped — each named in one sentence.
class _ItemKindsRestoreController extends RestoreController {
  @override
  RestoreSummary? build() => const RestoreSummary(
    booksRestored: 3,
    wishlistRestored: 0,
    borrowersRestored: 0,
    loansRestored: 0,
    kindsApplied: 2,
    periodicalsRestored: 1,
    issuesDetached: 1,
    rowsSkippedUnknownKind: 1,
  );
}

/// W2 failure fixture: both item-details entries declared but unreadable.
class _UnreadableItemDetailsController extends RestoreController {
  @override
  RestoreSummary? build() => const RestoreSummary(
    booksRestored: 3,
    wishlistRestored: 0,
    borrowersRestored: 0,
    loansRestored: 0,
    itemKindsInvalid: true,
    periodicalsInvalid: true,
  );
}

class _FakeVault with VaultWriteUnsupported implements VaultRepository {
  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async => right(VaultData.empty);
}

/// Picker seam: hands back an in-memory [XFile] (no file IO, so the test's
/// FakeAsync zone never blocks).
class _FakeFileSelector extends FileSelectorPlatform {
  _FakeFileSelector(this.bytes, {this.reportedLength});
  final Uint8List bytes;

  /// M05: lets a test hand the page a file whose reported size differs from
  /// its real bytes (a huge declared length without allocating it).
  final int? reportedLength;
  int picks = 0;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    picks++;
    return XFile.fromData(bytes, name: 'test.pitabak', length: reportedLength);
  }
}

/// N11: a vault that parks inside `unlockAndRead` until the test says so,
/// then refuses — this is how a test holds a restore mid-flight.
class _GatedVault with VaultWriteUnsupported implements VaultRepository {
  _GatedVault({required this.entered, required this.gate});

  /// Completes once the restore has reached the vault unlock.
  final Completer<void> entered;

  /// The test's release valve for the parked unlock.
  final Completer<void> gate;

  @override
  Future<Either<Failure, VaultData>> unlockAndRead({
    required SecretBytes passphrase,
    required String blob,
    required String dbPath,
  }) async {
    if (!entered.isCompleted) entered.complete();
    await gate.future;
    return left(const WrongPassphraseFailure());
  }
}

/// A vault-CARRYING archive (manifest + backup_blob + borrowers.db) so the
/// restorer reaches the vault unlock phase.
Uint8List _vaultArchive() {
  final manifest = utf8.encode(
    jsonEncode({
      'schemaVersion': 1,
      'exportedAt': 123,
      'hasBooks': false,
      'hasWishlist': false,
      'hasBorrowers': true,
      'hasBackupBlob': true,
      'hasCovers': false,
    }),
  );
  final blob = utf8.encode('blob-from-archive');
  final borrowersDb = utf8.encode('opaque-encrypted-db');
  final a = Archive()
    ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
    ..addFile(ArchiveFile('backup_blob', blob.length, blob))
    ..addFile(ArchiveFile('borrowers.db', borrowersDb.length, borrowersDb));
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

Uint8List _archive({required bool withVault, int exportedAt = 123}) {
  final manifest = jsonEncode({
    'schemaVersion': 1,
    'exportedAt': exportedAt,
    'hasBooks': true,
    'hasWishlist': true,
    'hasBorrowers': withVault,
    'hasBackupBlob': withVault,
    'hasCovers': false,
  });
  final a = Archive()
    ..addFile(
      ArchiveFile('manifest.json', manifest.length, utf8.encode(manifest)),
    );
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late GenerationFixture gen;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('restore_page_test');
    // M02: the restorer works on a real on-disk data generation.
    gen = GenerationFixture(tmp);
  });

  tearDown(() async {
    await gen.db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget wrap(
    Uint8List archiveBytes, {
    Failure? replacementFailure,
    int? reportedLength,
  }) {
    final restorer = gen.restorer(
      vault: _FakeVault(),
      guard: FakeReplacementGuard(failure: replacementFailure),
    );
    FileSelectorPlatform.instance = _FakeFileSelector(
      archiveBytes,
      reportedLength: reportedLength,
    );
    return ProviderScope(
      overrides: [
        restoreBackupProvider.overrideWith((ref) async => restorer),
        vaultStoreProvider.overrideWith((ref) async => gen.store),
      ],
      child: const MaterialApp(home: RestorePage()),
    );
  }

  Future<void> pick(WidgetTester tester) async {
    await tester.tap(find.text('Choose .pitabak file'));
    await tester.pumpAndSettle();
  }

  testWidgets('vault-free backup: no passphrase asked, Restore enabled', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(_archive(withVault: false)));

    // Before picking: nothing to restore.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );

    await pick(tester);

    // The manifest summary says there is no vault...
    expect(find.textContaining('No borrowers vault'), findsOneWidget);
    // ...so no passphrase field is shown...
    expect(find.text('Passphrase'), findsNothing);
    expect(find.textContaining('no passphrase is needed'), findsOneWidget);
    // ...and Restore is enabled immediately.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isTrue,
    );
  });

  testWidgets('M03: refusal is shown before any restore work', (tester) async {
    await tester.pumpWidget(
      wrap(
        _archive(withVault: false),
        replacementFailure: const ValidationFailure(
          'Unlock the borrowers vault first.',
        ),
      ),
    );
    expect(
      find.textContaining('every book link can be matched safely'),
      findsOneWidget,
    );
    await pick(tester);
    await tester.ensureVisible(find.text('Restore'));
    await tester.pumpAndSettle(); // let the scroll settle before the tap
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock the borrowers vault first.'), findsOneWidget);
    expect(find.text('Restore complete'), findsNothing);
    expect(Directory('${tmp.path}/restore_work').existsSync(), isFalse);
  });

  testWidgets('M03: retained-vault success reports preserved history', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          restoreControllerProvider.overrideWith(
            _RetainedRestoreController.new,
          ),
        ],
        child: const MaterialApp(home: RestorePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('including returned loan history'),
      findsOneWidget,
    );
    expect(find.textContaining('may no longer match'), findsNothing);
  });

  testWidgets('vault backup: passphrase required before Restore enables', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(_archive(withVault: true)));
    await pick(tester);

    expect(
      find.textContaining('encrypted — passphrase required'),
      findsOneWidget,
    );
    expect(find.text('Passphrase'), findsOneWidget);
    // Disabled while the passphrase is empty...
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    // ...enabled once something was entered.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isTrue,
    );
  });

  testWidgets('an unreadable file is rejected before any restore', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(Uint8List.fromList([9, 9, 9])));
    await pick(tester);

    expect(
      find.textContaining('doesn’t look like a valid Pitak backup'),
      findsOneWidget,
    );
    // The bad file was dropped: Restore stays disabled, no passphrase field.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );
    expect(find.text('Passphrase'), findsNothing);
  });

  testWidgets('M05: an oversized pick is refused before it is read', (
    tester,
  ) async {
    // A perfectly valid archive whose picker-reported size is 5 GiB. The
    // page must refuse on the report alone: no bytes buffered, no
    // inspection, nothing to restore.
    await tester.pumpWidget(
      wrap(_archive(withVault: false), reportedLength: 5 * 1024 * 1024 * 1024),
    );
    await pick(tester);

    expect(find.textContaining('too large'), findsOneWidget);
    expect(find.text('Choose .pitabak file'), findsOneWidget);
    expect(find.textContaining('No borrowers vault'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );

    // Picking a sane file afterwards clears the error and proceeds normally.
    FileSelectorPlatform.instance = _FakeFileSelector(
      _archive(withVault: false),
    );
    await pick(tester);
    expect(find.textContaining('too large'), findsNothing);
    expect(find.textContaining('No borrowers vault'), findsOneWidget);
  });

  testWidgets('M15: an out-of-range manifest exportedAt renders without a '
      'date instead of throwing', (tester) async {
    // The manifest is untrusted: exportedAt above DateTime's range used to
    // throw RangeError inside _ManifestSummary.build on INSPECT, before any
    // passphrase or restore.
    await tester.pumpWidget(
      wrap(_archive(withVault: false, exportedAt: 8640000000000001)),
    );
    await pick(tester);

    // The page renders the summary; the date line is simply absent.
    expect(find.textContaining('No borrowers vault'), findsOneWidget);
    expect(find.textContaining('Made on:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('N11: leaving the page mid-restore neither crashes nor loses '
      'the terminal state', (tester) async {
    // The restore outlives the page (keep-alive in the controller). Popping
    // Restore mid-run used to throw StateError in the page's post-await
    // `ref.read` (widget ref dead) AND dispose the controller mid-flight.
    final entered = Completer<void>();
    final gate = Completer<void>();
    final vault = _GatedVault(entered: entered, gate: gate);
    final container = ProviderContainer(
      overrides: [
        restoreBackupProvider.overrideWith(
          (ref) async =>
              gen.restorer(vault: vault, guard: FakeReplacementGuard()),
        ),
        vaultStoreProvider.overrideWith((ref) async => gen.store),
        vaultRepositoryProvider.overrideWithValue(vault),
      ],
    );
    addTearDown(container.dispose);
    FileSelectorPlatform.instance = _FakeFileSelector(_vaultArchive());

    // A listener held by the TEST (not the page) so the terminal state is
    // observable after the page is gone.
    AsyncValue<RestoreSummary?> lastSeen = const AsyncLoading();
    final sub = container.listen(
      restoreControllerProvider,
      (_, next) => lastSeen = next,
    );
    addTearDown(sub.close);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const RestorePage()),
                ),
                child: const Text('open restore'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open restore'));
    await tester.pumpAndSettle();

    await pick(tester);
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    await tester.ensureVisible(find.text('Restore'));
    await tester.pumpAndSettle(); // let the scroll settle before the tap
    await tester.tap(find.text('Restore'));
    await tester.pump();
    // The restore is now parked inside the (gated) vault unlock.
    await entered.future;

    // Leave the page mid-restore. Settle FIRST: the pop animation must
    // finish so the widget is fully disposed before the restore completes —
    // otherwise the continuation races the disposal and the test is flaky.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(lastSeen.error, isA<WrongPassphraseFailure>());
  });

  group('§5.10 — identity + network copy', () {
    /// An archive that also carries identity.json + network.json.
    Uint8List archiveWithExtras() {
      final manifest = utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'exportedAt': 123,
          'hasBooks': false,
          'hasWishlist': false,
          'hasBorrowers': false,
          'hasBackupBlob': false,
          'hasCovers': false,
          'hasIdentity': true,
          'hasNetwork': true,
        }),
      );
      final identity = utf8.encode(
        '{"libraryId": "${'a' * 32}", "libraryName": "Meera Road"}',
      );
      final network = utf8.encode('{"schemaVersion": 1, "libraries": []}');
      final a = Archive()
        ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
        ..addFile(ArchiveFile('identity.json', identity.length, identity))
        ..addFile(ArchiveFile('network.json', network.length, network));
      return Uint8List.fromList(ZipEncoder().encode(a)!);
    }

    testWidgets('inspection names the identity and lists the network', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(archiveWithExtras()));
      await pick(tester);

      expect(
        find.text('• Library identity for "Meera Road" (restoring adopts it)'),
        findsOneWidget,
      );
      expect(find.text('• Saved-libraries list'), findsOneWidget);
    });

    testWidgets('a flagged-but-invalid identity is called out, not promised', (
      tester,
    ) async {
      final manifest = utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'exportedAt': 1,
          'hasBooks': false,
          'hasWishlist': false,
          'hasBorrowers': false,
          'hasBackupBlob': false,
          'hasCovers': false,
          'hasIdentity': true,
        }),
      );
      final badIdentity = utf8.encode('{"libraryId": "NOPE"}');
      final a = Archive()
        ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
        ..addFile(
          ArchiveFile('identity.json', badIdentity.length, badIdentity),
        );
      final zip = Uint8List.fromList(ZipEncoder().encode(a)!);

      await tester.pumpWidget(wrap(zip));
      await pick(tester);

      expect(
        find.text('• Library identity (unreadable — it will not be adopted)'),
        findsOneWidget,
      );
    });

    testWidgets('success sentences: identity adopted + libraries restored', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            restoreControllerProvider.overrideWith(
              _AdoptedRestoreController.new,
            ),
          ],
          child: const MaterialApp(home: RestorePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('This device now uses the backup’s library identity.'),
        findsOneWidget,
      );
      expect(find.text('Saved libraries restored: 2'), findsOneWidget);
    });

    testWidgets('dropped network rows are named in one sentence (M9)', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            restoreControllerProvider.overrideWith(
              _DroppedRowsRestoreController.new,
            ),
          ],
          child: const MaterialApp(home: RestorePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saved libraries restored: 1'), findsOneWidget);
      expect(
        find.text(
          '2 saved-libraries row(s) could not be read from the backup and '
          'were skipped.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('W2 sentences: titles restored, detached + skipped named', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            restoreControllerProvider.overrideWith(
              _ItemKindsRestoreController.new,
            ),
          ],
          child: const MaterialApp(home: RestorePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Magazine titles restored: 1'), findsOneWidget);
      expect(
        find.text(
          '1 issue link(s) could not be honoured; the affected items were '
          'restored as books.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          '1 item-kind row(s) in the backup could not be read; the affected '
          'items were restored as books.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('W2 failure sentences: both entries unreadable', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            restoreControllerProvider.overrideWith(
              _UnreadableItemDetailsController.new,
            ),
          ],
          child: const MaterialApp(home: RestorePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'The item-kind list in this backup could not be read',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'The magazine titles in this backup could not be read',
        ),
        findsOneWidget,
      );
    });

    testWidgets('failure sentences: identity not adopted, list unreadable', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            restoreControllerProvider.overrideWith(
              _FailedExtrasRestoreController.new,
            ),
          ],
          child: const MaterialApp(home: RestorePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'The library identity in this backup could not be adopted',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'The saved-libraries list in this backup could not be read',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    await tester.pumpWidget(wrap(_archive(withVault: false)));
    await tester.pumpAndSettle();
    await expectMeetsA11yGuidelines(tester);
  });
}
