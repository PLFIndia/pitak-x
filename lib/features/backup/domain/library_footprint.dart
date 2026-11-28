/// How much room the library takes on this phone (backup domain, backup
/// rework BR9).
///
/// WHY THIS FILE EXISTS (beginner note): before a backup or a restore the
/// app tells the user how much free storage the run needs (decision D5).
/// That need follows from how large the library is on disk: a backup packs
/// it, a restore copies parts of it. This file holds the three sizes as a
/// plain value, and the PORT through which the application layer asks for
/// them. The code that looks at real folders lives in the infrastructure
/// layer (`file_library_footprint.dart`); this layer stays pure Dart.
library;

/// The size of the library's files on this phone, in bytes.
///
/// A value object: immutable, and no size may be negative.
final class LibraryFootprint {
  /// Creates a footprint from the three sizes.
  const LibraryFootprint({
    required this.catalogueBytes,
    required this.coverBytes,
    required this.vaultBytes,
  }) : assert(catalogueBytes >= 0, 'catalogueBytes must not be negative'),
       assert(coverBytes >= 0, 'coverBytes must not be negative'),
       assert(vaultBytes >= 0, 'vaultBytes must not be negative');

  /// The catalogue database (books and wishlist) with the side files SQLite
  /// keeps next to it.
  final int catalogueBytes;

  /// Every cover picture together.
  final int coverBytes;

  /// The files of the borrowers vault; 0 when there is no vault.
  final int vaultBytes;

  /// Everything together.
  int get totalBytes => catalogueBytes + coverBytes + vaultBytes;
}

/// Answers how large the library is on disk right now.
///
/// A port (an interface the domain declares and the infrastructure
/// implements), so that the notice can be tested without real folders.
// One method on purpose: the port has one job.
// ignore: one_member_abstracts
abstract interface class LibraryFootprintSource {
  /// The sizes, or null when they could not be read. Never throws: a size
  /// that cannot be read makes the notice say so, it never stops a backup
  /// or a restore (decision D5: the notice informs, it never blocks).
  Future<LibraryFootprint?> read();
}
