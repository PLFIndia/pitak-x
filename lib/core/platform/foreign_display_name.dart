/// Cleaning a file's name that another app gave us, before it is shown
/// (core/platform).
///
/// WHY THIS EXISTS (beginner note): when the user picks a file, or saves
/// one, the place the file lives in tells the app what the file is called.
/// That name is foreign text: it can hold line breaks, invisible control
/// characters or be absurdly long, and it crosses the method channel from
/// the Android side. So it is cleaned here before any page shows it, and it
/// is NEVER used as a file name or a path.
///
/// ONE function for both directions (review finding P4-M6): the picker that
/// brings a file in (`channel_document_picker.dart`) and the saver that
/// takes one out (`channel_document_saver.dart`) clean a name the same way.
/// Pure Dart.
library;

/// Longest display name that is passed on, in UTF-16 units. The same
/// number as `PickedDocumentChannel.MAX_NAME_CHARS` in Kotlin.
const int maxForeignDisplayNameLength = 255;

/// A file's name as it may be shown: control characters removed and cut at
/// [maxForeignDisplayNameLength]. Android cleans the name the same way; it
/// is done again here because what crosses the channel is not trusted.
///
/// Other invisible characters stay: several scripts (Indic ones among
/// them) need joiner characters to be written correctly.
String cleanForeignDisplayName(String raw) {
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
    if (cleaned.length + units > maxForeignDisplayNameLength) break;
    cleaned.writeCharCode(rune);
  }
  return cleaned.toString();
}
