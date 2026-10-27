/// Hand-built multipart bodies for the trial (Cloudflare plan B.2/B.3).
///
/// Why not `http.MultipartRequest` (beginner note): the trial must send EXACTLY
/// what the contract says — the part NAME and FILENAME are the asset hash, the
/// part `Content-Type` becomes the served type, and the body is base64 — and it
/// must be able to say so in the report. Building the body here keeps every
/// byte visible, needs no extra package, and mirrors the shape the production
/// adapter will have to stream.
///
/// The deploy body is the metadata-only form Wrangler emits for an assets-only
/// Worker: ONE `metadata` part and no file parts. T6 exists because the API
/// reference still documents module-oriented uploads.
library;

import 'dart:convert';

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'trial_assets.dart';

/// Builds the two multipart bodies the trial needs.
abstract final class TrialMultipart {
  /// A fresh boundary. Random so a body can never contain it by accident.
  static String newBoundary() {
    final random = DateTime.now().microsecondsSinceEpoch;
    return '----pitak-trial-$random';
  }

  /// The bucket-upload body: one part per asset, named by its hash.
  static List<int> bucketBody({
    required String boundary,
    required List<TrialAsset> assets,
  }) {
    final out = <int>[];
    for (final asset in assets) {
      out
        ..addAll(
          utf8.encode(
            '--$boundary\r\n'
            'Content-Disposition: form-data; name="${asset.hash}"; '
            'filename="${asset.hash}"\r\n'
            'Content-Type: ${asset.type.header}\r\n'
            '\r\n',
          ),
        )
        ..addAll(utf8.encode(base64.encode(asset.bytes)))
        ..addAll(utf8.encode('\r\n'));
    }
    out.addAll(utf8.encode('--$boundary--\r\n'));
    return out;
  }

  /// The metadata-only deploy body.
  ///
  /// [completionJwt] is the completion token from the upload step (or the
  /// session token when every asset was already known). It is written into the
  /// body and never returned or printed.
  static List<int> deployBody({
    required String boundary,
    required String completionJwt,
    required String htmlHandling,
    required String notFoundHandling,
    required String headers,
  }) {
    final metadata = jsonEncode({
      'assets': {
        'jwt': completionJwt,
        'config': {
          'html_handling': htmlHandling,
          'not_found_handling': notFoundHandling,
          '_headers': headers,
        },
      },
      'compatibility_date': CloudflareLimits.compatibilityDate,
    });
    return [
      ...utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="metadata"\r\n'
        '\r\n'
        '$metadata\r\n'
        '--$boundary--\r\n',
      ),
    ];
  }

  /// The live site's `_headers` (R26): GitHub CORS parity, no caching.
  static const String liveHeaders =
      '/*\n'
      '  Cache-Control: no-cache\n'
      '  Access-Control-Allow-Origin: *\n';

  /// The retired site's `_headers` (R27): full CSP plus the hardening headers.
  static const String retiredHeaders =
      '/*\n'
      '  Cache-Control: no-cache\n'
      "  Content-Security-Policy: default-src 'none'; "
      "style-src 'unsafe-inline'; base-uri 'none'; "
      "form-action 'none'; frame-ancestors 'none'\n"
      '  X-Content-Type-Options: nosniff\n'
      '  Referrer-Policy: no-referrer\n';
}
