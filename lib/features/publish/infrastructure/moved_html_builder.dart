/// Builds and validates old-site moved-library pages (R27/S9).
///
/// Each schema maps to ONE frozen template ([MovedHtmlBuilder.templates]);
/// schema 1 is `assets/publish/moved.html`. Changing a template's output would
/// break every pending Retry from an older install, so a new renderer adds
/// `moved_v2.html` and bumps the schema instead (fix-plan L11).
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

  /// ONE template per renderer schema (fix-plan L11).
  ///
  /// A pending move persists the exact bytes it will upload, and Retry
  /// re-renders from the stored name and destination to authenticate them. If
  /// this build edited the schema-1 asset, every pending Retry from an older
  /// install would fail validation and the user could not finish the move.
  /// A future renderer therefore adds its own file and schema; it never
  /// touches an existing entry. `test/features/publish/moved_page_freeze_test.dart`
  /// pins both the asset and one rendering.
  static const Map<int, String> templates = {1: 'assets/publish/moved.html'};

  /// Loads the frozen template and returns substituted UTF-8 bytes.
  Future<List<int>> build() async {
    final template = await _loadTemplate(currentSchema);
    if (template == null) throw StateError('Unsupported moved-page schema');
    final rendered = render(
      schema: currentSchema,
      template: template,
      // The caller normalizes ONCE when the record is created (M9); the
      // renderer below reproduces the stored name byte-for-byte.
      libraryName: normalizeLibraryName(libraryName),
      newTarget: newTarget,
    );
    if (rendered == null) throw StateError('Unsupported moved-page schema');
    return rendered;
  }

  /// Loads the asset for [schema], or null when the schema has no template.
  ///
  /// `rootBundle` throws `FlutterError`, which is not an `Exception`, so a
  /// missing or unreadable asset fails closed as null rather than escaping as a
  /// crash (AGENTS §5).
  static Future<String?> _loadTemplate(int schema) async {
    final asset = templates[schema];
    if (asset == null) return null;
    try {
      return await rootBundle.loadString(asset);
    } on Object {
      return null;
    }
  }

  /// Normalizes the one name persisted with a pending retirement descriptor.
  static String normalizeLibraryName(String value) =>
      normalizeMovedLibraryName(value);

  /// Synchronous, versioned rendering separated from asynchronous asset IO.
  ///
  /// [libraryName] is the name exactly as stored in the pending record: it was
  /// normalized once when that record was created (M9). Normalizing here would
  /// make a Retry re-render bytes that differ from the persisted document if
  /// the normalizer ever changed. Unknown schemas return null rather than
  /// rendering different bytes.
  static List<int>? render({
    required int schema,
    required String template,
    required String libraryName,
    required PublishTarget newTarget,
  }) {
    if (schema != 1) return null;
    final name = _escapeHtml(libraryName);
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
    final template = await _loadTemplate(descriptor.movedPageSchema);
    // An unknown schema has no frozen renderer, so nothing can be reproduced.
    if (template == null) return false;
    final expected = render(
      schema: descriptor.movedPageSchema,
      template: template,
      libraryName: descriptor.libraryName,
      newTarget: pending.newTarget,
    );
    return expected != null &&
        _sameBytes(expected, descriptor.indexHtml) &&
        _sameBytes(expected, descriptor.notFoundHtml);
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
