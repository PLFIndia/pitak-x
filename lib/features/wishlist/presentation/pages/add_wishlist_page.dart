/// Add / edit wishlist entry form (presentation layer, AGENTS.md §3.1).
///
/// One screen for both modes: no book → "Add", a [WishlistBook] → "Edit"
/// (prefilled). View state only; persistence + validation go through
/// [AddWishlistController]. On success it pops and the list refreshes.
///
/// Deferred (PLAN Step 14): ISBN lookup, cover pick. `addedDate` is immutable
/// on edit (Kotlin D30 mirror), so the form does not expose it for edits.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/error/failure.dart';
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

  WishlistBook _build() {
    final base = widget.book;
    return WishlistBook(
      id: base?.id ?? WishlistBook.emptyId,
      title: _title.text.trim(),
      titleTransliteration: base?.titleTransliteration,
      author: _trimToNull(_author),
      isbn: _trimToNull(_isbn),
      publisher: _trimToNull(_publisher),
      publishedYear: int.tryParse(_year.text.trim()),
      coverUrl: base?.coverUrl,
      priceEstimate: double.tryParse(_price.text.trim()),
      priority: _priority,
      notes: _trimToNull(_notes),
      source: base?.source ?? WishlistSource.manual,
      // addedDate is immutable on edit; new rows get "now".
      addedDate: base?.addedDate ?? DateTime.now().millisecondsSinceEpoch,
      purchased: base?.purchased ?? false,
      purchasedDate: base?.purchasedDate,
      needsMetadata: base?.needsMetadata ?? false,
    );
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _titleError = true);
      return;
    }
    await ref.read(addWishlistControllerProvider.notifier).save(_build());
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
          _field(_isbn, 'ISBN'),
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
