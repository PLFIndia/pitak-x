/// The Cloudflare limits and fixed protocol constants Pitak relies on
/// (publish domain, pure Dart; Cloudflare plan B.3/B.6/R20/R21/R24).
///
/// One file, so a limit is never re-typed at a call site (beginner note: a
/// second copy of "25 MiB" is how one code path starts accepting a file the
/// other refuses). Every value here is either documented by Cloudflare or
/// pinned by the plan; the trial (S2) records the ones it confirms.
///
/// Nothing in this file performs IO — it is the numbers and the fixed strings,
/// and the adapters read them.
library;

/// Cloudflare's documented limits and the app's own bounds.
abstract final class CloudflareLimits {
  // ---- Cloudflare's documented limits (B.6) --------------------------------

  /// Files per Worker version on the free plan.
  static const int maxFilesPerVersion = 20000;

  /// Bytes per file on the free plan (25 MiB).
  static const int maxFileBytes = 25 * 1024 * 1024;

  /// Workers per account on the free plan.
  static const int maxWorkersPerAccount = 100;

  /// API requests per five minutes per user, shared with dashboard use.
  static const int apiRequestsPerFiveMinutes = 1200;

  // ---- The app's own bounds (R20–R24) --------------------------------------

  /// Hard cap on an API response body, streamed and cancelled past this.
  static const int maxApiBodyBytes = 1024 * 1024;

  /// Maximum JSON nesting depth accepted before `jsonDecode` runs.
  static const int maxJsonDepth = 16;

  /// Account-list pages read before the manual Account ID path is offered.
  static const int maxAccountPages = 4;

  /// Accounts requested per page.
  static const int accountsPerPage = 50;

  /// Cap on the public publish marker (`pitak-publish.json`).
  static const int maxMarkerBytes = 4 * 1024;

  /// Cap on a public `library.json` read-back.
  static const int maxDescriptorBytes = 64 * 1024;

  /// Cap on a public `events.json` read-back.
  static const int maxEventsBytes = 64 * 1024;

  /// Abortable total deadline for a normal API call.
  static const Duration apiDeadline = Duration(seconds: 30);

  /// Abortable total deadline for a metadata-only deployment.
  ///
  /// Deploys carry no file bytes (the assets are already uploaded), so the
  /// ordinary 60 s is enough. Uploads use the size-derived profile below
  /// (fix-plan H2).
  static const Duration deployDeadline = Duration(seconds: 60);

  // ---- Upload timing (fix-plan H2, decided D3) -----------------------------
  //
  // Two different questions used to share one 60 s number: "is this
  // connection dead?" (an idle timeout) and "has this run taken too long?"
  // (a total deadline). A 56 MB bucket needs 7.5 Mbit/s to finish in 60 s, so
  // a slow-but-healthy phone was cut off and re-sent the whole bucket from
  // byte 0. These constants answer each question separately.

  /// Longest wait for a connection before the body's first pulled chunk.
  static const Duration uploadConnectTimeout = Duration(seconds: 60);

  /// Longest silence between body chunks the network is still draining.
  static const Duration uploadIdleTimeout = Duration(seconds: 60);

  /// Slowest sustained upload the app is willing to wait for.
  ///
  /// 64 KiB/s: slower than any usable mobile link, so a trickle is stopped,
  /// while a real 3G upload (≈200 KiB/s and up) always fits.
  static const int uploadFloorBytesPerSecond = 64 * 1024;

  /// Bytes the socket and TLS layer may hold before our progress sees them.
  ///
  /// dart:io pauses the request body while the kernel send buffer is full, so
  /// after the last observed pull up to this much may still be in flight.
  static const int maxUnobservedInFlightBytes = 8 * 1024 * 1024;

  /// Longest wait for response headers after the body has been sent.
  ///
  /// The server must first receive everything still buffered
  /// ([maxUnobservedInFlightBytes]) at no less than the floor rate, then
  /// answer: 60 s + 8 MiB ÷ 64 KiB/s = 188 s.
  static const Duration uploadResponseWait = Duration(
    milliseconds:
        60 * 1000 +
        (maxUnobservedInFlightBytes * 1000) ~/ uploadFloorBytesPerSecond,
  );

