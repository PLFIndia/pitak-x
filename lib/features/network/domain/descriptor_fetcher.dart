/// The descriptor-fetch port (network domain, pure Dart; libNetwork.md §5.2).
///
/// A function type, not an interface: the refresh use case needs exactly one
/// operation — "fetch `<siteUrl>library.json` and hand back the typed
/// outcome" — so tests inject a fake closure and production injects the
/// bounded fetcher adapter (infrastructure). Same seam style as the publish
/// use case's `RemoteCoverFetcher`.
library;

import 'package:pitaka/features/network/domain/descriptor_fetch_result.dart';

/// Fetches and parses the `library.json` at [url] (a full file URL). Never
/// throws for expected failures: every transport refusal, oversize body or
/// invalid document is a [DescriptorRefused].
typedef DescriptorFetcher = Future<DescriptorFetchResult> Function(String url);
