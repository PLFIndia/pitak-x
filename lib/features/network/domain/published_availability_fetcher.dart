/// The published-availability ports (network domain, pure Dart; ADR 0019,
/// ADR 0018 amendment).
///
/// [PublishedAvailabilityFetcher] reports a `404` as [PublishedFileMissing],
/// like the events port: most sites have no `availability.json`. It ALSO
/// reports a file it refuses (too large, malformed, a newer format) as
/// missing, because ADR 0019 Decision 4 says such a file is "treated as
/// missing": the viewer then uses the inline tags, and no older saved copy is
/// shown in its place. Only transport failures stay [PublishedFileFailed]
/// (then a saved copy may be shown with its note, ADR 0018).
/// [PublishedAvailabilityDecoder] re-reads a saved copy with the same codec.
library;

import 'package:pitaka/features/network/domain/entities/published_availability_file.dart';
import 'package:pitaka/features/network/domain/published_file_fetch.dart';

/// Fetches and decodes an exact `availability.json` URL, conditionally.
typedef PublishedAvailabilityFetcher =
    PublishedFileFetcher<PublishedAvailabilityFile>;

/// Decodes the bytes of a saved availability copy.
typedef PublishedAvailabilityDecoder =
    PublishedFileDecoder<PublishedAvailabilityFile>;
