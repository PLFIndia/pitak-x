/// A saved library's decoded `availability.json` (network domain, pure Dart;
/// ADR 0019 Decision 4 and its S7 clarification, ADR 0015 amendment).
///
/// What it is (beginner note): a publishing library may update a tiny file
/// listing the public keys of the items whose every copy is lent out. The
/// viewer uses it to show *Available / Not available* without waiting for
/// the library to republish its whole catalogue.
///
/// Named `PublishedAvailabilityFile` because `PublishedAvailability` already
/// names the per-item enum in `published_catalogue.dart` (plan A.6 #22). It
/// is the READER's model: the publish feature's `AvailabilitySnapshot` is the
/// writer's, and the two stay separate on purpose (ADR 0015 decision 5);
/// shared fixtures pin their agreement.
///
/// Only a file that passed every reader rule (`PublishedAvailabilityCodec`)
/// becomes one of these. A refused file is treated as missing, never as
/// "nothing is out" (that would show every item as Available).
library;

/// One accepted `availability.json`.
final class PublishedAvailabilityFile {
  /// Creates the model from already-validated parts. [outKeys] is stored
  /// unmodifiable so no screen can change what another screen reads.
  PublishedAvailabilityFile({
    required this.keySet,
    required Set<String> outKeys,
    this.asOf,
  }) : outKeys = Set<String>.unmodifiable(outKeys);

  /// The only schema version this build reads. A newer file is ignored (the
  /// inline tags in `books.json` are used instead).
  static const int schemaVersion = 1;

  /// Readers refuse a larger file (ADR 0019 AV15): 1 MiB.
  static const int maxBytes = 1024 * 1024;

  /// Readers refuse a file listing more keys than this (AV15).
  static const int maxKeys = 100000;

  /// Deepest JSON nesting accepted. A real file nests 2 deep (root → `out`);
  /// the margin still stops a `[[[[…` stack-overflow bomb.
  static const int maxJsonDepth = 16;

  /// The earliest `asOf` worth showing: 2020-01-01T00:00:00Z. No Pitak build
  /// existed before then, so an earlier time is damaged or made up.
  static const int earliestPlausibleAsOf = 1577836800000;

  /// How far in the future an `asOf` may lie and still be shown: 24 hours,
  /// for a publishing phone whose clock runs ahead.
  static const int allowedClockSkewMillis = 24 * 60 * 60 * 1000;

  static final RegExp _keyPattern = RegExp(r'^[0-9a-f]{16}$');

  /// True when [value] is a string with the exact public key shape: 16
  /// lower-case hex characters. Item `key`s, both `keySet`s and every entry
  /// of `out` must pass it. No trimming and no case folding: anything else
  /// never came from a Pitak writer.
  ///
  /// The reader keeps its OWN copy of the rule rather than importing the
  /// writer's (`PublishItemKeys.isValidKey`): the hostile reader and the
  /// trusted writer stay separate (ADR 0015 decision 5), and the parity
  /// tests prove they agree.
  static bool isKey(Object? value) =>
      value is String && _keyPattern.hasMatch(value);

  /// The key set every key in [outKeys] belongs to (16 lower-case hex). The
  /// file applies to a catalogue only when its `keySet` is the same (plan
  /// J10, A.6 #68).
  final String keySet;

  /// Keys of the items that are not available (duplicates already merged).
  final Set<String> outKeys;

  /// When the library's set was computed (epoch ms) as the file claims it, or
  /// null when the value was absent or not a whole number. Untrusted: shown
  /// only through [plausibleAsOf].
  final int? asOf;

  /// [asOf] when it is believable at [nowMillis]: not before
  /// [earliestPlausibleAsOf] and not more than [allowedClockSkewMillis]
  /// ahead of now. Otherwise null, and the viewer shows no time at all
  /// (ADR 0019 AV15: "shown only when plausible").
  int? plausibleAsOf(int nowMillis) {
    final value = asOf;
    if (value == null) return null;
    if (value < earliestPlausibleAsOf) return null;
    if (value > nowMillis + allowedClockSkewMillis) return null;
    return value;
  }

  @override
  String toString() => 'PublishedAvailabilityFile(${outKeys.length} out)';
}
