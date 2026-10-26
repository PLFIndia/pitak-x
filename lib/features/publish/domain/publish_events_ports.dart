/// Function ports for machine-readable published events (domain, §3.3).
///
/// The application layer depends on this byte-producing function type; JSON
/// encoding stays in the infrastructure implementation supplied by DI.
library;

import 'package:pitaka/features/publish/domain/events_posters_html.dart';

/// Produces the public `events.json` bytes for the redacted [posters].
typedef EventsJsonFactory = List<int> Function(List<PublishPoster> posters);
