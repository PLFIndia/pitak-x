/// Renders one string of guide copy with its inline markup (presentation).
///
/// `**label**` becomes a bold span, `` `value` `` a monospace span on a
/// faint background; everything else inherits [GuideText.style]. One
/// `Text.rich`, so screen readers get the whole sentence as a single node.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/guides/domain/guide.dart';
import 'package:pitaka/features/guides/domain/guide_markup.dart';

/// A paragraph / bullet / step of guide copy.
class GuideText extends StatelessWidget {
  /// Creates the text from a markup [source].
  const GuideText(this.source, {this.style, super.key});

  /// The copy, with `**` / `` ` `` markup (see `parseGuideMarkup`).
  final String source;

  /// Base style of the plain runs; bold and code runs derive from it.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = style ?? DefaultTextStyle.of(context).style;
    final bold = base.copyWith(fontWeight: FontWeight.w600);
    final code = base.copyWith(
      fontFamily: 'monospace',
      // `monospace` is a platform alias; the fallbacks cover the usual
      // desktop/test environments so the span never falls back to a
      // proportional face.
      fontFamilyFallback: const ['Menlo', 'Courier New', 'Courier'],
      backgroundColor: scheme.surfaceContainerHighest,
    );
    return Text.rich(
      TextSpan(
        children: [
          for (final run in parseGuideMarkup(source))
            TextSpan(text: run.text, style: _styleFor(run, bold, code)),
        ],
      ),
      style: base,
    );
  }

  /// Plain runs carry no style of their own and inherit the `Text.rich` base.
  static TextStyle? _styleFor(GuideRun run, TextStyle bold, TextStyle code) {
    if (run.bold) return bold;
    if (run.code) return code;
    return null;
  }
}
