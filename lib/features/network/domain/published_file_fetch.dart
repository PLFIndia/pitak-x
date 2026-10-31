/// One conditional read of a saved library's published file (network domain,
/// pure Dart; ADR 0018).
///
/// The viewer reads two files from a saved library's site: `books.json` (the
/// catalogue) and the optional `events.json`. Both now go through the same
/// "check first, fall back to the saved copy" algorithm
/// (`PublishedFileLoader`), so both ports share these result types.
///
/// Why the adapter returns the decoded value AND the raw bytes on a fresh
/// download (beginner note): the bytes are what gets saved on the device, and
/// the decoded value is what the screen shows. Decoding happens in the
/// infrastructure adapter (a worker isolate for the large catalogue), and only
/// bytes that DECODED are ever saved, so a broken download can never replace
/// a good saved copy.
library;

import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';

/// Why a fresh copy could not be used. Coarse on purpose: it picks one plain
/// sentence for the "showing your saved copy" note and never carries a URL,
/// status code or exception text (AGENTS §6.2).
enum PublishedFileProblem {
  /// No answer: offline, DNS/TLS/connection fault, or the deadline expired.
  unreachable,

  /// The host answered, but not with the file (error status, refused or too
  /// many redirects).
  notServed,

  /// The file arrived but this build cannot use it (too large or unreadable).
  unreadable,
}

/// Outcome of one conditional fetch of a published file whose decoded form
/// is [T].
sealed class PublishedFileFetch<T> {
  const PublishedFileFetch();
}

/// The host served the file (`200`) and it decoded.
final class PublishedFileFetched<T> extends PublishedFileFetch<T> {
  /// Creates the fresh result.
  const PublishedFileFetched({
    required this.value,
    required this.bytes,
    this.validator,
  });

  /// The decoded file, ready to show.
  final T value;

  /// The exact body that decoded into [value] — what a saved copy stores.
  final Uint8List bytes;

  /// The host's validated entity tag for these bytes, or null when it sent
  /// none (the next open then downloads the whole file again).
  final String? validator;
}

/// The host answered `304 Not Modified` to the validator that was sent: the
/// saved copy is current. Only possible when a validator was sent.
final class PublishedFileUnchanged<T> extends PublishedFileFetch<T> {
  /// Creates the not-modified result.
  const PublishedFileUnchanged();
}

/// The host answered `404`. For the OPTIONAL `events.json` this means "this
/// library publishes no events"; the catalogue adapter never returns it (a
/// missing `books.json` is a [PublishedFileFailed] with
/// [PublishedFileProblem.notServed]).
final class PublishedFileMissing<T> extends PublishedFileFetch<T> {
  /// Creates the missing-file result.
  const PublishedFileMissing();
}

/// No usable fresh copy: a transport refusal or a body that did not decode.
final class PublishedFileFailed<T> extends PublishedFileFetch<T> {
  /// Creates the failure. [failure] is what the screen shows when no saved
  /// copy exists; [problem] picks the note when one does.
  const PublishedFileFailed({required this.failure, required this.problem});

  /// The typed failure for the "nothing to show" case.
  final Failure failure;

  /// The coarse reason for the saved-copy note.
  final PublishedFileProblem problem;
}

/// Fetches the exact file [url], sending [validator] as `If-None-Match` when
/// non-null. [abortTrigger] cancels the actual request when the viewer
/// reloads or closes. Never throws for expected failures.
typedef PublishedFileFetcher<T> =
    Future<PublishedFileFetch<T>> Function(
      String url, {
      String? validator,
      Future<void>? abortTrigger,
    });

/// Decodes the bytes of a SAVED copy with the same defensive reader a fresh
/// download uses: a file on the device is re-validated, never trusted.
typedef PublishedFileDecoder<T> =
    Future<Either<Failure, T>> Function(Uint8List bytes);
