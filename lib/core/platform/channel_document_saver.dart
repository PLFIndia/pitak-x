/// The [DocumentSaver] that talks to the app's Android code (core/platform;
/// review finding P4-M6, decisions D168, D171 and D176).
///
/// The Android half is `SavedDocumentChannel.kt`: one method on the channel
/// `dev.khoj.pitaka/saved_document`. Dart sends the path of one finished
/// file of its own and nothing else: no name, no type, no place. Android
/// answers with the name the place gave the saved file and the size it
/// counted, or with an error code.
///
/// TRUST BOUNDARY (beginner note): the method channel is a border between
/// two programs. Each side checks what the other sends, even though both
/// are our own code:
///
///  - Android refuses every path that is not a finished file in one of the
///    app's two working folders (`DocumentCopyOut.kt`), so a mistake here
///    cannot copy the catalogue, the vault or a key out of the app;
///  - this side believes "saved" only when the size Android counted is the
///    length of the file that was sent, and it cleans the name again.
///
/// A SUCCESS THAT DOES NOT PASS THE CHECK is [DocumentSaveLeftBehind], not
/// "failed": by then Android has written SOMETHING at the place the user
/// chose, and nobody can vouch for it. The page then never says "saved"
/// and tells the user that a file may lie there.
///
/// D171: where the Android side is missing (any other platform, a desktop
/// run during development) the answer is [DocumentSaveUnavailable]. There
/// is deliberately no second way through a plugin.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/platform/app_log.dart';
import 'package:pitaka/core/platform/document_saver.dart';
import 'package:pitaka/core/platform/foreign_display_name.dart';

/// See the library doc.
final class ChannelDocumentSaver implements DocumentSaver {
  /// Creates the saver. It keeps nothing between two calls.
  const ChannelDocumentSaver();

  /// The single method-channel name shared with the native side. The same
  /// text as `SavedDocumentChannel.CHANNEL` in Kotlin.
  static const String channelName = 'dev.khoj.pitaka/saved_document';

  /// The one method of the channel, and its one argument.
  static const String methodSaveCopy = 'saveCopy';
  static const String _argumentPath = 'path';

  /// The two fields of a success answer.
  static const String _keyName = 'name';
  static const String _keySize = 'size';

  static const MethodChannel _channel = MethodChannel(channelName);

  @override
  Future<DocumentSaveResult> saveCopy({required String path}) async {
    // A name Android would refuse anyway is a mistake in the calling code:
    // say so here, where it is cheap to find.
    if (!isSavableFileName(p.basename(path))) {
      appLog('document_saver: save failed: file name not allowed');
      return const DocumentSaveFailed();
    }
    // The length is read BEFORE Android is asked: a success is believed
    // only when Android counted exactly this many bytes.
    final length = await _lengthOfFile(path);
    if (length == null) return const DocumentSaveSourceGone();

    final Object? reply;
    try {
      reply = await _channel.invokeMethod<Object?>(methodSaveCopy, {
        _argumentPath: path,
      });
    } on MissingPluginException {
      // No native side: not Android, or a build without it (D171).
      return const DocumentSaveUnavailable();
    } on PlatformException catch (e) {
      return _fromCode(e.code);
    }
    return _checked(reply, length);
  }

  /// The length of the real file at [path] (not a link, not a folder), or
  /// null when there is none.
  static Future<int?> _lengthOfFile(String path) async {
    try {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type != FileSystemEntityType.file) return null;
      return await File(path).length();
    } on FileSystemException {
      return null;
    }
  }

  /// The error codes of `SavedDocumentChannel.kt`, one to one. `busy`,
  /// `invalid`, `failed` and anything unknown are mistakes in code, not
  /// something a user can act on: they all become [DocumentSaveFailed].
  DocumentSaveResult _fromCode(String code) {
    switch (code) {
      case 'cancelled':
        return const DocumentSaveCancelled();
      case 'not_saved':
        return const DocumentSaveNotSaved();
      case 'source':
        return const DocumentSaveSourceGone();
      case 'left_behind':
        return const DocumentSaveLeftBehind();
      case 'not_empty':
        return const DocumentSaveNotEmpty();
      case 'unconfirmed':
        return const DocumentSaveUnconfirmed();
      case 'unavailable':
        return const DocumentSaveUnavailable();
    }
    // The code only (debug builds only), and only when it looks like one of
    // ours: never a message, a name or a path (§6.2).
    final known = _codeShape.hasMatch(code) ? code : 'unknown code';
    appLog('document_saver: save failed: $known');
    return const DocumentSaveFailed();
  }

  static final RegExp _codeShape = RegExp(r'^[a-z_]{1,32}$');

  /// Checks a success answer field by field. See the library doc for why
  /// anything unexpected is [DocumentSaveLeftBehind].
  DocumentSaveResult _checked(Object? reply, int length) {
    final name = reply is Map ? reply[_keyName] : null;
    final size = reply is Map ? reply[_keySize] : null;
    if (name is! String || size is! int || size != length) {
      appLog('document_saver: save failed: answer not as expected');
      return const DocumentSaveLeftBehind();
    }
    return DocumentSaved(
      SavedDocument(
        displayName: cleanForeignDisplayName(name),
        sizeBytes: size,
      ),
    );
  }
}
