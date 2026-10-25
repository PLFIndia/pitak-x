/// Search / filter / sort controls for the published-catalogue viewer
/// (network presentation; viewer plan S4).
///
/// Every control is provider state, never local business logic: the widget
/// forwards an intent to `PublishedCatalogueQueryController`, which debounces
/// typed text and never performs IO. Changing a filter must not start a new
/// catalogue request — that is the controller's contract and the page tests
/// assert it.
///
/// Layout: the chips WRAP and the two dropdowns share a row with `isExpanded`,
/// so narrow phones and long Indic text never overflow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/network/application/published_catalogue_query_controller.dart';
import 'package:pitaka/features/network/domain/published_catalogue_query.dart';

/// The viewer's control bar.
class PublishedCatalogueControls extends ConsumerStatefulWidget {
  /// Creates the controls for the library saved at [siteUrl].
  const PublishedCatalogueControls({
    required this.siteUrl,
    required this.languages,
    super.key,
  });

  /// The family key of the query controller.
  final String siteUrl;

  /// The language facet (distinct, already sorted by the engine).
  final List<String> languages;

  @override
  ConsumerState<PublishedCatalogueControls> createState() =>
      _PublishedCatalogueControlsState();
}

class _PublishedCatalogueControlsState
    extends ConsumerState<PublishedCatalogueControls> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      publishedCatalogueQueryControllerProvider(widget.siteUrl),
    );
    final controller = ref.read(
      publishedCatalogueQueryControllerProvider(widget.siteUrl).notifier,
    );
    // Keep the field in sync when something else clears the intent (the
    // "No matches" action, or a fresh mount).
    ref.listen(
      publishedCatalogueQueryControllerProvider(
        widget.siteUrl,
      ).select((s) => s.search),
      (previous, next) {
        if (_search.text == next) return;
        _search.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          decoration: InputDecoration(
            labelText: 'Search this catalogue',
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: state.search.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.clear),
                    onPressed: () => controller.search(''),
                  ),
          ),
          onChanged: controller.search,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final filter in PublishedKindFilter.values)
              ChoiceChip(
                label: Text(_kindLabel(filter)),
                selected: state.kind == filter,
                onSelected: (_) => controller.setKind(filter),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              // A CONTROLLED DropdownButton (not the FormField variant, whose
              // `initialValue` would keep showing an old choice after the
              // "clear filters" reset).
              child: _LabeledDropdown<String>(
                label: 'Language',
                value: state.language ?? '',
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('All languages'),
                  ),
                  for (final language in widget.languages)
                    DropdownMenuItem(value: language, child: Text(language)),
                ],
                onChanged: (value) => controller.setLanguage(
                  (value ?? '').isEmpty ? null : value,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _LabeledDropdown<PublishedSortOrder>(
                label: 'Sort',
                value: state.sort,
                items: [
                  for (final order in PublishedSortOrder.values)
                    DropdownMenuItem(
                      value: order,
                      child: Text(_sortLabel(order)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) controller.setSort(value);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _kindLabel(PublishedKindFilter filter) => switch (filter) {
    PublishedKindFilter.all => 'All',
    PublishedKindFilter.books => 'Books',
    PublishedKindFilter.magazines => 'Magazines',
    PublishedKindFilter.others => 'Others',
  };

  static String _sortLabel(PublishedSortOrder order) => switch (order) {
    // Deliberately NOT "Recently added": the payload has no added date.
    PublishedSortOrder.publishedOrder => 'Published order',
    PublishedSortOrder.language => 'Language',
    PublishedSortOrder.ageGroup => 'Age group',
  };
}

/// A compact, keyboard/screen-reader friendly dropdown with a floating label.
class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      // No `isDense`: a dense dropdown shrinks its tap target to 24 dp and
      // fails the 48 dp accessibility guideline.
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
