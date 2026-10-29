/// "My library card" state (network application layer, AGENTS.md §4).
///
/// The card is what another library scans to add me as a member (§5.8): the
/// site URL + a fragment carrying my FINGERPRINT (never the raw ID, D3) and
/// display name. It exists only once two things are true:
///  - the catalogue has been published at least once (`publishedSiteUrl`),
///    because the card QR IS the site URL — with no site there is nothing to
///    scan somebody to;
///  - the library identity is available (read through its single owner, N07).
///
/// `AsyncValue<LibraryCard?>`: null (with no error) means "not available
/// yet" and the My-card tab explains what to do first.
library;

import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/network/application/build_own_descriptor.dart';
import 'package:pitaka/features/network/domain/value_objects/library_card_payload.dart';
import 'package:pitaka/features/network/domain/value_objects/library_fingerprint.dart';
import 'package:pitaka/features/network/domain/value_objects/network_name.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'my_library_card_controller.g.dart';

/// Builds this device's [LibraryCard] from identity + published site URL.
@riverpod
class MyLibraryCardController extends _$MyLibraryCardController {
  @override
  FutureOr<LibraryCard?> build() async {
    // Watched, so the card updates when a publish lands or the name changes.
    final siteUrl = await ref.watch(publishedSiteUrlProvider.future);
    if (siteUrl == null) return null; // never published yet
    // Watched so the card follows a name change, never awaited: a failed
    // settings SAVE must not break the card (fix-plan M8).
    ref.watch(settingsControllerProvider);
    // Identity through the LibraryNamespace owner (N07): current() mints the
    // ID on first use and returns a Left if that fails — no card then.
    final identity = await ref
        .read(settingsControllerProvider.notifier)
        .current();
    final own = identity.toNullable();
    if (own == null) return null;
    final fingerprint = LibraryFingerprint.of(own.id);
    if (fingerprint == null) return null;
    // Same name rule as the published descriptor (§5.5): an unusable name
    // falls back rather than producing a card nobody recognises.
    return LibraryCard.tryCreate(
      siteUrl: siteUrl,
      fingerprint: fingerprint,
      name:
          NetworkName.normalizeOrNull(own.name) ??
          BuildOwnDescriptor.fallbackName,
    );
  }
}
