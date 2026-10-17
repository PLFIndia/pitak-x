/// Bounded fetcher for `library.json` descriptors (network infrastructure;
/// libNetwork.md §5.1/§6).
///
/// A thin adapter over the shared [BoundedHttpFetcher] (D14 — the same three
/// defences the cover fetch uses): the allow-list is [BookmarkUrl.normalize]
/// (https, no userinfo, `github.io`/`pages.dev` hosts), applied to the
/// initial URL AND re-applied at every redirect hop; the deadline is 15 s and
/// ABORTS the socket; the body cap is the descriptor cap (64 KiB). Fetched
/// bytes go straight through [LibraryDescriptorCodec.decode], so the wire
/// rules (§3.1) are enforced here too and the caller only ever sees the
/// sealed [DescriptorFetchResult].
library;

import 'package:http/http.dart' as http;
import 'package:pitaka/core/network/bounded_fetch_outcome.dart';
import 'package:pitaka/core/network/bounded_http_fetcher.dart';
import 'package:pitaka/features/bookmarks/domain/library_bookmark.dart';
import 'package:pitaka/features/network/domain/descriptor_fetch_result.dart';
import 'package:pitaka/features/network/domain/library_descriptor_codec.dart';

/// Fetches and parses one descriptor under strict origin/time/size limits.
final class BoundedDescriptorFetcher {
  /// Creates the fetcher over an injected [client].
  BoundedDescriptorFetcher({
    required http.Client client,
    this.timeout = defaultTimeout,
    this.maxBytes = defaultMaxBytes,
  }) : _fetcher = BoundedHttpFetcher(
         client: client,
         sanitize: BookmarkUrl.normalize,
         timeout: timeout,
         maxBytes: maxBytes,
       );

  final BoundedHttpFetcher _fetcher;

  /// Whole-request deadline (§6: 15 s, abortable).
  final Duration timeout;

  /// Body cap (§6: 64 KiB, streamed and aborted over cap).
  final int maxBytes;

  /// Default deadline for one descriptor fetch.
  static const Duration defaultTimeout = Duration(seconds: 15);

  /// Default body cap — the codec's own limit, in one place.
  static const int defaultMaxBytes = LibraryDescriptorCodec.maxBodyBytes;

  /// Fetches [url] and decodes the body. Never throws for expected failures.
  Future<DescriptorFetchResult> fetch(String url) async {
    return switch (await _fetcher.fetch(url)) {
      FetchedBytes(:final bytes) => LibraryDescriptorCodec.decode(
        bytes,
      ).match(DescriptorRefused.new, DescriptorFetched.new),
      FetchRefused(:final reason) => DescriptorRefused(_mapRefusal(reason)),
    };
  }

  /// The core transport refusals map 1:1 onto the descriptor refusals (the
  /// descriptor set adds only the two parse-step reasons).
  static DescriptorRefusal _mapRefusal(FetchRefusal reason) => switch (reason) {
    FetchRefusal.disallowedUrl => DescriptorRefusal.disallowedUrl,
    FetchRefusal.redirectRefused => DescriptorRefusal.redirectRefused,
    FetchRefusal.tooManyRedirects => DescriptorRefusal.tooManyRedirects,
    FetchRefusal.httpStatus => DescriptorRefusal.httpStatus,
    FetchRefusal.tooLarge => DescriptorRefusal.tooLarge,
    FetchRefusal.timedOut => DescriptorRefusal.timedOut,
    FetchRefusal.transport => DescriptorRefusal.transport,
  };
}
