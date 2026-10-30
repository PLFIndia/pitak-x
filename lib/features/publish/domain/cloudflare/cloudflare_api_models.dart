/// Typed inputs and results for the Cloudflare API ports (publish domain, pure
/// Dart; Cloudflare plan E.1/Part G).
///
/// These objects contain only validated domain values and fixed protocol
/// choices. JSON, HTTP and IO belong to the infrastructure adapters. Upload
/// and completion JWTs are bearer secrets: their wrappers expose values only
/// through scoped callbacks and always redact `toString()`.
library;

import 'dart:async';

import 'package:pitaka/core/text/safe_display_text.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_html_routing.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_subdomain.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_worker_name.dart';
import 'package:pitaka/features/publish/domain/site/site_path.dart';

/// The token state reported by Cloudflare's verification endpoint.
final class CloudflareTokenVerification {
  /// Creates a verification result.
  const CloudflareTokenVerification({
    required this.status,
    required this.expiresOn,
  });

  /// Cloudflare's status value. Only `active` permits setup to continue.
  final String status;

  /// Optional token expiry to display to the user.
  final DateTime? expiresOn;

  /// True only for Cloudflare's exact `active` status.
  bool get isActive => status == 'active';
}

/// One Cloudflare account that can be selected during setup.
final class CloudflareAccount {
  /// Creates an account summary.
  const CloudflareAccount({required this.id, required this.name});

  /// Longest account name this app stores or renders.
  static const int maxNameLength = 256;

  /// The validated account identity used in API paths.
  final CloudflareAccountId id;

  /// The account name exactly as Cloudflare returned it.
  final String name;

  /// Whether [value] is a bounded, control-free account name.
  ///
  /// Null is valid on purpose: "no name" is a real, storable state. The
  /// forbidden-character rule is SHARED with library names (fix-plan L14), so
  /// bidi/zero-width/C1/separator characters cannot reach the picker through
  /// either path.
  static bool isValidName(String? value) {
    if (value == null) return true;
    if (value.isEmpty || value.length > maxNameLength) return false;
    return SafeDisplayText.isSafe(value);
  }

  /// The label this app may render in the picker.
  ///
  /// A hostile or unrenderable name is replaced by "Account …{last 4 of id}"
  /// instead of failing the entire discovery, so one bad name can never hide
  /// the other accounts or the manual Account ID path (fix-plan L14).
  String get displayName => name.isNotEmpty && isValidName(name)
      ? name
      : 'Account …${id.value.substring(id.value.length - 4)}';

  /// The name to persist, or null when only [displayName]'s fallback applies.
  ///
  /// A replacement label is a UI convenience, not a fact Cloudflare published,
  /// so it is never stored as the account name.
  String? get storageName => name.isNotEmpty && isValidName(name) ? name : null;
}

/// A bounded account listing.
final class CloudflareAccountListing {
  /// Creates a listing and defensively copies [accounts].
  CloudflareAccountListing({
    required List<CloudflareAccount> accounts,
    required this.truncated,
  }) : accounts = List.unmodifiable(accounts);

  /// Accounts read within the four-page budget.
  final List<CloudflareAccount> accounts;

  /// True when four full pages were read and more accounts may exist.
  ///
  /// A truncated listing requires the manual Account ID path; it must not be
  /// presented as a complete picker.
  final bool truncated;
}

/// A bounded listing of Worker names in one account (fix-plan RH2).
final class CloudflareWorkerNameListing {
  /// Creates a listing and defensively copies [names].
  CloudflareWorkerNameListing({
    required List<CloudflareWorkerName> names,
    required this.truncated,
  }) : names = List.unmodifiable(names);

  /// Each script's `id`, which IS the Worker name. No other field is read.
  final List<CloudflareWorkerName> names;

  /// True when the page budget was exhausted and more Workers may exist.
  ///
  /// A truncated listing proves nothing about a missing name, so the caller
  /// must fail closed rather than assume the name is free.
  final bool truncated;
}

/// What Cloudflare reports about a candidate account subdomain.
enum CloudflareSubdomainAvailability {
  /// The candidate can be used.
  available,

  /// The candidate is already in use.
  taken,

  /// The response did not establish either availability outcome.
  unknown,
}

/// The checked candidate and its availability outcome.
final class CloudflareSubdomainCheckResult {
  /// Creates an availability result.
  const CloudflareSubdomainCheckResult({
    required this.candidate,
    required this.availability,
  });

  /// The exact candidate that was checked.
  final CloudflareSubdomain candidate;

