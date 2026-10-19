/// The app's single outbound HTTP User-Agent (core; docs/ARCHITECTURE.md §3).
///
/// ONE constant for every request the app makes to a third party: ISBN
/// lookups, `library.json` descriptor fetches, and OpenStreetMap tiles. Two
/// reasons it is shared:
///  - The OSM tile policy REQUIRES a unique, stable UA naming the application
///    (https://operations.osmfoundation.org/policies/tiles/), and Open
///    Library's API policy requires a descriptive one — one honest string
///    satisfies both instead of three drifting ones.
///  - The version number is omitted ON PURPOSE: a hard-coded "1.1" silently
///    drifts from `pubspec.yaml` on every release, and a stale UA is worse
///    than a versionless one when a service needs to identify us.
library;

/// The User-Agent header value for all app-initiated HTTP requests.
abstract final class AppUserAgent {
  /// `Pitak (+<repo URL>)` — the RFC 9110 "product + comment" shape: the app
  /// name plus a contact point where the service operator can reach us.
  static const String value = 'Pitak (+https://github.com/PLFIndia/pitak-x)';
}
