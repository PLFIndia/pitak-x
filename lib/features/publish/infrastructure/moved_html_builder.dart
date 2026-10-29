/// Builds and validates old-site moved-library pages (R27/S9).
///
/// Schema 1 uses `assets/publish/moved.html`. That asset is a FROZEN renderer:
/// changing its output requires a new schema and renderer: pending retries
/// must reproduce their persisted bytes exactly after an app upgrade.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/site/move_plan.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';

/// Assembles and semantically validates moved-library HTML bytes.
final class MovedHtmlBuilder {
  /// Creates the schema-1 builder for [libraryName] and [newTarget].
  const MovedHtmlBuilder({required this.libraryName, required this.newTarget});

  /// Display name shown in the page title and heading.
  final String libraryName;

  /// The exact new publish destination.
  final PublishTarget newTarget;

  /// Current renderer schema, shared with the pending journal.
  static const int currentSchema = RetirementDescriptor.currentMovedPageSchema;

  /// Loads the frozen template and returns substituted UTF-8 bytes.
  Future<List<int>> build() async {
    final template = await rootBundle.loadString('assets/publish/moved.html');
    final rendered = render(
      schema: currentSchema,
      template: template,
      libraryName: libraryName,
      newTarget: newTarget,
    );
    if (rendered == null) throw StateError('Unsupported moved-page schema');
    return rendered;
  }

  /// Normalizes the one name persisted with a pending retirement descriptor.
  static String normalizeLibraryName(String value) =>
      normalizeMovedLibraryName(value);

  /// Synchronous, versioned rendering separated from asynchronous asset IO.
  /// Unknown schemas return null rather than rendering different bytes.
  static List<int>? render({
    required int schema,
    required String template,
    required String libraryName,
    required PublishTarget newTarget,
  }) {
    if (schema != 1) return null;
    final name = _escapeHtml(normalizeLibraryName(libraryName));
    final address = _escapeHtml(newTarget.siteUrl);
    final html = template
        .replaceAll('{{LIBRARY_NAME}}', name)
        .replaceAll('{{NEW_SITE_URL}}', address);
    return utf8.encode(html);
  }

  /// Authenticates persisted documents before retirement or retry adoption.
  /// Preferences are not trusted to authorize arbitrary HTML: both documents
  /// must equal the versioned rendering of the persisted name and destination.
  static Future<bool> validatePending(PendingMove pending) async {
    final descriptor = pending.retirement;
    if (descriptor.movedPageSchema != 1) return false;
    try {
      final template = await rootBundle.loadString('assets/publish/moved.html');
      final expected = render(
        schema: descriptor.movedPageSchema,
        template: template,
        libraryName: descriptor.libraryName,
        newTarget: pending.newTarget,
      );
      return expected != null &&
          _sameBytes(expected, descriptor.indexHtml) &&
          _sameBytes(expected, descriptor.notFoundHtml);
    } on Object {
      // `rootBundle` throws FlutterError, which is not an Exception.
      return false;
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Escapes text and quoted-attribute contexts.
  static String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
