/// Local git blob SHA-1 (pure domain, AGENTS.md §3.1, #32).
///
/// Port of Kotlin `GitBlobSha`. Git names a blob object by
/// `sha1("blob " + <byteLength> + "\u0000" + <bytes>)` — exactly the `sha`
/// GitHub's Git Data / Trees API reports for a file. Computing it locally lets a
/// repeat publish decide "this file is unchanged, skip it" with zero network.
///
/// Not a security hash — SHA-1's collision weakness is irrelevant here (we only
/// match git's own object names; an attacker who can write the user's repo
/// already owns the page).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Computes git blob SHA-1 values for change detection.
abstract final class GitBlobSha {
  /// Lowercase 40-char hex git blob sha of [bytes].
  static String of(List<int> bytes) {
    final header = ascii.encode('blob ${bytes.length}\u0000');
    final input = Uint8List(header.length + bytes.length)
      ..setRange(0, header.length, header)
      ..setRange(header.length, header.length + bytes.length, bytes);
    return sha1.convert(input).toString();
  }
}
