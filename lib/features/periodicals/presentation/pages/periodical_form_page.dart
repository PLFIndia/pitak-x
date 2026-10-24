/// Add / edit magazine-title form (periodicals presentation layer,
/// AGENTS.md §3.1; ADR 0013 D2, D7).
///
/// One screen for both modes: passed no series → "New magazine title",
/// passed a [Periodical] → "Edit" (prefilled). The form owns only view state
/// (text controllers, dropdown selections, the tracked-subscription switch);
/// all persistence + validation goes through [PeriodicalFormController]. On
/// a successful save the controller fires both mutation signals itself, so
/// the page just pops.
///
/// N03: in edit mode the [Periodical] passed in only PREFILLS the form. At
/// save time the controller re-reads the row and this form builds the new
/// value on top of that fresh row — fields the form does not edit (removed
/// flag, attribution, uid) come from the database as it is now.
///
/// The ISSN is validated inline (structure + check digit via `Issn`) and
/// again at the gate (`Periodical.validate`, which also canonicalises it);
/// a duplicate surfaces as the typed `DuplicateIssnFailure` wording.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/calendar_date.dart';
import 'package:pitaka/features/library/presentation/catalogue_save_messages.dart';
import 'package:pitaka/features/library/presentation/widgets/form_cover_field.dart';
import 'package:pitaka/features/library/presentation/widgets/language_field.dart';
import 'package:pitaka/features/periodicals/application/periodical_form_controller.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/issn.dart';
import 'package:pitaka/features/periodicals/domain/value_objects/periodical_frequency.dart';
import 'package:pitaka/features/periodicals/presentation/widgets/form_rows.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

/// Form screen to add a new magazine title or edit an existing one.
class PeriodicalFormPage extends ConsumerStatefulWidget {
  /// Creates the page. When [periodical] is non-null the form opens in edit
  /// mode. [initialIssn] pre-fills the ISSN field for the scanned-ISSN route
  /// (ADR 0013 D11, add mode only).
  const PeriodicalFormPage({this.periodical, this.initialIssn, super.key});

  /// The series to edit, or null to add a new one.
  final Periodical? periodical;

  /// Optional canonical ISSN to pre-fill in add mode (from a barcode scan).
  final String? initialIssn;

  @override
  ConsumerState<PeriodicalFormPage> createState() => _PeriodicalFormPageState();
}

class _PeriodicalFormPageState extends ConsumerState<PeriodicalFormPage> {
  late final TextEditingController _title;
  late final TextEditingController _transliteration;
  late final TextEditingController _issn;
  late final TextEditingController _publisher;
  late final TextEditingController _language;
  late final TextEditingController _notes;
  late final TextEditingController _location;
  late final TextEditingController _sourceDetail;

  ItemSourceType? _sourceType;
  AgeGroup? _ageGroup;
  PeriodicalFrequency? _frequency;
  late int _addedDate;
  bool _titleError = false;

  /// The cover reference the form currently holds (a stored
  /// `covers/<uuid>.jpg` from the form-cover pipeline, or the series'
  /// existing cover in edit mode). Null = no cover.
  String? _coverRef;

  /// D5: a subscription is "tracked" exactly when it has an end date. The
  /// switch drives that: on = both dates are picked and saved; off = the
  /// saved window is null. The picked values are KEPT in state while off, so
  /// an accidental toggle does not erase them.
  late bool _trackSubscription;
  int? _subscriptionStart;
  int? _subscriptionEnd;

  bool get _isEdit => widget.periodical != null;

