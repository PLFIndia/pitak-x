/// Events editor controller (application layer, AGENTS.md §4).
///
/// Holds the in-app Events screen state: the current [EventsContent] plus the
/// orchestration for adding/removing/captioning posters. The platform image
/// pick (a plugin call) stays in the widget; this controller takes the RAW
/// picked bytes and runs the testable downscale->store->persist pipeline,
/// exercised via `ProviderContainer` overrides without a camera.
library;

import 'dart:typed_data';

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/events/domain/entities/event_poster.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'events_controller.g.dart';

/// Loads + mutates the library's event posters.
@riverpod
class EventsController extends _$EventsController {
  @override
  Future<EventsContent> build() async {
    final repo = await ref.read(eventsRepositoryProvider.future);
    return repo.load();
  }

  /// Adds a poster from RAW picked image [bytes] (downscaled + EXIF-stripped by
  /// the repository). No-op when the cap is reached. Returns true on success.
  Future<bool> addPoster(Uint8List bytes, {String description = ''}) async {
    final current = state.valueOrNull ?? EventsContent.empty;
    if (current.isFull) return false;

    final repo = await ref.read(eventsRepositoryProvider.future);
    final imageResult = await repo.savePosterImage(bytes);
    return imageResult.match((_) => false, (imageRef) async {
      final poster = EventPoster.create(
        imageRef: imageRef,
        description: description,
      );
      final next = poster == null ? null : current.add(poster);
      final saved = next != null && await _persist(next);
      if (!saved) {
        // The image file was written but the metadata was not: remove the
        // file so a failed add leaves no orphan behind (decision Q12).
        await repo.deletePosterImage(imageRef);
      }
      return saved;
    });
  }

  /// Replaces the caption of the poster at [index]. Returns true on success.
  Future<bool> setDescription(int index, String description) async {
    final current = state.valueOrNull ?? EventsContent.empty;
    if (index < 0 || index >= current.posters.length) return false;
    final updated = current.posters[index].withDescription(description);
    if (updated == null) return false; // over the length cap
    final next = current.replaceAt(index, updated);
    if (next == null) return false;
    return _persist(next);
  }

  /// Removes the poster at [index] and, once the metadata is saved without
  /// it, deletes its image file (decision Q12). Returns true on success.
  Future<bool> removePoster(int index) async {
    final current = state.valueOrNull ?? EventsContent.empty;
    if (index < 0 || index >= current.posters.length) return false;
    final removed = current.posters[index];
    final next = current.removeAt(index);
    final saved = await _persist(next);
    if (saved && !next.posters.any((p) => p.imageRef == removed.imageRef)) {
      final repo = await ref.read(eventsRepositoryProvider.future);
      await repo.deletePosterImage(removed.imageRef);
    }
    return saved;
  }

  /// Saves [content], reflecting it into state on success.
  Future<bool> _persist(EventsContent content) async {
    final repo = await ref.read(eventsRepositoryProvider.future);
    final result = await repo.save(content);
    return result.match((_) => false, (saved) {
      state = AsyncData(saved);
      return true;
    });
  }
}
