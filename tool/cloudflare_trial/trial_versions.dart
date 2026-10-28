/// Strict parsing and address construction for trial-only version diagnostics.
library;

import 'trial_http.dart';

/// Cloudflare version-list and Version URL rules used by T11/T15.
abstract final class TrialVersions {
  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  /// Reads `result.items`, failing closed on a failed or malformed envelope.
  ///
  /// An absent `items` field is Cloudflare's empty-list form. Every
  /// supplied item needs a full lower-case UUID; partial evidence is unsafe.
  static List<String>? idsFrom(TrialResponse response) {
    if (!response.ok || !(response.success ?? false)) return null;
    final result = response.result;
    if (result == null) return null;
    final raw = result['items'];
    if (raw == null) return const [];
    if (raw is! List) return null;
    final ids = <String>[];
    for (final entry in raw) {
      if (entry is! Map || entry['id'] is! String) return null;
      final id = entry['id'] as String;
      if (!_uuid.hasMatch(id)) return null;
      ids.add(id);
    }
    return ids;
  }

  /// Builds the documented Version URL using the UUID's first 8 characters.
  static Uri? previewUri({required String versionId, required Uri site}) {
    if (!_uuid.hasMatch(versionId)) return null;
    final prefix = versionId.substring(0, 8);
    return Uri.https('$prefix-${site.host}', '/');
  }
}