  /// The outcome, which remains [CloudflareSubdomainAvailability.unknown] when
  /// the service response cannot be interpreted safely.
  final CloudflareSubdomainAvailability availability;
}

/// The Worker's `workers.dev` route and Version URL configuration.
final class CloudflareWorkerRoute {
  /// Creates route settings.
  const CloudflareWorkerRoute({
    required this.enabled,
    required this.previewsEnabled,
  });

  /// Whether the `workers.dev` route is enabled.
  final bool enabled;

  /// Whether public Version URLs are enabled.
  ///
  /// Subsequent deploys and retirement require this to be confirmed false.
  final bool previewsEnabled;
}

/// One path and its content-addressed metadata in an upload-session manifest.
final class CloudflareAssetManifestEntry {
  /// Creates a manifest entry.
  const CloudflareAssetManifestEntry({
    required this.path,
    required this.hash,
    required this.size,
  });

  /// Safe site-relative path. Only the HTTP adapter adds Cloudflare's leading
  /// slash to the wire key.
  final SitePath path;

  /// The 32-character Cloudflare asset hash.
  final String hash;

  /// Raw (not base64-encoded) byte length.
  final int size;
}

/// Opens one artifact stream. A new invocation must return a fresh, readable
/// stream so an idempotent retry never reuses a consumed stream.
typedef CloudflareByteSource = Stream<List<int>> Function();

/// A fixed refusal for an invalid, over-chunk or wrong-sized artifact stream.
final class CloudflareByteSourceException implements Exception {
  /// Creates a refusal with no file path, byte value or platform error text.
  const CloudflareByteSourceException();

  @override
  String toString() => 'CloudflareByteSourceException(invalid artifact stream)';
}

/// The on-demand bytes for one hash requested in an asset bucket.
final class CloudflareBucketAsset {
  /// Creates a bucket asset from a reopenable byte source.
  const CloudflareBucketAsset({
    required this.hash,
    required this.type,
    required this.size,
    required this.openBytes,
  });

  /// The multipart part name and filename.
  final String hash;

  /// The exact media type Cloudflare will serve for these bytes.
  final CloudflareContentType type;

  /// Exact raw byte length, used for content length and stream validation.
  final int size;

  /// Opens the raw bytes. The publishing spool may read a file or another
  /// bounded source; the whole bucket is never retained in this object.
  final CloudflareByteSource openBytes;

  /// Opens a validated stream for hashing or multipart encoding.
  ///
  /// Every chunk is capped, byte values and the exact total size are checked,
  /// and source exceptions become one fixed refusal. Calling this again opens
  /// the source again, which is what makes a retry safe.
  Stream<List<int>> openValidated() async* {
    if (size < 0 || size > CloudflareLimits.maxFileBytes) {
      throw const CloudflareByteSourceException();
    }
    var total = 0;
    try {
      await for (final chunk in openBytes()) {
        if (chunk.length > CloudflareLimits.maxArtifactChunkBytes ||
            total + chunk.length > size) {
          throw const CloudflareByteSourceException();
        }
        for (final byte in chunk) {
          if (byte < 0 || byte > 255) {
            throw const CloudflareByteSourceException();
          }
        }
        total += chunk.length;
        yield chunk;
      }
    } on CloudflareByteSourceException {
      rethrow;
    } on Exception {
      throw const CloudflareByteSourceException();
    }
    if (total != size) throw const CloudflareByteSourceException();
  }
}

/// A completion JWT accepted by the assets-only deployment endpoint.
final class CloudflareCompletionToken {
  const CloudflareCompletionToken._(this._value);

  /// Longest JWT accepted from Cloudflare, in UTF-16 code units.
  static const int maxLength = 16 * 1024;

  final String _value;

  /// Validates a non-empty visible-ASCII JWT, or returns null.
  ///
  /// Nothing is trimmed: whitespace and control characters are rejected rather
  /// than repaired. The value is never included in a log or exception.
  static CloudflareCompletionToken? tryParse(String? raw) =>
      _hasValidJwtShape(raw) ? CloudflareCompletionToken._(raw!) : null;

  /// Runs [action] with the secret value in a narrow scope.
  R use<R>(R Function(String token) action) => action(_value);

  @override
  String toString() => 'CloudflareCompletionToken(***)';
}

/// An upload session's requested buckets and short-lived upload credential.
final class CloudflareUploadSession {
  const CloudflareUploadSession._(
    this._uploadJwt,
    this.buckets,
    this.issuedAtMillis,
  );

  final String _uploadJwt;

