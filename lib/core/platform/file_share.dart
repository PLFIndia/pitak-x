/// Hands a generated file's bytes to the user via the OS share sheet
/// (core/platform, AGENTS.md §3.1).
///
/// Single source of truth for "let the user keep this file". On Android the
/// share sheet includes "Save to Files" alongside WhatsApp/Drive/email, which
/// matches the Kotlin app's `ACTION_SEND` export and the merge "pass a file"
/// workflow (PLAN-merge.md §C). `file_selector` is NOT usable for this on
/// Android — it implements open dialogs only, no save — which is why the prior
/// `getSaveLocation` path silently did nothing on the phone.
///
/// Wraps `share_plus` so the rest of the app depends on this thin seam, not the
/// package directly (easier to test/override and to swap later).
library;

import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:share_plus/share_plus.dart';

/// Outcome of a share attempt, mapped off `share_plus`'s result so callers
/// don't import the package's types.
enum ShareOutcome {
  /// The user completed the share (saved/sent).
  success,

  /// The user dismissed the sheet without choosing a target.
  dismissed,

  /// Sharing is unavailable on this platform/build.
  unavailable,
}

/// Shares in-memory bytes as a named file through the OS share sheet.
///
/// Kept as an interface (not a single function) so it can be provided via DI
/// and overridden with a fake in widget tests — the seam is the point.
abstract interface class FileShareService {
  /// Presents the share sheet for [bytes] under [fileName] with [mimeType].
  ///
  /// [sharePositionOrigin] anchors the iPad popover (ignored on phones); pass
  /// the source widget's global rect where available.
  Future<ShareOutcome> shareBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    Rect? sharePositionOrigin,
  });

  /// Presents the share sheet for plain [text] (e.g. the published site URL).
  Future<ShareOutcome> shareText(String text, {Rect? sharePositionOrigin});
}

/// `share_plus`-backed implementation.
final class SharePlusFileShareService implements FileShareService {
  /// Creates the service.
  const SharePlusFileShareService();

  @override
  Future<ShareOutcome> shareBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: fileName, mimeType: mimeType)],
        // XFile.fromData ignores `name` on some platforms; this guarantees the
        // saved/shared file keeps its extension (so PDF viewers open it).
        fileNameOverrides: [fileName],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    return _outcome(result);
  }

  @override
  Future<ShareOutcome> shareText(
    String text, {
    Rect? sharePositionOrigin,
  }) async {
    final result = await SharePlus.instance.share(
      ShareParams(text: text, sharePositionOrigin: sharePositionOrigin),
    );
    return _outcome(result);
  }

  static ShareOutcome _outcome(ShareResult result) => switch (result.status) {
    ShareResultStatus.success => ShareOutcome.success,
    ShareResultStatus.dismissed => ShareOutcome.dismissed,
    ShareResultStatus.unavailable => ShareOutcome.unavailable,
  };
}
