/// "Basic info" tab of the publish hub (presentation, AGENTS §7).
///
/// Library name + public address / GPS / email / phone — the info shown on
/// the published page. Moved verbatim out of `publish_page.dart`
/// (render-only presentation, AGENTS §7) so the page file stays a thin
/// renderer. Local state is UI-only: the text controllers and the edit/view toggle; persistence goes
/// through `settingsControllerProvider`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/widgets/labeled_value_field.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

/// Plain-words label for a location-sharing mode — the view-mode display row
/// uses the same wording as the segmented control's segments.
String sharingLabel(LocationSharing sharing) => switch (sharing) {
  LocationSharing.off => 'Not shared',
  LocationSharing.approximate => 'Approximate (~1 km)',
  LocationSharing.exact => 'Exact',
};

/// The "Basic info" tab body.
class BasicInfoTab extends ConsumerStatefulWidget {
  /// Creates the tab.
  const BasicInfoTab({super.key});

  @override
  ConsumerState<BasicInfoTab> createState() => _BasicInfoTabState();
}

class _BasicInfoTabState extends ConsumerState<BasicInfoTab> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _gps = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  /// Location-sharing choice being edited; null until Save writes it (the
  /// segmented control then falls back to the persisted value).
  LocationSharing? _sharing;

  bool _editing = false;
  bool _seeded = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _gps.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _seed(AppSettings s) {
    _name.text = s.libraryName;
    _address.text = s.publishContactAddress;
    _gps.text = s.publishContactGps;
    _email.text = s.publishContactEmail;
    _phone.text = s.publishContactPhone;
    _sharing = s.publishLocationSharing;
    _seeded = true;
  }

  Future<void> _save() async {
    final notifier = ref.read(settingsControllerProvider.notifier);
    await notifier.setLibraryName(_name.text);
    await notifier.setPublishContact(
      address: _address.text,
      gps: _gps.text,
      email: _email.text,
      phone: _phone.text,
    );
    // D7: the switch gates the published pin AND the network-map location —
    // persisted through the single serialised settings writer (M16).
    await notifier.setPublishLocationSharing(_sharing ?? LocationSharing.off);
    if (mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(settingsControllerProvider);
    final textTheme = Theme.of(context).textTheme;

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (_, _) => const Center(child: Text("Couldn't load your info.")),
      data: (settings) {
        // Seed the controllers once from storage; later edits are local until
        // Save writes them back (so a rebuild mid-edit won't clobber typing).
        if (!_seeded) _seed(settings);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'This information appears publicly on your published library '
              'page so visitors can find and contact you. Every field is '
              'optional — leave blank to show nothing. The location switch '
              'below also decides what the Library network map may show.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text('Library', style: textTheme.titleSmall),
            const SizedBox(height: 8),
            // Same `libraryName` setting as Appearance — one source of truth.
            LabeledValueField(
              label: 'Library name',
              hint: 'Shown as the page title (also set in Appearance)',
              controller: _name,
              editing: _editing,
            ),
            const SizedBox(height: 24),
            Text('Public contact', style: textTheme.titleSmall),
            const SizedBox(height: 8),
            LabeledValueField(
              label: 'Library address',
              hint: 'A street address or place name (shown as a map search)',
              controller: _address,
              editing: _editing,
            ),
            const SizedBox(height: 16),
            LabeledValueField(
              label: 'GPS location',
              hint: 'Coordinates as "lat, lng" — shown as a map pin',
              controller: _gps,
              editing: _editing,
            ),
            const SizedBox(height: 8),
            Text(
              'Share my location on the network map',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            // 3-way opt-in (docs/ARCHITECTURE.md §6 location sharing): default is NOT SHARED — no
            // coordinates leave the device until the user picks a precision.
            // View mode shows the current choice as a plain value row (the
            // LabeledValueField pattern this tab already uses) instead of a
            // DISABLED control — disabled Material text fails the WCAG
            // contrast guideline, and a read-only row says the same thing.
            if (_editing)
              SegmentedButton<LocationSharing>(
                segments: const [
                  ButtonSegment(
                    value: LocationSharing.off,
                    label: Text('Not shared'),
                    tooltip: 'No coordinates are published anywhere',
                  ),
                  ButtonSegment(
                    value: LocationSharing.approximate,
                    label: Text('Approximate (~1 km)'),
                    tooltip: 'Rounded to about 1.1 km — a city-map pin',
                  ),
                  ButtonSegment(
                    value: LocationSharing.exact,
                    label: Text('Exact'),
                    tooltip: 'Published exactly as typed',
                  ),
                ],
                selected: {_sharing ?? settings.publishLocationSharing},
                onSelectionChanged: (selection) =>
                    setState(() => _sharing = selection.first),
                showSelectedIcon: false,
                // 48 dp minimum tap height (accessibility guideline).
                style: const ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(0, 48)),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(
                  sharingLabel(_sharing ?? settings.publishLocationSharing),
                  style: textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            LabeledValueField(
              label: 'Email',
              hint: 'Shown as a mailto link',
              controller: _email,
              editing: _editing,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            LabeledValueField(
              label: 'Phone',
              hint: 'Shown as a tel link',
              controller: _phone,
              editing: _editing,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 24),
            if (_editing)
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: const Text('Save'),
              )
            else
              OutlinedButton.icon(
                onPressed: () => setState(() => _editing = true),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
          ],
        );
      },
    );
  }
}
