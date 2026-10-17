/// Function ports for the published-page HTML builders (domain, §3.3).
///
/// The concrete builders (`infrastructure/viewer_html_builder.dart`,
/// `infrastructure/events_html_builder.dart`) load bundled templates via
/// Flutter's `rootBundle` — a side effect — so the application layer depends
/// on these pure function types instead and the composition root
/// (`core/di/providers.dart`) injects the implementations.
library;

import 'package:pitaka/features/publish/domain/events_posters_html.dart';
import 'package:pitaka/features/publish/domain/publish_contact_links.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

/// Produces the published viewer `index.html` bytes for the given library
/// name + public contact info. [sharing] gates the GPS pin (libNetwork.md
/// D7: the same switch that gates the `library.json` location).
typedef ViewerHtmlFactory =
    Future<List<int>> Function({
      required String libraryName,
      required PublishContact contact,
      required LocationSharing sharing,
    });

/// Produces the published `events.html` bytes for the given library name +
/// redacted posters.
typedef EventsHtmlFactory =
    Future<List<int>> Function({
      required String libraryName,
      required List<PublishPoster> posters,
    });