  /// Server-requested buckets of unique asset hashes.
  ///
  /// Both the outer list and every bucket are immutable defensive copies.
  final List<List<String>> buckets;

  /// When the adapter created this session, in epoch milliseconds.
  ///
  /// Not a secret: it only carries the one-hour upload-JWT lifetime so a
  /// bucket that could not finish inside it is refused (fix-plan H2). Null
  /// means "no time recorded" (a test double); the production adapter always
  /// stamps it.
  final int? issuedAtMillis;

  /// Validates and copies an upload session, or returns null when its JWT or
  /// bucket shape is unsafe.
  ///
  /// Every requested hash must be exactly 32 lower-case hexadecimal characters.
  /// There may be at most 20,000 requested hashes in total, and a hash may
  /// occur only once across all buckets. Empty [buckets] is the valid fully
  /// deduplicated response.
  static CloudflareUploadSession? tryCreate({
    required String? uploadJwt,
    required List<List<String>> buckets,
    int? issuedAtMillis,
  }) {
    if (!_hasValidJwtShape(uploadJwt) || !_hasValidBuckets(buckets)) {
      return null;
    }
    final copiedBuckets = <List<String>>[
      for (final bucket in buckets) List<String>.unmodifiable(bucket),
    ];
    return CloudflareUploadSession._(
      uploadJwt!,
      List<List<String>>.unmodifiable(copiedBuckets),
      issuedAtMillis,
    );
  }

  /// Runs [action] with the upload JWT in a narrow scope.
  R useUploadJwt<R>(R Function(String token) action) => action(_uploadJwt);

  /// The session JWT as a completion token only when nothing needs uploading.
  ///
  /// A non-empty bucket list must obtain its completion JWT from the final
  /// successful bucket upload instead.
  CloudflareCompletionToken? get completionTokenWhenDeduplicated =>
      buckets.isEmpty ? CloudflareCompletionToken._(_uploadJwt) : null;

  @override
  String toString() => 'CloudflareUploadSession(***)';
}

/// The two assets-only deployment configurations Pitak can write.
enum CloudflareDeploymentKind {
  /// A normal or verification-only site with real missing-file 404s.
  live(
    notFoundHandling: 'none',
    headers:
        '/*\n'
        '  Cache-Control: no-cache\n'
        '  Access-Control-Allow-Origin: *\n',
  ),

  /// A moved page with the full response-header hardening policy.
  retired(
    notFoundHandling: '404-page',
    headers:
        '/*\n'
        '  Cache-Control: no-cache\n'
        "  Content-Security-Policy: default-src 'none'; "
        "style-src 'unsafe-inline'; base-uri 'none'; "
        "form-action 'none'; frame-ancestors 'none'\n"
        '  X-Content-Type-Options: nosniff\n'
        '  Referrer-Policy: no-referrer\n',
  );

  const CloudflareDeploymentKind({
    required this.notFoundHandling,
    required this.headers,
  });

  /// Cloudflare's fixed HTML routing behavior, identical for both kinds. It
  /// comes from [CloudflareHtmlRouting] so public read-back always requests
  /// the address this setting actually serves.
  String get htmlHandling => CloudflareHtmlRouting.htmlHandling;

  /// `none` for live assets or `404-page` for a retired site.
  final String notFoundHandling;

  /// The exact `_headers` string embedded in deployment metadata.
  final String headers;
}

final RegExp _assetHashPattern = RegExp(r'^[0-9a-f]{32}$');

bool _hasValidJwtShape(String? raw) {
  if (raw == null ||
      raw.isEmpty ||
      raw.length > CloudflareCompletionToken.maxLength) {
    return false;
  }
  for (final unit in raw.codeUnits) {
    // Printable non-space ASCII only: JWTs never contain whitespace, controls,
    // or non-ASCII text. Do not trim or otherwise repair a bearer secret.
    if (unit < 0x21 || unit > 0x7e) return false;
  }
  return true;
}

bool _hasValidBuckets(List<List<String>> buckets) {
  var total = 0;
  final requested = <String>{};
  for (final bucket in buckets) {
    // Empty buckets have no completion-upload work and are not a valid server
    // bucket shape. Only an empty OUTER list means full deduplication.
    if (bucket.isEmpty) return false;
    for (final hash in bucket) {
      if (!_assetHashPattern.hasMatch(hash)) return false;
      total++;
      if (total > CloudflareLimits.maxFilesPerVersion) return false;
      if (!requested.add(hash)) return false;
    }
  }
  return true;
}
