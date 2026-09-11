/// Add / edit wishlist entry form (presentation layer, AGENTS.md §3.1).
///
/// One screen for both modes: no book → "Add", a [WishlistBook] → "Edit"
/// (prefilled). View state only; persistence + validation go through
/// [AddWishlistController]. On success it refreshes the list and pops.
///
/// N03: in edit mode the entry passed in only PREFILLS the form. At save time
/// the controller re-reads the row and this form builds the new value on top
/// of that fresh row — fields the form does not edit (cover, purchased state,
/// source, added date) come from the database as it is now.
///
/// ISBN entry supports a barcode scan (#29) and a metadata lookup (#30),
/// reusing the same Open Library -> Google Books chain as the library form; a
/// successful lookup prefills EMPTY fields only (never overwrites the user's).
/// `addedDate` is immutable on edit (Kotlin D30 mirror), so the form does not
/// expose it for edits.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/lookup/domain/entities/book_metadata.dart';
import 'package:pitaka/features/lookup/domain/isbn_format.dart';
import 'package:pitaka/features/lookup/domain/lookup_result.dart';
import 'package:pitaka/features/lookup/presentation/pages/scanner_page.dart';
import 'package:pitaka/features/publish/domain/cover_url_allow_list.dart';
import 'package:pitaka/features/wishlist/application/add_wishlist_controller.dart';
import 'package:pitaka/features/wishlist/application/wishlist_controller.dart';
import 'package:pitaka/features/wishlist/domain/entities/wishlist_book.dart';

/// Form screen to add or edit a wishlist entry.
class AddWishlistPage extends ConsumerStatefulWidget {
  /// Creates the page. When [book] is non-null the form opens in edit mode.
  const AddWishlistPage({this.book, super.key});

  /// The entry to edit, or null to add a new one.
  final WishlistBook? book;

  @override
  ConsumerState<AddWishlistPage> createState() => _AddWishlistPageState();
}

class _AddWishlistPageState extends ConsumerState<AddWishlistPage> {
  late final TextEditingController _title;
  late final TextEditingController _author;
  late final TextEditingController _isbn;
  late final TextEditingController _publisher;
  late final TextEditingController _year;
  late final TextEditingController _price;
  late final TextEditingController _notes;

  int _priority = WishlistBook.priorityMed;
  bool _titleError = false;

  /// N02: the cover URL a successful lookup returned, kept ONLY when it
  /// passes the publish allow-list. An existing cover on the entry wins.
  String? _lookupCoverUrl;

  /// N02: user-editable "needs metadata" flag (a lookup clears it).
  late bool _needsMetadata;

  bool get _isEdit => widget.book != null;

