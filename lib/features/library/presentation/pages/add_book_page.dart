/// Add / edit book form (presentation layer, AGENTS.md §3.1).
///
/// One screen for both modes: passed no book → "Add", passed a [Book] →
/// "Edit" (prefilled). The form owns only view state (text controllers,
/// dropdown selections); all persistence + validation goes through
/// [AddBookController]. On a successful save it pops and the caller refreshes
/// the library.
///
/// ISBN entry supports a barcode scan (#29) and a metadata lookup (#30):
/// Open Library → Google Books, chained over a cache. A successful lookup
/// prefills empty fields (never overwrites what the user already typed).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/library/application/add_book_controller.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/book.dart';
import 'package:pitaka/features/lookup/domain/entities/book_metadata.dart';
import 'package:pitaka/features/lookup/domain/isbn_format.dart';
import 'package:pitaka/features/lookup/domain/lookup_result.dart';
import 'package:pitaka/features/lookup/presentation/pages/scanner_page.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

/// Form screen to add a new book or edit an existing one.
class AddBookPage extends ConsumerStatefulWidget {
  /// Creates the page. When [book] is non-null the form opens in edit mode.
  /// [initialIsbn] pre-fills the ISBN field for the quick-add-by-scan flow
  /// (add mode only); the user still taps Lookup explicitly.
  const AddBookPage({this.book, this.initialIsbn, super.key});

  /// The book to edit, or null to add a new one.
  final Book? book;

  /// Optional ISBN to pre-fill in add mode (from a barcode scan).
  final String? initialIsbn;

  @override
  ConsumerState<AddBookPage> createState() => _AddBookPageState();
}

class _AddBookPageState extends ConsumerState<AddBookPage> {
  late final TextEditingController _title;
  late final TextEditingController _transliteration;
  late final TextEditingController _author;
  late final TextEditingController _isbn;
  late final TextEditingController _publisher;
  late final TextEditingController _year;
  late final TextEditingController _genre;
  late final TextEditingController _language;
  late final TextEditingController _pages;
  late final TextEditingController _notes;
  late final TextEditingController _location;
  late final TextEditingController _quantity;
  late final TextEditingController _sourceDetail;

  BookSourceType? _sourceType;
  AgeGroup? _ageGroup;
  late int _addedDate;
  bool _titleError = false;

  bool get _isEdit => widget.book != null;

