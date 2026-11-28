/// Review finding N11 widget tests: create-backup must reach a typed
/// terminal state on EVERY path — a throwing share plugin or use-case
/// provider used to escape as an unhandled async error and leave the busy
/// spinner stuck forever.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/device_resources.dart';
import 'package:pitaka/core/platform/document_saver.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/features/backup/application/create_backup_use_case.dart';
import 'package:pitaka/features/backup/domain/backup_progress.dart';
import 'package:pitaka/features/backup/domain/create_backup_result.dart';
import 'package:pitaka/features/backup/presentation/pages/create_backup_page.dart';
import 'package:pitaka/features/backup/presentation/resource_notice_messages.dart';
import 'package:pitaka/features/backup/presentation/widgets/backup_run_result.dart';
import 'package:pitaka/features/backup/presentation/widgets/resource_notice_dialog.dart';

import '../../support/a11y.dart';
import '../../support/fake_device_resources.dart';
import '../../support/fake_document_saver.dart';
import '../../support/fake_library_footprint_source.dart';
import '../../support/live_regions.dart';

/// Where the fake use case says the finished backup is. No file is written:
/// the share sheet is a fake too.
const String _fakeBackupPath =
    '/fake/backup_work/run-1/Pitak-backup-20260101-000000.pitabak';

/// What happened, in order, across the two fakes of one test (BR4: the file
/// must be given back AFTER sharing, not before).
typedef _Events = List<String>;

/// Use-case fake: returns a fixed result. The collaborator fields are never
/// touched — `noSuchMethod` throws if that ever changes.
///
/// The first argument is still "the archive" as bytes, so the tests read as
/// before; since BR4 the result carries a path and the size instead.
class _FakeCreateBackup implements CreateBackupUseCase {
  _FakeCreateBackup(
    Either<Failure, Uint8List> result, {
    bool includesIdentity = true,
    bool includesNetwork = true,
    bool missingPublishState = false,
    List<String> coversLeftOut = const [],
    bool vaultLeftOut = false,
    this.gate,
    this.gateFromCall = 1,
    this.events,
    this.error,
  }) : _result = result.map(
         (bytes) => CreateBackupResult(
           path: _fakeBackupPath,
           sizeBytes: bytes.length,
           includesIdentity: includesIdentity,
           includesNetwork: includesNetwork,
           missingPublishState: missingPublishState,
           coversLeftOut: coversLeftOut,
           vaultLeftOut: vaultLeftOut,
         ),
       );

  final Either<Failure, CreateBackupResult> _result;

  /// When given, the build waits for it: a test can then act "while the
  /// backup is being built".
  final Completer<void>? gate;

  /// The first build that waits at [gate] (1 = every build). With 2, a test
  /// can let a first backup run through and stop the second one.
  final int gateFromCall;
  int _calls = 0;

  /// How many builds were started.
  int get calls => _calls;

  final _Events? events;

  /// When given, the build throws it instead of returning (after [gate]).
  final Object? error;

  /// The results handed back through [discard], in order.
  final List<CreateBackupResult> discarded = [];

  /// The progress listener of the latest call (BR4 rider 3). A test calls
  /// [report] to play the builder that packs cover pictures.
  BackupProgressListener? _onProgress;

  /// Reports "[done] of [total] covers" to the page, as the running build
  /// would.
  void report(int done, int total) => _onProgress!(
    BackupProgress.tryCreate(coversDone: done, coversTotal: total)!,
  );

  @override
  Future<Either<Failure, CreateBackupResult>> call({
    BackupProgressListener? onProgress,
  }) async {
    _onProgress = onProgress;
    _calls++;
    if (_calls >= gateFromCall) await gate?.future;
    final e = error;
    if (e != null) Error.throwWithStackTrace(e, StackTrace.current);
    return _result;
  }

