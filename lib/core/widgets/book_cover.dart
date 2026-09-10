/// Shared book-cover widget (presentation, AGENTS.md §3.1).
///
/// Renders a LOCAL cover (`covers/<uuid>.jpg` or legacy `file://`) from app
/// storage via `Image.file`, falling back to an initial-letter placeholder when
/// there is no cover or the file is missing.
///
/// **Display is local-only (M09).** A remote `https://` cover reference is a
/// *pending download*, never an image this widget streams from the network.
/// When such a reference is on an allow-listed host (`CoverUrlAllowList`) and
/// the caller supplied the book's id, the widget asks the session-wide
/// `RemoteCoverMaterializer` — once, after the frame — to download it. That
/// scheduler holds the consent gate (the Settings "Load cover images from the
/// internet" switch, default off), the once-per-book rule and the bounded
/// fetch; on success the book's row is rewritten to a local file and the list
/// refreshes, so this widget then renders it like any photo cover. Anything
/// not allow-listed (any other host, `http://`) shows the placeholder and is
/// never requested.
///
/// **Consent turning on re-asks (Session 13, device-found).** The request is
/// made from lifecycle hooks, and a request made while consent was off is
/// dropped by the scheduler without a trace. When the user flips the Settings
/// switch, the list underneath the Settings route stays mounted — rows are
/// neither re-created nor given a different book — so nothing asked again and
/// the switch looked broken until a book was opened or the app restarted.
/// Each cover therefore also listens to the consent bit and asks once more on
/// the OFF→ON edge; the scheduler's once-per-book rule keeps that at a single
/// download.
///
/// Cover classification + safe leaf extraction reuse [CoverPaths] (the single
/// source of truth, with zip-slip / traversal defence), so this widget does no
/// path parsing of its own.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/import_export/domain/cover_paths.dart';
import 'package:pitaka/features/library/application/remote_cover_materializer.dart';
import 'package:pitaka/features/publish/domain/cover_url_allow_list.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

/// A book cover thumbnail with a graceful initial-letter fallback.
class BookCover extends ConsumerStatefulWidget {
  /// Creates a cover for [title], rendering [coverUrl] when it is a local file.
  ///
  /// [bookId] lets an allow-listed remote cover be materialised for that row;
  /// without it a remote reference simply shows the placeholder.
  const BookCover({
    required this.title,
    required this.coverUrl,
    this.bookId,
    this.width = 40,
    this.height = 56,
    super.key,
  });

  /// Book title — its first character is the placeholder glyph.
  final String title;

  /// Cover reference (`covers/<uuid>.jpg`, `file://…`, `https://…`, or null).
  final String? coverUrl;

  /// Persisted id of the book this cover belongs to (null when unknown, e.g.
  /// a not-yet-saved form preview).
  final int? bookId;

  /// Thumbnail width.
  final double width;

  /// Thumbnail height.
  final double height;

  @override
  ConsumerState<BookCover> createState() => _BookCoverState();
}

class _BookCoverState extends ConsumerState<BookCover> {
  /// Consent-bit subscription; present only while this cover is a pending
  /// (fetchable) download. Closed automatically on unmount by flutter_riverpod
  /// (`ConsumerStatefulElement.unmount`, 2.6.1) — and explicitly when the row
  /// is recycled for a book that has nothing to fetch.
  ProviderSubscription<bool?>? _consentSubscription;

  @override
  void initState() {
    super.initState();
    _syncPendingDownload();
  }

  @override
  void didUpdateWidget(BookCover old) {
    super.didUpdateWidget(old);
    // A list row is recycled for a different book: ask again for the new one.
    if (old.coverUrl != widget.coverUrl || old.bookId != widget.bookId) {
      _syncPendingDownload();
    }
  }

  /// The book id whose cover is a fetchable remote reference, or null when
  /// there is nothing to download (blank, local file, unsafe host, no id).
  int? get _pendingBookId {
    final id = widget.bookId;
    if (id == null) return null;
    if (CoverUrlAllowList.remoteHttpsOf(widget.coverUrl) == null) return null;
    return id;
  }

  /// Asks the scheduler for a fetchable cover and keeps (or drops) the
  /// consent subscription to match. Only fetchable covers touch Riverpod at
  /// all, so a plain local/blank cover can render without a ProviderScope
  /// and the ordinary row pays nothing for this.
  void _syncPendingDownload() {
    final id = _pendingBookId;
    if (id == null) {
      _consentSubscription?.close();
      _consentSubscription = null;
      return;
    }
    _requestMaterialization(id);
    // `listenManual` is the initState-safe listener. Narrowed with `select` so
    // unrelated settings writes (theme, sort, …) never reach this callback;
    // `null` = settings unknown/loading, so only a real false→true flip
    // re-asks. One subscription per State — re-syncs for a recycled row
    // reuse it; the callback reads the CURRENT widget's pending id.
    _consentSubscription ??= ref.listenManual(
      settingsControllerProvider.select((s) => s.valueOrNull?.loadRemoteCovers),
      (previous, next) {
        if ((previous, next) case (false, true)) {
          final current = _pendingBookId;
          if (current != null) _requestMaterialization(current);
        }
      },
    );
  }

  /// Side effects stay out of `build` (§7): the request is scheduled once per
  /// (bookId, coverUrl) from a lifecycle hook, after the frame, so a rebuild
  /// storm cannot turn into a request storm. The scheduler dedups as well.
  void _requestMaterialization(int id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(remoteCoverMaterializerProvider.notifier).request(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final leaf = CoverPaths.leafOf(widget.coverUrl);
    if (leaf == null) {
      // Not a local cover: blank, remote (pending download), or unsafe.
      return _placeholder();
    }

    // Resolve `<coversDir>/<leaf>` once we know the dir; show the placeholder
    // while resolving or if the file is absent/unreadable.
    final coversAsync = ref.watch(coversDirProvider);
    return coversAsync.maybeWhen(
      data: (coversDir) {
        final file = File(p.join(coversDir, leaf));
        if (!file.existsSync()) return _placeholder();
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            file,
            width: widget.width,
            height: widget.height,
            fit: BoxFit.cover,
            // A corrupt/partial file must never crash the list.
            errorBuilder: (_, _, _) => _placeholder(),
          ),
        );
      },
      orElse: _placeholder,
    );
  }

  Widget _placeholder() => _Placeholder(
    title: widget.title,
    width: widget.width,
    height: widget.height,
  );
}

/// Initial-letter placeholder shown when no local cover renders.
class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.title,
    required this.width,
    required this.height,
  });

  final String title;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = title.trim().isEmpty
        ? '?'
        : title.trim().characters.first.toUpperCase();
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        initial,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
