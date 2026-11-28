/// What the Export page says when a run has ended (presentation layer):
/// one sentence, drawn by how the run ended.
///
/// WHY A WIDGET OF ITS OWN (beginner note): three things belong to this
/// one sentence, and here they are in one place.
///
///  * HOW IT LOOKS (decision D193): a success in the theme's main colour,
///    a window the user left in plain text, a failure in the error colour,
///    as on the Create backup page. Before, every sentence looked the same,
///    and one that tells the user to delete an unfinished file looked like
///    "Saved as NAME.".
///  * IT IS READ OUT (decision D190): the sentence is a live region, so a
///    screen reader says it when it appears.
///  * IT IS SCROLLED TO (decision D177): the page brings the sentence into
///    view when a run ends, and finds it by the key it is given.
///
/// It also keeps the page under its size limit.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/core/widgets/live_region.dart';
import 'package:pitaka/features/import_export/application/export_controller.dart';
import 'package:pitaka/features/import_export/presentation/export_messages.dart';

/// The sentence for [result], the end of the last export.
class ExportStatusLine extends StatelessWidget {
  /// Creates the line.
  const ExportStatusLine({
    required this.result,
    required this.sentenceKey,
    super.key,
  });

  /// How the run ended, and under which name a file was saved or shared.
  final ExportRunResult result;

  /// Key of the sentence itself, for the page to scroll to.
  final GlobalKey sentenceKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plain = theme.textTheme.bodyMedium;
    // The colour is not the only sign: every sentence says in words what
    // happened. The colour is for the eye that only glances.
    final style = switch (exportEndKind(result.outcome)) {
      ExportEndKind.success => plain?.copyWith(
        color: theme.colorScheme.primary,
      ),
      ExportEndKind.notice => plain,
      ExportEndKind.failure => plain?.copyWith(color: theme.colorScheme.error),
    };
    return LiveRegion(
      child: Text(exportStatusMessage(result), key: sentenceKey, style: style),
    );
  }
}