  @override
  Future<void> discard(CreateBackupResult result) async {
    discarded.add(result);
    events?.add('discard');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Share-sheet fake: a fixed outcome, or throws like a crashing plugin.
class _FakeShare implements FileShareService {
  _FakeShare({
    this.outcome = ShareOutcome.success,
    this.error,
    this.events,
    this.gate,
  });

  /// Not final: one test changes the outcome between two runs.
  ShareOutcome outcome;
  final Object? error;
  final _Events? events;

  /// When given, the share sheet "stays open" until it completes.
  final Completer<void>? gate;

  /// The (path, MIME type) of every file handed to the share sheet.
  final List<({String path, String mimeType})> files = [];

  @override
  Future<ShareOutcome> shareFile({
    required String path,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    files.add((path: path, mimeType: mimeType));
    events?.add('share');
    await gate?.future;
    final e = error;
    if (e != null) Error.throwWithStackTrace(e, StackTrace.current);
    return outcome;
  }

  // BR4: a backup is shared as a FILE. Holding it in memory to share it is
  // exactly what the rework removed, so this must never be called.
  @override
  Future<ShareOutcome> shareBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? text,
    Rect? sharePositionOrigin,
  }) => throw UnimplementedError();

  @override
  Future<ShareOutcome> shareText(String text, {Rect? sharePositionOrigin}) =>
      throw UnimplementedError();
}

void main() {
  // BR9: what the notice before a backup reads. A phone with plenty of room
  // and a small library, unless a test says otherwise.
  late FakeDeviceResources device;
  late FakeLibraryFootprintSource library;

  setUp(() {
    device = FakeDeviceResources();
    library = FakeLibraryFootprintSource();
    // A tall screen for every test of this file. The page is a lazy list,
    // and since it has two buttons and a note under them (P4-M6) the
    // sentence of a run lies below what a default test screen builds. What
    // a SHORT screen shows of the page is a question for a phone, not for
    // these tests.
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!
          ..physicalSize = const Size(800, 2400)
          ..devicePixelRatio = 1;
    addTearDown(view.reset);
  });

  /// The two sources of the notice, faked.
  List<Override> noticeSources() => [
    deviceResourcesProvider.overrideWithValue(device),
    libraryFootprintSourceProvider.overrideWithValue(library),
  ];

  Widget page({
    CreateBackupUseCase? useCase,
    _FakeShare? share,
    FakeDocumentSaver? saver,
  }) => ProviderScope(
    overrides: [
      if (useCase != null)
        createBackupUseCaseProvider.overrideWith((ref) async => useCase),
      fileShareServiceProvider.overrideWithValue(share ?? _FakeShare()),
      documentSaverProvider.overrideWithValue(saver ?? FakeDocumentSaver()),
      ...noticeSources(),
    ],
    child: const MaterialApp(home: CreateBackupPage()),
  );

  // Until review finding P4-M6 the page had ONE button, "Create backup", and
  // it ended in the share sheet. It has two now. The tests from before go
  // the Share way, through [shareButton]; the Save way has a group of its
  // own at the end of this file.
  Finder shareButton() => find.widgetWithText(OutlinedButton, 'Share backup');
  Finder saveButton() => find.widgetWithText(FilledButton, 'Save backup');

  /// Whether the two buttons are on. The page locks BOTH while it works and
  /// frees both afterwards; null when they differ, which no test expects.
  bool? buttonsEnabled(WidgetTester tester) {
    final save = tester.widget<FilledButton>(find.byType(FilledButton));
    final share = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    return save.enabled == share.enabled ? save.enabled : null;
  }

  Finder noticeConfirm() => find.byKey(ResourceNoticeDialog.confirmKey);
  Finder noticeCancel() => find.byKey(ResourceNoticeDialog.cancelKey);

  /// Taps "Share backup" and lets the notice open (BR9).
  Future<void> openNotice(WidgetTester tester) async {
    await tester.tap(shareButton());
    await tester.pumpAndSettle();
  }

  /// Taps "Share backup" and says "Go on" to the notice: the build starts.
  ///
  /// The two pumps at the end let the dialog go (half a second on the
  /// test's clock) without waiting for the page to come to rest: a build
  /// that a test holds half-way keeps a spinner turning.
  Future<void> tapCreateBackup(WidgetTester tester) async {
    await openNotice(tester);
    await tester.tap(noticeConfirm());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('success shows the hand-off confirmation', (tester) async {
    await tester.pumpWidget(
      page(useCase: _FakeCreateBackup(right(Uint8List.fromList([1, 2, 3])))),
    );
    await tapCreateBackup(tester);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Backup handed to the selected app; confirm it was saved or sent.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('plan CV6: the intro says the publishing record is inside', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    expect(
      find.textContaining('its publishing record is included too'),
      findsOneWidget,
    );
    expect(
      find.textContaining('your GitHub or Cloudflare sign-in'),
      findsOneWidget,
    );
    expect(find.textContaining('publishing setup'), findsNothing);
  });

  // Decision D12: a backup made by a newer Pitak need not open in an older
  // one. The user is told BEFORE the backup is made, not after.
  testWidgets('D12: says before the backup that an older Pitak may not open '
      'it', (tester) async {
    await tester.pumpWidget(page());
    expect(
      find.text(
        'A backup made with this version may not open in an older version '
        'of Pitak. Update Pitak on the other phone before you restore there.',
      ),
      findsOneWidget,
    );
    // It sits above the button: visible without having made a backup.
    final sentence = tester.getTopLeft(
      find.textContaining('may not open in an older version'),
    );
    final button = tester.getTopLeft(
      find.widgetWithText(FilledButton, 'Save backup'),
    );
    expect(sentence.dy, lessThan(button.dy));
  });

  testWidgets('plan CV6: a record that could not be carried is named', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        useCase: _FakeCreateBackup(
          right(Uint8List.fromList([1])),
          missingPublishState: true,
        ),
      ),
    );
    await tapCreateBackup(tester);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Note: this backup does not carry your website publishing record — '
        'it could not be read. Everything else is inside.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('three missing parts read naturally', (tester) async {
    await tester.pumpWidget(
      page(
        useCase: _FakeCreateBackup(
          right(Uint8List.fromList([1])),
          includesIdentity: false,
          includesNetwork: false,
          missingPublishState: true,
        ),
      ),
    );
    await tapCreateBackup(tester);
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'does not carry your library identity, your saved-libraries list and '
        'your website publishing record',
      ),
      findsOneWidget,
    );
  });

  testWidgets('share unavailable shows its message', (tester) async {
    await tester.pumpWidget(
      page(
        useCase: _FakeCreateBackup(right(Uint8List.fromList([1]))),
        share: _FakeShare(outcome: ShareOutcome.unavailable),
      ),
    );
    await tapCreateBackup(tester);
    await tester.pumpAndSettle();
    expect(find.text('Sharing is unavailable on this device.'), findsOneWidget);
  });

  testWidgets('a share sheet that is left gets a sentence, and it is not an '
      'error (D170)', (tester) async {
    await tester.pumpWidget(
      page(
        useCase: _FakeCreateBackup(right(Uint8List.fromList([1]))),
        share: _FakeShare(outcome: ShareOutcome.dismissed),
      ),
    );
    await tapCreateBackup(tester);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Backup handed to the selected app; confirm it was saved or sent.',
      ),
      findsNothing,
    );
    expect(find.text('Sharing is unavailable on this device.'), findsNothing);
    // Until P4-M6 the page said NOTHING here, which is also all a user saw
    // on a phone whose sheet had no app for the file.
    expect(
      find.text(
        'Nothing was shared. If no app on that list could take the file, '
        'use Save backup.',
      ),
      findsOneWidget,
    );
    expect(buttonsEnabled(tester), isTrue);
  });

  // S5 (L5): a catalogue too large for the format gets its OWN sentence —
  // retrying cannot help, so "please try again" would be a lie.
  testWidgets('S5: a too-large catalogue says nothing was exported', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        useCase: _FakeCreateBackup(
          left(const BackupTooLargeFailure('itemKindsTooLarge')),
        ),
      ),
    );
    await tapCreateBackup(tester);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This catalogue is too large for this backup format. '
        'Nothing was exported.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Backup handed to the selected app; confirm it was saved or sent.',
      ),
      findsNothing,
    );
  });

  // BR3: a refusal that carries its numbers gets the sentence for its limit.
  // (Every sentence is tested in create_backup_messages_test.dart; this
  // proves the page shows it.)
  testWidgets('BR3: too many cover pictures are named with both numbers', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(
        useCase: _FakeCreateBackup(
          left(const BackupTooLargeFailure('tooManyCovers', 10300, 10000)),
        ),
      ),
    );
    await tapCreateBackup(tester);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This library has 10,300 cover pictures; a backup can hold 10,000. '
        'Nothing was exported.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Backup handed to the selected app; confirm it was saved or sent.',
      ),
      findsNothing,
    );
    expect(buttonsEnabled(tester), isTrue);
  });

  group('BR3 (D10): cover pictures that were left out', () {
    const sentenceForFive =
        'Note: the cover pictures of 5 items are too large for a backup and '
        'are not inside. The items themselves are inside:';

    testWidgets('five items: the count, the first three titles, and how '
        'many more', (tester) async {
      await tester.pumpWidget(
        page(
          useCase: _FakeCreateBackup(
            right(Uint8List.fromList([1])),
            coversLeftOut: const ['Alpha', 'Beta', 'Gamma', 'Delta', 'Eta'],
          ),
        ),
      );
      await tapCreateBackup(tester);
      await tester.pumpAndSettle();

      // The backup itself completed.
      expect(
        find.text(
          'Backup handed to the selected app; confirm it was saved or sent.',
        ),
        findsOneWidget,
      );
      expect(find.text(sentenceForFive), findsOneWidget);
      expect(find.text('• Alpha'), findsOneWidget);
      expect(find.text('• Beta'), findsOneWidget);
      expect(find.text('• Gamma'), findsOneWidget);
      expect(find.textContaining('Delta'), findsNothing);
      expect(find.textContaining('Eta'), findsNothing);
      expect(find.text('and 2 more'), findsOneWidget);
      await expectMeetsA11yGuidelines(tester);
    });

    testWidgets('one item: singular wording and no "more" line', (
      tester,
    ) async {
      await tester.pumpWidget(
        page(
          useCase: _FakeCreateBackup(
            right(Uint8List.fromList([1])),
            coversLeftOut: const ['Alpha'],
          ),
        ),
      );
      await tapCreateBackup(tester);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Note: the cover picture of 1 item is too large for a backup and '
          'is not inside. The item itself is inside:',
        ),
        findsOneWidget,
      );
      expect(find.text('• Alpha'), findsOneWidget);
      expect(find.textContaining('more'), findsNothing);
    });

    testWidgets('a very long title stays on one line', (tester) async {
      await tester.pumpWidget(
        page(
          useCase: _FakeCreateBackup(
            right(Uint8List.fromList([1])),
            coversLeftOut: ['A very long title ${'word ' * 400}'],
          ),
        ),
      );
      await tapCreateBackup(tester);
      await tester.pumpAndSettle();
      final title = tester.widget<Text>(
        find.textContaining('A very long title'),
      );
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nothing left out: no note', (tester) async {
      await tester.pumpWidget(
        page(useCase: _FakeCreateBackup(right(Uint8List.fromList([1])))),
      );
      await tapCreateBackup(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('cover picture'), findsNothing);
    });

    testWidgets('the note is gone when the next backup starts', (tester) async {
      // The note belongs to ONE finished backup. A second run whose share
      // sheet is dismissed must not keep showing the first run's titles.
      final share = _FakeShare();
      await tester.pumpWidget(
        page(
          useCase: _FakeCreateBackup(
            right(Uint8List.fromList([1])),
            coversLeftOut: const ['Alpha'],
          ),
          share: share,
        ),
      );
      await tapCreateBackup(tester);
      await tester.pumpAndSettle();
      expect(find.text('• Alpha'), findsOneWidget);

      share.outcome = ShareOutcome.dismissed;
      await tapCreateBackup(tester);
      await tester.pumpAndSettle();
      expect(find.text('• Alpha'), findsNothing);
    });
  });

  // BR4 rider 2 (decision D17): a vault whose last change did not finish is
  // left out of the backup. The backup itself succeeds, so the page MUST say
  // what is missing: without the note the user would believe borrowers and
  // loans are safe in the file.
  group('BR4 rider 2 (D17): the borrowers vault was left out', () {
    final note = find.byKey(const Key('backup-vault-left-out'));
    const handedOver =
        'Backup handed to the selected app; confirm it was saved or sent.';

    Future<void> createBackup(WidgetTester tester) async {
      await tapCreateBackup(tester);
      await tester.pumpAndSettle();
    }

    testWidgets('the note is shown under the hand-off sentence, word for '
        'word', (tester) async {
      await tester.pumpWidget(
        page(
          useCase: _FakeCreateBackup(
            right(Uint8List.fromList([1])),
            vaultLeftOut: true,
          ),
        ),
      );
      await createBackup(tester);

      // The backup itself was made and handed over.
      expect(find.text(handedOver), findsOneWidget);
      expect(
        tester.widget<Text>(note).data,
        'Note: the borrowers vault is not inside this backup. Its last '
        'change did not finish, for example because the app was closed in '
        'the middle of it. Unlock the vault once (lock it first if it is '
        'open), then create the backup again. The rest of this backup is '
        'not affected.',
      );
      expect(
        tester.getTopLeft(note).dy,
        greaterThan(tester.getBottomLeft(find.text(handedOver)).dy),
      );
      await expectMeetsA11yGuidelines(tester);
    });

    testWidgets('it comes first among the notes', (tester) async {
      // A tall screen: the page is a lazy list, and with three notes the
      // last ones lie below what a default test screen builds.
      tester.view
        ..physicalSize = const Size(800, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        page(
          useCase: _FakeCreateBackup(
            right(Uint8List.fromList([1])),
            vaultLeftOut: true,
            includesIdentity: false,
            coversLeftOut: const ['Alpha'],
          ),
        ),
      );
      await createBackup(tester);

      final vault = tester.getTopLeft(note).dy;
      final identity = tester
          .getTopLeft(find.textContaining('does not carry your library'))
          .dy;
      final covers = tester.getTopLeft(find.text('• Alpha')).dy;
      expect(vault, lessThan(identity));
      expect(identity, lessThan(covers));
    });

    testWidgets('a vault that is inside, or no vault at all: no note', (
      tester,
    ) async {
      await tester.pumpWidget(
        page(useCase: _FakeCreateBackup(right(Uint8List.fromList([1])))),
      );
      await createBackup(tester);

      expect(find.text(handedOver), findsOneWidget);
      expect(note, findsNothing);
      expect(
        find.textContaining('borrowers vault is not inside'),
        findsNothing,
      );
    });

    testWidgets('a dismissed share sheet shows no note, like the other '
        'notes', (tester) async {
      // Nothing was handed to another app, so there is no file to describe.
      await tester.pumpWidget(
        page(
          useCase: _FakeCreateBackup(
            right(Uint8List.fromList([1])),
            vaultLeftOut: true,
          ),
          share: _FakeShare(outcome: ShareOutcome.dismissed),
        ),
      );
      await createBackup(tester);

      expect(note, findsNothing);
    });

    testWidgets('the note is gone when the next backup starts', (tester) async {
      // The note belongs to ONE finished backup. While the next one is
      // being built it must not stay on the screen.
      final gate = Completer<void>();
      final share = _FakeShare();
      await tester.pumpWidget(
        page(
          useCase: _FakeCreateBackup(
            right(Uint8List.fromList([1])),
            vaultLeftOut: true,
            gate: gate,
            gateFromCall: 2,
          ),
          share: share,
        ),
      );
      await createBackup(tester);
      expect(note, findsOneWidget);

      await tapCreateBackup(tester);
      await tester.pump();
      expect(note, findsNothing, reason: 'the second build is running');

      gate.complete();
      await tester.pumpAndSettle();
      expect(note, findsOneWidget, reason: 'the second backup says it again');
    });
  });

  testWidgets('N11: a throwing share plugin shows a safe error and frees the '
      'button', (tester) async {
    await tester.pumpWidget(
      page(
        useCase: _FakeCreateBackup(right(Uint8List.fromList([1]))),
        share: _FakeShare(error: StateError('plugin exploded')),
      ),
    );
    await tapCreateBackup(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('Something went wrong creating the backup.'),
      findsOneWidget,
    );
    expect(
      buttonsEnabled(tester),
      isTrue,
      reason: 'the busy flag must reset on an unexpected failure',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('N11: a throwing use-case provider shows a safe error and frees '
      'the button', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          createBackupUseCaseProvider.overrideWith(
            (ref) async => throw StateError('storage exploded'),
          ),
          fileShareServiceProvider.overrideWithValue(_FakeShare()),
          ...noticeSources(),
        ],
        child: const MaterialApp(home: CreateBackupPage()),
      ),
    );
    await tapCreateBackup(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('Something went wrong creating the backup.'),
      findsOneWidget,
    );
    expect(buttonsEnabled(tester), isTrue);
    expect(tester.takeException(), isNull);
  });

  // BR9 (decision D5): before a backup the page says what it needs and
  // what the phone has. The dialog itself is proven in
  // `resource_notice_dialog_test.dart`; here: what the PAGE does with it.
  group('the notice before a backup', () {
    testWidgets('"Share backup" opens the notice, and nothing is built '
        'until "Go on" is tapped', (tester) async {
      final useCase = _FakeCreateBackup(right(Uint8List.fromList([1, 2, 3])));
      await tester.pumpWidget(page(useCase: useCase));

      await openNotice(tester);

      expect(find.byType(ResourceNoticeDialog), findsOneWidget);
      expect(find.text('Before you create the backup'), findsOneWidget);
      // The fake library takes 9 MB: a backup needs twice that.
      expect(
        find.text(
          'Storage: this needs about 18.0 MB. This phone has 64.0 GB free.',
        ),
        findsOneWidget,
      );
      // A backup replaces nothing, and its notice does not say so.
      expect(find.text(resourceNoticeReplacesLibraryMessage), findsNothing);
      expect(useCase.calls, 0);

      await tester.tap(noticeConfirm());
      await tester.pumpAndSettle();

      expect(find.byType(ResourceNoticeDialog), findsNothing);
      expect(useCase.calls, 1);
      expect(
        find.text(
          'Backup handed to the selected app; confirm it was saved or sent.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Cancel builds nothing, shares nothing, and leaves the '
        'button ready', (tester) async {
      final useCase = _FakeCreateBackup(right(Uint8List.fromList([1, 2, 3])));
      final share = _FakeShare();
      await tester.pumpWidget(page(useCase: useCase, share: share));

      await openNotice(tester);
      await tester.tap(noticeCancel());
      await tester.pumpAndSettle();

      expect(useCase.calls, 0);
      expect(share.files, isEmpty);
      expect(buttonsEnabled(tester), isTrue);
      expect(find.text('Creating…'), findsNothing);
      expect(find.textContaining('Backup handed'), findsNothing);
    });

    testWidgets('Cancel keeps what the page says about the backup before', (
      tester,
    ) async {
      await tester.pumpWidget(
        page(useCase: _FakeCreateBackup(right(Uint8List.fromList([1])))),
      );
      await tapCreateBackup(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('Backup handed'), findsOneWidget);

      // A second backup is asked for and then not wanted: the first one's
      // sentence is still true and stays.
      await openNotice(tester);
      await tester.tap(noticeCancel());
      await tester.pumpAndSettle();

      expect(find.textContaining('Backup handed'), findsOneWidget);
    });

    testWidgets('a phone that is short of storage is told so, and can make '
        'the backup all the same (D5: the notice never blocks)', (
      tester,
    ) async {
      device.facts = const DeviceResourceFacts(
        freeStorageBytes: 1024,
        availableMemoryBytes: 4 * 1024 * 1024 * 1024,
        lowMemoryThresholdBytes: 256 * 1024 * 1024,
        lowMemory: false,
      );
      final useCase = _FakeCreateBackup(right(Uint8List.fromList([1])));
      await tester.pumpWidget(page(useCase: useCase));

      await openNotice(tester);

      expect(
        find.textContaining('does not have enough free storage'),
        findsOneWidget,
      );
      expect(
        find.text('If it fails, nothing is changed and no backup is made.'),
        findsOneWidget,
      );

      await tester.tap(noticeConfirm());
      await tester.pumpAndSettle();
      expect(useCase.calls, 1);
    });

    testWidgets('a device that cannot be asked: the notice says so, and '
        'the backup can be made', (tester) async {
      device.failure = StateError('no channel');
      library.footprint = null;
      final useCase = _FakeCreateBackup(right(Uint8List.fromList([1])));
      await tester.pumpWidget(page(useCase: useCase));

      await openNotice(tester);

      expect(find.text(resourceNoticeUnknownMessage), findsOneWidget);

      await tester.tap(noticeConfirm());
      await tester.pumpAndSettle();
      expect(useCase.calls, 1);
    });

    testWidgets('a page that is gone while the notice is open builds '
        'nothing, even on a yes', (tester) async {
      final useCase = _FakeCreateBackup(right(Uint8List.fromList([1])));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            createBackupUseCaseProvider.overrideWith((ref) async => useCase),
            fileShareServiceProvider.overrideWithValue(_FakeShare()),
            ...noticeSources(),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CreateBackupPage(),
                    ),
                  ),
                  child: const Text('open backup'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open backup'));
      await tester.pumpAndSettle();
      await openNotice(tester);

      // The page under the dialog is taken away; the dialog itself stays.
      final dialog = ModalRoute.of(
        tester.element(find.byType(ResourceNoticeDialog)),
      )!;
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .removeRouteBelow(dialog);
      await tester.pump();
      expect(find.byType(CreateBackupPage), findsNothing);

      await tester.tap(noticeConfirm());
      await tester.pumpAndSettle();

      expect(useCase.calls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('meets accessibility guidelines with the notice open', (
      tester,
    ) async {
      await tester.pumpWidget(page());
      await openNotice(tester);

      expect(find.byType(ResourceNoticeDialog), findsOneWidget);
      await expectMeetsA11yGuidelines(tester);
    });
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    await tester.pumpWidget(
      page(useCase: _FakeCreateBackup(right(Uint8List.fromList([1, 2, 3])))),
    );
    await tester.pumpAndSettle();
    await expectMeetsA11yGuidelines(tester);
  });

  // BR4: the backup is a FILE in a private folder of the app, a plain copy
  // of the whole library. The page shares it by its path and gives it back
  // on every way out, so that it never stays behind.
  group('BR4 — the finished file is shared by path and always given back', () {
    Future<void> createBackup(WidgetTester tester) async {
      await tapCreateBackup(tester);
      await tester.pumpAndSettle();
    }

    testWidgets('the path goes to the share sheet as a generic binary, and '
        'the file is given back after sharing', (tester) async {
      final events = <String>[];
      final useCase = _FakeCreateBackup(
        right(Uint8List.fromList([1, 2, 3])),
        events: events,
      );
      final share = _FakeShare(events: events);
      await tester.pumpWidget(page(useCase: useCase, share: share));
      await createBackup(tester);

      expect(share.files, [
        (path: _fakeBackupPath, mimeType: 'application/octet-stream'),
      ]);
      expect(useCase.discarded, hasLength(1));
      expect(useCase.discarded.single.path, _fakeBackupPath);
      expect(events, ['share', 'discard']);
    });

    for (final outcome in [ShareOutcome.dismissed, ShareOutcome.unavailable]) {
      testWidgets('the file is given back once when sharing ends as '
          '${outcome.name}', (tester) async {
        final useCase = _FakeCreateBackup(right(Uint8List.fromList([1])));
        await tester.pumpWidget(
          page(
            useCase: useCase,
            share: _FakeShare(outcome: outcome),
          ),
        );
        await createBackup(tester);

        expect(useCase.discarded, hasLength(1));
      });
    }

    testWidgets('the file is given back once when the share plugin throws', (
      tester,
    ) async {
      final useCase = _FakeCreateBackup(right(Uint8List.fromList([1])));
      await tester.pumpWidget(
        page(
          useCase: useCase,
          share: _FakeShare(error: StateError('plugin exploded')),
        ),
      );
      await createBackup(tester);

      expect(useCase.discarded, hasLength(1));
      expect(
        find.text('Something went wrong creating the backup.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a second backup gives back its own file too', (tester) async {
      final useCase = _FakeCreateBackup(right(Uint8List.fromList([1])));
      await tester.pumpWidget(page(useCase: useCase));
      await createBackup(tester);
      await createBackup(tester);

      expect(useCase.discarded, hasLength(2));
    });

    testWidgets('a failed build shares nothing and has nothing to give back', (
      tester,
    ) async {
      final useCase = _FakeCreateBackup(left(const StorageFailure('x')));
      final share = _FakeShare();
      await tester.pumpWidget(page(useCase: useCase, share: share));
      await createBackup(tester);

      expect(share.files, isEmpty);
      expect(useCase.discarded, isEmpty);
      expect(
        find.text('Could not build the backup. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('a page that was left while the backup was being built '
        'gives the file back and shares nothing', (tester) async {
      final gate = Completer<void>();
      final useCase = _FakeCreateBackup(
        right(Uint8List.fromList([1])),
        gate: gate,
      );
      final share = _FakeShare();
      await tester.pumpWidget(page(useCase: useCase, share: share));
      await tapCreateBackup(tester);
      await tester.pump();

      // The user leaves: the page is removed while the build still runs.
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await tester.pumpAndSettle();

      expect(share.files, isEmpty);
      expect(useCase.discarded, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a page that was left before a FAILED build returned does '
        'nothing more', (tester) async {
      final gate = Completer<void>();
      final useCase = _FakeCreateBackup(
        left(const StorageFailure('x')),
        gate: gate,
      );
      await tester.pumpWidget(page(useCase: useCase));
      await tapCreateBackup(tester);
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await tester.pumpAndSettle();

      expect(useCase.discarded, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  // BR4 rider 3 (the backup part of review finding P4-M7): a large backup
  // spends its time packing cover pictures, and a spinner alone does not
  // say whether anything is still happening. One line under the button
  // counts the covers. The fake use case plays the build: it waits at a
  // gate, and the test reports progress "from inside" it.
  group('BR4 rider 3 — progress while the cover pictures are packed', () {
    final line = find.byKey(const Key('backup-progress'));
    const handedOver =
        'Backup handed to the selected app; confirm it was saved or sent.';

    bool? buttonEnabled(WidgetTester tester) => buttonsEnabled(tester);

    /// Shows the page with [useCase] and taps the button. The build then
    /// waits at the use case's gate.
    Future<void> startBuild(
      WidgetTester tester,
      _FakeCreateBackup useCase, {
      _FakeShare? share,
    }) async {
      await tester.pumpWidget(page(useCase: useCase, share: share));
      await tapCreateBackup(tester);
      await tester.pump();
    }

    testWidgets('before the first report, and for a library without cover '
        'pictures, there is only the spinner', (tester) async {
      final gate = Completer<void>();
      final useCase = _FakeCreateBackup(
        right(Uint8List.fromList([1])),
        gate: gate,
      );
      await startBuild(tester, useCase);

      expect(line, findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Creating…'), findsOneWidget);

      // No report ever comes (no covers): the backup finishes without the
      // line having been shown.
      gate.complete();
      await tester.pumpAndSettle();
      expect(line, findsNothing);
      expect(find.text(handedOver), findsOneWidget);
    });

    testWidgets('a report shows "Cover 1,234 of 9,000" under the button, and '
        'the next report replaces it', (tester) async {
      final gate = Completer<void>();
      final useCase = _FakeCreateBackup(
        right(Uint8List.fromList([1])),
        gate: gate,
      );
      await startBuild(tester, useCase);

      useCase.report(1234, 9000);
      await tester.pump();

      expect(tester.widget<Text>(line).data, 'Cover 1,234 of 9,000');
      // Under BOTH buttons: the lower one is "Share backup", which reads
      // "Creating…" just now, so it is found by its kind.
      final buttonBottom = tester.getBottomLeft(find.byType(OutlinedButton)).dy;
      expect(tester.getTopLeft(line).dy, greaterThan(buttonBottom));
      // The spinner stays, and the button stays locked: still one backup.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(buttonEnabled(tester), isFalse);

      useCase.report(9000, 9000);
      await tester.pump();

      expect(line, findsOneWidget);
      expect(tester.widget<Text>(line).data, 'Cover 9,000 of 9,000');

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('the line is removed as soon as the build is over, while '
        'the share sheet is still open', (tester) async {
      final buildGate = Completer<void>();
      final shareGate = Completer<void>();
      final useCase = _FakeCreateBackup(
        right(Uint8List.fromList([1])),
        gate: buildGate,
      );
      final share = _FakeShare(gate: shareGate);
      await startBuild(tester, useCase, share: share);
      useCase.report(3, 3);
      await tester.pump();
      expect(line, findsOneWidget);

      buildGate.complete();
      await tester.pump();

      expect(share.files, hasLength(1), reason: 'the share sheet is open');
      expect(line, findsNothing);
      expect(buttonEnabled(tester), isFalse, reason: 'not finished yet');

      shareGate.complete();
      await tester.pumpAndSettle();
      expect(line, findsNothing);
      expect(find.text(handedOver), findsOneWidget);
      expect(buttonEnabled(tester), isTrue);
    });

    testWidgets('the line is removed when the build fails', (tester) async {
      final gate = Completer<void>();
      final useCase = _FakeCreateBackup(
        left(const StorageFailure('x')),
        gate: gate,
      );
      await startBuild(tester, useCase);
      useCase.report(2, 5);
      await tester.pump();
      expect(line, findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(line, findsNothing);
      expect(
        find.text('Could not build the backup. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('the line is removed when the build throws after a report', (
      tester,
    ) async {
      final gate = Completer<void>();
      final useCase = _FakeCreateBackup(
        right(Uint8List.fromList([1])),
        gate: gate,
        error: StateError('disk went away'),
      );
      await startBuild(tester, useCase);
      useCase.report(2, 5);
      await tester.pump();
      expect(line, findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(line, findsNothing);
      expect(
        find.text('Something went wrong creating the backup.'),
        findsOneWidget,
      );
      expect(buttonEnabled(tester), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a report that arrives after the page was left is dropped', (
      tester,
    ) async {
      // The build goes on in its worker when the user leaves the page. A
      // report for a page that is gone must not touch it.
      final gate = Completer<void>();
      final useCase = _FakeCreateBackup(
        right(Uint8List.fromList([1])),
        gate: gate,
      );
      await startBuild(tester, useCase);
      await tester.pumpWidget(const SizedBox());

      useCase.report(1, 2);
      gate.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(useCase.discarded, hasLength(1), reason: 'still given back');
    });

    testWidgets('meets accessibility guidelines while the line is shown', (
      tester,
    ) async {
      final gate = Completer<void>();
      final useCase = _FakeCreateBackup(
        right(Uint8List.fromList([1])),
        gate: gate,
      );
      await startBuild(tester, useCase);
      useCase.report(1234, 9000);
      await tester.pump();

      await expectMeetsA11yGuidelines(tester);

      gate.complete();
      await tester.pumpAndSettle();
    });
  });

  // Review finding P4-M6 (decisions D165 to D170, and D176): the page has a
  // second way out. "Save backup" builds the backup exactly as "Share
  // backup" does and then hands the finished FILE to the app's own saver,
  // which opens the system's save window and copies the file. The saver is
  // a fake here; its real half has its own tests.
  group('P4-M6: Save backup', () {
    const savedAs = 'Backup saved as pitak-backup-02Nov2026-134659.pitabak.';
    const handedOver =
        'Backup handed to the selected app; confirm it was saved or sent.';
    const failedRun = 'Something went wrong creating the backup.';

    _FakeCreateBackup builds({
      _Events? events,
      Completer<void>? gate,
      bool vaultLeftOut = false,
      bool includesIdentity = true,
    }) => _FakeCreateBackup(
      right(Uint8List.fromList([1, 2, 3])),
      events: events,
      gate: gate,
      vaultLeftOut: vaultLeftOut,
      includesIdentity: includesIdentity,
    );

    /// Taps "Save backup" and says "Go on" to the notice: the build starts.
    /// (The two pumps at the end are those of [tapCreateBackup].)
    Future<void> tapSaveBackup(WidgetTester tester) async {
      await tester.tap(saveButton());
      await tester.pumpAndSettle();
      await tester.tap(noticeConfirm());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('two buttons, Save first, and under them a note that says '
        'what kind of file a backup is', (tester) async {
      await tester.pumpWidget(page(useCase: builds()));

      expect(saveButton(), findsOneWidget);
      expect(shareButton(), findsOneWidget);
      // The old label is the page's title only.
      expect(find.text('Create backup'), findsOneWidget);
      expect(
        tester.getTopLeft(saveButton()).dy,
        lessThan(tester.getTopLeft(shareButton()).dy),
      );
      final note = find.text(
        'The backup is an ordinary file: whoever can open the place you put '
        'it can read your library from it. Only the borrowers vault inside '
        'stays encrypted. A copy kept only on this phone is lost with the '
        'phone.',
      );
      expect(note, findsOneWidget);
      expect(
        tester.getTopLeft(note).dy,
        greaterThan(tester.getBottomLeft(shareButton()).dy),
      );
    });

    testWidgets('Save asks first, builds, saves the FILE that was built, and '
        'says under which name', (tester) async {
      final events = <String>[];
      final useCase = builds(events: events);
      final saver = FakeDocumentSaver(events: events);
      final share = _FakeShare(events: events);
      await tester.pumpWidget(
        page(useCase: useCase, share: share, saver: saver),
      );

      await tester.tap(saveButton());
      await tester.pumpAndSettle();
      // The notice of BR9 is open, and nothing is built before "Go on".
      expect(noticeConfirm(), findsOneWidget);
      expect(useCase.calls, 0);

      await tester.tap(noticeConfirm());
      await tester.pumpAndSettle();

      expect(useCase.calls, 1);
      expect(saver.paths, [_fakeBackupPath]);
      expect(share.files, isEmpty);
      expect(find.text(savedAs), findsOneWidget);
      expect(find.text(handedOver), findsNothing);
      // The file is given back AFTER the save has ended, not before.
      expect(events, ['save', 'discard']);
      expect(useCase.discarded, hasLength(1));
      expect(buttonsEnabled(tester), isTrue);
    });

    testWidgets('the name is the one the place gave; without a name the '
        'sentence ends after "saved"', (tester) async {
      final saver = FakeDocumentSaver(
        result: FakeDocumentSaver.saved(
          name: 'pitak-backup-02Nov2026-134659 (1).pitabak',
        ),
      );
      await tester.pumpWidget(page(useCase: builds(), saver: saver));

      await tapSaveBackup(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('Backup saved as pitak-backup-02Nov2026-134659 (1).pitabak.'),
        findsOneWidget,
      );

      saver.result = FakeDocumentSaver.saved(name: '');
      await tapSaveBackup(tester);
      await tester.pumpAndSettle();
      expect(find.text('Backup saved.'), findsOneWidget);
      expect(find.textContaining('Backup saved as'), findsNothing);
    });

    testWidgets('what the backup does not carry is said under "saved" as it '
        'is under "handed"', (tester) async {
      await tester.pumpWidget(
        page(useCase: builds(vaultLeftOut: true, includesIdentity: false)),
      );

      await tapSaveBackup(tester);
      await tester.pumpAndSettle();

      expect(find.text(savedAs), findsOneWidget);
      expect(find.byKey(const Key('backup-vault-left-out')), findsOneWidget);
      expect(
        find.textContaining('does not carry your library identity'),
        findsOneWidget,
      );
    });

    // One test for each way a save can end WITHOUT a saved file. Every one:
    // its sentence and no other, no note about what "the backup" carries
    // (there is none), the file given back, both buttons free again.
    const endings = <String, (DocumentSaveResult, String)>{
      'the save window was left': (
        DocumentSaveCancelled(),
        'No place was chosen, so nothing was saved.',
      ),
      'the place could not take the file, and nothing was left behind': (
        DocumentSaveNotSaved(),
        'The backup could not be saved there. Nothing was left behind. '
            'Check the free storage of that place, or choose another, and '
            'try again.',
      ),
      'an unfinished file could not be taken back': (
        DocumentSaveLeftBehind(),
        'The backup could not be saved there. An unfinished file with the '
            "backup's name may be left at that place: it is not a backup, "
            'so delete it. Then try again.',
      ),
      'the file chosen already has something in it (D176)': (
        DocumentSaveNotEmpty(),
        'That file already has something in it, so it was left as it is. '
            'Choose a new name in the save window and try again.',
      ),
      'the place cannot confirm that the file is stored (D183)': (
        DocumentSaveUnconfirmed(),
        'That place cannot confirm that a file is stored, so nothing was '
            'saved there. Choose a place on this phone or on a memory card, '
            'or use Share instead.',
      ),
      'this device has no save window (D171)': (
        DocumentSaveUnavailable(),
        'Saving to a file is not available on this device.',
      ),
      'the built file was gone before it could be copied': (
        DocumentSaveSourceGone(),
        failedRun,
      ),
      'a mistake in code on either side of the channel': (
        DocumentSaveFailed(),
        failedRun,
      ),
    };
    for (final MapEntry(key: title, value: (result, sentence))
        in endings.entries) {
      testWidgets('not saved: $title', (tester) async {
        final events = <String>[];
        final useCase = builds(events: events, vaultLeftOut: true);
        final share = _FakeShare(events: events);
        await tester.pumpWidget(
          page(
            useCase: useCase,
            share: share,
            saver: FakeDocumentSaver(result: result, events: events),
          ),
        );

        await tapSaveBackup(tester);
        await tester.pumpAndSettle();

        expect(find.text(sentence), findsOneWidget);
        expect(find.textContaining('Backup saved'), findsNothing);
        expect(find.text(handedOver), findsNothing);
        expect(find.byKey(const Key('backup-vault-left-out')), findsNothing);
        expect(events, ['save', 'discard']);
        expect(useCase.discarded, hasLength(1));
        expect(buttonsEnabled(tester), isTrue);
      });
    }

    testWidgets('a saver that throws ends in the sentence for a failed run, '
        'and the file is given back', (tester) async {
      final useCase = builds();
      await tester.pumpWidget(
        page(
          useCase: useCase,
          saver: FakeDocumentSaver(error: StateError('channel exploded')),
        ),
      );

      await tapSaveBackup(tester);
      await tester.pumpAndSettle();

      expect(find.text(failedRun), findsOneWidget);
      expect(find.textContaining('channel exploded'), findsNothing);
      expect(useCase.discarded, hasLength(1));
      expect(buttonsEnabled(tester), isTrue);
    });

    testWidgets('the tapped button says what is going on, "Creating…" and '
        'then "Saving…", and both buttons are off meanwhile', (tester) async {
      final buildGate = Completer<void>();
      final saveGate = Completer<void>();
      await tester.pumpWidget(
        page(
          useCase: builds(gate: buildGate),
          saver: FakeDocumentSaver(gate: saveGate),
        ),
      );

      await tapSaveBackup(tester);
      await tester.pump();
      expect(find.widgetWithText(FilledButton, 'Creating…'), findsOneWidget);
      // The other button keeps its words.
      expect(shareButton(), findsOneWidget);
      expect(buttonsEnabled(tester), isFalse);

      // The file is made: from here on it is being saved (the system's
      // window is open, or the copy runs).
      buildGate.complete();
      await tester.pump();
      await tester.pump();
      expect(find.widgetWithText(FilledButton, 'Saving…'), findsOneWidget);
      expect(find.text('Creating…'), findsNothing);
      expect(buttonsEnabled(tester), isFalse);

      saveGate.complete();
      await tester.pumpAndSettle();
      expect(saveButton(), findsOneWidget);
      expect(find.text(savedAs), findsOneWidget);
      expect(buttonsEnabled(tester), isTrue);
    });

    testWidgets('on the Share way the tapped button reads "Creating…" to the '
        'end, never "Saving…"', (tester) async {
      final buildGate = Completer<void>();
      final shareGate = Completer<void>();
      await tester.pumpWidget(
        page(
          useCase: builds(gate: buildGate),
          share: _FakeShare(gate: shareGate),
        ),
      );

      await tapCreateBackup(tester);
      await tester.pump();
      expect(find.widgetWithText(OutlinedButton, 'Creating…'), findsOneWidget);
      expect(saveButton(), findsOneWidget);

      buildGate.complete();
      await tester.pump();
      await tester.pump();
      expect(find.widgetWithText(OutlinedButton, 'Creating…'), findsOneWidget);
      expect(find.text('Saving…'), findsNothing);
      expect(buttonsEnabled(tester), isFalse);

      shareGate.complete();
      await tester.pumpAndSettle();
      expect(find.text(handedOver), findsOneWidget);
    });

    testWidgets('a page that is left while the save window is open still '
        'gives the file back', (tester) async {
      final saveGate = Completer<void>();
      final useCase = builds();
      await tester.pumpWidget(
        page(
          useCase: useCase,
          saver: FakeDocumentSaver(gate: saveGate),
        ),
      );
      await tapSaveBackup(tester);
      await tester.pump();
      expect(useCase.discarded, isEmpty);

      // The page goes away; the system's window is still open above it.
      await tester.pumpWidget(const SizedBox());
      saveGate.complete();
      await tester.pumpAndSettle();

      expect(useCase.discarded, hasLength(1));
    });

    testWidgets('a second run takes the sentence of the first away as soon '
        'as it starts', (tester) async {
      // The second build waits at a gate, so the test can look at the page
      // WHILE it runs: what the first run ended with must be gone by then,
      // not only replaced at the end.
      final gate = Completer<void>();
      final useCase = _FakeCreateBackup(
        right(Uint8List.fromList([1, 2, 3])),
        gate: gate,
        gateFromCall: 2,
      );
      await tester.pumpWidget(page(useCase: useCase));

      await tapSaveBackup(tester);
      await tester.pumpAndSettle();
      expect(find.text(savedAs), findsOneWidget);

      await tapSaveBackup(tester);
      await tester.pump();
      expect(find.text(savedAs), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text(savedAs), findsOneWidget);
    });

    testWidgets('the page with two buttons, the note and a sentence meets '
        'the accessibility guidelines', (tester) async {
      await tester.pumpWidget(page(useCase: builds()));
      await expectMeetsA11yGuidelines(tester);

      await tapSaveBackup(tester);
      await tester.pumpAndSettle();
      expect(find.text(savedAs), findsOneWidget);
      await expectMeetsA11yGuidelines(tester);
    });
  });

  // Decision D177 (after the first look on a device): the sentence of a
  // finished run could lie below the screen, and after a save the system's
  // window is gone and the page is all the user has. The page brings the
  // sentence into view by itself.
  group('D177: the sentence of a finished run is brought into view', () {
    /// Whether the widget of [finder] lies on the screen, below the bar at
    /// the top, with all of its height.
    bool onScreen(WidgetTester tester, Finder finder) {
      if (finder.evaluate().isEmpty) return false;
      final rect = tester.getRect(finder);
      final height =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      return rect.top >= kToolbarHeight && rect.bottom <= height;
    }

    /// Starts a run from [button] and stops the clock at the moment that
    /// matters: the run is held at [gate], and the screen is cut off just
    /// under the tapped button, so that everything below it (the other
    /// button, the note, and the sentence to come) lies BELOW the screen.
    /// Then the run is let go.
    ///
    /// Why not simply a short screen from the start: the notice of BR9
    /// needs room, and how long the page is depends on the test's font. So
    /// the button's place is measured, not guessed.
    Future<void> finishRunWithTheButtonAtTheBottomEdge(
      WidgetTester tester,
      Finder button,
      Type buttonType,
      Completer<void> gate, {
      double? screenHeight,
    }) async {
      tester.view
        ..physicalSize = const Size(400, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pump();
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(noticeConfirm());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // The run waits at the gate. (The tapped button reads "Creating…" or
      // "Saving…" now, so it is found by its kind.)
      final bottom = tester.getRect(find.byType(buttonType)).bottom;
      // Without [screenHeight] the screen ends 4 pixels under the button.
      // With it the screen is shorter still (for a test that needs the
      // RESULT to be taller than the screen), and the list is moved so
      // that the button sits at the bottom edge all the same.
      final height = screenHeight ?? bottom + 4;
      tester.view.physicalSize = Size(400, height);
      await tester.pump();
      if (screenHeight != null) {
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(bottom + 4 - height);
        await tester.pump();
      }
      expect(tester.getRect(find.byType(buttonType)).bottom, height - 4);

      gate.complete();
      await tester.pumpAndSettle();
    }

    _FakeCreateBackup built({Completer<void>? gate}) =>
        _FakeCreateBackup(right(Uint8List.fromList([1, 2, 3])), gate: gate);

    testWidgets('after a save, "Backup saved as …" is on the screen', (
      tester,
    ) async {
      final gate = Completer<void>();
      await tester.pumpWidget(
        page(
          useCase: built(),
          saver: FakeDocumentSaver(gate: gate),
        ),
      );

      await finishRunWithTheButtonAtTheBottomEdge(
        tester,
        saveButton(),
        FilledButton,
        gate,
      );

      expect(onScreen(tester, find.textContaining('Backup saved as')), isTrue);
    });

    testWidgets('a save window that was left: its sentence is on the '
        'screen', (tester) async {
      final gate = Completer<void>();
      await tester.pumpWidget(
        page(
          useCase: built(),
          saver: FakeDocumentSaver(
            result: const DocumentSaveCancelled(),
            gate: gate,
          ),
        ),
      );

      await finishRunWithTheButtonAtTheBottomEdge(
        tester,
        saveButton(),
        FilledButton,
        gate,
      );

      expect(
        onScreen(
          tester,
          find.text('No place was chosen, so nothing was saved.'),
        ),
        isTrue,
      );
    });

    testWidgets('a share sheet that was left: its sentence is on the '
        'screen', (tester) async {
      final gate = Completer<void>();
      await tester.pumpWidget(
        page(
          useCase: built(),
          share: _FakeShare(outcome: ShareOutcome.dismissed, gate: gate),
        ),
      );

      await finishRunWithTheButtonAtTheBottomEdge(
        tester,
        shareButton(),
        OutlinedButton,
        gate,
      );

      expect(
        onScreen(tester, find.textContaining('Nothing was shared')),
        isTrue,
      );
    });

    testWidgets('a backup that could not be built: its sentence is on the '
        'screen', (tester) async {
      final gate = Completer<void>();
      await tester.pumpWidget(
        page(
          useCase: _FakeCreateBackup(
            left(const StorageFailure('disk')),
            gate: gate,
          ),
        ),
      );

      await finishRunWithTheButtonAtTheBottomEdge(
        tester,
        saveButton(),
        FilledButton,
        gate,
      );

      expect(
        onScreen(
          tester,
          find.text('Could not build the backup. Please try again.'),
        ),
        isTrue,
      );
    });

    testWidgets('a run that throws: its sentence is on the screen', (
      tester,
    ) async {
      final gate = Completer<void>();
      await tester.pumpWidget(
        page(
          useCase: built(),
          saver: FakeDocumentSaver(
            error: StateError('channel exploded'),
            gate: gate,
          ),
        ),
      );

      await finishRunWithTheButtonAtTheBottomEdge(
        tester,
        saveButton(),
        FilledButton,
        gate,
      );

      expect(
        onScreen(
          tester,
          find.text('Something went wrong creating the backup.'),
        ),
        isTrue,
      );
    });

    testWidgets('a result that is taller than the screen shows its first '
        'line, the sentence', (tester) async {
      final gate = Completer<void>();
      await tester.pumpWidget(
        page(
          useCase: _FakeCreateBackup(
            right(Uint8List.fromList([1, 2, 3])),
            includesIdentity: false,
            includesNetwork: false,
            missingPublishState: true,
            vaultLeftOut: true,
            coversLeftOut: List.generate(
              5,
              (i) => 'A book with a rather long title, number $i',
            ),
          ),
          saver: FakeDocumentSaver(gate: gate),
        ),
      );

      // A screen of 300 pixels, 56 of them the bar at the top.
      await finishRunWithTheButtonAtTheBottomEdge(
        tester,
        saveButton(),
        FilledButton,
        gate,
        screenHeight: 300,
      );

      // Every note is under the sentence, and together they need more room
      // than this screen has under its top bar (checked, so that the test
      // cannot pass for a result that simply fits). The sentence is what
      // must be read first.
      expect(
        tester.getSize(find.byType(BackupRunResult)).height,
        greaterThan(300 - kToolbarHeight),
      );
      expect(onScreen(tester, find.textContaining('Backup saved as')), isTrue);
    });
  });

  // Decision D190 (the review stop of P4-M6). After a save the system's
  // window closes and the page's sentence is all the user has. A user who
  // sees the screen gets it scrolled into view (D177); a user of a screen
  // reader gets it read out: the result is a "live region". What is asked
  // here is what a screen reader is GIVEN; that it speaks is its own side
  // and is seen on a device only.
  group('D190, for a screen reader: the result of a run is read out when '
      'it appears', () {
    const savedAs = 'Backup saved as pitak-backup-02Nov2026-134659.pitabak.';

    _FakeCreateBackup builds({
      Completer<void>? gate,
      int gateFromCall = 1,
      bool vaultLeftOut = false,
    }) => _FakeCreateBackup(
      right(Uint8List.fromList([1, 2, 3])),
      gate: gate,
      gateFromCall: gateFromCall,
      vaultLeftOut: vaultLeftOut,
    );

    /// Taps "Save backup" and says "Go on" to the notice. The run then goes
    /// as far as it can: to its end, or to a gate.
    Future<void> tapSaveBackup(WidgetTester tester) async {
      await tester.tap(saveButton());
      await tester.pumpAndSettle();
      await tester.tap(noticeConfirm());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('after a save, "Backup saved as …" is a live region of its '
        'own: that sentence and nothing else of the page', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(page(useCase: builds()));
      // Before a run there is no result, and nothing to read out.
      expect(liveRegionLabels(tester), isEmpty);

      await tapSaveBackup(tester);
      await tester.pumpAndSettle();

      // Exactly the sentence: the note under the buttons ("The backup is
      // an ordinary file: …") stands just above it and is NOT part of it.
      expect(liveRegionLabels(tester), [savedAs]);
      handle.dispose();
    });

    testWidgets('what the backup does not carry is read out with "saved", '
        'after it', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(page(useCase: builds(vaultLeftOut: true)));

      await tapSaveBackup(tester);
      await tester.pumpAndSettle();

      final vaultNote = tester
          .widget<Text>(find.byKey(const Key('backup-vault-left-out')))
          .data;
      expect(vaultNote, startsWith('Note: the borrowers vault is not inside'));
      // A user who hears "saved" is also told what is missing.
      expect(liveRegionLabels(tester), ['$savedAs\n$vaultNote']);
      handle.dispose();
    });

    testWidgets('a save window that was left: its sentence is a live '
        'region', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        page(
          useCase: builds(),
          saver: FakeDocumentSaver(result: const DocumentSaveCancelled()),
        ),
      );

      await tapSaveBackup(tester);
      await tester.pumpAndSettle();

      expect(liveRegionLabels(tester), [
        'No place was chosen, so nothing was saved.',
      ]);
      handle.dispose();
    });

    testWidgets('a backup that could not be built: its sentence is a live '
        'region', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        page(useCase: _FakeCreateBackup(left(const StorageFailure('disk')))),
      );

      await tapSaveBackup(tester);
      await tester.pumpAndSettle();

      expect(liveRegionLabels(tester), [
        'Could not build the backup. Please try again.',
      ]);
      handle.dispose();
    });

    testWidgets('while a run goes nothing is a live region: not the note, '
        'not the progress line, and not the result of the run before', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      // The second build waits at a gate, so the test can look at the page
      // WHILE it runs.
      final gate = Completer<void>();
      final useCase = builds(gate: gate, gateFromCall: 2);
      await tester.pumpWidget(page(useCase: useCase));

      await tapSaveBackup(tester);
      await tester.pumpAndSettle();
      expect(liveRegionLabels(tester), [savedAs]);

      await tapSaveBackup(tester);
      useCase.report(1, 2);
      await tester.pump();

      // The progress line is there and changes at every step. If it were
      // part of a live region, a screen reader would be handed it (and the
      // note above it) again and again.
      expect(find.byKey(const Key('backup-progress')), findsOneWidget);
      expect(liveRegionLabels(tester), isEmpty);

      // The second run's result is a region again: built anew, read anew.
      gate.complete();
      await tester.pumpAndSettle();
      expect(liveRegionLabels(tester), [savedAs]);
      handle.dispose();
    });
  });
}
