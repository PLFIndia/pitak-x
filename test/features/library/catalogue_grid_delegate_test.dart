/// `CatalogueGridDelegate`: the same columns as Flutter's max-cross-axis
/// delegate, cell heights from (book-shaped cover + reserved text), and —
/// end to end — the longest texts at 1.0 / 1.3 / 2.0× never overflow a card
/// nor squash its cover.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/presentation/widgets/catalogue_grid_delegate.dart';
import 'package:pitaka/features/library/presentation/widgets/catalogue_item_grid_card.dart';
import 'package:pitaka/features/periodicals/domain/repositories/periodical_repository.dart';

class _NoPeriodicals implements PeriodicalRepository {
  @override
  Future<Either<Failure, List<PeriodicalSummary>>> listAll() async =>
      right(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}

SliverConstraints _constraints(double crossAxisExtent) => SliverConstraints(
  axisDirection: AxisDirection.down,
  growthDirection: GrowthDirection.forward,
  userScrollDirection: ScrollDirection.idle,
  scrollOffset: 0,
  precedingScrollExtent: 0,
  overlap: 0,
  remainingPaintExtent: 1000,
  crossAxisExtent: crossAxisExtent,
  crossAxisDirection: AxisDirection.right,
  viewportMainAxisExtent: 1000,
  remainingCacheExtent: 1000,
  cacheOrigin: 0,
);

void main() {
  group('layout maths', () {
    const reference = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: CatalogueGridDelegate.maxCrossAxisExtent,
      crossAxisSpacing: CatalogueGridDelegate.spacing,
      mainAxisSpacing: CatalogueGridDelegate.spacing,
      mainAxisExtent: 1,
    );

    for (final width in [568.0, 600.0, 768.0, 868.0, 1248.0, 2000.0]) {
      test('columns match the Flutter SDK delegate at $width px', () {
        final ours =
            const CatalogueGridDelegate(
                  reservedTextHeight: 100,
                ).getLayout(_constraints(width))
                as SliverGridRegularTileLayout;
        final theirs =
            reference.getLayout(_constraints(width))
                as SliverGridRegularTileLayout;
        expect(ours.crossAxisCount, theirs.crossAxisCount);
        expect(ours.childCrossAxisExtent, theirs.childCrossAxisExtent);
        expect(ours.crossAxisStride, theirs.crossAxisStride);
      });
    }

    test('cell height = padding + book-shaped cover + reserved text', () {
      final layout =
          const CatalogueGridDelegate(
                reservedTextHeight: 100,
              ).getLayout(_constraints(868))
              as SliverGridRegularTileLayout;
      final coverWidth = layout.childCrossAxisExtent - 16;
      expect(
        layout.childMainAxisExtent,
        closeTo(
          16 + coverWidth / CatalogueItemGridCard.coverAspectRatio + 100,
          0.001,
        ),
      );
      expect(
        layout.mainAxisStride,
        layout.childMainAxisExtent + CatalogueGridDelegate.spacing,
      );
    });

    test('relayout only when the reserved text height changes', () {
      const a = CatalogueGridDelegate(reservedTextHeight: 100);
      expect(
        a.shouldRelayout(const CatalogueGridDelegate(reservedTextHeight: 100)),
        isFalse,
      );
      expect(
        a.shouldRelayout(const CatalogueGridDelegate(reservedTextHeight: 120)),
        isTrue,
      );
    });
  });

  group('end to end on a tablet', () {
    // Longest realistic texts: every line cap is hit.
    final longest = CatalogueItem(
      id: 1,
      title: 'The Remarkable and Extraordinarily Long History of ' * 3,
      author: 'Shiyali Ramamrita Ranganathan and Krishna Kumar ' * 3,
      location: 'Back room, second cupboard, third shelf from the top ' * 2,
      copyCount: 12,
      needsMetadata: true,
    );

    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('${scale}x text: no overflow and the cover keeps its '
          'book shape', (tester) async {
        tester.view.physicalSize = const Size(900, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              periodicalRepositoryProvider.overrideWith(
                (ref) async => _NoPeriodicals(),
              ),
              coversDirProvider.overrideWith((ref) async => '.'),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => CustomScrollView(
                    slivers: [
                      SliverGrid.builder(
                        gridDelegate: CatalogueGridDelegate(
                          reservedTextHeight:
                              CatalogueItemGridCard.reservedTextHeight(context),
                        ),
                        itemCount: 4,
                        itemBuilder: (_, _) => CatalogueItemGridCard(
                          book: longest,
                          unavailable: true,
                          copiesOut: 12,
                          onTap: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // The reservation was enough: the fail-soft cover did not shrink.
        final cover = tester.getSize(find.byType(AspectRatio).first);
        expect(
          cover.width / cover.height,
          closeTo(CatalogueItemGridCard.coverAspectRatio, 0.01),
        );
        final card = tester.getSize(find.byType(CatalogueItemGridCard).first);
        expect(cover.width, closeTo(card.width - 16, 0.5));
      });
    }
  });
}
