/// "**Copies:** 2 · 1 out" — how many copies the library owns and, while the
/// vault is unlocked, how many of them are out on loan.
///
/// Shared by the library list row (plain text on the bottom line) and the
/// grid card (inside a pill on the cover) so both say it the same way.
///
/// Why words instead of the old "×2" (beginner note): "×2" said nothing about
/// loans, and a bare "2(1)" would be ambiguous (one out, or one left?).
/// "1 out" uses the same red as the Not-available shelf line, so red keeps
/// one meaning everywhere: on loan. Screen readers hear "2 copies, 1 on
/// loan" instead of symbols.
///
/// The out count is whatever the vault says. It is shown even if it is
/// larger than the copy count — that is a data problem worth seeing, not one
/// to hide.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/core/theme/availability_colors.dart';

/// The copies text, or nothing for a single-copy item.
class CopiesLabel extends StatelessWidget {
  /// Creates the label for [copyCount] copies with [copiesOut] on loan.
  const CopiesLabel({
    required this.copyCount,
    required this.copiesOut,
    required this.style,
    required this.color,
    super.key,
  });

  /// Copies the library owns.
  final int copyCount;

  /// Active loans for this item; 0 when none or when the vault is locked
  /// (unknown is shown the same as none — nothing is guessed).
  final int copiesOut;

  /// Base text style.
  final TextStyle? style;

  /// Colour of "Copies: N" (the "M out" part is always the Not-available red).
  final Color color;

  /// Only items with more than one copy show the label (unchanged rule from
  /// the old "×N"): for a single copy the shelf line already says it all.
  static bool isVisibleFor(int copyCount) => copyCount > 1;

  /// What screen readers hear, e.g. "2 copies, 1 on loan".
  static String semanticLabelFor(int copyCount, int copiesOut) => copiesOut > 0
      ? '$copyCount copies, $copiesOut on loan'
      : '$copyCount copies';

  @override
  Widget build(BuildContext context) {
    if (!isVisibleFor(copyCount)) return const SizedBox.shrink();
    final red = AvailabilityColors.unavailableForeground(
      Theme.of(context).brightness,
    );
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(
            text: 'Copies: ',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: '$copyCount'),
          if (copiesOut > 0) ...[
            const TextSpan(text: ' · '),
            TextSpan(
              text: '$copiesOut out',
              style: TextStyle(color: red, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
      style: style?.copyWith(color: color) ?? TextStyle(color: color),
      semanticsLabel: semanticLabelFor(copyCount, copiesOut),
    );
  }
}
