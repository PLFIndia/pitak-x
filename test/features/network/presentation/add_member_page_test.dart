import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/network/application/network_controller.dart';
import 'package:pitaka/features/network/domain/descriptor_fetch_result.dart';
import 'package:pitaka/features/network/domain/entities/library_descriptor.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/usecases/add_member_use_case.dart';
import 'package:pitaka/features/network/domain/value_objects/library_card_payload.dart';
import 'package:pitaka/features/network/presentation/pages/add_member_page.dart';

import '../../../support/a11y.dart';

/// Flow tests for the add-member screen (libNetwork.md S3): the scan seam
/// feeds payloads the real `QrScanPage` decision would accept/reject, and
/// the REAL `AddMemberUseCase` runs over an in-memory repository — so these
/// cover page + use case wiring together.
void main() {
  const fp = 'adb28b53d57009ce04d4e0b28563ebcd395375c0d719fd53986908233687f664';
  const fpOther =
      '22c2231357479c9a7b9d2d98ffc544ef97fce94c974a3a6835cceb4352139f1e';
  const site = 'https://member.github.io/lib/';
  final cardPayload = LibraryCardPayload.encode(
    LibraryCard.tryCreate(
      siteUrl: site,
      fingerprint: fp,
      name: 'Member Library',
    )!,
  );

  /// Fake scanner: one button per payload, feeding the page's decision.
  Widget Function(void Function(String)) fakeScanner(List<String> payloads) =>
      (onText) => Column(
        children: [
          for (final (i, payload) in payloads.indexed)
            ElevatedButton(
              onPressed: () => onText(payload),
              child: Text('emit-$i'),
            ),
        ],
      );

  /// Pushes AddMemberPage over a result-capturing button; returns the value
  /// it popped with (or 'OPEN' while the page is still up).
  Future<Object?> pumpAndScan(
    WidgetTester tester, {
    required _FakeRepo repo,
    required DescriptorFetchResult fetch,
    required List<String> payloads,
    String? tapAfterScan,
  }) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Object? popped = 'OPEN';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          addMemberUseCaseProvider.overrideWith(
            (ref) async => AddMemberUseCase(
              repository: repo,
              fetchDescriptor: (_) async => fetch,
              clock: () => 1000,
            ),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) =>
                          AddMemberPage(scanner: fakeScanner(payloads)),
                    ),
                  );
                },
                child: const Text('open-add-member'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-add-member'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan a library card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('emit-0'));
    await tester.pumpAndSettle();
    if (tapAfterScan != null) {
      await tester.tap(find.text(tapAfterScan));
      await tester.pumpAndSettle();
    }
    return popped;
  }

  testWidgets('a valid card adds the member and reports verification', (
    tester,
  ) async {
    await pumpAndScan(
      tester,
      repo: _FakeRepo(),
      fetch: const DescriptorFetched(
        LibraryDescriptor(
          fingerprint: fp,
          name: 'Member Library',
          siteUrl: site,
          updatedAt: 1,
        ),
      ),
      payloads: [cardPayload],
    );
    // The success panel shows the outcome …
    expect(find.text('Added Member Library'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    // … and Done simply returns to the caller.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('open-add-member'), findsOneWidget);
  });

  testWidgets('M10: the network window is re-read the moment a member is '
      'saved — before Done, so the system back button cannot leave the '
      'list stale', (tester) async {
    final repo = _FakeRepo();
    final windowReads = <int>[];
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkRepositoryProvider.overrideWith((ref) async => repo),
          addMemberUseCaseProvider.overrideWith(
            (ref) async => AddMemberUseCase(
              repository: repo,
              fetchDescriptor: (_) async =>
                  const DescriptorRefused(DescriptorRefusal.transport),
              clock: () => 1000,
            ),
          ),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              // Stand-in for the Libraries tab: watch the window and record
              // every row count it delivers.
              final window = ref.watch(networkControllerProvider);
              final rows = window.valueOrNull?.rows.length;
              if (rows != null) windowReads.add(rows);
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          AddMemberPage(scanner: fakeScanner([cardPayload])),
                    ),
                  ),
                  child: Text('rows=$rows'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('rows=0'), findsOneWidget);

    await tester.tap(find.text('rows=0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan a library card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('emit-0'));
    await tester.pumpAndSettle();
    expect(find.text('Added Member Library'), findsOneWidget);

    // Leave via the system back button — NOT Done.
    await tester.pageBack();
    await tester.pumpAndSettle();

    // The list already knows about the new member.
    expect(find.text('rows=1'), findsOneWidget);
    expect(windowReads.last, 1);
  });

  testWidgets('offline: the member is added, visibly unverified', (
    tester,
  ) async {
    await pumpAndScan(
      tester,
      repo: _FakeRepo(),
      fetch: const DescriptorRefused(DescriptorRefusal.transport),
      payloads: [cardPayload],
    );
    expect(find.text('Added Member Library'), findsOneWidget);
    expect(find.text('Unverified'), findsOneWidget);
    expect(find.textContaining('Not verified yet'), findsOneWidget);
  });

  testWidgets('D2: a pairing code shows the plain-words rejection', (
    tester,
  ) async {
    final repo = _FakeRepo();
    await pumpAndScan(
      tester,
      repo: repo,
      fetch: const DescriptorRefused(DescriptorRefusal.httpStatus),
      payloads: ['pitaka-lib:0123456789abcdef'],
    );
    // The scanner itself refuses with the D2 message and stays open; nothing
    // was added.
    expect(find.textContaining("That's a pairing code"), findsOneWidget);
    expect(find.text('Added Member Library'), findsNothing);
    expect(repo.rows, isEmpty);
  });

  testWidgets('a contradicting fingerprint shows the mismatch message', (
    tester,
  ) async {
    final repo = _FakeRepo(
      seed: [
        const NetworkLibrary(
          id: 1,
          siteUrl: site,
          name: 'Existing',
          fingerprint: fpOther,
        ),
      ],
    );
    await pumpAndScan(
      tester,
      repo: repo,
      fetch: const DescriptorRefused(DescriptorRefusal.httpStatus),
      payloads: [cardPayload],
    );
    expect(find.text(AddMemberUseCase.identityMismatchMessage), findsOneWidget);
    expect(find.textContaining('Added'), findsNothing);
    expect(repo.rows.single.isMember, isFalse);
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          addMemberUseCaseProvider.overrideWith(
            (ref) async => AddMemberUseCase(
              repository: _FakeRepo(),
              fetchDescriptor: (_) async =>
                  const DescriptorRefused(DescriptorRefusal.transport),
              clock: () => 1,
            ),
          ),
        ],
        child: const MaterialApp(home: AddMemberPage()),
      ),
    );
    await tester.pumpAndSettle();
    await expectMeetsA11yGuidelines(tester);
  });
}

class _FakeRepo implements NetworkRepository {
  _FakeRepo({List<NetworkLibrary> seed = const []}) : rows = [...seed];

  final List<NetworkLibrary> rows;
  int _nextId = 1;

  @override
  Future<List<NetworkLibrary>> loadAll() async => List.of(rows);

  @override
  Future<Either<Failure, NetworkLibrary>> upsertBySiteUrl(
    NetworkLibrary row,
  ) async {
    rows.removeWhere((r) => r.siteUrl == row.siteUrl);
    final saved = row.copyWith(id: _nextId++);
    rows.add(saved);
    return right(saved);
  }

  @override
  Future<int> count() async => rows.length;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository operation');
}
