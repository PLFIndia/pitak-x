import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/widgets/qr_view.dart';
import 'package:pitaka/features/network/domain/entities/network_library.dart';
import 'package:pitaka/features/network/domain/repositories/network_repository.dart';
import 'package:pitaka/features/network/domain/value_objects/library_card_payload.dart';
import 'package:pitaka/features/network/presentation/pages/network_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/a11y.dart';

/// Page tests for the Library network screen (libNetwork.md S3): the
/// Libraries list over the real provider chain (fake repository at the
/// edge), removal, the My-card tab in both states, and the a11y trio.
void main() {
  const rawId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const fp = 'adb28b53d57009ce04d4e0b28563ebcd395375c0d719fd53986908233687f664';

  Future<void> pumpPage(
    WidgetTester tester, {
    List<NetworkLibrary> rows = const [],
    String? publishedUrl,
  }) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'library_id': rawId});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkRepositoryProvider.overrideWith(
            (ref) async => _FakeRepo(rows),
          ),
          publishedSiteUrlProvider.overrideWith((ref) async => publishedUrl),
        ],
        child: const MaterialApp(home: NetworkPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty state explains how libraries get added', (tester) async {
    await pumpPage(tester);
    // The empty state is ONE text with both sentences (line-broken inside).
    expect(find.textContaining('No libraries saved yet.'), findsOneWidget);
    expect(find.textContaining('Add a member by scanning'), findsOneWidget);
    expect(
      find.widgetWithText(FloatingActionButton, 'Add member'),
      findsOneWidget,
    );
  });

  testWidgets('rows render with their badges', (tester) async {
    await pumpPage(
      tester,
      rows: [
        const NetworkLibrary(
          id: 1,
          siteUrl: 'https://m.github.io/x/',
          name: 'Member Library',
          fingerprint: fp,
          source: NetworkSource.card,
          isMember: true,
          memberVerified: true,
        ),
        const NetworkLibrary(
          id: 2,
          siteUrl: 'https://u.github.io/y/',
          name: 'Unverified One',
          source: NetworkSource.card,
          isMember: true,
        ),
        const NetworkLibrary(
          id: 3,
          siteUrl: 'https://c.github.io/z/',
          name: 'Clashing',
          fingerprint: fp,
          fetchStatus: FetchStatus.identityConflict,
        ),
      ],
    );
    expect(find.text('Member Library'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Unverified'), findsOneWidget);
    expect(find.text('Identity conflict'), findsOneWidget);
    expect(find.text('https://m.github.io/x/'), findsOneWidget);
  });

  testWidgets('removing a row asks the repository and refreshes the list', (
    tester,
  ) async {
    await pumpPage(
      tester,
      rows: [
        const NetworkLibrary(
          id: 1,
          siteUrl: 'https://m.github.io/x/',
          name: 'Doomed',
        ),
      ],
    );
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Removed.'), findsOneWidget);
    expect(find.text('Doomed'), findsNothing);
  });

  testWidgets('My card tab: unpublished explains what to do first', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(find.text('My card'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('appears once you have published'),
      findsOneWidget,
    );
    expect(find.byType(QrView), findsNothing);
  });

  testWidgets('My card tab: published shows the card QR and its payload', (
    tester,
  ) async {
    await pumpPage(tester, publishedUrl: 'https://me.github.io/lib/');
    await tester.tap(find.text('My card'));
    await tester.pumpAndSettle();

    final qr = tester.widget<QrView>(find.byType(QrView));
    final card = LibraryCardPayload.parse(qr.data);
    expect(card, isNotNull);
    expect(card!.siteUrl, 'https://me.github.io/lib/');
    expect(card.fingerprint, isNot(rawId)); // D3, again at the UI edge
    expect(qr.data, isNot(contains(rawId)));
    expect(find.text('https://me.github.io/lib/'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Share as image'), findsOneWidget);
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    await pumpPage(
      tester,
      rows: [
        const NetworkLibrary(
          id: 1,
          siteUrl: 'https://m.github.io/x/',
          name: 'Member Library',
          source: NetworkSource.card,
          isMember: true,
        ),
      ],
    );
    await expectMeetsA11yGuidelines(tester);
  });
}

/// In-memory repository fake; removals really remove so the invalidation
/// path re-reads a shorter list.
class _FakeRepo implements NetworkRepository {
  _FakeRepo(List<NetworkLibrary> seed) : rows = [...seed];

  final List<NetworkLibrary> rows;

  @override
  Future<List<NetworkLibrary>> loadAll() async => List.of(rows);

  @override
  Future<Either<Failure, Unit>> removeById(int id) async {
    rows.removeWhere((r) => r.id == id);
    return right(unit);
  }

  @override
  Future<int> count() async => rows.length;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository operation');
}
