/// Book-cover replacement controller (application layer, AGENTS.md §4/§7).
///
/// The platform capture (camera + crop plugins) stays in the widget — those
/// are untestable OS activities. This controller takes the RAW captured bytes
/// and runs the testable downscale → store → persist pipeline, mirroring how
/// `EventsController.addPoster` handles poster images. Failures come back as
/// a typed `Either` so the page shows a safe message (§5) instead of
/// swallowing storage/repository errors.
library;

import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'book_cover_controller.g.dart';

/// Replaces a book's cover image from raw captured bytes.
@riverpod
class BookCoverController extends _$BookCoverController {
  @override
  FutureOr<void> build() {
    // Idle until replaceCover() is called; no initial work.
  }

  /// Downscales [rawBytes], stores the JPEG under `covers/`, persists the new
  /// reference on [book], and refreshes the library list.
  ///
  /// Returns the new `covers/<uuid>.jpg` reference on success. Every failure
  /// path is typed: unprocessable image → [ValidationFailure]; store/repo
  /// errors surface as their own [Failure] (never swallowed, §5).
  Future<Either<Failure, String>> replaceCover(
    Book book,
    Uint8List rawBytes,
  ) async {
    final jpeg = ImageDownscaler.downscaleJpeg(rawBytes);
    if (jpeg == null) {
      return left(const ValidationFailure('image could not be decoded'));
    }
    final store = await ref.read(coverStoreProvider.future);
    final String coverRef;
    try {
      coverRef = await store.saveJpeg(jpeg);
    } on Exception {
      // File IO failed; no book row was touched (fail closed, nothing to
      // roll back).
      return left(const StorageFailure('could not write the cover file'));
    }
    final repo = await ref.read(bookRepositoryProvider.future);
    final result = await repo.update(book.copyWith(coverUrl: coverRef));
    return result.map((_) {
      ref.invalidate(libraryControllerProvider);
      return coverRef;
    });
  }
}
