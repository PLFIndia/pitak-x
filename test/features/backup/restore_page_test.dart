/// Widget tests of the Restore screen.
///
/// Review finding N13: the screen must inspect the archive's bounded manifest
/// FIRST and only ask for a passphrase when the backup actually carries an
/// encrypted vault. A vault-free backup used to demand a password the user
/// never created.
///
/// BR6: the page no longer reads the chosen file. It asks the controller
/// for a private copy (`pickArchive`), has it inspected, hands it to
/// `restore`, and gives it back (`releaseArchive`) when it no longer wants
/// it. These tests therefore stand on a SCRIPTED controller: a widget test
/// runs on a made-up clock and cannot wait for the worker isolates and the
/// file work a real restore needs. The real chain (picker, restorer, data
/// generations) is proven in `restore_controller_test.dart`; what is proven
/// here is what the page shows and what it asks of the controller.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/features/backup/application/restore_controller.dart';
import 'package:pitaka/features/backup/domain/archive_inspection.dart';
import 'package:pitaka/features/backup/domain/backup_identity.dart';
import 'package:pitaka/features/backup/domain/backup_manifest.dart';
import 'package:pitaka/features/backup/domain/backup_progress.dart';
import 'package:pitaka/features/backup/domain/restore_summary.dart';
import 'package:pitaka/features/backup/presentation/pages/restore_page.dart';
import 'package:pitaka/features/backup/presentation/restore_messages.dart';

import '../../support/a11y.dart';

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

