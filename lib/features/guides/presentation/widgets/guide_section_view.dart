/// Renders one [GuideSection] (presentation).
///
/// The `switch` over the sealed section type is exhaustive: adding a new
/// section kind in the domain fails to compile here until it is drawn.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/guides/domain/guide.dart';
import 'package:pitaka/features/guides/presentation/widgets/guide_text.dart';

/// Heading (when the section has one) plus the section body.
class GuideSectionView extends StatelessWidget {
  /// Creates the view for [section].
  const GuideSectionView(this.section, {super.key});

  /// The block to draw.
  final GuideSection section;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (section.hasTitle) ...[
          Text(
            section.title,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
        ],
        switch (section) {
          GuideSteps(:final steps) => _NumberedList(steps),
          GuideBullets(:final bullets) => _BulletList(bullets),
          GuideParagraphs(:final paragraphs) => _Paragraphs(paragraphs),
          GuideTable(:final rows) => _PickerTable(rows),
        },
      ],
    );
  }
}

/// Numbered rows: a 26 dp primary circle with the step number, then the text.
class _NumberedList extends StatelessWidget {
  const _NumberedList(this.steps);

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: textTheme.labelMedium?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    // Optically align the first text line with the circle.
                    padding: const EdgeInsets.only(top: 3),
                    child: GuideText(steps[i], style: textTheme.bodyMedium),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Plain "•" rows.
class _BulletList extends StatelessWidget {
  const _BulletList(this.bullets);

  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < bullets.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == bullets.length - 1 ? 0 : 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•', style: textTheme.bodyMedium),
                const SizedBox(width: 10),
                Expanded(
                  child: GuideText(bullets[i], style: textTheme.bodyMedium),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Paragraphs with a small gap between them.
class _Paragraphs extends StatelessWidget {
  const _Paragraphs(this.paragraphs);

  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < paragraphs.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == paragraphs.length - 1 ? 0 : 8,
            ),
            child: GuideText(paragraphs[i], style: textTheme.bodyMedium),
          ),
      ],
    );
  }
}

/// The two-column "I want to… / Use" picker. The "Use" column carries its
/// own `**bold**` button names, so the markup — not a column style — makes
/// the label stand out while the arrow and file name stay regular.
class _PickerTable extends StatelessWidget {
  const _PickerTable(this.rows);

  final List<GuideTableRow> rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final header = textTheme.labelLarge?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    const cellPadding = EdgeInsets.symmetric(vertical: 8);
    return Table(
      columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(2)},
      border: TableBorder(
        horizontalInside: BorderSide(color: scheme.outlineVariant),
        bottom: BorderSide(color: scheme.outlineVariant),
      ),
      children: [
        TableRow(
          children: [
            Padding(
              padding: cellPadding,
              child: Text(GuideTable.wantHeader, style: header),
            ),
            Padding(
              padding: cellPadding,
              child: Text(GuideTable.useHeader, style: header),
            ),
          ],
        ),
        for (final row in rows)
          TableRow(
            children: [
              Padding(
                padding: cellPadding.copyWith(right: 12),
                child: GuideText(row.want, style: textTheme.bodyMedium),
              ),
              Padding(
                padding: cellPadding,
                child: GuideText(row.use, style: textTheme.bodyMedium),
              ),
            ],
          ),
      ],
    );
  }
}
