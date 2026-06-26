/// Create-backup use case (application layer, AGENTS.md §4).
///
/// Gathers the current library + wishlist from their repositories and asks the
/// [BackupArchiveWriter] to build a `.pitabak` archive (including the
/// persistent vault + covers when present). Returns the bytes for the UI.
///
/// Read-only with respect to app state: it reads books/wishlist and copies the
/// existing vault artifacts; it mutates nothing. The vault key never appears.
library;

import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/backup/infrastructure/backup_archive_writer.dart';
import 'package:pitaka/features/library/domain/repositories/book_repository.dart';
import 'package:pitaka/features/wishlist/domain/repositories/wishlist_repository.dart';

/// Builds a `.pitabak` backup of the whole local catalog.
class CreateBackupUseCase {
  /// Creates the use case.
  const CreateBackupUseCase({
    required this.books,
    required this.wishlist,
    required this.writer,
    required this.workDir,
  });

  /// Library source.
  final BookRepository books;

  /// Wishlist source.
  final WishlistRepository wishlist;

  /// The archive writer (Room-format DBs + vault copy + covers + manifest).
  final BackupArchiveWriter writer;

  /// Scratch directory for the transient Room DB files.
  final String workDir;

  /// Builds the archive bytes, or a [Failure] if the catalog can't be read.
  Future<Either<Failure, Uint8List>> call() async {
    final booksResult = await books.getAll();
    final allBooks = booksResult.toNullable();
    if (allBooks == null) {
      return left(booksResult.getLeft().toNullable()!);
    }
    final wishlistResult = await wishlist.getAll();
    final allWishlist = wishlistResult.toNullable();
    if (allWishlist == null) {
      return left(wishlistResult.getLeft().toNullable()!);
    }
    try {
      final bytes = writer.build(
        books: allBooks,
        wishlist: allWishlist,
        workDir: workDir,
        exportedAt: DateTime.now().millisecondsSinceEpoch,
      );
      return right(bytes);
    } on Object catch (e) {
      return left(StorageFailure('Could not build the backup: $e'));
    }
  }
}
