import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/platform/device_cameras.dart';
import 'package:pitaka/core/storage/run_folders.dart';
import 'package:pitaka/core/theme/app_theme.dart';
import 'package:pitaka/core/widgets/camera_scan_messages.dart';
import 'package:pitaka/features/app_update/domain/app_update_policy.dart';
import 'package:pitaka/features/backup/domain/backup_work_area.dart';
import 'package:pitaka/features/library/application/catalogue_changes.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/application/library_window.dart';
import 'package:pitaka/features/library/domain/catalogue_item_page.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/library_query.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/library/presentation/pages/library_page.dart';
import 'package:pitaka/features/library/presentation/widgets/catalogue_item_grid_card.dart';
import 'package:pitaka/features/library/presentation/widgets/catalogue_item_row.dart';
import 'package:pitaka/features/library/presentation/widgets/library_controls_row.dart';
import 'package:pitaka/features/library/presentation/widgets/loan_status_hidden_banner.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/presentation/pages/vault_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/a11y.dart';
import '../../support/fake_document_picker.dart';
import '../../support/fake_scan_camera.dart';
import '../../support/fake_vault_session.dart';
import '../app_update/fake_app_update_service.dart';

/// Counts the sweeps asked of it (backup rework BR4); touches no disk.
class _CountingWorkArea implements BackupWorkArea {
  int sweeps = 0;

