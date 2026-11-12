/// The [DocumentPicker] that talks to the app's Android code (core/platform,
/// backup rework BR5b, decisions D8 and D19).
///
/// The Android half is `PickedDocumentChannel.kt`: one method on the channel
/// `dev.khoj.pitaka/picked_document`. Dart sends the size cap and nothing
/// else. Android answers with the path of the copy, the document's display
/// name and the counted size, or with an error code.
///
/// TRUST BOUNDARY (beginner note): the method channel is a border between
/// two programs. What comes back over it is checked like any other input,
/// even though the other side is our own code: a path is accepted only when
/// it is exactly `<temp>/picked_documents/pick-<random>/document`, the size
/// must fit the cap and must be the real length of that file, and the name
/// is cleaned again. A bug on one side then cannot make the other side read
/// or delete a file it should not.
///
/// WHO DELETES: Android only creates a copy. Removing it happens here, with
/// the rules of [RunFolders] (only a real folder of the expected name inside
/// our own root is ever deleted; a copy in use is never swept).
///
/// D19: where the Android side is missing (any other platform, a desktop
/// run during development) the answer is [DocumentPickUnavailable]. There
/// is deliberately no second way through `file_selector`: that plugin loads
/// the whole file into memory, which is the problem this class removes.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/core/platform/document_picker.dart';
import 'package:pitaka/core/storage/run_folders.dart';

/// See the library doc.
final class ChannelDocumentPicker implements DocumentPicker {
  /// Creates the picker. [tempRoot] is the app's temporary folder, which on
  /// Android is the cache folder the native side copies into.
  ChannelDocumentPicker({required String tempRoot})
    : _folders = RunFolders(
        rootPath: p.join(tempRoot, directoryName),
        prefix: _folderPrefix,
      );

  /// Folder under the temporary folder that holds every picked copy. The
  /// same text as `PickedDocumentChannel.DIRECTORY` in Kotlin.
  static const String directoryName = 'picked_documents';

  /// The fixed name of a copy. The same text as
  /// `PickedDocumentChannel.FILE_NAME` in Kotlin.
  static const String fileName = 'document';

  /// Longest display name that is passed on, in UTF-16 units. The same
  /// number as `PickedDocumentChannel.MAX_NAME_CHARS` in Kotlin.
  static const int maxNameLength = 255;

  /// First part of the folder one copy lies in (`pick-<random>`).
  static const String _folderPrefix = 'pick';

  /// The single method-channel name shared with the native side.
  static const MethodChannel _channel = MethodChannel(
    'dev.khoj.pitaka/picked_document',
  );

  /// Which copies exist, which are in use, and the only code that deletes
  /// one.
  final RunFolders _folders;

  @override
  Future<DocumentPickResult> pickCopy({required int maxBytes}) async {
    // A cap that allows nothing is a mistake in the calling code. Do not
    // even open the picker for it.
    if (maxBytes <= 0) return const DocumentPickFailed();
    final Object? reply;
    try {
      reply = await _channel.invokeMethod<Object?>('pickAndCopy', {
        'maxBytes': maxBytes,
      });
    } on MissingPluginException {
      // No native side: not Android, or a build without it (D19).
      return const DocumentPickUnavailable();
    } on PlatformException catch (e) {
      return _fromCode(e.code);
    }
    return _checked(reply, maxBytes);
  }

  @override
  Future<void> discard(PickedDocument document) async {
    // Only a `pick-…` folder of our own root is ever deleted; any other
    // path is ignored. A failure is left to the next sweep.
    await _folders.discard(document.path);
  }

  @override
  Future<void> sweep() async {
    await _folders.sweep();
  }

  /// The error codes of `PickedDocumentChannel.kt`, one to one. `busy`,
  /// `invalid`, `failed` and anything unknown are mistakes in code, not
  /// something a user can act on: they all become [DocumentPickFailed].
  DocumentPickResult _fromCode(String code) {
    switch (code) {
      case 'cancelled':
        return const DocumentPickCancelled();
      case 'too_large':
        return const DocumentPickTooLarge();
      case 'unreadable':
        return const DocumentPickUnreadable();
      case 'storage':
        return const DocumentPickNotSaved();
      case 'unavailable':
        return const DocumentPickUnavailable();
    }
    // The code only (debug builds only), and only when it looks like one of
    // ours: never a message, a name or a path (§6.2).
    final known = _codeShape.hasMatch(code) ? code : 'unknown code';
    appLog('document_picker: pick failed: $known');
    return const DocumentPickFailed();
  }

  static final RegExp _codeShape = RegExp(r'^[a-z_]{1,32}$');

  /// Checks a success answer field by field. Anything unexpected is
  /// [DocumentPickFailed], and a folder of ours that came with it is
  /// removed.
  Future<DocumentPickResult> _checked(Object? reply, int maxBytes) async {
    if (reply is! Map) return const DocumentPickFailed();
    final path = reply['path'];
    final name = reply['name'];
    final size = reply['size'];
    if (path is! String) return const DocumentPickFailed();

    // The path must lie in a real `pick-…` folder directly inside our own
    // root. `adopt` also marks that folder "in use", so no sweep takes it.
    final folder = await _folders.adopt(path);
    if (folder == null) return const DocumentPickFailed();

    // From here on there is a folder of ours: every refusal removes it.
    if (name is! String || size is! int) return _refuse(folder);
    final file = p.join(folder, fileName);
    final accepted =
        p.equals(p.normalize(p.absolute(path)), file) &&
        size >= 0 &&
        size <= maxBytes &&
        await _isFileOfLength(file, size);
    if (!accepted) return _refuse(folder);
    return DocumentPicked(
      PickedDocument(
        // Our own tidy spelling of the path, not the text that came in.
        path: file,
        displayName: cleanDisplayName(name),
        sizeBytes: size,
      ),
    );
  }

  Future<DocumentPickResult> _refuse(String folder) async {
    await _folders.discard(folder);
    return const DocumentPickFailed();
  }

  /// Whether [path] is a real file (not a link, not a folder) of exactly
  /// [length] bytes.
  static Future<bool> _isFileOfLength(String path, int length) async {
    try {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type != FileSystemEntityType.file) return false;
      return await File(path).length() == length;
    } on FileSystemException {
      return false;
    }
  }

  /// A document's name as it may be shown: control characters removed and
  /// cut at [maxNameLength]. Android cleans the name the same way; it is
  /// done again here because what crosses the channel is not trusted.
  ///
  /// Other invisible characters stay: several scripts (Indic ones among
  /// them) need joiner characters to be written correctly.
  static String cleanDisplayName(String raw) {
    final cleaned = StringBuffer();
    // Runes are whole characters, so a two-part character (an emoji, a rare
    // letter) is kept or dropped whole, never cut in half.
    for (final rune in raw.runes) {
      final isControl = rune < 0x20 || (rune >= 0x7f && rune <= 0x9f);
      // Half of a two-part character on its own is not text, and drawing
      // it can throw.
      final isLoneHalf = rune >= 0xd800 && rune <= 0xdfff;
      if (isControl || isLoneHalf) continue;
      final units = rune > 0xffff ? 2 : 1;
      if (cleaned.length + units > maxNameLength) break;
      cleaned.writeCharCode(rune);
    }
    return cleaned.toString();
  }
}
