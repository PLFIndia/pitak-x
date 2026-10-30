/// Time bounds for one Cloudflare request (fix-plan H2, decided D3).
///
/// A single "deadline" could not answer two different questions: "is this
/// connection dead?" (idle) and "has this run taken too long?" (total). This
/// value object names each phase, and the transport maps it onto
/// `TimeoutHttpClient` exactly once. Keeping the numbers in
/// [CloudflareLimits] means no adapter re-types a duration.
library;

import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_limits.dart';

/// How one Cloudflare request is bounded in each of its phases.
final class CloudflareRequestTiming {
  /// Creates a timing profile.
  const CloudflareRequestTiming({
    required this.connect,
    this.idle,
    this.responseWait,
    this.total,
    this.totalCap,
  });

  /// Upload profile for a request carrying site bytes.
  ///
  /// The total deadline is DERIVED from the request's content length once the
  /// request exists ([resolveTotal]), because `package:http` computes a
  /// multipart length from its parts. [cap] is the upload session's remaining
  /// lifetime, when known: a request may never outlive its JWT.
  const CloudflareRequestTiming.upload({Duration? cap})
    : connect = CloudflareLimits.uploadConnectTimeout,
      idle = CloudflareLimits.uploadIdleTimeout,
      responseWait = CloudflareLimits.uploadResponseWait,
      total = null,
      totalCap = cap;

  /// Ordinary API call: 30 s connect and 30 s total, no body timing.
  static const api = CloudflareRequestTiming(
    connect: CloudflareLimits.apiDeadline,
    total: CloudflareLimits.apiDeadline,
  );

  /// Metadata-only deployment: 60 s connect and 60 s total.
  ///
  /// The deploy body is metadata, not site bytes, so it needs no idle timer.
  static const deploy = CloudflareRequestTiming(
    connect: CloudflareLimits.deployDeadline,
    total: CloudflareLimits.deployDeadline,
  );

  /// How long the connection and the first pulled body chunk may take.
  final Duration connect;

  /// How long the request body may make no progress. Null outside upload mode.
  final Duration? idle;

  /// How long the response headers may take once the body has ended.
  final Duration? responseWait;

  /// Fixed whole-request limit. Null means "derive it from the body size".
  final Duration? total;

  /// Upper bound applied to a derived total (the upload session's budget).
  final Duration? totalCap;

  /// True when this profile watches request-body progress.
  bool get observesRequestBody => idle != null;

  /// The whole-request deadline for a request of [contentLength] bytes.
  ///
  /// A null length (chunked transfer) assumes the largest allowed upload, so
  /// an unknown size can never get a SHORTER bound than a known one. The
  /// result is never shorter than [connect], which keeps the client's own
  /// "total must not be shorter than the phase" invariant.
  Duration resolveTotal(int? contentLength) {
    final derived =
        total ??
        (contentLength == null
            ? CloudflareLimits.maxUploadDeadline
            : CloudflareLimits.uploadTotalDeadline(contentLength));
    final capped = totalCap == null || derived <= totalCap!
        ? derived
        : totalCap!;
    return capped < connect ? connect : capped;
  }
}
