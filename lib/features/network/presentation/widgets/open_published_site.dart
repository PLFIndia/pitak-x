/// The explicit "open in browser" fallback (network presentation; ADR 0015
/// V10, viewer plan S4).
///
/// The native viewer is read-only and does not cover everything a published
/// site may have, so every loading/empty/error state offers a deliberate
/// browser action. Two rules keep it honest:
///  1. the saved URL is re-validated with `BookmarkUrl.sanitize` immediately
///     before launching — a corrupted or hand-edited row never reaches the OS;
///  2. it always uses `LaunchMode.externalApplication`, so untrusted third-
///     party pages stay OUTSIDE the app process (no in-app WebView, ever).
///
/// [PublishedSiteOpener] is a small injectable seam: widget tests pass a
/// recorder to prove the normal row tap makes ZERO external launches and only
/// this explicit action makes one.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/network/domain/value_objects/bookmark_url.dart';
import 'package:url_launcher/url_launcher.dart';

/// The OS hand-off signature (`url_launcher`'s shape, minus its extra options).
typedef ExternalUrlLauncher = Future<bool> Function(Uri url, LaunchMode mode);

/// Opens one already-validated published site in the device browser.
final class PublishedSiteOpener {
  /// Creates an opener. Production uses the real launcher; tests pass a
  /// recorder through [launch].
  const PublishedSiteOpener({this.launch = defaultLaunch});

  /// The launcher seam.
  final ExternalUrlLauncher launch;

  /// The production hand-off: external application only.
  static Future<bool> defaultLaunch(Uri url, LaunchMode mode) =>
      launchUrl(url, mode: mode);

  /// Returns true when the browser was opened. Re-runs the allow-list on the
  /// exact saved URL; an invalid URL returns false WITHOUT launching anything.
  Future<bool> open(String siteUrl) async {
    final safe = BookmarkUrl.sanitize(siteUrl);
    if (safe == null) return false;
    final uri = Uri.tryParse(safe);
    if (uri == null) return false;
    try {
      return await launch(uri, LaunchMode.externalApplication);
    } on Object {
      // A platform failure is a "couldn't open" — never exception text in UI.
      return false;
    }
  }
}

/// Opens [siteUrl] externally and shows the app's one safe failure message.
///
/// Returns after the browser hand-off attempt. The message text is fixed (no
/// URL, no platform exception) so the UI can never leak where the user is
/// going.
Future<void> openPublishedSiteInBrowser(
  BuildContext context,
  String siteUrl,
  PublishedSiteOpener opener,
) async {
  final opened = await opener.open(siteUrl);
  if (opened || !context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text("Couldn't open that link.")));
}
