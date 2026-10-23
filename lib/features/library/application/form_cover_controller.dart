/// Cover capture for FORMS (application layer, AGENTS.md §4/§7).
///
/// `BookCoverController.replaceCover` persists the new reference onto an
/// existing row — which a form does not have yet (the row is assembled on
/// save). This controller is the form-side half of the same pipeline: the
/// widget owns the untestable plugin steps (camera + crop), hands over the
/// RAW bytes, and gets back a stored `covers/<uuid>.jpg` reference the form
/// holds in its view state until the entity is saved with it.
///
/// A replaced or abandoned form cover is simply never referenced by a saved
/// row, so the startup orphan sweep (decision Q12) reclaims the file — no
/// per-form release bookkeeping that could fire on a file still about to be
/// saved.
library;

import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'form_cover_controller.g.dart';

/// Stores captured cover bytes for a not-yet-saved form.
@riverpod
class FormCoverController extends _$FormCoverController {
  @override
  FutureOr<void> build() {
    // Idle until storeCapture() is called; no initial work.
  }

  /// Downscales [rawBytes] and stores the JPEG under `covers/`, returning
  /// its relative reference. Typed failures, never raw exceptions (§5):
  /// unprocessable image → [ValidationFailure]; file IO → [StorageFailure].
  Future<Either<Failure, String>> storeCapture(Uint8List rawBytes) async {
    // Worker isolate (N10-a): a fresh camera capture is a multi-megapixel
    // decode + resize; on the UI isolate that froze the form.
    final jpeg = await ImageDownscaler.downscaleJpegAsync(rawBytes);
    if (jpeg == null) {
      return left(const ValidationFailure('image could not be decoded'));
    }
    final store = await ref.read(coverStoreProvider.future);
    try {
      return right(await store.saveJpeg(jpeg));
    } on Exception {
      return left(const StorageFailure('could not write the cover file'));
    }
  }
}
