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

/// Fixed message when the target repository no longer serves GitHub Pages
/// from a branch root (turned off, moved to `/docs`, or switched to a
/// workflow build) — a commit would land but never reach the live site
/// (N09, D2-a).
const String gitHubPagesNotServingMessage =
    'GitHub Pages is not serving this repository from a branch any more. '
    'Open Publish › Connection and set up the repository again.';

/// Fixed message when the repository's current state could not be read, so
/// the publish cannot know which paths it owns (cloudflare plan R6).
///
/// A publish that cannot prove which files it wrote must not commit: the
/// commit would either upload blindly or delete nothing at all.
const String gitHubSiteStateUnreadableMessage =
    'Could not check what is currently on your site, so nothing was '
    'published. Try again in a minute.';

/// Fixed message when GitHub truncated the repository listing (a very large
/// repository). Refusing is deliberate: a partial listing cannot prove which
/// paths exist, so it cannot prove which paths this app owns.
const String gitHubTreeTooLargeMessage =
    'This repository has too many files for Pitak to check safely, so '
    'nothing was published. Use a repository that only holds your library '
    'site.';

/// Fixed message when the branch head moved between this phone's read and its
/// commit (R6). Nothing was written; the next publish starts from the remote's
/// newest state instead of overwriting it.
const String gitHubStalePublishMessage =
    'Your site was changed by something else after this phone checked it, so '
    'nothing was published. Publish again to update the newest version.';

/// Fixed message when the live site serves DIFFERENT content than this phone
/// recorded for its last unconfirmed publish (F.4 step 2, deviation 48).
///
/// Nothing is written: a new publish would silently overwrite whatever changed
/// the site. The user is told what was observed, not what to guess — the site
/// may have been edited by hand, by another device, or by another app.
const String gitHubSiteChangedSincePublishMessage =
    'Your site is showing something different from what this phone last '
    'published, so nothing was changed. Check the site, then publish again '
    'if you want to replace it.';

/// Fixed message when the commit landed but the phone could not save its own
/// record of the publish (R9).
///
/// The remote site IS updated — saying "nothing was published" here would be a
/// lie. The next publish re-reads the remote tree, so the lost record only
/// costs one reconciliation.
const String gitHubPublishRecordUnsavedMessage =
    'Your site was updated, but this phone could not save the record of it. '
    'The next publish will check the site again.';
