/// Widget tests: the vault loan row resolves book titles
/// through `bookTitleProvider` — the widget itself does no repository IO —
/// and falls back to "Book #id" (fail-soft, no raw error text) when the
/// read fails or the book is missing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/theme/app_theme.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/repositories/catalogue_item_repository.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_data.dart';
import 'package:pitaka/features/vault/presentation/pages/vault_contents_page.dart';

import '../../support/a11y.dart';

/// Minimal book repo serving titles for the read model (same fake shape as
/// the N06 borrower-profile tests).
class _TitleBooks implements CatalogueItemRepository {
  _TitleBooks(this.byId, {this.failure});

  final Map<int, String> byId;

  /// When set, `getById` returns this failure instead of a book.
  final Failure? failure;

  @override
  Future<Either<Failure, CatalogueItem?>> getById(int id) async {
    final f = failure;
    if (f != null) return left(f);
    return right(
      byId.containsKey(id) ? CatalogueItem(id: id, title: byId[id]!) : null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

void main() {
  const borrower = Borrower(id: 1, name: 'Asha');
  const loan = Loan(id: 10, bookId: 7, borrowerId: 1, lentDate: 1000);
  const data = VaultData(borrowers: [borrower], loans: [loan]);

  /// Pumps the contents page with [books] behind the read model.
  Future<void> pumpPage(
    WidgetTester tester,
    CatalogueItemRepository books,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogueItemRepositoryProvider.overrideWith((ref) async => books),
          // The real tick self-reschedules a 60 s timer; stub it out so no
          // timer outlives the widget tree (same note as the N06 tests).
          nowTickProvider.overrideWith((ref) => 0),
        ],
        child: const MaterialApp(home: VaultContentsPage(data: data)),
      ),
    );
    await tester.pumpAndSettle();
    // The loan rows live in an ExpansionTile — open it first.
    await tester.tap(find.text('Asha'));
    await tester.pumpAndSettle();
  }

  testWidgets('loan row resolves the book title through the read model', (
    tester,
  ) async {
    await pumpPage(tester, _TitleBooks(const {7: 'Godaan'}));

    expect(find.text('Godaan'), findsOneWidget);
    expect(find.textContaining('Book #7'), findsNothing);
  });

  testWidgets('a missing book falls back to "Book #id"', (tester) async {
    await pumpPage(tester, _TitleBooks(const {}));

    expect(find.text('Book #7'), findsOneWidget);
  });

  testWidgets('a failed read falls back to "Book #id" — fail-soft, no raw '
      'error text (§5)', (tester) async {
    await pumpPage(
      tester,
      _TitleBooks(const {}, failure: const StorageFailure('private-detail')),
    );

    expect(find.text('Book #7'), findsOneWidget);
    expect(find.textContaining('private-detail'), findsNothing);
  });

  testWidgets('meets accessibility guidelines', (tester) async {
    await pumpPage(tester, _TitleBooks(const {7: 'Godaan'}));
    await expectMeetsA11yGuidelines(tester);
  });

  testWidgets('meets accessibility guidelines (dark theme)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogueItemRepositoryProvider.overrideWith(
            (ref) async => _TitleBooks(const {7: 'Godaan'}),
          ),
          nowTickProvider.overrideWith((ref) => 0),
        ],
        child: MaterialApp(
          // The shipped dark theme, so contrast is checked on real colours.
          theme: AppTheme.dark,
          home: const VaultContentsPage(data: data),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Open the ExpansionTile as pumpPage does.
    await tester.tap(find.text('Asha'));
    await tester.pumpAndSettle();
    await expectMeetsA11yGuidelines(tester);
  });
}
