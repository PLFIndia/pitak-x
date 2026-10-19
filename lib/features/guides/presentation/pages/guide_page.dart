/// One "How Pitak works" guide (presentation, AGENTS.md §3.1).
///
/// Render-only: the page draws a [Guide] from the catalog top to bottom —
/// intro, "You need" chips, the sections, the "Good to know" callout — and
/// ends with one button that opens the screen the guide described. No state,
/// no providers; the only side effect is that navigation, and it goes through
/// `GuidePage.openDestination` so tests can record it instead of pushing real
/// pages.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/guides/domain/guide.dart';
import 'package:pitaka/features/guides/presentation/guide_destinations.dart';
import 'package:pitaka/features/guides/presentation/widgets/guide_section_view.dart';
import 'package:pitaka/features/guides/presentation/widgets/guide_text.dart';

/// Signature of the deep-link opener (see [openGuideDestination]).
typedef GuideDestinationOpener =
    void Function(BuildContext context, GuideDestination destination);

/// A single guide page.
class GuidePage extends StatelessWidget {
  /// Creates the page for [guide].
  ///
  /// [openDestination] defaults to the production opener; tests pass a
  /// recording function.
  const GuidePage({
    required this.guide,
    this.openDestination = openGuideDestination,
    super.key,
  });

  /// The guide to render.
  final Guide guide;

  /// Called when the bottom button is pressed.
  final GuideDestinationOpener openDestination;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(guide.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GuideText(guide.intro, style: textTheme.bodyLarge),
          if (guide.needs.isNotEmpty) ...[
            const SizedBox(height: 16),
            _NeedsRow(guide.needs),
          ],
          for (final section in guide.sections) ...[
            const SizedBox(height: 20),
            GuideSectionView(section),
          ],
          if (guide.goodToKnow.isNotEmpty) ...[
            const SizedBox(height: 24),
            _GoodToKnow(guide.goodToKnow),
          ],
          const SizedBox(height: 24),
          FilledButton(
            // 48 dp: the Material minimum tap target (the a11y gate checks
            // it), a touch taller than the mockup's 44.
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => openDestination(context, guide.destination),
            child: Text('${guide.destinationLabel} →'),
          ),
        ],
      ),
    );
  }
}

/// "You need" label + one outlined chip per prerequisite.
class _NeedsRow extends StatelessWidget {
  const _NeedsRow(this.needs);

  final List<String> needs;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('You need', style: textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final need in needs)
              Chip(
                label: Text(need),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
      ],
    );
  }
}

/// The "Good to know" callout: a secondary-container card with ≤ 3 bullets.
class _GoodToKnow extends StatelessWidget {
  const _GoodToKnow(this.bullets);

  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final body = textTheme.bodyMedium?.copyWith(
      color: scheme.onSecondaryContainer,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Good to know',
            style: textTheme.titleMedium?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < bullets.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == bullets.length - 1 ? 0 : 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•', style: body),
                  const SizedBox(width: 10),
                  Expanded(child: GuideText(bullets[i], style: body)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
