/// Fixed, user-safe messages for GitHub publish errors (domain, AGENTS.md §5).
///
/// Why this exists (beginner note): HTTP error bodies and exception strings
/// can contain ANYTHING — a captive portal or proxy can inject arbitrary text
/// into a response, and exception `toString()` may embed request URLs. If we
/// rendered those verbatim, a hostile network could put its own words inside
/// a trusted app dialog. So the UI only ever sees one of these fixed strings,
/// chosen by status code. (Same policy as the curated `_messageFor` mappers
/// used elsewhere in the app.)
library;

/// Maps an HTTP status [code] from the GitHub API to a fixed, safe message.
///
/// Never include response-body text in the returned string.
String gitHubHttpErrorMessage(int code) => switch (code) {
  401 =>
    'GitHub rejected the sign-in (401). Your token may have been '
        'revoked — sign out and sign in again.',
  403 =>
    'GitHub refused the request (403). You may have hit a rate limit '
        'or lack permission for this repository. Try again later.',
  404 =>
    'GitHub could not find the repository (404). Check that it still '
        'exists and that your account can access it.',
  409 || 422 =>
    'GitHub rejected the update (HTTP $code). Try publishing '
        'again; if it persists, re-select the target repository.',
  >= 500 =>
    'GitHub had a server problem (HTTP $code). Try again in a few '
        'minutes.',
  _ => 'GitHub returned an unexpected error (HTTP $code). Try again.',
};

/// Fixed message for transport-level failures (timeouts, DNS, TLS, malformed
/// responses). Exception text is deliberately not included.
const String gitHubNetworkErrorMessage =
    'Could not reach GitHub. Check your connection and try again.';