  @override
  void initState() {
    super.initState();
    final p = widget.periodical;
    _title = TextEditingController(text: p?.title ?? '');
    _transliteration = TextEditingController(text: p?.titleTransliteration);
    _issn = TextEditingController(text: p?.issn ?? widget.initialIssn);
    _publisher = TextEditingController(text: p?.publisher);
    _language = TextEditingController(text: p?.language);
    _notes = TextEditingController(text: p?.notes);
    _location = TextEditingController(text: p?.location);
    _sourceDetail = TextEditingController(text: p?.sourceDetail);
    _sourceType = p?.sourceType;
    _ageGroup = p?.ageGroup;
    _frequency = p?.frequency;
    _addedDate = p?.addedDate ?? DateTime.now().millisecondsSinceEpoch;
    _coverRef = p?.coverUrl;
    _subscriptionStart = p?.subscriptionStart;
    _subscriptionEnd = p?.subscriptionEnd;
    _trackSubscription = p?.subscriptionEnd != null;
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _transliteration,
      _issn,
      _publisher,
      _language,
      _notes,
      _location,
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

  /// Live ISSN check (D7): blank is fine (no ISSN recorded); anything else
  /// must be structurally valid. The gate re-checks and canonicalises on
  /// save — this error only saves the user a round trip.
  bool get _issnInvalid {
    final raw = _issn.text.trim();
    return raw.isNotEmpty && !Issn.isValid(raw);
  }

  /// The maintainer name from settings, or null when unset/blank. Only used
  /// to attribute newly-added titles (mirrors the book form).
  String? _maintainerStamp() {
    final name = ref
        .read(settingsControllerProvider)
        .maybeWhen(data: (s) => s.maintainerName, orElse: () => '')
        .trim();
    return name.isEmpty ? null : name;
  }

  /// Assembles the entity to persist from the form fields, taking every
  /// field the form does not edit from [base]: null in add mode, the FRESH
  /// row in edit mode (N03). The gate (`Periodical.validate` in the use
  /// cases) trims, canonicalises the ISSN and rejects invalid values.
  Periodical _buildPeriodical(Periodical? base, {String? maintainerStamp}) {
    return Periodical(
      // Preserve identity in edit mode; add mode uses the sentinel.
      id: base?.id ?? Periodical.emptyId,
      periodicalUid: base?.periodicalUid,
      title: _title.text.trim(),
      titleTransliteration: _trimToNull(_transliteration),
      issn: _trimToNull(_issn),
      publisher: _trimToNull(_publisher),
      language: _trimToNull(_language),
      coverUrl: _coverRef,
      frequency: _frequency,
      subscriptionStart: _trackSubscription ? _subscriptionStart : null,
      subscriptionEnd: _trackSubscription ? _subscriptionEnd : null,
      notes: _trimToNull(_notes),
      location: _trimToNull(_location),
      sourceType: _sourceType,
      sourceDetail: _trimToNull(_sourceDetail),
      ageGroup: _ageGroup,
      addedDate: _addedDate,
      removed: base?.removed ?? false,
      removedAt: base?.removedAt,
      // Stamp the maintainer name onto a NEW title that has none yet; edits
      // keep the existing value (same rule as the book form).
      addedBy: base?.addedBy ?? maintainerStamp,
    );
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _titleError = true);
      return;
    }
    if (_issnInvalid) return; // the inline error already says why
    final controller = ref.read(periodicalFormControllerProvider.notifier);
    final stamp = _maintainerStamp();
    final editing = widget.periodical;
    if (editing == null) {
      await controller.save(_buildPeriodical(null, maintainerStamp: stamp));
    } else {
      // The controller re-reads the row and calls back with it; the form
      // fields win, everything else is the row as it is NOW.
      await controller.saveEdit(
        editing.id,
        (current) => _buildPeriodical(current, maintainerStamp: stamp),
      );
    }
    final state = ref.read(periodicalFormControllerProvider);
    if (!mounted) return;
    // The controller fired both mutation signals itself — only pop.
    if (state.hasValue && state.value != null) {
      Navigator.of(context).pop();
    }
  }

  /// Opens the shared date picker (1900–2100) and stores the pick.
  Future<void> _pickDate({
    required int? current,
    required String helpText,
    required ValueChanged<int> onPicked,
  }) async {
    final picked = await pickFormDate(
      context,
      current: current,
      helpText: helpText,
    );
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(periodicalFormControllerProvider);
    final saving = state.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit magazine title' : 'New magazine title'),
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
          FormTextRow(
            controller: _transliteration,
            label: 'Title (transliteration)',
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _issn,
              decoration: InputDecoration(
                labelText: 'ISSN',
                border: const OutlineInputBorder(),
                errorText: _issnInvalid
                    ? 'That does not look like a valid ISSN.'
                    : null,
              ),
              onChanged: (_) => setState(() {}), // live inline validation
            ),
          ),
          FormTextRow(controller: _publisher, label: 'Publisher'),
          LanguageField(controller: _language),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FormCoverField(
              title: _title.text,
              coverRef: _coverRef,
              onChanged: (ref) => setState(() => _coverRef = ref),
            ),
          ),
          DropdownButtonFormField<PeriodicalFrequency?>(
            initialValue: _frequency,
            decoration: const InputDecoration(
              labelText: 'Frequency',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(child: Text('Not set')),
              for (final f in PeriodicalFrequency.values)
                DropdownMenuItem(value: f, child: Text(f.label)),
            ],
            onChanged: (v) => setState(() => _frequency = v),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Track subscription'),
            subtitle: const Text(
              'Keep the subscription window here so the Magazines list can '
              'warn before it lapses.',
            ),
            value: _trackSubscription,
            onChanged: (v) => setState(() {
              _trackSubscription = v;
              if (v) {
                // Sensible defaults the user then corrects: starting today,
                // ending one year from today.
                final today = CalendarDate.fromPickerDate(DateTime.now());
                _subscriptionStart ??= today.epochMillis;
                _subscriptionEnd ??= today.addMonthsClamped(12).epochMillis;
              }
            }),
          ),
          if (_trackSubscription) ...[
            DatePickerRow(
              label: 'Subscription start',
              valueText: formatFormDate(_subscriptionStart) ?? '—',
              onPick: () => _pickDate(
                current: _subscriptionStart,
                helpText: 'Subscription start',
                onPicked: (d) => setState(() => _subscriptionStart = d),
              ),
            ),
            DatePickerRow(
              label: 'Subscription end',
              valueText: formatFormDate(_subscriptionEnd) ?? '—',
              onPick: () => _pickDate(
                current: _subscriptionEnd,
                helpText: 'Subscription end',
                onPicked: (d) => setState(() => _subscriptionEnd = d),
              ),
            ),
          ],
          FormTextRow(controller: _location, label: 'Shelf location'),
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
          const SizedBox(height: 12),
          FormTextRow(controller: _notes, label: 'Notes', maxLines: 4),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: saving ? null : _save,
            child: saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEdit ? 'Save changes' : 'Add magazine title'),
          ),
          if (state.hasError) ...[
            const SizedBox(height: 12),
            Text(
              catalogueSaveMessage(state.error!, noun: 'magazine title'),
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
