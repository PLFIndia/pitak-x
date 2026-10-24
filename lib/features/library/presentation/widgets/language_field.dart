/// The Language form field (presentation layer) — extracted from
/// `add_book_page.dart` in S16 so the book form AND the periodical form share
/// the one implementation (AGENTS §0 "one blessed way"; the behaviour is the
/// Session-33 design, unchanged).
///
/// A dropdown of the languages already in this library — seeded with
/// [LanguageName.defaults] while the library is empty — plus "Not set" and
/// "Other…". Choosing "Other…" reveals a text box; whatever is typed there
/// becomes a dropdown entry for every later row once saved (the list is
/// live, no restart needed).
///
/// The controller stays the single source of truth for the VALUE (the save
/// path reads it unchanged); the dropdown is a view over it. The repository
/// still snaps the value to the library's one spelling per language on
/// write, so this widget is a convenience, not the rule. The box is also
/// shown whenever the current value is not in the list — e.g. editing a row
/// from an old backup — so a language is never hidden.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/library/domain/value_objects/language_name.dart';

/// Dropdown-of-known-languages + free-text "Other…" form field.
class LanguageField extends ConsumerStatefulWidget {
  /// Creates the field over [controller] (its text is the saved value).
  const LanguageField({required this.controller, super.key});

  /// The form's language text controller — read on every build and written
  /// by both the dropdown picks and the "Other…" box.
  final TextEditingController controller;

  @override
  ConsumerState<LanguageField> createState() => _LanguageFieldState();
}

class _LanguageFieldState extends ConsumerState<LanguageField> {
  /// True only after the user PICKS "Other…" (or types in its box). The box
  /// is ALSO shown, without this flag, whenever the current value is not in
  /// the list — see the class doc.
  bool _isOther = false;

  /// Dropdown value meaning "Other… — type a language below". A const object
  /// compared by identity, so it can never collide with a real language
  /// name the way a magic string could.
  static const Object _otherLanguage = Object();

  /// The dropdown's language entries. While the list is still loading,
  /// offer the row's current language (so an edit shows its language at
  /// once, no flash to "Other…"); once loaded, the library's languages, or
  /// [LanguageName.defaults] when the library has none yet.
  static List<String> _languageOptions(List<String>? loaded, String current) {
    if (loaded == null) {
      return current.isEmpty ? LanguageName.defaults : [current];
    }
    return loaded.isEmpty ? LanguageName.defaults : loaded;
  }

  @override
  Widget build(BuildContext context) {
    // `asData` is null while loading OR on error: both fall back to the
    // defaults so the user can always pick "Other…" and type (fail-open on a
    // read-only facet is safe; the value is validated on save regardless).
    final loaded = ref.watch(libraryLanguagesProvider).asData?.value;
    final current = widget.controller.text.trim();
    final options = _languageOptions(loaded, current);
    // "Other…" is shown when the user picked it, or when the current value
    // (a prefilled edit, or a lookup result) is simply not in the list.
    final showOther =
        _isOther || (current.isNotEmpty && !options.contains(current));
    final selected = showOther
        ? _otherLanguage
        : (current.isEmpty ? null : current);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<Object?>(
            key: const ValueKey('language-dropdown'),
            initialValue: selected,
            decoration: const InputDecoration(
              labelText: 'Language',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(child: Text('Not set')),
              for (final lang in options)
                DropdownMenuItem(value: lang, child: Text(lang)),
              const DropdownMenuItem(
                value: _otherLanguage,
                child: Text('Other…'),
              ),
            ],
            onChanged: (v) => setState(() {
              if (identical(v, _otherLanguage)) {
                _isOther = true;
                // Coming FROM a list pick, start with an empty box; coming
                // from an already-"other" value (old backup), keep it.
                if (options.contains(widget.controller.text.trim())) {
                  widget.controller.clear();
                }
              } else {
                _isOther = false;
                widget.controller.text = (v as String?) ?? '';
              }
            }),
          ),
        ),
        if (showOther)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: widget.controller,
              decoration: const InputDecoration(
                labelText: 'Other language',
                border: OutlineInputBorder(),
              ),
              // Typing here confirms "Other…" mode even when it was inferred
              // from an unlisted value, so clearing the box cannot make it
              // vanish on the next rebuild.
              onChanged: (_) => setState(() => _isOther = true),
            ),
          ),
      ],
    );
  }
}
