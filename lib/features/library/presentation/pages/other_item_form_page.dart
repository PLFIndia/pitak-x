/// Add / edit form for an **Other** item (presentation layer, AGENTS.md
/// §3.1; ADR 0013 O1, O3).
///
/// One screen for both modes: passed no item → "Add other item", passed a
/// [CatalogueItem] (an `other`-kind row) → "Edit item" (prefilled). The form
/// owns only view state (text controllers, dropdown selections); persistence
/// + validation go through [AddBookController] — which, despite the
/// historical name F7 kept, is the existing controller over the GENERIC
/// Add/UpdateCatalogueItemUseCase, exactly the save path O3 assigns to this
/// kind (a second controller with identical logic would violate "one blessed
/// way", AGENTS §0). On a successful save the page refreshes the library and
/// pops, the same division of labour as the book form.
///
/// N03: in edit mode the [CatalogueItem] passed in only PREFILLS the form. At
/// save time the controller re-reads the row and this form builds the new
/// value on top of that fresh row — fields the form does not edit (author,
/// ISBN, flags, attribution, uid) come from the database as it is now.
///
/// O1: an Other has no kind-specific fields. What the item *is* goes in the
/// shared `notes` column, labelled **Description** here ("Notes" on the book
/// form — same column, searchable per D10). The saved row always carries
/// `details: const OtherItemOf()` — the marker IS the kind (F5).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/library/application/add_book_controller.dart';
import 'package:pitaka/features/library/application/library_controller.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/presentation/catalogue_save_messages.dart';
import 'package:pitaka/features/library/presentation/widgets/form_cover_field.dart';
import 'package:pitaka/features/library/presentation/widgets/language_field.dart';
import 'package:pitaka/features/periodicals/presentation/widgets/form_rows.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

/// Form screen to add a new "other" item or edit an existing one.
class OtherItemFormPage extends ConsumerStatefulWidget {
  /// Creates the page. When [item] is non-null the form opens in edit mode
  /// (the row must be an `other`-kind one — the kind-aware Edit action in
  /// `catalogue_item_actions.dart` routes it here, ADR 0013 D8).
  const OtherItemFormPage({this.item, super.key});

  /// The item to edit, or null to add a new one.
  final CatalogueItem? item;

  @override
  ConsumerState<OtherItemFormPage> createState() => _OtherItemFormPageState();
}

class _OtherItemFormPageState extends ConsumerState<OtherItemFormPage> {
  late final TextEditingController _title;
  late final TextEditingController _transliteration;
  late final TextEditingController _language;
  late final TextEditingController _description;
  late final TextEditingController _location;
  late final TextEditingController _copies;
  late final TextEditingController _sourceDetail;

  ItemSourceType? _sourceType;
  AgeGroup? _ageGroup;
  late int _addedDate;
  bool _titleError = false;

  /// The cover reference the form currently holds (a stored
  /// `covers/<uuid>.jpg` from the form-cover pipeline, or the item's existing
  /// cover in edit mode). Null = no cover.
  String? _coverRef;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    final b = widget.item;
    _title = TextEditingController(text: b?.title ?? '');
    _transliteration = TextEditingController(text: b?.titleTransliteration);
    _language = TextEditingController(text: b?.language);
    _description = TextEditingController(text: b?.notes);
    _location = TextEditingController(text: b?.location);
    _copies = TextEditingController(text: (b?.copyCount ?? 1).toString());
    _sourceDetail = TextEditingController(text: b?.sourceDetail);
    _sourceType = b?.sourceType;
    _ageGroup = b?.ageGroup;
    _addedDate = b?.addedDate ?? DateTime.now().millisecondsSinceEpoch;
    _coverRef = b?.coverUrl;
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _transliteration,
      _language,
      _description,
      _location,
      _copies,
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

  /// The maintainer name from settings, or null when unset/blank. Only used
  /// to attribute newly-added rows (same rule as the book form).
  String? _maintainerStamp() {
    final name = ref
        .read(settingsControllerProvider)
        .maybeWhen(data: (s) => s.maintainerName, orElse: () => '')
        .trim();
    return name.isEmpty ? null : name;
  }

