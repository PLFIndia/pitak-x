/// The shared "section card" used across the publish hub (presentation).
///
/// Extracted verbatim out of `publish_page.dart` (Cloudflare plan S0: split
/// publish-page widgets BEFORE Cloudflare behavior is added, so the page stays
/// a thin renderer and the 500-line ratchet never needs a new entry).
///
/// Pure presentation: a titled card with consistent padding/margins. It makes
/// no decisions and holds no state.
library;

import 'package:flutter/material.dart';

/// A card with a title and arbitrary content, styled like the publish page's
/// existing sections (Publish / Your site).
class SectionCard extends StatelessWidget {
  /// Creates the card.
  const SectionCard({required this.title, required this.child, super.key});

  /// The section heading.
  final String title;

  /// The section body.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