  /// Hard ceiling for one upload request, however large it is.
  static const Duration maxUploadDeadline = Duration(minutes: 20);

  /// Cloudflare's upload JWT lives one hour; stop well before it expires.
  ///
  /// All buckets and the deploy that follows them must fit inside it, so a
  /// session is refused after this much wall-clock time. 55 min leaves 5 min
  /// for the final deploy and read-back.
  static const Duration uploadSessionBudget = Duration(minutes: 55);

  /// Largest body that may be re-sent after the connection failed.
  ///
  /// Re-sending more than this over mobile data is worse than asking the user
  /// to try again on Wi-Fi (fix-plan H2 step 4).
  static const int blindResendMaxBytes = 1024 * 1024;

  /// A request body above this size uses the upload timing profile (N13).
  ///
  /// The upload-session manifest can reach ~1.6 MB for 20 000 files, so it is
  /// not an API-sized body even though the endpoint is an ordinary JSON call.
  static const int largeBodyBytes = 256 * 1024;

  /// Total deadline for one upload request carrying [bytes] body bytes.
  ///
  /// `60 s + bytes ÷ 64 KiB/s`, capped at [maxUploadDeadline]. A 56,131,788-byte
  /// request gets about 15.3 min — the size the real-host trial used.
  static Duration uploadTotalDeadline(int bytes) {
    final safeBytes = bytes < 0 ? 0 : bytes;
    final scaled = Duration(
      milliseconds:
          uploadIdleTimeout.inMilliseconds +
          (safeBytes * 1000) ~/ uploadFloorBytesPerSecond,
    );
    return scaled < maxUploadDeadline ? scaled : maxUploadDeadline;
  }

  /// Longest `retry-after` honoured once for a 429.
  static const Duration maxRetryAfter = Duration(seconds: 60);

  /// Total attempts for a read or an idempotent hash upload.
  static const int maxAttempts = 3;

  /// Largest raw chunk accepted from an on-demand/spooled artifact source.
  ///
  /// Uploads are serial and every part is streamed, so raw bytes, base64 text,
  /// UTF-8 bytes and multipart copies stay bounded by a small number of chunks
  /// instead of growing with the server's bucket size (R24).
  static const int maxArtifactChunkBytes = 64 * 1024;

  /// Largest standard padded-base64 chunk produced from the raw chunk cap.
  static const int maxBase64ChunkBytes = 4 * ((maxArtifactChunkBytes + 2) ~/ 3);

  // ---- Fixed protocol values (B.3) -----------------------------------------

  /// The reviewed compatibility date every deploy sends.
  ///
  /// Fixed on purpose: a deploy must not silently pick up new runtime
  /// behaviour, and the value is part of what the trial verifies.
  static const String compatibilityDate = '2026-10-26';

  /// The API base. Every request goes here and nowhere else (R20).
  static const String apiBase = 'https://api.cloudflare.com/client/v4';

  /// The public marker file name (R10).
  static const String markerPath = 'pitak-publish.json';
}

/// One bounded read-back budget (fix-plan M2, R16).
///
/// Two questions need different answers: "did the deployment I just made
/// land?" can wait for a fresh edge, while "does this older record still
/// describe the live site?" must be cheap and must not hold the publish queue
/// for minutes. Both keep a total deadline, so a hung read can never make the
/// check unbounded.
final class CloudflareReadBackBudget {
  /// Creates a budget.
  const CloudflareReadBackBudget({
    required this.rounds,
    required this.interval,
    required this.deadline,
  });

  /// Rounds for a deployment made moments ago: 12 × 5 s inside 90 s.
  static const afterDeploy = CloudflareReadBackBudget(
    rounds: 12,
    interval: Duration(seconds: 5),
    deadline: Duration(seconds: 90),
  );

  /// Rounds for a record written by an earlier publish: 3 × 2 s inside 20 s.
  static const earlierDeployment = CloudflareReadBackBudget(
    rounds: 3,
    interval: Duration(seconds: 2),
    deadline: Duration(seconds: 20),
  );

  /// Maximum polling rounds.
  final int rounds;

  /// Delay before each polling round.
  final Duration interval;

  /// Total wall-clock budget. A read already in flight may overrun it by its
  /// own transport limit (15 s); no new read starts after it.
  final Duration deadline;
}
