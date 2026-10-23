/// Placeholder for the "Add other item" form (plan S17) — the LAST remaining
/// caller (S15 built the series pages, S16 the series and issue forms).
///
/// Why a placeholder at all (beginner note): the S14 add sheet needed a
/// destination to push before the forms existed — a named placeholder keeps
/// the navigation real (and testable) without pretending the form exists.
/// S17 replaces the last push at its call site; this page then has no caller
/// left and is deleted (AGENTS.md §2.4, no dead code).
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';

/// A bare scaffold that only names the page it stands in for.
class PlaceholderPage extends StatelessWidget {
  /// Creates a placeholder titled [pageName]. [periodical] is the series a
  /// scan preselected for the future add-issue form (carried now so the S16
  /// replacement does not change this route's call shape).
  const PlaceholderPage({required this.pageName, this.periodical, super.key});

  /// The name shown in the app bar (e.g. 'Add magazine issue').
  final String pageName;

  /// The preselected series, when the route came from a scanned ISSN.
  final Periodical? periodical;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(pageName)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '$pageName is not built yet.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