  /// Assembles the [CatalogueItem] to persist from the form fields, taking
  /// every field the form does not edit from [base]: null in add mode, the
  /// FRESH row in edit mode (N03). The gate (`CatalogueItem.validate` in the
  /// use cases) trims and rejects invalid values.
  CatalogueItem _buildItem(CatalogueItem? base, {String? maintainerStamp}) {
    final qty = int.tryParse(_copies.text.trim()) ?? 1;
    return CatalogueItem(
      // Preserve identity in edit mode; add mode uses the sentinel.
      id: base?.id ?? CatalogueItem.emptyId,
      itemUid: base?.itemUid,
      title: _title.text.trim(),
      titleTransliteration: _trimToNull(_transliteration),
      // Book-only fields pass through untouched (an Other has none of its
      // own; in add mode they are simply null).
      author: base?.author,
      isbn: base?.isbn,
      publisher: base?.publisher,
      publishedYear: base?.publishedYear,
      genre: base?.genre,
      pageCount: base?.pageCount,
      coverUrl: _coverRef,
      language: _trimToNull(_language),
      notes: _trimToNull(_description),
      location: _trimToNull(_location),
      sourceType: _sourceType,
      sourceDetail: _trimToNull(_sourceDetail),
      ageGroup: _ageGroup,
      addedDate: _addedDate,
      copyCount: qty < 1 ? 1 : qty,
      needsMetadata: base?.needsMetadata ?? false,
      removed: base?.removed ?? false,
      removedAt: base?.removedAt,
      // Stamp the maintainer name onto a NEW row that has none yet; edits
      // keep the existing value.
      addedBy: base?.addedBy ?? maintainerStamp,
      // O1/O3: the field-less marker, always — kind is derived from it (F5),
      // so an edit can never flip the row's kind (D8).
      details: const OtherItemOf(),
    );
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _titleError = true);
      return;
    }
    final controller = ref.read(addBookControllerProvider.notifier);
    final stamp = _maintainerStamp();
    final editing = widget.item;
    if (editing == null) {
      await controller.save(_buildItem(null, maintainerStamp: stamp));
    } else {
      // The controller re-reads the row and calls back with it; the form
      // fields win, everything else is the row as it is NOW.
      await controller.saveEdit(
        editing.id,
        (current) => _buildItem(current, maintainerStamp: stamp),
      );
    }
    final state = ref.read(addBookControllerProvider);
    if (!mounted) return;
    if (state.hasValue && state.value != null) {
      await ref.read(libraryControllerProvider.notifier).refresh();
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addBookControllerProvider);
    final saving = state.isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit item' : 'Add other item')),
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
          FormTextRow(
            controller: _transliteration,
            label: 'Title (transliteration)',
          ),
          // Session 33 dropdown-of-known-languages + "Other…" (shared by
          // every form since S16).
          LanguageField(controller: _language),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FormCoverField(
              title: _title.text,
              coverRef: _coverRef,
              onChanged: (ref) => setState(() => _coverRef = ref),
            ),
          ),
          // O1: what the item IS goes here — the shared notes column,
          // relabelled for this kind.
          FormTextRow(
            controller: _description,
            label: 'Description',
            maxLines: 4,
          ),
          FormTextRow(controller: _location, label: 'Shelf location'),
          FormTextRow(
            controller: _copies,
            label: 'Copies',
            keyboardType: TextInputType.number,
            digitsOnly: true,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ItemSourceType?>(
            initialValue: _sourceType,
            decoration: const InputDecoration(
              labelText: 'Source',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(child: Text('Not set')),
              for (final t in ItemSourceType.values)
                DropdownMenuItem(value: t, child: Text(_sourceLabel(t))),
            ],
            onChanged: (v) => setState(() => _sourceType = v),
          ),
          const SizedBox(height: 12),
          FormTextRow(controller: _sourceDetail, label: 'Source detail'),
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
                Text(formatInstantFormDate(_addedDate) ?? ''),
                TextButton(
                  onPressed: () async {
                    final picked = await pickInstantFormDate(
                      context,
                      current: _addedDate,
                      helpText: 'Date added',
                    );
                    if (picked != null) setState(() => _addedDate = picked);
                  },
                  child: const Text('Change'),
                ),
              ],
            ),
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
                : Text(_isEdit ? 'Save changes' : 'Add item'),
          ),
          if (state.hasError) ...[
            const SizedBox(height: 12),
            Text(
              catalogueSaveMessage(state.error!, noun: 'item'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  static String _sourceLabel(ItemSourceType t) => switch (t) {
    ItemSourceType.purchased => 'Purchased',
    ItemSourceType.gift => 'Gift',
    ItemSourceType.donated => 'Donated',
    ItemSourceType.inherited => 'Inherited',
    ItemSourceType.other => 'Other',
  };

  static String _ageGroupLabel(AgeGroup g) => switch (g) {
    AgeGroup.above3 => 'Ages 3+',
    AgeGroup.above6 => 'Ages 6+',
    AgeGroup.above10 => 'Ages 10+',
    AgeGroup.above15 => 'Ages 15+',
    AgeGroup.advanced => 'Advanced',
  };
}