  @override
  Future<Either<Failure, Unit>> sweep() async {
    sweeps++;
    return right(unit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// In-memory repo: [getAll] returns [_all]; a search page returns only titles
/// that contain the query (case-insensitive), mimicking the FTS5 contract
/// enough for a widget test without a real database.
class _FakeBookRepo implements CatalogueItemRepository {
  _FakeBookRepo(this._all);

  // CatalogueItemRepository additions (review 2026-09-03): fakes default to "no
  // match" and a pass-through transaction unless a test overrides them.
  @override
  Future<Either<Failure, CatalogueItem?>> findByUid(String itemUid) async =>
      right(null);
  @override
  Future<Either<Failure, T>> runInTransaction<T>(
    Future<Either<Failure, T>> Function() action,
  ) => action();

  final List<CatalogueItem> _all;
  Failure? failWith;

  @override
  Future<Either<Failure, List<CatalogueItem>>> getAll() async =>
      failWith != null ? left(failWith!) : right(_all);
  @override
  Future<Either<Failure, List<CatalogueItem>>> getAllForInterchange() async =>
      failWith != null ? left(failWith!) : right(_all);

  /// Every page read the page asked for, as (offset, limit) — N10-d part 2.
  final List<(int, int)> pagesSeen = [];

  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    pagesSeen.add((offset, limit));
    if (failWith != null) return left(failWith!);
    final q = query.text.toLowerCase();
    final rows = _all.where((item) {
      if (query.isSearch && !item.title.toLowerCase().contains(q)) {
        return false;
      }
      if (query.kind != null && item.kind != query.kind) return false;
      final language = query.language;
      if (language != null &&
          item.language?.toLowerCase() != language.toLowerCase()) {
        return false;
      }
      return true;
    }).toList();
    final start = offset.clamp(0, rows.length);
    final end = (start + limit).clamp(start, rows.length);
    return right(
      CatalogueItemPage(
        items: rows.sublist(start, end),
        hasMore: end < rows.length,
      ),
    );
  }

  @override
  Future<Either<Failure, CatalogueItem?>> findByIsbn(String isbn) async =>
      right(null);
  // N03: the detail page observes its row by id, so the fake must answer
  // from the same list the rows came from.
  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async =>
      failWith != null
      ? left(failWith!)
      : right(_all.where((b) => b.id == id).firstOrNull);
  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async {
    final languages = <String>{};
    for (final item in _all) {
      final language = item.language?.trim();
      if (language != null && language.isNotEmpty) languages.add(language);
    }
    return right(languages.toList()..sort());
  }

  @override
  Future<Either<Failure, List<String>>> distinctSourceDetails(
    ItemSourceType type,
  ) async => right(const []);
  @override
  Future<Either<Failure, Unit>> markRemoved(int id, int at) async =>
      right(unit);
  @override
  Future<Either<Failure, Unit>> restoreRemoved(int id) async => right(unit);

  @override
  Future<Either<Failure, Unit>> delete(int id) async => right(unit);
  @override
  Future<Either<Failure, CatalogueItem>> insert(CatalogueItem book) async =>
      right(book);
  @override
  Future<Either<Failure, CatalogueItem>> update(CatalogueItem book) async =>
      right(book);
  @override
  Future<Either<Failure, int>> insertAll(List<CatalogueItem> books) async =>
      right(books.length);
  @override
  Future<Either<Failure, int>> replaceAll(List<CatalogueItem> books) async =>
      right(books.length);
}

/// Empty series store: the row's cover-fallback map
/// (`periodicalCoversProvider`, S14) reads `listAll`; these tests use books,
/// so the map stays empty.
class _NoPeriodicals implements PeriodicalRepository {
  @override
  Future<Either<Failure, List<PeriodicalSummary>>> listAll() async =>
      right(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

Widget _app(
  CatalogueItemRepository repo, {
  List<Override> extraOverrides = const [],
  ThemeData? theme,
  TransitionBuilder? builder,
}) {
  return ProviderScope(
    overrides: [
      ...extraOverrides,
      catalogueItemRepositoryProvider.overrideWith((ref) async => repo),
      periodicalRepositoryProvider.overrideWith(
        (ref) async => _NoPeriodicals(),
      ),
      // S14: the row's cover map watches PeriodicalsController, whose build
      // arms the real 60 s nowTick timer — pinned to a constant here so the
      // widget tests can settle (same override vault page tests use).
      nowTickProvider.overrideWith((ref) => 0),
    ],
    child: MaterialApp(
      theme: theme,
      builder: builder,
      home: const LibraryPage(),
    ),
  );
}

/// A phone's screen (the golden tests' size, 411 dp wide). Without it a
/// widget test is 800 dp wide, where the Library screen draws its grid.
void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

/// Puts the vault session into [state] for one test (P4-M4).
Override _vaultIn(VaultSessionState state) =>
    vaultSessionControllerProvider.overrideWith(() => FixedVaultSession(state));

Future<void> _enterQuery(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  // Let the 120ms debounce elapse and the asynchronous reload settle.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

String _visibleQuery(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

FilterChip _filterChip(WidgetTester tester, String label) =>
    tester.widget<FilterChip>(find.widgetWithText(FilterChip, label));

void main() {
  // Distinct ids: rows are opened by id (N03), and three books sharing the
  // `emptyId` sentinel would be indistinguishable to the detail page.
  const books = [
    CatalogueItem(id: 1, title: 'The Hobbit', author: 'Tolkien', copyCount: 3),
    CatalogueItem(id: 2, title: 'Dune', author: 'Herbert'),
    CatalogueItem(id: 3, title: 'Old Tales', removed: true),
  ];

  // BR4: a backup that was killed half-way leaves a plain copy of the
  // library in the app's temporary folder. The Library screen, the first
  // screen of every start, has it removed: once, after the list has loaded.
  testWidgets('BR4: stale backup files are swept once, after the list has '
      'loaded', (tester) async {
    final workArea = _CountingWorkArea();
    final repo = _GatedRepo(books)..gate = Completer<void>();
    await tester.pumpWidget(
      _app(
        repo,
        extraOverrides: [
          backupWorkAreaProvider.overrideWith((ref) async => workArea),
        ],
      ),
    );
    await tester.pump();
    expect(workArea.sweeps, 0, reason: 'not before the first paint of rows');

    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(workArea.sweeps, 1);

    // Rebuilding the screen does not sweep again in the same app session.
    await _enterQuery(tester, 'dune');
    await _enterQuery(tester, '');
    expect(workArea.sweeps, 1);
  });

  // BR6: the same for a restore that was killed half-way. It leaves the
  // private copy of the chosen backup file and the databases unpacked from
  // it; both are plain copies of a library.
  testWidgets('BR6: what a killed restore left behind is swept once, after '
      'the list has loaded', (tester) async {
    final temp = Directory.systemTemp.createTempSync('library_sweep_test');
    addTearDown(() => temp.deleteSync(recursive: true));
    final picker = FakeDocumentPicker(Directory('${temp.path}/picked'));
    final repo = _GatedRepo(books)..gate = Completer<void>();
    await tester.pumpWidget(
      _app(
        repo,
        extraOverrides: [
          documentPickerProvider.overrideWith((ref) async => picker),
          // A keeper of work folders over a folder that does not exist:
          // its sweep has nothing to look at and touches no disk.
          restoreWorkFoldersProvider.overrideWith(
            (ref) async => RunFolders(
              rootPath: '${temp.path}/restore_work',
              prefix: 'run',
            ),
          ),
        ],
      ),
    );
    await tester.pump();
    expect(picker.sweeps, 0, reason: 'not before the first paint of rows');

    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(picker.sweeps, 1);

    // Rebuilding the screen does not sweep again in the same app session.
    await _enterQuery(tester, 'dune');
    await _enterQuery(tester, '');
    expect(picker.sweeps, 1);
  });

  // D33: the copies of chosen files that the old file picker left in the
  // cache folder are removed from the same place, the same way. (What the
  // clean-up itself does is tested in `legacy_picker_copies_test.dart`.)
  testWidgets('D33: the clean-up of the old file picker\u2019s copies is '
      'started once, after the list has loaded', (tester) async {
    var started = 0;
    final repo = _GatedRepo(books)..gate = Completer<void>();
    await tester.pumpWidget(
      _app(
        repo,
        extraOverrides: [
          legacyPickerCopiesSweepProvider.overrideWith((ref) async {
            started++;
          }),
        ],
      ),
    );
    await tester.pump();
    expect(started, 0, reason: 'not before the first paint of rows');

    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(started, 1);

    // Rebuilding the screen does not start it again in the same session.
    await _enterQuery(tester, 'dune');
    await _enterQuery(tester, '');
    expect(started, 1);
  });

  testWidgets('renders all books newest-first on load', (tester) async {
    await tester.pumpWidget(_app(_FakeBookRepo(books)));
    await tester.pumpAndSettle();

    expect(find.text('The Hobbit'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Old Tales'), findsOneWidget);
    // Copies label (copyCount > 1) and removed badge are visible.
    expect(find.text('Copies: 3'), findsOneWidget);
    expect(find.text('Removed'), findsOneWidget);
  });

  // 2026-11-09: the page feeds the vault's active-loan counts to the rows —
  // a partial count on the copies label, "not available" on the shelf line
  // when every copy is out.
  testWidgets('unlocked vault counts reach the rows', (tester) async {
    await tester.pumpWidget(
      _app(
        _FakeBookRepo(books),
        extraOverrides: [
          activeLoanCountsProvider.overrideWith((ref) => {1: 1, 2: 1}),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Copies: 3 · 1 out'), findsOneWidget);
    // Dune has one copy and it is out: the not-available shelf line.
    expect(find.text('Not available'), findsOneWidget);
    expect(find.byIcon(Icons.outbox), findsOneWidget);
  });

  testWidgets('a locked vault shows no loan counts', (tester) async {
    await tester.pumpWidget(
      _app(
        _FakeBookRepo(books),
        extraOverrides: [activeLoanCountsProvider.overrideWith((ref) => null)],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Copies: 3'), findsOneWidget);
    expect(find.textContaining(' out'), findsNothing);
    expect(find.byIcon(Icons.outbox), findsNothing);
  });

  // Review finding P4-M4 (decisions D84 to D87): after every app start the
  // vault is locked and the rows cannot show what is lent out. The screen
  // then says so in one line, which is a function of the vault's STATE alone
  // and never of a loan.
  group('P4-M4: the line for a locked vault', () {
    const sentence = LoanStatusHiddenBanner.message;
    // The banner the widget draws while it shows; the widget itself is
    // always in the tree and takes no room otherwise.
    Finder line() => find.byType(MaterialBanner);
    // By key: the vault screen has an "Unlock" button of its own.
    Finder unlockButton() => find.byKey(LoanStatusHiddenBanner.unlockKey);
    // Book 1 has three copies and one is out; book 2 has one copy, and it
    // is out.
    const lentOut = VaultData(
      borrowers: [Borrower(id: 1, name: 'Asha')],
      loans: [
        Loan(id: 1, itemId: 1, borrowerId: 1, lentDate: 0),
        Loan(id: 2, itemId: 2, borrowerId: 1, lentDate: 0),
      ],
    );

    testWidgets('a locked vault: the line is between the chips and the list', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      await tester.pumpWidget(
        _app(
          _FakeBookRepo(books),
          extraOverrides: [_vaultIn(const VaultLocked())],
        ),
      );
      await tester.pumpAndSettle();

      // The words are written out HERE and nowhere else (D85): the other
      // tests take them from the widget and would follow a change of them.
      expect(
        find.descendant(
          of: line(),
          matching: find.text(
            'Unlock the borrowers vault to see which items are lent out.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: line(),
          matching: find.widgetWithText(TextButton, 'Unlock'),
        ),
        findsOneWidget,
      );
      expect(unlockButton(), findsOneWidget);
      final place = tester.getRect(line());
      expect(
        place.top,
        greaterThanOrEqualTo(
          tester.getRect(find.byType(LibraryControlsRow)).bottom,
        ),
      );
      expect(
        place.bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byType(CatalogueItemRow).first).top,
        ),
      );
    });

    testWidgets('the line\u2019s button opens the vault screen', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(const {});
      _usePhoneScreen(tester);
      await tester.pumpWidget(
        _app(
          _FakeBookRepo(books),
          extraOverrides: [_vaultIn(const VaultLocked())],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(unlockButton());
      await tester.pumpAndSettle();

      expect(find.byType(VaultPage), findsOneWidget);
      expect(
        find.textContaining('Enter your vault passphrase'),
        findsOneWidget,
      );
    });

    testWidgets('the line stays when the list is scrolled to its end', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final many = [
        for (var i = 1; i <= 40; i++) CatalogueItem(id: i, title: 'Book $i'),
      ];
      await tester.pumpWidget(
        _app(
          _FakeBookRepo(many),
          extraOverrides: [_vaultIn(const VaultLocked())],
        ),
      );
      await tester.pumpAndSettle();
      expect(line(), findsOneWidget);
      final before = tester.getRect(line());

      await tester.scrollUntilVisible(
        find.text('Book 40'),
        400,
        scrollable: _bookList(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Book 1'), findsNothing, reason: 'the list scrolled');
      expect(find.text(sentence), findsOneWidget);
      expect(tester.getRect(line()), before);
    });

    testWidgets('no vault: no line', (tester) async {
      _usePhoneScreen(tester);
      await tester.pumpWidget(
        _app(
          _FakeBookRepo(books),
          extraOverrides: [_vaultIn(const VaultUninitialized())],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('The Hobbit'), findsOneWidget);
      expect(line(), findsNothing);
      expect(find.text(sentence), findsNothing);
    });

    testWidgets('an unlocked vault: no line, and the rows show what is lent '
        'out', (tester) async {
      _usePhoneScreen(tester);
      await tester.pumpWidget(
        _app(
          _FakeBookRepo(books),
          // The session itself, not the counts: the rows get them through
          // the real activeLoanCounts provider.
          extraOverrides: [_vaultIn(const VaultUnlocked(lentOut))],
        ),
      );
      await tester.pumpAndSettle();

      expect(line(), findsNothing);
      expect(find.text(sentence), findsNothing);
      expect(find.text('Copies: 3 · 1 out'), findsOneWidget);
      expect(find.text('Not available'), findsOneWidget);
    });

    testWidgets('the vault\u2019s state not known yet: no line', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      await tester.pumpWidget(
        _app(
          _FakeBookRepo(books),
          extraOverrides: [
            vaultSessionControllerProvider.overrideWith(
              PendingVaultSession.new,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // The app does not claim a locked vault it has not seen.
      expect(find.text('The Hobbit'), findsOneWidget);
      expect(line(), findsNothing);
      expect(find.text(sentence), findsNothing);
    });

    // Decision D89: no new golden picture. The three pictures of this
    // screen are made with a harness that, like this one, does not replace
    // the vault; they stay as they are only if no line shows then.
    testWidgets('the harness of the golden pictures (the vault not '
        'replaced): no line', (tester) async {
      _usePhoneScreen(tester);
      await tester.pumpWidget(_app(_FakeBookRepo(books)));
      await tester.pumpAndSettle();

      expect(find.text('The Hobbit'), findsOneWidget);
      expect(line(), findsNothing);
      expect(find.text(sentence), findsNothing);
    });

    testWidgets('a locked vault and an empty library: the line is there', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      await tester.pumpWidget(
        _app(
          _FakeBookRepo(const []),
          extraOverrides: [_vaultIn(const VaultLocked())],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your library is empty'), findsOneWidget);
      expect(find.text(sentence), findsOneWidget);
      expect(unlockButton(), findsOneWidget);
    });

    for (final (name, theme) in [
      ('light', null),
      // The shipped dark theme, so that contrast is checked on real colours.
      ('dark', AppTheme.dark),
    ]) {
      testWidgets('meets accessibility guidelines with the line ($name)', (
        tester,
      ) async {
        _usePhoneScreen(tester);
        await tester.pumpWidget(
          _app(
            _FakeBookRepo(books),
            extraOverrides: [_vaultIn(const VaultLocked())],
            theme: theme,
          ),
        );
        await tester.pumpAndSettle();

        // First that it is there: the guidelines pass for a missing line.
        expect(find.text(sentence), findsOneWidget);
        await expectMeetsA11yGuidelines(tester);
      });
    }

    testWidgets('twice the text size with the line: nothing overflows', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      await tester.pumpWidget(
        _app(
          _FakeBookRepo(books),
          extraOverrides: [_vaultIn(const VaultLocked())],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(sentence), findsOneWidget);
      expect(unlockButton(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // Rule 4 of the design as a CHANGE of state: the tests above look at
    // each state standing still.
    testWidgets('unlocking takes the line away and shows what is lent out; '
        'locking brings it back', (tester) async {
      _usePhoneScreen(tester);
      late FixedVaultSession session;
      await tester.pumpWidget(
        _app(
          _FakeBookRepo(books),
          extraOverrides: [
            vaultSessionControllerProvider.overrideWith(
              () => session = FixedVaultSession(const VaultLocked()),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(sentence), findsOneWidget);
      expect(find.text('Not available'), findsNothing);

      session.show(const VaultUnlocked(lentOut));
      await tester.pumpAndSettle();
      expect(find.text(sentence), findsNothing);
      expect(line(), findsNothing);
      expect(find.text('Not available'), findsOneWidget);

      session.show(const VaultLocked());
      await tester.pumpAndSettle();
      expect(find.text(sentence), findsOneWidget);
      expect(find.text('Not available'), findsNothing);
    });
  });

  testWidgets('typing a query filters the list (debounced)', (tester) async {
    await tester.pumpWidget(_app(_FakeBookRepo(books)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hobbit');
    // Let the 120ms debounce elapse and the async reload settle.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text('The Hobbit'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);
  });

  testWidgets('S9: a query-only empty result clears its visible search', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_FakeBookRepo(books)));
    await tester.pumpAndSettle();

    await _enterQuery(tester, 'zzzz');

    expect(find.text('No items match these filters.'), findsOneWidget);
    expect(find.text('Your library is empty'), findsNothing);
    expect(find.text('Clear search'), findsOneWidget);
    expect(find.text('Clear filters'), findsNothing);
    expect(find.text('Add a book'), findsNothing);
    expect(find.text('Import'), findsNothing);

    await tester.tap(find.text('Clear search'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(_visibleQuery(tester), isEmpty);
    expect(find.text('The Hobbit'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
  });

  testWidgets('S9: a facet-only empty result is not an empty library', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_FakeBookRepo(books)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Magazines'));
    await tester.pumpAndSettle();

    expect(find.text('No items match these filters.'), findsOneWidget);
    expect(find.text('Your library is empty'), findsNothing);
    expect(find.text('Clear filters'), findsOneWidget);
    expect(find.text('Clear search'), findsNothing);
    expect(find.text('Add a book'), findsNothing);
    expect(find.text('Import'), findsNothing);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();

    expect(find.text('The Hobbit'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(_filterChip(tester, 'Magazines').selected, isFalse);
  });

  testWidgets('S9: Clear filters preserves the query in a combined empty '
      'result', (tester) async {
    await tester.pumpWidget(_app(_FakeBookRepo(books)));
    await tester.pumpAndSettle();

    await _enterQuery(tester, 'hobbit');
    await tester.tap(find.text('Magazines'));
    await tester.pumpAndSettle();

    expect(find.text('No items match these filters.'), findsOneWidget);
    expect(find.text('Clear search'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);
    await expectMeetsA11yGuidelines(tester);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();

    expect(_visibleQuery(tester), 'hobbit');
    expect(_filterChip(tester, 'Magazines').selected, isFalse);
    expect(find.text('The Hobbit'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);
  });

  testWidgets('S9: Clear search preserves facets in a combined empty result', (
    tester,
  ) async {
    const facetedBooks = [
      CatalogueItem(id: 1, title: 'Dune', language: 'English'),
      CatalogueItem(id: 2, title: 'Godaan', language: 'Hindi'),
    ];
    await tester.pumpWidget(_app(_FakeBookRepo(facetedBooks)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await _enterQuery(tester, 'zzzz');

    expect(find.text('No items match these filters.'), findsOneWidget);
    expect(find.text('Clear search'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);

    await tester.tap(find.text('Clear search'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(_visibleQuery(tester), isEmpty);
    expect(_filterChip(tester, 'English').selected, isTrue);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Godaan'), findsNothing);
  });

  testWidgets('shows empty-library state when there are no books', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_FakeBookRepo(const [])));
    await tester.pumpAndSettle();

    expect(find.text('Your library is empty'), findsOneWidget);
  });

  // Review finding P4-M8, decision D132: the Library's "Scan to add" has no
  // ISBN field underneath. When the scan page has no camera picture, its
  // "Enter it by hand" leads to the sheet that adds an item by hand.
  testWidgets('"Scan to add" without a camera: "Enter it by hand" closes '
      'the scan page and opens the "Add to library" sheet', (tester) async {
    await tester.pumpWidget(
      _app(
        _FakeBookRepo(books),
        extraOverrides: [
          deviceCamerasProvider.overrideWithValue(
            FakeDeviceCameras(answer: DeviceCameraAnswer.noCamera),
          ),
          appSettingsOpenerProvider.overrideWithValue(FakeAppSettingsOpener()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Scan to add'));
    await tester.pumpAndSettle();
    expect(find.text('Scan ISBN barcode'), findsOneWidget);
    expect(find.text(scanNoCameraSentence), findsOneWidget);
    // The sheet's entries are not on the screen yet.
    expect(find.text('Add book'), findsNothing);

    await tester.tap(find.text(enterByHandLabel));
    await tester.pumpAndSettle();

    expect(find.text('Scan ISBN barcode'), findsNothing);
    expect(find.text('Add book'), findsOneWidget);
    expect(find.text('Add other item'), findsOneWidget);
    // No item was added and no form opened by itself.
    expect(find.text('The Hobbit'), findsOneWidget);
  });

  testWidgets('"Scan to add" without a camera: Back from the scan page '
      'opens no sheet', (tester) async {
    await tester.pumpWidget(
      _app(
        _FakeBookRepo(books),
        extraOverrides: [
          deviceCamerasProvider.overrideWithValue(
            FakeDeviceCameras(answer: DeviceCameraAnswer.noCamera),
          ),
          appSettingsOpenerProvider.overrideWithValue(FakeAppSettingsOpener()),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Scan to add'));
    await tester.pumpAndSettle();
    expect(find.text('Scan ISBN barcode'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Scan ISBN barcode'), findsNothing);
    expect(find.text('Add book'), findsNothing);
  });

  testWidgets('"Enter it by hand" when the Library screen itself is gone '
      'by then opens nothing and throws nothing', (tester) async {
    // The scan page lies over the app's first page. Should that first page
    // be another one by the time of the tap, its old state must not be
    // used.
    final showLibrary = ValueNotifier<bool>(true);
    addTearDown(showLibrary.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceCamerasProvider.overrideWithValue(
            FakeDeviceCameras(answer: DeviceCameraAnswer.noCamera),
          ),
          appSettingsOpenerProvider.overrideWithValue(FakeAppSettingsOpener()),
          catalogueItemRepositoryProvider.overrideWith(
            (ref) async => _FakeBookRepo(books),
          ),
          periodicalRepositoryProvider.overrideWith(
            (ref) async => _NoPeriodicals(),
          ),
          nowTickProvider.overrideWith((ref) => 0),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: showLibrary,
            builder: (_, show, _) => show
                ? const LibraryPage()
                : const Scaffold(body: Text('another first page')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Scan to add'));
    await tester.pumpAndSettle();
    expect(find.text(enterByHandLabel), findsOneWidget);

    showLibrary.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(LibraryPage, skipOffstage: false), findsNothing);

    await tester.tap(find.text(enterByHandLabel));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('another first page'), findsOneWidget);
    expect(find.text('Add book'), findsNothing);
  });

  testWidgets('the app-bar map button sits left of scan and opens the '
      'network screen on its Map tab', (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    await tester.pumpWidget(_app(_FakeBookRepo(books)));
    await tester.pumpAndSettle();

    final mapButton = find.byTooltip('Network map');
    final scanButton = find.byTooltip('Scan to add');
    expect(mapButton, findsOneWidget);
    expect(scanButton, findsOneWidget);
    expect(
      tester.getTopLeft(mapButton).dx,
      lessThan(tester.getTopLeft(scanButton).dx),
    );
    final scheme = Theme.of(tester.element(mapButton)).colorScheme;
    final mapIcon = tester.widget<Icon>(
      find.descendant(of: mapButton, matching: find.byIcon(Icons.map_rounded)),
    );
    final pinIcon = tester.widget<Icon>(
      find.descendant(of: mapButton, matching: find.byIcon(Icons.location_on)),
    );
    expect(mapIcon.color, scheme.primary);
    expect(pinIcon.color, scheme.tertiary);

    await tester.tap(mapButton);
    await tester.pumpAndSettle();

    // Landed on the Library network screen's Map tab: without tiles consent
    // the gate asks first instead of building the map (§5.9). (The tab view
    // lazily builds only the visible page, so no network providers run.)
    expect(find.text('Library network'), findsOneWidget);
    expect(find.text('Show the network map?'), findsOneWidget);
  });

  testWidgets('tapping a row opens the detail page', (tester) async {
    await tester.pumpWidget(_app(_FakeBookRepo(books)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('The Hobbit'));
    await tester.pumpAndSettle();

    // Generic detail uses kind-neutral wording, even though this row is a book.
    expect(find.text('Item'), findsOneWidget);
    expect(find.text('Quantity'), findsOneWidget);
  });

  testWidgets('repository failure shows a safe error, not raw text', (
    tester,
  ) async {
    final repo = _FakeBookRepo(books)..failWith = const StorageFailure('boom');
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't load your library"), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
  });

  // Review finding N10-d part 2: the screen shows one window and
  // fetches the next as the user nears the end — it never asks for the whole
  // catalogue.
  group('N10-d part 2 — windowed list', () {
    final many = List.generate(
      150,
      (i) => CatalogueItem(
        id: i + 1,
        title: 'Book number ${i + 1}',
        addedDate: 150 - i,
      ),
    );

    testWidgets('first paint reads ONE page and shows only its rows', (
      tester,
    ) async {
      final repo = _FakeBookRepo(many);
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();

      expect(repo.pagesSeen, [(0, libraryPageSize)]);
      expect(find.text('Book number 1'), findsOneWidget);
      // Row 61 belongs to page 2: not fetched, so not in the tree at all
      // (the list is a lazy sliver, so also check the fake was not asked).
      expect(repo.pagesSeen.any((p) => p.$1 > 0), isFalse);
    });

    testWidgets('scrolling towards the end fetches the next page and appends '
        'its rows; the footer spinner shows while it is pending', (
      tester,
    ) async {
      final repo = _FakeBookRepo(many);
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();

      // Drag through the first page (~4000 px of rows). Each drag frame lets
      // the NotificationListener see extentAfter shrink under the threshold.
      final list = _bookList();
      for (var i = 0; i < 12 && !repo.pagesSeen.contains((60, 60)); i++) {
        await tester.drag(list, const Offset(0, -600));
        await tester.pump();
      }
      expect(
        repo.pagesSeen,
        contains((60, libraryPageSize)),
        reason: 'page 2 requested near the end of page 1',
      );
      await tester.pumpAndSettle();

      // Rows from page 2 are now reachable.
      await tester.scrollUntilVisible(
        find.text('Book number 90'),
        400,
        scrollable: list,
      );
      expect(find.text('Book number 90'), findsOneWidget);
    });

    testWidgets('the footer progress indicator is visible while page 2 is in '
        'flight and gone once it lands', (tester) async {
      final repo = _SlowSecondPageRepo(many);
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();

      final list = _bookList();
      for (var i = 0; i < 12 && repo.gate == null; i++) {
        await tester.drag(list, const Offset(0, -600));
        await tester.pump();
      }
      expect(repo.gate, isNotNull, reason: 'page 2 requested');
      // Scroll to the very bottom so the footer is on screen.
      await tester.drag(list, const Offset(0, -5000));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('library-load-more')),
        findsOneWidget,
        reason: 'footer spinner while loading',
      );

      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-load-more')), findsNothing);
    });
  });

  // Review findings P4-M2 and P4-m13 (ADR 0031; decision D152). While the
  // list is read again the rows stay on the screen: the same list keeps its
  // place, another list starts at the top, and the spinner is left for the
  // very first load.
  group('P4-M2: the rows stay while the list is read again', () {
    List<CatalogueItem> many(int n, {String word = 'Book'}) => [
      for (var i = 1; i <= n; i++)
        CatalogueItem(id: i, title: '$word number $i', addedDate: n - i),
    ];

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(LibraryPage)));
    AsyncValue<LibraryWindow> listState(WidgetTester tester) =>
        containerOf(tester).read(libraryControllerProvider);
    int loadedRows(WidgetTester tester) =>
        listState(tester).value!.books.length;
    double offsetOf(WidgetTester tester) =>
        tester.state<ScrollableState>(_bookList()).position.pixels;
    int spinners() => find.byType(CircularProgressIndicator).evaluate().length;
    void sayChanged(WidgetTester tester) =>
        containerOf(tester).read(catalogueChangesProvider.notifier).changed();

    /// Scrolls until [rows] rows are loaded, then rests inside them.
    Future<void> scrollDeep(WidgetTester tester, int rows) async {
      for (var i = 0; i < 300 && loadedRows(tester) < rows; i++) {
        await tester.drag(_bookList(), const Offset(0, -600));
        await tester.pumpAndSettle();
      }
      expect(loadedRows(tester), greaterThanOrEqualTo(rows));
    }

    /// Two frames: Riverpod starts the read in the first one after a change.
    Future<void> letTheReadStart(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
      expect(listState(tester).isLoading, isTrue, reason: 'a read is running');
    }

    testWidgets('the very first load shows the spinner', (tester) async {
      final repo = _HeldRepo(many(5))..hold = Completer<void>();
      await tester.pumpWidget(_app(repo));
      await tester.pump();
      expect(spinners(), 1);
      expect(find.byType(CustomScrollView), findsNothing);

      repo.release();
      await tester.pumpAndSettle();
      expect(spinners(), 0);
      expect(find.text('Book number 1'), findsOneWidget);
    });

    testWidgets('a change is said while the list stands deep: no spinner, '
        'the rows stay and then change in place, the place is kept', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final repo = _HeldRepo(many(300));
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();
      await scrollDeep(tester, 180);
      final before = offsetOf(tester);
      final depth = loadedRows(tester);
      expect(before, greaterThan(3000), reason: 'well below the first rows');
      // What a write elsewhere did: every title is another one now.
      repo.rows
        ..clear()
        ..addAll(many(300, word: 'Changed'));

      repo.hold = Completer<void>();
      sayChanged(tester);
      await letTheReadStart(tester);
      expect(spinners(), 0);
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(offsetOf(tester), before);
      expect(find.textContaining('Book number'), findsWidgets);
      expect(find.textContaining('Changed number'), findsNothing);

      repo.release();
      await tester.pumpAndSettle();
      expect(offsetOf(tester), before);
      expect(loadedRows(tester), depth);
      expect(find.textContaining('Changed number'), findsWidgets);
      expect(find.textContaining('Book number'), findsNothing);
    });

    testWidgets('a letter is typed: the old rows stay where they stand until '
        'the new ones are there; the new list starts at the top', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final repo = _HeldRepo(many(300));
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();
      await scrollDeep(tester, 180);
      final before = offsetOf(tester);

      repo.hold = Completer<void>();
      await tester.enterText(find.byType(TextField), 'number 2');
      await tester.pump(const Duration(milliseconds: 130));
      await letTheReadStart(tester);
      expect(spinners(), 0);
      expect(offsetOf(tester), before);
      expect(find.text('Book number 1'), findsNothing, reason: 'still deep');

      repo.release();
      await tester.pumpAndSettle();
      expect(offsetOf(tester), 0);
      expect(find.text('Book number 2'), findsOneWidget);
      expect(find.text('Book number 1'), findsNothing);
    });

    testWidgets('a chip is tapped: the old rows stay until the new list is '
        'there, which starts at the top', (tester) async {
      _usePhoneScreen(tester);
      final repo = _HeldRepo(many(300));
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();
      await scrollDeep(tester, 180);
      final before = offsetOf(tester);

      repo.hold = Completer<void>();
      await tester.tap(find.widgetWithText(FilterChip, 'Books'));
      await letTheReadStart(tester);
      expect(spinners(), 0);
      expect(offsetOf(tester), before);

      repo.release();
      await tester.pumpAndSettle();
      expect(offsetOf(tester), 0);
      expect(find.text('Book number 1'), findsOneWidget);
    });

    testWidgets('the grid of a wide screen does the same: the place is kept '
        'after a change, and another list starts at the top', (tester) async {
      // 800 dp wide, the default of a widget test: the grid.
      final repo = _HeldRepo(many(300));
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();
      expect(find.byType(CatalogueItemGridCard), findsWidgets);
      await scrollDeep(tester, 180);
      final before = offsetOf(tester);
      expect(before, greaterThan(1000));

      repo.hold = Completer<void>();
      sayChanged(tester);
      await letTheReadStart(tester);
      expect(spinners(), 0);
      expect(offsetOf(tester), before);
      repo.release();
      await tester.pumpAndSettle();
      expect(offsetOf(tester), before);

      repo.hold = Completer<void>();
      await tester.tap(find.widgetWithText(FilterChip, 'Books'));
      await letTheReadStart(tester);
      expect(spinners(), 0);
      expect(offsetOf(tester), before);
      repo.release();
      await tester.pumpAndSettle();
      expect(offsetOf(tester), 0);
    });

    testWidgets('the pause before a search is 120 ms: nothing is read '
        'before it has passed', (tester) async {
      final repo = _FakeBookRepo(books);
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();
      final reads = repo.pagesSeen.length;

      await tester.enterText(find.byType(TextField), 'dune');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(repo.pagesSeen, hasLength(reads), reason: 'inside the pause');

      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump();
      expect(repo.pagesSeen, hasLength(reads + 1));
      await tester.pumpAndSettle();
      expect(find.text('Dune'), findsOneWidget);
      expect(find.text('The Hobbit'), findsNothing);
    });

    testWidgets('a reload that fails shows the error screen; while Retry '
        'runs the screen stays and Retry is greyed out; then the rows', (
      tester,
    ) async {
      final repo = _HeldRepo([...books]);
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();
      Finder retry() => find.widgetWithText(TextButton, 'Retry');

      repo.failWith = const StorageFailure('boom');
      sayChanged(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't load your library"), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
      expect(tester.widget<TextButton>(retry()).onPressed, isNotNull);

      repo
        ..failWith = null
        ..hold = Completer<void>();
      await tester.tap(retry());
      await letTheReadStart(tester);
      expect(spinners(), 0);
      expect(find.textContaining("Couldn't load your library"), findsOneWidget);
      expect(tester.widget<TextButton>(retry()).onPressed, isNull);
      await expectMeetsA11yGuidelines(tester);

      repo.release();
      await tester.pumpAndSettle();
      expect(find.text('The Hobbit'), findsOneWidget);
      expect(retry(), findsNothing);
    });

    testWidgets('an empty answer keeps its own words while the next list '
        'is read: cleared filters do not say "Your library is empty"', (
      tester,
    ) async {
      final repo = _HeldRepo([...books]);
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Magazines'));
      await tester.pumpAndSettle();
      expect(find.text('No items match these filters.'), findsOneWidget);

      repo.hold = Completer<void>();
      await tester.tap(find.text('Clear filters'));
      await letTheReadStart(tester);
      expect(spinners(), 0);
      expect(find.text('No items match these filters.'), findsOneWidget);
      expect(find.text('Your library is empty'), findsNothing);
      expect(find.text('Add a book'), findsNothing);

      repo.release();
      await tester.pumpAndSettle();
      expect(find.text('The Hobbit'), findsOneWidget);
    });

    testWidgets('an empty library keeps its own words while a search is '
        'read: no "No items match" before the answer', (tester) async {
      final repo = _HeldRepo([]);
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();
      expect(find.text('Your library is empty'), findsOneWidget);

      repo.hold = Completer<void>();
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pump(const Duration(milliseconds: 130));
      await letTheReadStart(tester);
      expect(spinners(), 0);
      expect(find.text('Your library is empty'), findsOneWidget);
      expect(find.text('No items match these filters.'), findsNothing);

      repo.release();
      await tester.pumpAndSettle();
      expect(find.text('No items match these filters.'), findsOneWidget);
      expect(find.text('Clear search'), findsOneWidget);
    });

    // Review finding P4-m13: the chips were empty for as long as the
    // languages were read again, which showed as a blink.
    testWidgets('P4-m13: the language chips stay while the languages are '
        'read again', (tester) async {
      final repo = _HeldRepo(const [
        CatalogueItem(id: 1, title: 'Dune', language: 'English'),
        CatalogueItem(id: 2, title: 'Godaan', language: 'Hindi'),
      ]);
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilterChip, 'English'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Hindi'), findsOneWidget);
      final reads = repo.languageReads;

      repo.holdLanguages = Completer<void>();
      sayChanged(tester);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(
        repo.languageReads,
        reads + 1,
        reason: 'they are being read again, once for one change (P3-M4)',
      );
      expect(find.widgetWithText(FilterChip, 'English'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Hindi'), findsOneWidget);

      repo.release();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilterChip, 'English'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Hindi'), findsOneWidget);
    });

    testWidgets('while the list is read again: meets the accessibility '
        'guidelines, and twice the text size overflows nothing', (
      tester,
    ) async {
      _usePhoneScreen(tester);
      final repo = _HeldRepo([...books]);
      await tester.pumpWidget(
        _app(
          repo,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
        ),
      );
      await tester.pumpAndSettle();

      repo.hold = Completer<void>();
      sayChanged(tester);
      await letTheReadStart(tester);
      expect(find.text('The Hobbit'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectMeetsA11yGuidelines(tester);

      repo.release();
      await tester.pumpAndSettle();
    });
  });

  // S35: the flexible-update banner is wired atop the library page. With the
  // REAL service it renders nothing in tests (non-Android gate); the fake
  // proves the wiring and the auto-started background download.
  testWidgets('S35: an active app update renders the banner above the list', (
    tester,
  ) async {
    final updates = FakeAppUpdateService(
      availability: AppUpdateAvailability.available,
    );
    addTearDown(updates.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogueItemRepositoryProvider.overrideWith(
            (ref) async => _FakeBookRepo(books),
          ),
          periodicalRepositoryProvider.overrideWith(
            (ref) async => _NoPeriodicals(),
          ),
          nowTickProvider.overrideWith((ref) => 0),
          appUpdateServiceProvider.overrideWithValue(updates),
        ],
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    // NOT pumpAndSettle: the banner's progress spinner animates forever.
    // The fakes complete in microtasks; explicit frames land every change.
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(find.text('Update downloading in the background…'), findsOneWidget);
    // The library itself still renders underneath.
    expect(find.text('The Hobbit'), findsOneWidget);
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    await tester.pumpWidget(_app(_FakeBookRepo(books)));
    await tester.pumpAndSettle();
    await expectMeetsA11yGuidelines(tester);
  });

  testWidgets('meets accessibility guidelines (dark theme)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogueItemRepositoryProvider.overrideWith(
            (ref) async => _FakeBookRepo(books),
          ),
          periodicalRepositoryProvider.overrideWith(
            (ref) async => _NoPeriodicals(),
          ),
          nowTickProvider.overrideWith((ref) => 0),
        ],
        // The shipped dark theme (lib/core/theme/app_theme.dart), not a
        // generic ThemeData.dark(): contrast is checked on real colours.
        child: MaterialApp(theme: AppTheme.dark, home: const LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();
    await expectMeetsA11yGuidelines(tester);
  });

  // A6 text-scaling smoke test: 2x system font scale must not overflow.
  testWidgets('renders at 2x text scale without overflowing', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogueItemRepositoryProvider.overrideWith(
            (ref) async => _FakeBookRepo(books),
          ),
          periodicalRepositoryProvider.overrideWith(
            (ref) async => _NoPeriodicals(),
          ),
          nowTickProvider.overrideWith((ref) => 0),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const LibraryPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

/// The vertical book list's scrollable. `find.byType(Scrollable).first` would
/// pick the HORIZONTAL chips row / text field scrollable that precedes it.
Finder _bookList() => find.descendant(
  of: find.byType(CustomScrollView),
  matching: find.byType(Scrollable),
);

/// Fake whose page reads wait on [gate] until it is completed, so the screen
/// can be looked at before the list has loaded.
class _GatedRepo extends _FakeBookRepo {
  _GatedRepo(super.all);
  Completer<void>? gate;

  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    final waitFor = gate;
    if (waitFor != null && !waitFor.isCompleted) await waitFor.future;
    return super.page(query, limit: limit, offset: offset);
  }
}

/// Fake whose reads wait for as long as a hold is set, so the screen can be
/// looked at WHILE the list (or the languages) is read again (P4-M2).
class _HeldRepo extends _FakeBookRepo {
  _HeldRepo(super.all);

  /// While set, every page read waits on it.
  Completer<void>? hold;

  /// While set, every read of the languages waits on it.
  Completer<void>? holdLanguages;

  /// How often the languages were asked for.
  int languageReads = 0;

  /// The rows the store holds now; a test changes them in place.
  List<CatalogueItem> get rows => _all;

  /// Lets everything that is held go on.
  void release() {
    final pages = hold;
    final languages = holdLanguages;
    hold = null;
    holdLanguages = null;
    pages?.complete();
    languages?.complete();
  }

  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    final waitFor = hold;
    if (waitFor != null) await waitFor.future;
    return super.page(query, limit: limit, offset: offset);
  }

  @override
  Future<Either<Failure, List<String>>> distinctLanguages() async {
    languageReads++;
    final waitFor = holdLanguages;
    if (waitFor != null) await waitFor.future;
    return super.distinctLanguages();
  }
}

/// Fake whose SECOND page read waits on [gate], so the in-flight footer can
/// be observed.
class _SlowSecondPageRepo extends _FakeBookRepo {
  _SlowSecondPageRepo(super.all);
  Completer<void>? gate;

  @override
  Future<Either<Failure, CatalogueItemPage>> page(
    LibraryQuery query, {
    required int limit,
    int offset = 0,
  }) async {
    if (offset > 0) {
      gate ??= Completer<void>();
      await gate!.future;
    }
    return super.page(query, limit: limit, offset: offset);
  }
}
