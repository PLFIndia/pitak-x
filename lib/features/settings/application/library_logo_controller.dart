/// Library-logo controller (application layer, AGENTS.md §4/§7).
///
/// Same split as `BookCoverController` and `EventsController.addPoster`: the
/// gallery pick (a plugin OS activity) stays in the widget; this controller
/// takes the RAW picked bytes and runs the testable downscale → store →
/// persist pipeline, returning a typed `Either` so failures are surfaced,
/// never silently dropped (§5).
library;

import 'dart:typed_data';

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'library_logo_controller.g.dart';

/// Sets or clears the user's library logo image.
@riverpod
class LibraryLogoController extends _$LibraryLogoController {
  @override
  FutureOr<void> build() {
    // Idle until setLogo()/clearLogo() is called; no initial work.
  }

  /// Downscales [rawBytes], stores the JPEG under `covers/`, and persists the
  /// reference in settings. Returns the stored reference on success.
  Future<Either<Failure, String>> setLogo(Uint8List rawBytes) async {
    final jpeg = ImageDownscaler.downscaleJpeg(rawBytes);
    if (jpeg == null) {
      return left(const ValidationFailure('image could not be decoded'));
    }
    final store = await ref.read(coverStoreProvider.future);
    final previous = _currentLogoReference();
    final String reference;
    try {
      reference = await store.saveJpeg(jpeg);
    } on Exception {
      return left(const StorageFailure('could not write the logo file'));
    }
    try {
      await ref
          .read(settingsControllerProvider.notifier)
          .setLibraryLogo(reference);
    } on Exception {
      // Settings write failed: the new file is unreferenced → remove it so a
      // failed pick leaves no garbage; report the failure honestly.
      await store.deleteFile(reference);
      return left(const StorageFailure('could not save the logo setting'));
    }
    // The old logo file is unreferenced now (unless a book cover shares it —
    // the janitor checks). Decision Q12.
    await _release(previous);
    return right(reference);
  }

  /// Clears the stored logo reference (reverts to the default icon) and
  /// removes the old file when nothing else uses it.
  Future<Either<Failure, Unit>> clearLogo() async {
    final previous = _currentLogoReference();
    try {
      await ref.read(settingsControllerProvider.notifier).setLibraryLogo('');
    } on Exception {
      return left(const StorageFailure('could not clear the logo setting'));
    }
    await _release(previous);
    return right(unit);
  }

  String? _currentLogoReference() =>
      ref.read(settingsControllerProvider).valueOrNull?.libraryLogo;

  Future<void> _release(String? reference) async {
    if (reference == null || reference.isEmpty) return;
    final janitor = await ref.read(coverFileJanitorProvider.future);
    await janitor.releaseReference(reference);
  }
}
