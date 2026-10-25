import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/import_export/domain/import_payload.dart';

/// Validated, immutable bundle data; validation grants no access to live files.
final class ImportBundle {
  ImportBundle._(this.payload, this.covers);

  /// Parsed rows whose local references are backed by this bundle's bytes.
  final ImportPayload payload;

  /// Image bytes indexed by source leaf, never by a destination path.
  final Map<String, Uint8List> covers;

  /// Validates references before any persistence, including wishlist covers.
  ///
  /// The result is LOSSLESS (S5, H4): every collection the parser produced —
  /// items, magazine titles and wishlist rows — plus the parser's warnings
  /// travels on to the importer. Dropping `periodicals` here (the pre-S5 bug)
  /// turned a v4 bundle into a books-and-wishlist import, so every issue lost
  /// its series and restored as a book.
  static Either<Failure, ImportBundle> validate(
    ImportPayload payload,
    Map<String, Uint8List> covers,
  ) {
    final schemaTooNewFailure = payload.schemaTooNewFailure;
    if (schemaTooNewFailure != null) {
      return left(schemaTooNewFailure);
    }
    if (payload.parseErrors.isNotEmpty || payload.fatalErrors.isNotEmpty) {
      return left(const BackupCorruptFailure('Invalid bundle catalogue.'));
    }
    final referenced = <String>{};
    for (final ref in [
      ...payload.items.map((b) => b.coverUrl),
      // A series cover is an image reference like any other: it must be
      // backed by bundled bytes and it counts as a referenced leaf, or the
      // unreferenced-cover check below would reject the bundle's own art.
      ...payload.periodicals.map((p) => p.coverUrl),
      ...payload.wishlist.map((b) => b.coverUrl),
    ]) {
      if (!CoverPaths.isLocal(ref)) continue;
      final leaf = CoverPaths.leafOf(ref);
      if (leaf == null ||
          !isSafeBundleCoverLeaf(leaf) ||
          !covers.containsKey(leaf)) {
        return left(
          const BackupCorruptFailure('Missing or unsafe bundle cover.'),
        );
      }
      referenced.add(leaf);
    }
    if (covers.keys.any(
      (leaf) => !isSafeBundleCoverLeaf(leaf) || !referenced.contains(leaf),
    )) {
      return left(
        const BackupCorruptFailure('Unreferenced or unsafe bundle cover.'),
      );
    }
    return right(
      ImportBundle._(
        ImportPayload(
          items: List.unmodifiable(payload.items),
          periodicals: List.unmodifiable(payload.periodicals),
          wishlist: List.unmodifiable(payload.wishlist),
          // `parseErrors` stays empty: a payload carrying any is refused
          // above. Warnings are adjustments already applied to kept rows —
          // the summary must keep reporting them.
          warnings: List.unmodifiable(payload.warnings),
        ),
        Map.unmodifiable(
          covers.map(
            (leaf, bytes) =>
                MapEntry(leaf, Uint8List.fromList(bytes).asUnmodifiableView()),
          ),
        ),
      ),
    );
  }
}

/// Additional portable filename checks at the untrusted bundle boundary.
bool isSafeBundleCoverLeaf(String leaf) =>
    leaf.trim().isNotEmpty &&
    CoverPaths.leafOf('${CoverPaths.prefix}$leaf') == leaf &&
    !leaf.contains(r'\') &&
    !leaf.contains('\u0000');

/// Decodes bundles without file or database side effects.
// A nominal domain port, like Importer, keeps the no-IO decoding contract
// explicit for infrastructure implementations and DI overrides.
// ignore: one_member_abstracts
abstract interface class BundleReader {
  /// Returns validated content or a typed corruption failure.
  Future<Either<Failure, ImportBundle>> read(Uint8List bytes);
}