/// Review finding 4 fixture: the backup's ID was saved but its name was not,
/// and the rollback failed — the page must never say "unchanged".
class _PartiallyAdoptedRestoreController extends RestoreController {
  @override
  RestoreSummary? build() => const RestoreSummary(
    booksRestored: 1,
    wishlistRestored: 0,
    borrowersRestored: 0,
    loansRestored: 0,
    restoredIdentity: (id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', name: 'M'),
    identityPartiallyAdopted: true,
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

/// S5 fixture (M2): detached ROWS and dropped ENTRIES are different units and
/// must appear as two separate sentences.
class _SplitIssueCountsController extends RestoreController {
  @override
  RestoreSummary? build() => const RestoreSummary(
    booksRestored: 3,
    wishlistRestored: 0,
    borrowersRestored: 0,
    loansRestored: 0,
    issuesDetached: 2,
    issueEntriesDropped: 3,
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

/// D23 fixture: the restore left the cover pictures of [titles] out.
class _LeftOutCoversController extends RestoreController {
  _LeftOutCoversController(this.titles);
  final List<String> titles;

  @override
  RestoreSummary? build() => RestoreSummary(
    booksRestored: 7,
    wishlistRestored: 0,
    borrowersRestored: 0,
    loansRestored: 0,
    coverPicturesLeftOut: titles,
  );
}

/// The copy the picker hands out in these tests. The page never opens the
/// file, so no file exists.
const _document = PickedDocument(
  path: '/picked_documents/pick-1/document',
  displayName: 'test.pitabak',
  sizeBytes: 3,
);

/// A second, different copy.
const _secondDocument = PickedDocument(
  path: '/picked_documents/pick-2/document',
  displayName: 'second.pitabak',
  sizeBytes: 5,
);

const _summary = RestoreSummary(
  booksRestored: 1,
  wishlistRestored: 0,
  borrowersRestored: 0,
  loansRestored: 0,
);

/// What an inspection found in a picked backup.
ArchiveInspection _inspection({
  bool withVault = false,
  int exportedAt = 123,
  bool hasIdentity = false,
  bool hasNetwork = false,
  BackupIdentity? identity,
}) => ArchiveInspection(
  manifest: BackupManifest(
    exportedAt: exportedAt,
    hasBorrowers: withVault,
    hasBackupBlob: withVault,
    hasIdentity: hasIdentity || identity != null,
    hasNetwork: hasNetwork,
  ),
  identity: identity,
);

/// A restore controller that does what the test scripted and records what
/// the page asked of it.
///
/// It can hold a pick, an inspection or a restore half-way (`hold…`), which
/// is how a test looks at the page in the middle of one.
class _ScriptedRestoreController extends RestoreController {
  /// The answers of the next picks, in order. A pick nobody scripted is
  /// "cancelled".
  final Queue<DocumentPickResult> picks = Queue();

  /// What every inspection answers.
  Either<Failure, ArchiveInspection> inspection = right(_inspection());

  /// When true, an inspection throws instead of answering.
  bool inspectionThrows = false;

  /// The state a restore ends in.
  AsyncValue<RestoreSummary?> outcome = const AsyncData(_summary);

  /// When set, the step waits for it before it answers.
  Completer<void>? holdPick;
  Completer<void>? holdInspection;
  Completer<void>? holdRestore;

  int pickCalls = 0;
  final List<PickedDocument> inspected = [];
  final List<PickedDocument> released = [];
  final List<({PickedDocument archive, bool withPassphrase})> restores = [];

  @override
  RestoreSummary? build() => null;

  @override
  Future<DocumentPickResult> pickArchive() async {
    pickCalls++;
    await holdPick?.future;
    return picks.isEmpty ? const DocumentPickCancelled() : picks.removeFirst();
  }

  @override
  Future<Either<Failure, ArchiveInspection>> inspectArchive(
    PickedDocument archive,
  ) async {
    inspected.add(archive);
    await holdInspection?.future;
    if (inspectionThrows) throw StateError('the restorer could not be made');
    return inspection;
  }

  @override
  Future<void> restore({
    required PickedDocument archive,
    SecretBytes? passphrase,
  }) async {
    restores.add((archive: archive, withPassphrase: passphrase != null));
    // The real controller owns and wipes the secret; so does this one.
    passphrase?.dispose();
    state = const AsyncLoading();
    await holdRestore?.future;
    state = outcome;
  }

  @override
  Future<void> releaseArchive(PickedDocument archive) async {
    released.add(archive);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ScriptedRestoreController controller;

  setUp(() => controller = _ScriptedRestoreController());

  /// The page on its own, driven by [controller].
  Widget wrap() => ProviderScope(
    overrides: [restoreControllerProvider.overrideWith(() => controller)],
    child: const MaterialApp(home: RestorePage()),
  );

  /// The page behind a button, so a test can leave it and open it again.
  Widget wrapBehindButton() => ProviderScope(
    overrides: [restoreControllerProvider.overrideWith(() => controller)],
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
  );

  /// The "Choose" button, whatever it says at the moment.
  Finder chooseButton() => find.bySubtype<OutlinedButton>();

  /// Taps "Choose" and lets the pick and the inspection run.
  Future<void> pick(WidgetTester tester, [DocumentPickResult? answer]) async {
    controller.picks.add(answer ?? const DocumentPicked(_document));
    await tester.tap(chooseButton());
    await tester.pumpAndSettle();
  }

  Future<void> tapRestore(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Restore'));
    await tester.pumpAndSettle(); // let the scroll settle before the tap
    await tester.tap(find.text('Restore'));
    await tester.pump();
  }

  bool restoreEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled;

  bool chooseEnabled(WidgetTester tester) =>
      tester.widget<OutlinedButton>(chooseButton()).enabled;

  testWidgets('vault-free backup: no passphrase asked, Restore enabled', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());

    // Before picking: nothing to restore.
    expect(restoreEnabled(tester), isFalse);
    expect(find.text('Choose .pitabak file'), findsOneWidget);

    await pick(tester);

    // The button names the chosen document, and the copy was inspected.
    expect(find.text('test.pitabak'), findsOneWidget);
    expect(controller.inspected, [_document]);
    // The manifest summary says there is no vault...
    expect(find.textContaining('No borrowers vault'), findsOneWidget);
    // ...so no passphrase field is shown...
    expect(find.text('Passphrase'), findsNothing);
    expect(find.textContaining('no passphrase is needed'), findsOneWidget);
    // ...and Restore is enabled immediately.
    expect(restoreEnabled(tester), isTrue);
  });

  testWidgets('a document without a name still shows that one is chosen', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    await pick(
      tester,
      const DocumentPicked(
        PickedDocument(
          path: '/p/pick-9/document',
          displayName: '',
          sizeBytes: 1,
        ),
      ),
    );

    expect(find.text('Backup file chosen'), findsOneWidget);
    expect(restoreEnabled(tester), isTrue);
  });

  testWidgets('M03: a refusal by the vault guard is shown, and nothing is '
      'called complete', (tester) async {
    controller.outcome = const AsyncError(
      ValidationFailure('Unlock the borrowers vault first.'),
      StackTrace.empty,
    );
    await tester.pumpWidget(wrap());
    expect(
      find.textContaining('every book link can be matched safely'),
      findsOneWidget,
    );
    await pick(tester);
    await tapRestore(tester);
    await tester.pumpAndSettle();

    expect(find.text('Unlock the borrowers vault first.'), findsOneWidget);
    expect(find.text('Restore complete'), findsNothing);
    // The vault-free backup was restored without a passphrase.
    expect(controller.restores.single.archive, _document);
    expect(controller.restores.single.withPassphrase, isFalse);
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
    controller.inspection = right(_inspection(withVault: true));
    await tester.pumpWidget(wrap());
    await pick(tester);

    expect(
      find.textContaining('encrypted — passphrase required'),
      findsOneWidget,
    );
    expect(find.text('Passphrase'), findsOneWidget);
    // Disabled while the passphrase is empty...
    expect(restoreEnabled(tester), isFalse);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    // ...enabled once something was entered.
    expect(restoreEnabled(tester), isTrue);

    // And the secret travels with the restore.
    await tapRestore(tester);
    await tester.pumpAndSettle();
    expect(controller.restores.single.withPassphrase, isTrue);
  });

  testWidgets('an unreadable file is rejected before any restore, and its '
      'copy is given back', (tester) async {
    controller.inspection = left(const BackupCorruptFailure('not a zip'));
    await tester.pumpWidget(wrap());
    await pick(tester);

    expect(
      find.textContaining('doesn’t look like a valid Pitak backup'),
      findsOneWidget,
    );
    // The bad file was dropped: Restore stays disabled, no passphrase field.
    expect(restoreEnabled(tester), isFalse);
    expect(find.text('Passphrase'), findsNothing);
    expect(find.text('Choose .pitabak file'), findsOneWidget);
    // D25: nobody will read that copy again.
    expect(controller.released, [_document]);
    expect(controller.restores, isEmpty);
  });

  testWidgets('an inspection that throws is a safe sentence, and the copy '
      'is given back', (tester) async {
    controller.inspectionThrows = true;
    await tester.pumpWidget(wrap());
    await pick(tester);

    expect(
      find.text('Could not read that file. Please try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    expect(restoreEnabled(tester), isFalse);
    expect(chooseEnabled(tester), isTrue, reason: 'the user can try again');
    expect(controller.released, [_document]);
  });

  testWidgets('a newer backup schema asks for an update before any restore', (
    tester,
  ) async {
    controller.inspection = left(const SchemaTooNewFailure(99));
    await tester.pumpWidget(wrap());
    await pick(tester);

    expect(
      find.text(
        'This backup was made by a newer version of the app and can’t be '
        'restored here. Please update first.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('valid Pitak backup'), findsNothing);
    expect(restoreEnabled(tester), isFalse);
    expect(controller.released, [_document]);
  });

  testWidgets('M15: an out-of-range manifest exportedAt renders without a '
      'date instead of throwing', (tester) async {
    // The manifest is untrusted: exportedAt above DateTime's range used to
    // throw RangeError inside _ManifestSummary.build on INSPECT, before any
    // passphrase or restore.
    controller.inspection = right(_inspection(exportedAt: 8640000000000001));
    await tester.pumpWidget(wrap());
    await pick(tester);

    // The page renders the summary; the date line is simply absent.
    expect(find.textContaining('No borrowers vault'), findsOneWidget);
    expect(find.textContaining('Made on:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Reading the backup…" is shown while the copy is inspected', (
    tester,
  ) async {
    controller.holdInspection = Completer<void>();
    await tester.pumpWidget(wrap());
    controller.picks.add(const DocumentPicked(_document));
    await tester.tap(chooseButton());
    await tester.pump();
    await tester.pump();

    expect(find.text('Reading the backup…'), findsOneWidget);
    expect(find.text(restoreCopyingMessage), findsNothing);
    expect(chooseEnabled(tester), isFalse);
    expect(restoreEnabled(tester), isFalse);

    controller.holdInspection!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Reading the backup…'), findsNothing);
    expect(restoreEnabled(tester), isTrue);
  });

  group('BR6 — choosing the file', () {
    testWidgets('while the picker is open and the file is copied, one line '
        'says so and both buttons are off', (tester) async {
      controller.holdPick = Completer<void>();
      await tester.pumpWidget(wrap());
      controller.picks.add(const DocumentPicked(_document));

      await tester.tap(chooseButton());
      await tester.pump();

      expect(find.text(restoreCopyingMessage), findsOneWidget);
      expect(chooseEnabled(tester), isFalse);
      expect(restoreEnabled(tester), isFalse);
      expect(controller.pickCalls, 1);

      controller.holdPick!.complete();
      await tester.pumpAndSettle();

      expect(find.text(restoreCopyingMessage), findsNothing);
      expect(find.text('test.pitabak'), findsOneWidget);
      expect(chooseEnabled(tester), isTrue);
    });

    // Five of the seven answers are a sentence; each is checked against the
    // text of `restore_messages.dart`, and one in full so that a swap of two
    // sentences shows here too.
    for (final (answer, sentence) in <(DocumentPickResult, String)>[
      (
        const DocumentPickTooLarge(),
        'This file is too large to be a Pitak backup. A backup file can be '
            'at most 504.0 MB.',
      ),
      (
        const DocumentPickUnreadable(),
        'That file could not be read. If it is kept online, check the '
            'connection and try again.',
      ),
      (
        const DocumentPickNotSaved(),
        'The file could not be copied to this phone. Free some storage and '
            'try again.',
      ),
      (
        const DocumentPickUnavailable(),
        'Choosing a file is not available on this device.',
      ),
      (
        const DocumentPickFailed(),
        'Something went wrong choosing the file. Please try again.',
      ),
    ]) {
      testWidgets('${answer.runtimeType}: its sentence, nothing to restore, '
          'and the earlier choice is dropped', (tester) async {
        await tester.pumpWidget(wrap());
        // An earlier, good choice.
        await pick(tester);
        expect(restoreEnabled(tester), isTrue);

        await pick(tester, answer);

        expect(find.text(sentence), findsOneWidget);
        expect(find.text('Choose .pitabak file'), findsOneWidget);
        expect(find.textContaining('This backup contains'), findsNothing);
        expect(restoreEnabled(tester), isFalse);
        expect(chooseEnabled(tester), isTrue);
        // The earlier copy went back; nothing new was inspected.
        expect(controller.released, [_document]);
        expect(controller.inspected, [_document]);
      });
    }

    testWidgets('cancelled: nothing is said and the earlier choice stays', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await pick(tester);

      await pick(tester, const DocumentPickCancelled());

      expect(find.text('test.pitabak'), findsOneWidget);
      expect(find.textContaining('This backup contains'), findsOneWidget);
      expect(restoreEnabled(tester), isTrue);
      expect(controller.released, isEmpty);
      expect(controller.inspected, [_document]);
    });

    testWidgets('cancelled with no earlier choice leaves the page as it '
        'was', (tester) async {
      await tester.pumpWidget(wrap());

      await pick(tester, const DocumentPickCancelled());

      expect(find.text('Choose .pitabak file'), findsOneWidget);
      expect(find.text(restoreCopyingMessage), findsNothing);
      expect(chooseEnabled(tester), isTrue);
      expect(controller.released, isEmpty);
    });

    testWidgets('a sentence about a failed pick goes when a good file is '
        'chosen', (tester) async {
      await tester.pumpWidget(wrap());
      await pick(tester, const DocumentPickTooLarge());
      expect(find.textContaining('too large'), findsOneWidget);

      await pick(tester);

      expect(find.textContaining('too large'), findsNothing);
      expect(find.textContaining('No borrowers vault'), findsOneWidget);
    });

    testWidgets('a new choice gives the earlier copy back and shows the new '
        'one', (tester) async {
      await tester.pumpWidget(wrap());
      await pick(tester);

      await pick(tester, const DocumentPicked(_secondDocument));

      expect(find.text('second.pitabak'), findsOneWidget);
      expect(controller.released, [_document]);
      expect(controller.inspected, [_document, _secondDocument]);

      // And it is the new copy that is restored.
      await tapRestore(tester);
      await tester.pumpAndSettle();
      expect(controller.restores.single.archive, _secondDocument);
    });
  });

  group('BR6 — who holds the copy (D25)', () {
    testWidgets('leaving the page gives the copy back', (tester) async {
      await tester.pumpWidget(wrapBehindButton());
      await tester.tap(find.text('open restore'));
      await tester.pumpAndSettle();
      await pick(tester);
      expect(controller.released, isEmpty);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(controller.released, [_document]);
    });

    testWidgets('leaving the page without a choice gives nothing back', (
      tester,
    ) async {
      await tester.pumpWidget(wrapBehindButton());
      await tester.tap(find.text('open restore'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(controller.released, isEmpty);
    });

    testWidgets('a pick that answers after the page was left gives its copy '
        'back', (tester) async {
      controller.holdPick = Completer<void>();
      await tester.pumpWidget(wrapBehindButton());
      await tester.tap(find.text('open restore'));
      await tester.pumpAndSettle();
      controller.picks.add(const DocumentPicked(_document));
      await tester.tap(chooseButton());
      await tester.pump();

      // The page is left while the picker is still open.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(controller.released, isEmpty);

      controller.holdPick!.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(controller.released, [_document]);
      expect(controller.inspected, isEmpty, reason: 'nobody is looking');
    });

    testWidgets('after a restore that succeeded the page forgets the file', (
      tester,
    ) async {
      await tester.pumpWidget(wrapBehindButton());
      await tester.tap(find.text('open restore'));
      await tester.pumpAndSettle();
      await pick(tester);
      await tapRestore(tester);
      await tester.pumpAndSettle();

      expect(find.text('Restore complete'), findsOneWidget);
      expect(find.text('Choose .pitabak file'), findsOneWidget);
      expect(find.textContaining('This backup contains'), findsNothing);
      expect(restoreEnabled(tester), isFalse);
      // The controller removed the copy itself; the page asks for nothing,
      // not even when it is left afterwards.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(controller.released, isEmpty);
    });

    testWidgets('after a restore that failed the page keeps the file for '
        'another try', (tester) async {
      controller
        ..inspection = right(_inspection(withVault: true))
        ..outcome = const AsyncError(
          WrongPassphraseFailure(),
          StackTrace.empty,
        );
      await tester.pumpWidget(wrap());
      await pick(tester);
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.pump();
      await tapRestore(tester);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'That passphrase did not unlock the backup. Please try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('test.pitabak'), findsOneWidget);
      expect(find.textContaining('This backup contains'), findsOneWidget);
      expect(controller.released, isEmpty);

      // The second try needs no second pick: only the passphrase again.
      controller.outcome = const AsyncData(_summary);
      await tester.enterText(find.byType(TextField), 'right');
      await tester.pump();
      await tapRestore(tester);
      await tester.pumpAndSettle();

      expect(find.text('Restore complete'), findsOneWidget);
      expect(controller.pickCalls, 1);
      expect(controller.restores.map((r) => r.archive), [_document, _document]);
    });
  });

  testWidgets('N11: leaving the page mid-restore neither crashes nor loses '
      'the terminal state', (tester) async {
    // The restore outlives the page (keep-alive in the controller). Popping
    // Restore mid-run used to throw StateError in the page's post-await
    // `ref.read` (widget ref dead) AND dispose the controller mid-flight.
    controller
      ..inspection = right(_inspection(withVault: true))
      ..holdRestore = Completer<void>()
      ..outcome = const AsyncError(WrongPassphraseFailure(), StackTrace.empty);
    await tester.pumpWidget(wrapBehindButton());
    await tester.tap(find.text('open restore'));
    await tester.pumpAndSettle();

    // A listener held by the TEST (not the page) so the terminal state is
    // observable after the page is gone.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RestorePage)),
    );
    AsyncValue<RestoreSummary?> lastSeen = const AsyncLoading();
    final sub = container.listen(
      restoreControllerProvider,
      (_, next) => lastSeen = next,
    );
    addTearDown(sub.close);

    await pick(tester);
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    await tapRestore(tester);
    // The restore is now parked inside the controller.
    expect(controller.restores, hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(chooseEnabled(tester), isFalse);

    // Leave the page mid-restore. Settle FIRST: the pop animation must
    // finish so the widget is fully disposed before the restore completes.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    // D25: the page said it no longer wants the copy. (The real controller
    // then removes it when the restore has ended.)
    expect(controller.released, [_document]);

    controller.holdRestore!.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(lastSeen.error, isA<WrongPassphraseFailure>());
  });

  testWidgets('item 11: a terminal result survives pop + reopen and clears '
      'only when a new archive is chosen', (tester) async {
    // Before: the controller was autoDispose, so popping Restore after the
    // run finished forgot the outcome and the reopened page showed IDLE.
    controller.outcome = const AsyncError(
      ValidationFailure('Unlock the borrowers vault first.'),
      StackTrace.empty,
    );
    await tester.pumpWidget(wrapBehindButton());
    await tester.tap(find.text('open restore'));
    await tester.pumpAndSettle();
    await pick(tester);
    await tapRestore(tester);
    await tester.pumpAndSettle();
    expect(find.text('Unlock the borrowers vault first.'), findsOneWidget);

    // Pop with the run finished, wait past the old auto-dispose turn, reopen.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('open restore'));
    await tester.pumpAndSettle();

    expect(
      find.text('Unlock the borrowers vault first.'),
      findsOneWidget,
      reason: 'the reopened page must show the same terminal outcome',
    );
    // The page-local file choice is gone, but the outcome is not.
    expect(find.text('Choose .pitabak file'), findsOneWidget);

    // Choosing a new archive clears it before the new inspection is shown.
    await pick(tester);
    expect(controller.pickCalls, 2);
    expect(find.text('Unlock the borrowers vault first.'), findsNothing);
    expect(find.textContaining('No borrowers vault'), findsOneWidget);
    // Looked at in the controller too: the page is a list that builds only
    // what is near the screen, so "not found" alone could mean "further
    // down".
    final state = ProviderScope.containerOf(
      tester.element(find.byType(RestorePage)),
    ).read(restoreControllerProvider);
    expect(state.hasError, isFalse);
    expect(state.value, isNull, reason: 'idle again');
  });

  group('BR6 — the cover count (D27)', () {
    testWidgets('one line under the button while covers are written, and '
        'none before and after', (tester) async {
      controller.holdRestore = Completer<void>();
      await tester.pumpWidget(wrap());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RestorePage)),
      );
      final progress = container.read(restoreProgressProvider.notifier);
      await pick(tester);
      await tapRestore(tester);

      // Running, before the first cover: the spinner only.
      expect(find.byKey(const Key('restore-progress')), findsNothing);

      progress.show(
        BackupProgress.tryCreate(coversDone: 1234, coversTotal: 9000),
      );
      await tester.pump();
      expect(find.text('Cover 1,234 of 9,000'), findsOneWidget);

      progress.show(
        BackupProgress.tryCreate(coversDone: 9000, coversTotal: 9000),
      );
      await tester.pump();
      expect(find.text('Cover 9,000 of 9,000'), findsOneWidget);
      expect(find.text('Cover 1,234 of 9,000'), findsNothing);

      // The controller clears the count when the restore ends.
      progress.show(null);
      controller.holdRestore!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('restore-progress')), findsNothing);
      expect(find.text('Restore complete'), findsOneWidget);
    });

    testWidgets('a page opened during a restore shows the count that is '
        'there', (tester) async {
      await tester.pumpWidget(wrapBehindButton());
      final container = ProviderScope.containerOf(
        tester.element(find.text('open restore')),
      );
      container
          .read(restoreProgressProvider.notifier)
          .show(BackupProgress.tryCreate(coversDone: 3, coversTotal: 40));

      await tester.tap(find.text('open restore'));
      await tester.pumpAndSettle();

      expect(find.text('Cover 3 of 40'), findsOneWidget);
    });
  });

  group('BR6 — cover pictures that were left out (D18, D23)', () {
    Future<void> pumpWith(WidgetTester tester, List<String> titles) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            restoreControllerProvider.overrideWith(
              () => _LeftOutCoversController(titles),
            ),
          ],
          child: const MaterialApp(home: RestorePage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('one item: the sentence for one, and its title', (
      tester,
    ) async {
      await pumpWith(tester, ['गोदान']);

      expect(
        find.text(
          'Note: the cover picture of 1 item in this backup is too large '
          'and was not restored. The item itself was restored:',
        ),
        findsOneWidget,
      );
      expect(find.text('• गोदान'), findsOneWidget);
      expect(find.textContaining('more'), findsNothing);
      expect(find.text('Books restored: 7'), findsOneWidget);
    });

    testWidgets('three items: all three titles, no "more"', (tester) async {
      await pumpWith(tester, ['One', 'Two', 'Three']);

      expect(
        find.text(
          'Note: the cover pictures of 3 items in this backup are too large '
          'and were not restored. The items themselves were restored:',
        ),
        findsOneWidget,
      );
      for (final title in ['One', 'Two', 'Three']) {
        expect(find.text('• $title'), findsOneWidget);
      }
      expect(find.textContaining('more'), findsNothing);
    });

    testWidgets('more than three: the first three and how many more', (
      tester,
    ) async {
      await pumpWith(tester, ['One', 'Two', 'Three', 'Four', 'Five']);

      expect(find.textContaining('of 5 items'), findsOneWidget);
      for (final title in ['One', 'Two', 'Three']) {
        expect(find.text('• $title'), findsOneWidget);
      }
      expect(find.text('• Four'), findsNothing);
      expect(find.text('and 2 more'), findsOneWidget);
    });

    testWidgets('no picture left out: no note', (tester) async {
      await pumpWith(tester, const []);

      expect(find.byKey(const Key('restore-covers-left-out')), findsNothing);
      expect(find.textContaining('too large'), findsNothing);
    });
  });

  group('§5.10 — identity + network copy', () {
    testWidgets('inspection names the identity and lists the network', (
      tester,
    ) async {
      controller.inspection = right(
        _inspection(
          hasNetwork: true,
          identity: BackupIdentity.fromJson(
            '{"libraryId": "${'a' * 32}", "libraryName": "Meera Road"}',
          ),
        ),
      );
      await tester.pumpWidget(wrap());
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
      // The manifest announces an identity; the entry did not parse.
      controller.inspection = right(_inspection(hasIdentity: true));
      await tester.pumpWidget(wrap());
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

    testWidgets('a partial identity adoption is named, not called unchanged', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            restoreControllerProvider.overrideWith(
              _PartiallyAdoptedRestoreController.new,
            ),
          ],
          child: const MaterialApp(home: RestorePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'The backup’s library ID was saved, but its name was not. '
          'Review this device’s library identity in Settings.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('your current identity is unchanged'),
        findsNothing,
      );
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

    testWidgets('S5: detached rows and dropped entries are separate '
        'sentences', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            restoreControllerProvider.overrideWith(
              _SplitIssueCountsController.new,
            ),
          ],
          child: const MaterialApp(home: RestorePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          '2 issue link(s) could not be honoured; the affected items were '
          'restored as books.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          '3 issue detail(s) in the backup could not be used and were '
          'ignored.',
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
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
    await expectMeetsA11yGuidelines(tester);
  });

  testWidgets('meets accessibility guidelines with a file chosen', (
    tester,
  ) async {
    controller.inspection = right(_inspection(withVault: true));
    await tester.pumpWidget(wrap());
    await pick(tester);
    await expectMeetsA11yGuidelines(tester);
  });
}
