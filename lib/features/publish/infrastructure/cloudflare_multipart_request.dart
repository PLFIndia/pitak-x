/// Fresh multipart requests for Cloudflare asset upload and deployment.
///
/// `package:http` owns the boundary and streaming wire format. This file only
/// validates Pitak's content-addressed inputs and maps them to the two shapes
/// confirmed by the S2 trial: base64 asset parts and a metadata-only deploy.
/// A new request is built on every call so a retry never reuses a finalized
/// request or a single-subscription part stream.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_asset_hash.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/infrastructure/cloudflare_json.dart';

/// Builds a `POST` bucket upload for [assets] at [url].
///
/// Call [validateCloudflareBucketAssets] before opening the network operation.
/// The request retains only stream objects: raw chunks are validated on demand,
/// base64 text and UTF-8 bytes are produced chunk by chunk, and package:http
/// streams one part at a time instead of retaining a whole encoded bucket. The
/// transmitted stream is hashed again on every attempt before it can complete.
http.MultipartRequest cloudflareBucketMultipartRequest({
  required Uri url,
  required List<CloudflareBucketAsset> assets,
}) {
  _validateBucketAssets(assets);
  final request = http.MultipartRequest('POST', url);
  for (final asset in assets) {
    final transmitted = CloudflareAssetHash.verifyStream(
      bytes: asset.openValidated(),
      extension: asset.type.extension,
      expectedHash: asset.hash,
    );
    final encoded = transmitted
        .transform(base64.encoder)
        .map((chunk) {
          if (chunk.length > CloudflareLimits.maxBase64ChunkBytes) {
            throw const CloudflareJsonException();
          }
          return chunk;
        })
        .transform(utf8.encoder);
    final encodedLength = 4 * ((asset.size + 2) ~/ 3);
    request.files.add(
      http.MultipartFile(
        asset.hash,
        encoded,
        encodedLength,
        filename: asset.hash,
        contentType: MediaType.parse(asset.type.header),
      ),
    );
  }
  return request;
}

/// Validates hash integrity by streaming each asset once before any upload.
///
/// Hashing is serial and bounded just like uploading. No whole-file base64
/// string or complete raw bucket is created, and every error is redacted.
Future<void> validateCloudflareBucketAssets(
  List<CloudflareBucketAsset> assets,
) async {
  _validateBucketAssets(assets);
  for (final asset in assets) {
    final String actual;
    try {
      actual = await CloudflareAssetHash.fromStream(
        asset.openValidated(),
        asset.type.extension,
      );
    } on CloudflareByteSourceException {
      throw const CloudflareJsonException();
    }
    if (actual != asset.hash) throw const CloudflareJsonException();
  }
}

/// Builds a `PUT` metadata-only deployment at [url].
///
/// Exactly one `metadata` field is emitted and there are no file parts. The
/// completion JWT is read only inside [CloudflareCompletionToken.use] and is
/// never included in an exception or diagnostic.
http.MultipartRequest cloudflareDeployMultipartRequest({
  required Uri url,
  required CloudflareCompletionToken completion,
  required CloudflareDeploymentKind kind,
}) {
  final metadata = completion.use(
    (jwt) => jsonEncode({
      'assets': {
        'jwt': jwt,
        'config': {
          'html_handling': kind.htmlHandling,
          'not_found_handling': kind.notFoundHandling,
          '_headers': kind.headers,
        },
      },
      'compatibility_date': CloudflareLimits.compatibilityDate,
    }),
  );
  return http.MultipartRequest('PUT', url)..fields['metadata'] = metadata;
}

void _validateBucketAssets(List<CloudflareBucketAsset> assets) {
  if (assets.isEmpty || assets.length > CloudflareLimits.maxFilesPerVersion) {
    throw const CloudflareJsonException();
  }

  final hashes = <String>{};
  final hashPattern = RegExp(r'^[0-9a-f]{32}$');
  for (final asset in assets) {
    if (asset.size < 0 ||
        asset.size > CloudflareLimits.maxFileBytes ||
        !hashPattern.hasMatch(asset.hash) ||
        !hashes.add(asset.hash)) {
      throw const CloudflareJsonException();
    }
  }
}
