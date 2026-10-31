/// The published-events ports (network domain, pure Dart; ADR 0016,
/// ADR 0018).
///
/// [PublishedEventsFetcher] reports a `404` as [PublishedFileMissing]: the
/// site has no `events.json`, which is normal for sites published before
/// native events support. Other transport and payload failures stay
/// [PublishedFileFailed] rather than being mistaken for "no events".
/// [PublishedEventsDecoder] re-reads a saved copy with the same bounded codec.
library;

import 'package:pitaka/features/network/domain/entities/published_events.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';

/// Fetches and decodes an exact `events.json` URL, conditionally.
/// `abortTrigger` cancels the actual request when the viewer reloads or
/// closes.
typedef PublishedEventsFetcher = PublishedFileFetcher<PublishedEvents>;

/// Decodes the bytes of a saved events copy.
typedef PublishedEventsDecoder = PublishedFileDecoder<PublishedEvents>;
