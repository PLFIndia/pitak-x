/// The ONE loop that uploads an asset session's requested buckets (B.2).
///
/// Ordinary publishing, manual-address verification, move destinations and
/// move retirements all upload buckets. Before this file each of them carried
/// its own copy of the loop, so a protocol rule had to be right four times.
/// The rule that matters most lives here now: Cloudflare acknowledges every
/// bucket except the last WITHOUT a completion token, and only the FINAL
/// bucket's response may supply the token that authorizes a deploy.
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';

/// Outcome of uploading every requested bucket.
///
/// A sealed class (a closed set of outcomes) lets each caller `switch` over
/// all three cases, so the compiler reports any case it forgets to handle.
/// API failures are not an outcome here: they still throw the redacted
/// [CloudflareApiException], which every caller already maps by stage.
sealed class CloudflareBucketUploadResult {
  const CloudflareBucketUploadResult();
}

/// Every bucket was accepted and the final one carried the completion token.
final class CloudflareBucketsUploaded extends CloudflareBucketUploadResult {
  /// Creates the success outcome.
  const CloudflareBucketsUploaded({
    required this.completion,
    required this.uploadedHashes,
  });

  /// The token for the deployment; never logged (its `toString` is redacted).
  final CloudflareCompletionToken completion;

  /// Every hash actually sent, in upload order. Empty when Cloudflare already
  /// held all bytes and the session token itself is the completion token.
  final List<String> uploadedHashes;
}

/// Cloudflare requested a hash this device has no bytes for.
///
/// Buckets before the one containing [hash] may already have been sent; no
/// later bucket was. Nothing was deployed.
final class CloudflareBucketHashMissing extends CloudflareBucketUploadResult {
  /// Creates the missing-bytes outcome.
  const CloudflareBucketHashMissing(this.hash);

  /// The requested hash with no local byte source (a public content hash).
  final String hash;
}

/// Every bucket was accepted but the final response carried no completion
/// token, so there is nothing that may be deployed. Fail closed.
final class CloudflareUploadNotConfirmed extends CloudflareBucketUploadResult {
  /// Creates the unconfirmed outcome.
  const CloudflareUploadNotConfirmed();
}

/// Uploads a session's buckets serially, in the order Cloudflare requested.
final class CloudflareBucketUploader {
  /// Creates an uploader over the deploy port.
  const CloudflareBucketUploader(this._api);

  final CloudflareDeployApi _api;

  /// Uploads every bucket in [session].
  ///
  /// [assetForHash] returns the local byte source for a requested hash, or
  /// null when this device has none. A bucket is checked completely BEFORE
  /// any of its bytes are sent. [beforeBucketUpload] runs just before each
  /// upload so callers can record that bytes may have reached Cloudflare.
  Future<CloudflareBucketUploadResult> upload({
    required CloudflareAccountId accountId,
    required CloudflareUploadSession session,
    required CloudflareBucketAsset? Function(String hash) assetForHash,
    void Function()? beforeBucketUpload,
  }) async {
    // A fully deduplicated session (no buckets) already carries the token.
    var completion = session.completionTokenWhenDeduplicated;
    final uploadedHashes = <String>[];
    for (final bucket in session.buckets) {
      final assets = <CloudflareBucketAsset>[];
      for (final hash in bucket) {
        final asset = assetForHash(hash);
        if (asset == null) return CloudflareBucketHashMissing(hash);
        assets.add(asset);
      }
      beforeBucketUpload?.call();
      // Plain assignment on purpose: each response REPLACES the previous
      // value, so after the loop only the final bucket's answer counts. An
      // early token is dropped rather than kept as a fallback.
      completion = await _api.uploadBucket(
        accountId: accountId,
        session: session,
        assets: assets,
      );
      uploadedHashes.addAll(bucket);
    }
    final token = completion;
    if (token == null) return const CloudflareUploadNotConfirmed();
    return CloudflareBucketsUploaded(
      completion: token,
      uploadedHashes: List.unmodifiable(uploadedHashes),
    );
  }
}
