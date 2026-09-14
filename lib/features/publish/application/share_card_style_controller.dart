/// Share-card style controller (application layer, AGENTS.md §4).
///
/// Holds the user's chosen [ShareCardStyle] for the "share library card"
/// sheet and persists it through the domain store. The sheet watches this
/// so the live preview re-renders as the user taps swatches.
///
/// Why a controller and not `setState` in the sheet: the pick must survive
/// closing the sheet (it is remembered for next time) and the persistence
/// failure must be a typed `Either` the UI can report, not a swallowed bool.
library;

import 'package:fpdart/fpdart.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/publish/domain/share_card_style.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'share_card_style_controller.g.dart';

/// Loads and updates the remembered share-card style.
@riverpod
class ShareCardStyleController extends _$ShareCardStyleController {
  @override
  FutureOr<ShareCardStyle> build() async {
    final store = await ref.read(shareCardStyleStoreProvider.future);
    return store.load();
  }

  /// Selects [style]: the preview updates immediately (optimistic — a style
  /// is cosmetic, so showing it before the disk write lands is harmless),
  /// then the pick is persisted. A left means "the card will look right now
  /// but the choice may not be remembered"; the caller decides whether to
  /// mention it. Never throws for a failed write (§5).
  Future<Either<Failure, Unit>> select(ShareCardStyle style) async {
    state = AsyncData(style);
    final store = await ref.read(shareCardStyleStoreProvider.future);
    try {
      return await store.save(style);
    } on Object catch (e) {
      // `on Object`, like `SettingsController._update`: a plugin throw (even
      // an Error) from a fire-and-forget preference write must fold into a
      // typed failure, not surface as an unhandled async error mid-share.
      return left(StorageFailure('share card style save ($e)'));
    }
  }
}
