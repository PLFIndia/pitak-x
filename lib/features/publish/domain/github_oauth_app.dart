/// GitHub OAuth App identity for Pitak (domain, #32).
///
/// Pitak ships with a baked-in OAuth **Client ID** used for the Device Flow
/// sign-in. This is safe and intentional:
///
/// - The Device Flow (RFC 8628) uses NO client secret at all — only this id,
///   which GitHub treats as public. It ships in every copy of the app, the
///   same way `gh` CLI and Localcart Orange ship theirs.
/// - Knowing the id grants nothing: the user still has to approve the sign-in
///   themselves at github.com/login/device in their own browser.
///
/// A compile-time const (not config/env) so there is a single source of truth
/// and no runtime path can vary it.
library;

/// Public OAuth App identifier ("Pitak"). Not a secret.
const String githubOAuthClientId = 'Ov23liagHDJ1Ek6ROWKY';

/// Validates the device-flow `verification_uri` before the app offers to
/// open it in the browser.
///
/// The value arrives from the network, so it is treated as hostile input
/// (§6.5): only an https github.com (or *.github.com) URL is accepted — the
/// same check Localcart Orange applies in its Rust core. Returns null when
/// the URL fails validation; callers must then fall back to showing plain
/// text instead of launching it.
Uri? safeGithubVerificationUri(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  final okHost = uri.host == 'github.com' || uri.host.endsWith('.github.com');
  return (uri.scheme == 'https' && okHost) ? uri : null;
}