  @override
  void initState() {
    super.initState();
    final b = widget.book;
    _title = TextEditingController(text: b?.title ?? '');
    _transliteration = TextEditingController(text: b?.titleTransliteration);
    _author = TextEditingController(text: b?.author);
    _isbn = TextEditingController(text: b?.isbn ?? widget.initialIsbn);
    _publisher = TextEditingController(text: b?.publisher);
    _year = TextEditingController(text: b?.publishedYear?.toString());
    _genre = TextEditingController(text: b?.genre);
    _language = TextEditingController(text: b?.language);
    _pages = TextEditingController(text: b?.pageCount?.toString());
    _notes = TextEditingController(text: b?.notes);
    _location = TextEditingController(text: b?.location);
    _quantity = TextEditingController(text: (b?.copyCount ?? 1).toString());
    _sourceDetail = TextEditingController(text: b?.sourceDetail);
    _sourceType = b?.sourceType;
    _ageGroup = b?.ageGroup;
    _addedDate = b?.addedDate ?? DateTime.now().millisecondsSinceEpoch;
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _transliteration,
      _author,
      _isbn,
      _publisher,
      _year,
      _genre,
      _language,
      _pages,
      _notes,
      _location,
      _quantity,
      _sourceDetail,
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
  /// The user then taps Lookup explicitly to make the network call — scanning
  /// never triggers a lookup or save on its own.
  Future<void> _scanIsbn() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const ScannerPage()),
    );
    if (scanned == null || !mounted) return;
    setState(() => _isbn.text = IsbnFormat.normalize(scanned));
  }

  /// Looks up the current ISBN and prefills EMPTY fields from the result.
  /// Never overwrites a field the user already filled in.
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

  /// Fills only empty fields from [m] (user-entered values win).
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
      fillIfEmpty(_genre, m.genre);
      fillIfEmpty(_language, m.language);
      fillIfEmpty(_pages, m.pageCount?.toString());
      if (_titleError && _title.text.trim().isNotEmpty) _titleError = false;
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Book _buildBook() {
    final base = widget.book;
    final qty = int.tryParse(_quantity.text.trim()) ?? 1;
    return Book(
      // Preserve identity in edit mode; add mode uses the sentinel.
      id: base?.id ?? Book.emptyId,
      bookUid: base?.bookUid,
      title: _title.text.trim(),
      titleTransliteration: _trimToNull(_transliteration),
      author: _trimToNull(_author),
      isbn: _trimToNull(_isbn),
      publisher: _trimToNull(_publisher),
      publishedYear: int.tryParse(_year.text.trim()),
      genre: _trimToNull(_genre),
      coverUrl: base?.coverUrl,
      pageCount: int.tryParse(_pages.text.trim()),
      language: _trimToNull(_language),
      notes: _trimToNull(_notes),
      location: _trimToNull(_location),
      sourceType: _sourceType,
      sourceDetail: _trimToNull(_sourceDetail),
      ageGroup: _ageGroup,
      addedDate: _addedDate,
      copyCount: qty < 1 ? 1 : qty,
      needsMetadata: base?.needsMetadata ?? false,
      removed: base?.removed ?? false,
      removedAt: base?.removedAt,
      // Stamp the maintainer name onto a NEW book that has none yet (mirrors
      // Kotlin AddBookUseCase's attribution); edits keep the existing value.
      addedBy: base?.addedBy ?? _maintainerStamp(),
    );
  }

  /// The maintainer name from settings, or null when unset/blank. Only used to
  /// attribute newly-added books.
  String? _maintainerStamp() {
    final name = ref
        .read(settingsControllerProvider)
        .maybeWhen(data: (s) => s.maintainerName, orElse: () => '')
        .trim();
    return name.isEmpty ? null : name;
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _titleError = true);
      return;
    }
    await ref.read(addBookControllerProvider.notifier).save(_buildBook());
    final state = ref.read(addBookControllerProvider);
    if (!mounted) return;
    if (state.hasValue && state.value != null) {
      await ref.read(libraryControllerProvider.notifier).refresh();
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _pickDate() async {
    final initial = DateTime.fromMillisecondsSinceEpoch(_addedDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _addedDate = picked.millisecondsSinceEpoch);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addBookControllerProvider);
    final saving = state.isLoading;
    final dateLabel = _formatDate(_addedDate);

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit book' : 'Add book')),
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
          _field(_transliteration, 'Title (transliteration)'),
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
          _field(_genre, 'Genre'),
          _field(_language, 'Language'),
          _field(
            _pages,
            'Pages',
            keyboardType: TextInputType.number,
            digitsOnly: true,
          ),
          _field(_location, 'Shelf location'),
          _field(
            _quantity,
            'Quantity',
            keyboardType: TextInputType.number,
            digitsOnly: true,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<BookSourceType?>(
            initialValue: _sourceType,
            decoration: const InputDecoration(
              labelText: 'Source',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(child: Text('Not set')),
              for (final t in BookSourceType.values)
                DropdownMenuItem(value: t, child: Text(_sourceLabel(t))),
            ],
            onChanged: (v) => setState(() => _sourceType = v),
          ),
          const SizedBox(height: 12),
          _field(_sourceDetail, 'Source detail'),
          DropdownButtonFormField<AgeGroup?>(
            initialValue: _ageGroup,
            decoration: const InputDecoration(
              labelText: 'Age group',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(child: Text('Not set')),
              for (final g in AgeGroup.values)
                DropdownMenuItem(value: g, child: Text(_ageGroupLabel(g))),
            ],
            onChanged: (v) => setState(() => _ageGroup = v),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Date added',
              border: OutlineInputBorder(),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(dateLabel),
                TextButton(onPressed: _pickDate, child: const Text('Change')),
              ],
            ),
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
                : Text(_isEdit ? 'Save changes' : 'Add book'),
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

  static String _sourceLabel(BookSourceType t) => switch (t) {
    BookSourceType.purchased => 'Purchased',
    BookSourceType.gift => 'Gift',
    BookSourceType.donated => 'Donated',
    BookSourceType.inherited => 'Inherited',
    BookSourceType.other => 'Other',
  };

  static String _ageGroupLabel(AgeGroup g) => switch (g) {
    AgeGroup.above3 => 'Ages 3+',
    AgeGroup.above6 => 'Ages 6+',
    AgeGroup.above10 => 'Ages 10+',
    AgeGroup.above15 => 'Ages 15+',
    AgeGroup.advanced => 'Advanced',
  };

  static String _formatDate(int epochMillis) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMillis).toLocal();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  static String _messageFor(Object error) {
    if (error is ValidationFailure) return error.message;
    if (error is NotFoundFailure) {
      return 'This book no longer exists and could not be saved.';
    }
    return 'Could not save the book. Please try again.';
  }
}
