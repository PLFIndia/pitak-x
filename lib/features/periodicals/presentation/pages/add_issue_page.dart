/// Add / edit magazine-issue form (periodicals presentation layer,
/// AGENTS.md §3.1; ADR 0013 D1, D4).
///
/// One screen for both modes: passed an issue → "Edit" (prefilled),
/// otherwise "Add magazine issue" — optionally with a preselected series
/// (the series page's "+ Add issue" and the scanned-ISSN route).
///
/// The form owns only view state; persistence + validation go through
/// [AddIssueController] (`save` / `saveEdit`, N03: edits build on top of the
/// CURRENT row). The issue's title/publisher/language/age group are never
/// typed here — they are PROJECTED from the series by the use case (D3), and
/// the live "title preview" shows exactly what will be composed
/// ([IssueTitlePreview]), so the user sees the result before saving.
///
/// Prefill (add mode, on picking a series): the next number/date come from
/// [IssueCadence] over the latest issue, shelf location from the series,
/// pages/copies from the latest issue — suggestions in EMPTY fields only,
/// never overwriting what the user typed (the book lookup's rule).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/library/domain/catalogue_rules.dart';
import 'package:pitaka/features/library/domain/entities/catalogue_item.dart';
import 'package:pitaka/features/library/domain/value_objects/item_details.dart';
import 'package:pitaka/features/library/presentation/catalogue_save_messages.dart';
import 'package:pitaka/features/library/presentation/widgets/form_cover_field.dart';
import 'package:pitaka/features/periodicals/application/add_issue_controller.dart';
import 'package:pitaka/features/periodicals/application/periodicals_controller.dart';
import 'package:pitaka/features/periodicals/domain/entities/periodical.dart';
import 'package:pitaka/features/periodicals/domain/issue_cadence.dart';
import 'package:pitaka/features/periodicals/presentation/widgets/add_issue_form_sections.dart';
import 'package:pitaka/features/periodicals/presentation/widgets/form_rows.dart';
import 'package:pitaka/features/periodicals/presentation/widgets/series_picker_field.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';

/// Form screen to add a new issue (or bound volume) to a series, or edit an
/// existing one.
class AddIssuePage extends ConsumerStatefulWidget {
  /// Creates the page. [periodical] preselects the series in add mode;
  /// [issue] opens the form in edit mode (prefilled from that row).
  const AddIssuePage({this.periodical, this.issue, super.key});

  /// The preselected series (add mode only).
  final Periodical? periodical;

  /// The issue to edit, or null to add a new one.
  final CatalogueItem? issue;

  @override
  ConsumerState<AddIssuePage> createState() => _AddIssuePageState();
}

class _AddIssuePageState extends ConsumerState<AddIssuePage> {
  late final TextEditingController _volume;
  late final TextEditingController _issueNumber;
  late final TextEditingController _label;
  late final TextEditingController _copies;
  late final TextEditingController _pages;
  late final TextEditingController _location;
  late final TextEditingController _notes;

  /// The selected series' uid (its cross-device identity — the value the
  /// issue's details carry, D2).
  String? _selectedUid;

  /// D4: a bound volume is one row with a date RANGE. The switch swaps the
  /// single cover date for "issues from / to".
  late bool _bound;
  int? _issueDate;
  int? _boundUntil;

  /// The cover reference the form currently holds, or null (the series
  /// cover stands in — W4; the row simply stores no cover of its own).
  String? _coverRef;

  /// Cover intent is explicit: background row updates win only while the user
  /// has not captured/removed a cover, and Save waits for pending storage.
  bool _coverDirty = false;
  bool _coverPending = false;

  /// Inline form-level error shown above the save button (mirrors the book
  /// form's title-error pattern, one message at a time).
  String? _formError;

  /// The prefill for the selected series has been applied (once per
  /// selection; a user pick re-arms it).
  bool _prefillArmed = false;

  /// Incremented on every selection. A response must match BOTH this
  /// generation and the currently selected UID before touching any field.
  int _prefillGeneration = 0;

  /// The default "1" is prefilled only until the user actually edits Copies.
  bool _copiesDirty = false;

  bool get _isEdit => widget.issue != null;

  @override
  void initState() {
    super.initState();
    final issue = widget.issue?.issue;
    _volume = TextEditingController(text: issue?.volume?.toString());
    _issueNumber = TextEditingController(text: issue?.issueNumber?.toString());
    _label = TextEditingController(text: issue?.label);
    _copies = TextEditingController(
      text: (widget.issue?.copyCount ?? 1).toString(),
    );
    _pages = TextEditingController(text: widget.issue?.pageCount?.toString());
    _location = TextEditingController(text: widget.issue?.location);
    _notes = TextEditingController(text: widget.issue?.notes);
    _bound = issue?.isBound ?? false;
    _issueDate = issue?.issueDate;
    _boundUntil = issue?.boundUntil;
    _coverRef = widget.issue?.coverUrl;
    _selectedUid = issue?.periodicalUid ?? widget.periodical?.periodicalUid;
    // Add mode with a preselected series: prefill once the page settles.
    _prefillArmed = widget.issue != null;
  }