  @override
  void initState() {
    super.initState();
    final b = widget.book;
    _title = TextEditingController(text: b?.title ?? '');
    _author = TextEditingController(text: b?.author);
    _isbn = TextEditingController(text: b?.isbn);
    _publisher = TextEditingController(text: b?.publisher);
    _year = TextEditingController(text: b?.publishedYear?.toString());
    _price = TextEditingController(text: b?.priceEstimate?.toString());
    _notes = TextEditingController(text: b?.notes);
    _priority = b?.priority ?? WishlistBook.priorityMed;
    _needsMetadata = b?.needsMetadata ?? false;
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _author,
      _isbn,
      _publisher,
      _year,
      _price,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _trimToNull(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  bool _looking = false;

  /// Opens the barcode scanner; on a successful scan fills ONLY the ISBN field.
  /// The user then taps Lookup explicitly — scanning never calls the network.
  Future<void> _scanIsbn() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const ScannerPage()),
    );
    if (scanned == null || !mounted) return;
    setState(() => _isbn.text = IsbnFormat.normalize(scanned));
  }

  /// Looks up the current ISBN and prefills EMPTY fields from the result.
  Future<void> _lookupIsbn() async {
    final normalized = IsbnFormat.normalize(_isbn.text);
    if (normalized.isEmpty) return;
    if (!IsbnFormat.isValid(normalized)) {
      _snack('That does not look like a valid ISBN.');
      return;
    }
    setState(() => _looking = true);
    final result = await ref
        .read(isbnLookupServiceProvider)
        .lookupByIsbn(normalized);
    if (!mounted) return;
    setState(() => _looking = false);
    switch (result) {
      case LookupFound(:final metadata):
        _applyMetadata(metadata);
        _snack('Details filled in from the lookup.');
      case LookupNotFound():
        _snack('No details found for that ISBN.');
      case LookupNetworkError():
        _snack('Could not reach the lookup service. Check your connection.');
    }
  }

  /// Fills only empty fields from [m] (user-entered values win). The wishlist
  /// form has a subset of Book's fields; lookup-only extras are ignored.
  ///
  /// N02: keeps the lookup's cover URL when it passes [CoverUrlAllowList]
  /// (https + fixed host set — a poisoned lookup cannot plant a beacon
  /// host) and clears the "needs metadata" flag the lookup just completed.
  void _applyMetadata(BookMetadata m) {
    void fillIfEmpty(TextEditingController c, String? value) {
      if (value != null && value.trim().isNotEmpty && c.text.trim().isEmpty) {
        c.text = value.trim();
      }
    }

    setState(() {
      fillIfEmpty(_title, m.title);
      fillIfEmpty(_author, m.author);
      fillIfEmpty(_publisher, m.publisher);
      fillIfEmpty(_year, m.publishedYear?.toString());
      final safeCover = CoverUrlAllowList.sanitize(m.coverUrl);
      if (safeCover != null) _lookupCoverUrl = safeCover;
      _needsMetadata = false;
      if (_titleError && _title.text.trim().isNotEmpty) _titleError = false;
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Assembles the entry to persist from the form fields, taking every field
  /// the form does not edit from [base]: null in add mode, the FRESH row in
  /// edit mode (N03).
  WishlistBook _build(WishlistBook? base) {
    return WishlistBook(
      id: base?.id ?? WishlistBook.emptyId,
      title: _title.text.trim(),
      titleTransliteration: base?.titleTransliteration,
      author: _trimToNull(_author),
      isbn: _trimToNull(_isbn),
      publisher: _trimToNull(_publisher),
      publishedYear: int.tryParse(_year.text.trim()),
      // N02: an existing cover wins; otherwise the validated lookup cover.
      coverUrl: (base?.coverUrl?.trim().isNotEmpty ?? false)
          ? base!.coverUrl
          : _lookupCoverUrl,
      priceEstimate: double.tryParse(_price.text.trim()),
      priority: _priority,
      notes: _trimToNull(_notes),
      source: base?.source ?? WishlistSource.manual,
      // addedDate is immutable on edit; new rows get "now".
      addedDate: base?.addedDate ?? DateTime.now().millisecondsSinceEpoch,
      purchased: base?.purchased ?? false,
      purchasedDate: base?.purchasedDate,
      needsMetadata: _needsMetadata,
    );
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _titleError = true);
      return;
    }
    final controller = ref.read(addWishlistControllerProvider.notifier);
    final editing = widget.book;
    if (editing == null) {
      await controller.save(_build(null));
    } else {
      // The controller re-reads the row and calls back with it; the form
      // fields win, everything else is the row as it is NOW.
      await controller.saveEdit(editing.id, _build);
    }
    final state = ref.read(addWishlistControllerProvider);
    if (!mounted) return;
    if (state.hasValue && state.value != null) {
      await ref.read(wishlistControllerProvider.notifier).refresh();
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addWishlistControllerProvider);
    final saving = state.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit wishlist item' : 'Add to wishlist'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: InputDecoration(
              labelText: 'Title *',
              border: const OutlineInputBorder(),
              errorText: _titleError ? 'A title is required.' : null,
            ),
            onChanged: (_) {
              if (_titleError) setState(() => _titleError = false);
            },
          ),
          const SizedBox(height: 12),
          _field(_author, 'Author'),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _isbn,
                    decoration: const InputDecoration(
                      labelText: 'ISBN',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Scan barcode',
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: _looking ? null : _scanIsbn,
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: 'Look up details',
                  icon: _looking
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  onPressed: _looking ? null : _lookupIsbn,
                ),
              ],
            ),
          ),
          _field(_publisher, 'Publisher'),
          _field(
            _year,
            'Published year',
            keyboardType: TextInputType.number,
            digitsOnly: true,
          ),
          _field(
            _price,
            'Price estimate',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 4),
          DropdownButtonFormField<int>(
            initialValue: _priority,
            decoration: const InputDecoration(
              labelText: 'Priority',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: WishlistBook.priorityLow,
                child: Text('Low'),
              ),
              DropdownMenuItem(
                value: WishlistBook.priorityMed,
                child: Text('Medium'),
              ),
              DropdownMenuItem(
                value: WishlistBook.priorityHigh,
                child: Text('High'),
              ),
            ],
            onChanged: (v) =>
                setState(() => _priority = v ?? WishlistBook.priorityMed),
          ),
          const SizedBox(height: 12),
          _field(_notes, 'Notes', maxLines: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Metadata incomplete'),
            subtitle: const Text(
              'On while this entry still needs details. A successful lookup '
              'clears it; turn it back on any time.',
            ),
            value: _needsMetadata,
            onChanged: (v) => setState(() => _needsMetadata = v),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: saving ? null : _save,
            child: saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEdit ? 'Save changes' : 'Add'),
          ),
          if (state.hasError) ...[
            const SizedBox(height: 12),
            Text(
              _messageFor(state.error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    bool digitsOnly = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        inputFormatters: digitsOnly
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  static String _messageFor(Object error) {
    if (error is ValidationFailure) return error.message;
    if (error is NotFoundFailure) {
      return 'This entry no longer exists and could not be saved.';
    }
    return 'Could not save the entry. Please try again.';
  }
}
