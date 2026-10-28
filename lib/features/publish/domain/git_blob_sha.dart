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

import 'package:crypto/crypto.dart';

/// Computes git blob SHA-1 values for change detection.
abstract final class GitBlobSha {
  /// Lowercase 40-char hex git blob sha of [bytes].
  static String of(List<int> bytes) {
    // Chunked conversion avoids allocating a second header+file-sized copy.
    // The bytes themselves remain owned by the caller; only the digest state
    // and small encoded header are retained here.
    final output = _DigestValueSink();
    sha1.startChunkedConversion(output)
      ..add(ascii.encode('blob ${bytes.length}\u0000'))
      ..add(bytes)
      ..close();
    final digest = output.value;
    if (digest == null) throw StateError('SHA-1 produced no digest');
    return digest.toString();
  }
}

final class _DigestValueSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest value) {
    if (this.value != null) throw StateError('SHA-1 emitted two digests');
    this.value = value;
  }

  @override
  void close() {}
}