  @override
  void dispose() {
    for (final c in [
      _volume,
      _issueNumber,
      _label,
      _copies,
      _pages,
      _location,
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

  static int? _parseCount(TextEditingController c) =>
      int.tryParse(c.text.trim());

  /// The details the current field values describe. Null only when no series
  /// is selected (the preview and save both require one).
  IssueOf? get _currentDetails {
    final uid = _selectedUid;
    if (uid == null) return null;
    return IssueOf(
      periodicalUid: uid,
      volume: _parseCount(_volume),
      issueNumber: _parseCount(_issueNumber),
      issueDate: _issueDate,
      boundUntil: _bound ? _boundUntil : null,
      label: _trimToNull(_label),
    );
  }

  /// Prefill on picking a series (ADD mode only): cadence suggestion from
  /// the latest issue plus the series' shelf location / the latest issue's
  /// pages and copies — into EMPTY fields only, so a re-pick never erases
  /// what the user typed.
  Future<void> _prefillFor(Periodical periodical) async {
    final uid = periodical.periodicalUid;
    if (uid == null) return;
    final generation = _prefillGeneration;
    final repo = await ref.read(periodicalRepositoryProvider.future);
    if (!_isCurrentPrefill(generation, uid)) return;
    final result = await repo.issuesOf(uid);
    if (!_isCurrentPrefill(generation, uid)) return;
    final latest = result
        .getOrElse((_) => const <CatalogueItem>[])
        .firstOrNull; // issuesOf is newest-first (IssueSorter)
    final suggestion = IssueCadence.next(
      latest: latest?.issue,
      frequency: periodical.frequency,
    );
    setState(() {
      if (_volume.text.trim().isEmpty && suggestion.volume != null) {
        _volume.text = suggestion.volume.toString();
      }
      if (_issueNumber.text.trim().isEmpty && suggestion.issueNumber != null) {
        _issueNumber.text = suggestion.issueNumber.toString();
      }
      _issueDate ??= suggestion.issueDate;
      if (_location.text.trim().isEmpty) {
        final loc = periodical.location?.trim() ?? '';
        if (loc.isNotEmpty) _location.text = loc;
      }
      if (_pages.text.trim().isEmpty && latest?.pageCount != null) {
        _pages.text = latest!.pageCount.toString();
      }
      final lastCopies = latest?.copyCount;
      if (!_copiesDirty &&
          (_copies.text.trim().isEmpty || _copies.text.trim() == '1') &&
          lastCopies != null &&
          lastCopies > 1) {
        _copies.text = lastCopies.toString();
      }
    });
  }

  /// A late response is valid only for the exact selection that requested it.
  bool _isCurrentPrefill(int generation, String uid) =>
      mounted && generation == _prefillGeneration && uid == _selectedUid;

  /// Assembles the item to persist. The title is left BLANK on purpose: the
  /// use case projects it from the series (D3). [base] is null in add mode,
  /// the FRESH row in edit mode (N03) — fields the form does not own
  /// (author, source, flags, attribution) come from the row as it is now.
  CatalogueItem _buildIssue(CatalogueItem? base, {String? maintainerStamp}) {
    final qty = int.tryParse(_copies.text.trim()) ?? 1;
    return CatalogueItem(
      id: base?.id ?? CatalogueItem.emptyId,
      itemUid: base?.itemUid,
      title: '', // projected from the series by the use case (D3)
      author: base?.author,
      isbn: base?.isbn,
      genre: base?.genre,
      coverUrl: _coverDirty ? _coverRef : base?.coverUrl,
      pageCount: _parseCount(_pages),
      notes: _trimToNull(_notes),
      location: _trimToNull(_location),
      sourceType: base?.sourceType,
      sourceDetail: base?.sourceDetail,
      addedDate: base?.addedDate ?? DateTime.now().millisecondsSinceEpoch,
      copyCount: qty < 1 ? 1 : qty,
      needsMetadata: base?.needsMetadata ?? false,
      removed: base?.removed ?? false,
      removedAt: base?.removedAt,
      addedBy: base?.addedBy ?? maintainerStamp,
      details: _currentDetails,
    );
  }

  /// The maintainer name from settings, or null when unset/blank (same rule
  /// as the book form: attribute newly-added rows only).
  String? _maintainerStamp() {
    final name = ref
        .read(settingsControllerProvider)
        .maybeWhen(data: (s) => s.maintainerName, orElse: () => '')
        .trim();
    return name.isEmpty ? null : name;
  }

  /// The form's own boundary checks (the use case re-checks everything —
  /// these messages just save a round trip). Returns the error text, or null
  /// when the input is complete enough to send.
  String? _validationError() {
    if (_selectedUid == null) return 'Choose a magazine title first.';
    if (_bound) {
      // D4: a bound volume IS its date range.
      if (_issueDate == null || _boundUntil == null) {
        return 'A bound volume needs both "from" and "to" dates.';
      }
      if (!CatalogueRules.isValidDateOrder(_issueDate, _boundUntil)) {
        return 'The "to" date must not be before the "from" date.';
      }
    } else if (_parseCount(_issueNumber) == null && _issueDate == null) {
      // A single issue needs something to be identified by (D6).
      return 'Add an issue number or a cover date.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_coverPending) return;
    final error = _validationError();
    if (error != null) {
      setState(() => _formError = error);
      return;
    }
    final controller = ref.read(addIssueControllerProvider.notifier);
    final stamp = _maintainerStamp();
    final editing = widget.issue;
    if (editing == null) {
      await controller.save(_buildIssue(null, maintainerStamp: stamp));
    } else {
      await controller.saveEdit(
        editing.id,
        (current) => _buildIssue(current, maintainerStamp: stamp),
      );
    }
    if (!mounted) return;
    final state = ref.read(addIssueControllerProvider);
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
    if (!mounted) return;
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addIssueControllerProvider);
    final saving = state.isLoading;
    final observed = _isEdit
        ? ref.watch(catalogueItemByIdProvider(widget.issue!.id))
        : null;
    final current = observed?.valueOrNull;
    final displayedCover =
        !_coverDirty && (observed?.hasValue ?? false) && current != null
        ? current.coverUrl
        : _coverRef;
    final entriesAsync = ref.watch(periodicalsControllerProvider);
    final entries = entriesAsync.valueOrNull;

    // The series list never flashes a spinner on the minute tick (N04);
    // only the FIRST load (or a failure) replaces the picker.
    final selected = entries
        ?.where((e) => e.periodical.periodicalUid == _selectedUid)
        .firstOrNull
        ?.periodical;

    // Add mode, preselected series: apply the cadence prefill once the list
    // (and thus the picker's value set) is available.
    if (!_isEdit && !_prefillArmed && _selectedUid != null && entries != null) {
      _prefillArmed = true;
      final preselected = selected;
      if (preselected != null) {
        // A build method never starts async work inline — schedule it.
        Future.microtask(() => _prefillFor(preselected));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit issue' : 'Add magazine issue'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SeriesPickerField(
            selectedUid: _selectedUid,
            onChanged: (uid) {
              setState(() {
                _selectedUid = uid;
                _prefillGeneration++;
                // This pick starts its own read below; do not also schedule
                // the one-time initial-prefill path from the next build.
                _prefillArmed = true;
                _formError = null;
              });
              // Add mode: prefill from the newly picked series (empty
              // fields only). Edit mode: never — the issue's own values
              // stay.
              if (!_isEdit) {
                final picked = entries
                    ?.where((e) => e.periodical.periodicalUid == uid)
                    .firstOrNull
                    ?.periodical;
                if (picked != null) _prefillFor(picked);
              }
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bound volume'),
            subtitle: const Text(
              'Several issues bound as one physical item — identified by the '
              'date range instead of a single cover date.',
            ),
            value: _bound,
            onChanged: (v) => setState(() => _bound = v),
          ),
          IssueNumberFields(
            volume: _volume,
            issueNumber: _issueNumber,
            onChanged: _onFieldChanged,
          ),
          IssueDateFields(
            bound: _bound,
            issueDate: _issueDate,
            boundUntil: _boundUntil,
            onPickIssueDate: () => _pickDate(
              current: _issueDate,
              helpText: _bound ? 'First issue in the volume' : 'Cover date',
              onPicked: (d) => setState(() => _issueDate = d),
            ),
            onPickBoundUntil: () => _pickDate(
              current: _boundUntil,
              helpText: 'Last issue in the volume',
              onPicked: (d) => setState(() => _boundUntil = d),
            ),
          ),
          FormTextRow(
            controller: _label,
            label: 'Label (e.g. Annual number)',
            onChanged: _onFieldChanged,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FormCoverField(
              title: selected?.title ?? '',
              coverRef: displayedCover,
              onChanged: (ref) => setState(() {
                _coverRef = ref;
                _coverDirty = true;
              }),
              onBusyChanged: (pending) =>
                  setState(() => _coverPending = pending),
            ),
          ),
          IssueCopyFields(
            copies: _copies,
            pages: _pages,
            onChanged: _onFieldChanged,
            onCopiesChanged: (value) {
              _copiesDirty = true;
              _onFieldChanged(value);
            },
          ),
          FormTextRow(controller: _location, label: 'Shelf location'),
          FormTextRow(controller: _notes, label: 'Notes', maxLines: 4),
          if (selected != null)
            // What the use case will compose (D3) — never typed.
            IssueTitlePreview(
              title: selected.title,
              details: _currentDetails ?? const IssueOf(periodicalUid: ''),
            ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: saving || _coverPending ? null : _save,
            child: saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEdit ? 'Save changes' : 'Add issue'),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 12),
            Text(
              _formError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (state.hasError) ...[
            const SizedBox(height: 12),
            Text(
              catalogueSaveMessage(state.error!, noun: 'issue'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  /// Text-field change hook: keeps the title preview live (rebuild) and
  /// clears a stale form-level error once the input could satisfy it.
  void _onFieldChanged(String _) => setState(() {
    if (_formError != null && _validationError() == null) {
      _formError = null;
    }
  });
}
