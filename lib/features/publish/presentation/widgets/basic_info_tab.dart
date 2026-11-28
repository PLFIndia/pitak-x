/// "Basic info" tab of the publish hub (presentation, AGENTS §7).
///
/// Library name + public address / GPS / email / phone — the info shown on
/// the published page. Moved verbatim out of `publish_page.dart`
/// (render-only presentation, AGENTS §7) so the page file stays a thin
/// renderer. Local state is UI-only: the text controllers and the edit/view toggle; persistence goes
/// through `settingsControllerProvider`.
///
/// Unsaved edits are protected in two ways (review finding P4-M1, ADR 0028):
/// the tab keeps its state when another tab is shown, and Back asks
/// "Discard changes?" from every tab of the Publish page while edits are
/// unsaved.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/widgets/discard_changes_guard.dart';
import 'package:pitaka/core/widgets/labeled_value_field.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/presentation/settings_write.dart';

/// Plain-words label for a location-sharing mode — the view-mode display row
/// uses the same wording as the segmented control's segments.
String sharingLabel(LocationSharing sharing) => switch (sharing) {
  LocationSharing.off => 'Not shared',
  LocationSharing.approximate => 'Approximate (~1 km)',
  LocationSharing.exact => 'Exact',
};

/// The sentence of the "Discard changes?" question for this tab. It names
/// the tab, because the question can come up while another tab is showing.
const String _unsavedMessage =
    'Your changes under "Basic info" have not been saved.';

/// The "Basic info" tab body.
class BasicInfoTab extends ConsumerStatefulWidget {
  /// Creates the tab.
  const BasicInfoTab({super.key});

  @override
  ConsumerState<BasicInfoTab> createState() => _BasicInfoTabState();
}

// Why the mixin (beginner note): a tab view throws away the state of a tab
// that is not on the screen. Half-typed contact details were lost by a mere
// look at another tab. `AutomaticKeepAliveClientMixin` with `wantKeepAlive`
// true tells the tab view to keep this tab's state while the page is open.
class _BasicInfoTabState extends ConsumerState<BasicInfoTab>
    with AutomaticKeepAliveClientMixin<BasicInfoTab> {
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

  /// True while the three writes of a Save run. Back waits then (the
  /// "Discard changes?" guard reads it); the Save button does not use it.
  bool _saving = false;

  /// What the fields held at the tap on "Edit", so that Back can ask before
  /// unsaved edits are lost (the "Discard changes?" guard, ADR 0028).
  late final OpenedValues _opened;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _opened = OpenedValues(_values);
  }

  /// What Save would store, for the guard to compare.
  List<Object?> _values() => [
    _name.text,
    _address.text,
    _gps.text,
    _email.text,
    _phone.text,
    _sharing,
  ];

  /// Starts a round of editing: what the fields hold at this moment is what
  /// "unsaved changes" are measured against.
  void _startEditing() {
    _opened.reset();
    setState(() => _editing = true);
  }

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
    setState(() => _saving = true);
    // `finally`: whatever happens to the writes, Back must work again.
    try {
      final notifier = ref.read(settingsControllerProvider.notifier);
      final name = await notifier.setLibraryName(_name.text);
      final contact = await notifier.setPublishContact(
        address: _address.text,
        gps: _gps.text,
        email: _email.text,
        phone: _phone.text,
      );
      // D7: the switch gates the published pin AND the network-map location —
      // persisted through the single serialised settings writer (M16).
      final sharing = await notifier.setPublishLocationSharing(
        _sharing ?? LocationSharing.off,
      );
      if (!mounted) return;
      if (name.isLeft() || contact.isLeft() || sharing.isLeft()) {
        // Stay in edit mode: the fields were not all stored (M8).
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(settingsSaveFailedMessage)),
        );
        return;
      }
      setState(() => _editing = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The keep-alive mixin needs this call to do its work.
    super.build(context);
    final async = ref.watch(settingsControllerProvider);
    final textTheme = Theme.of(context).textTheme;

    final body = async.when(
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
                onPressed: _startEditing,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
          ],
        );
      },
    );
    // In view mode nothing counts as changed: the fields are read-only then.
    return DiscardChangesGuard(
      hasChanges: () => _editing && _opened.changed,
      saving: _saving,
      message: _unsavedMessage,
      child: body,
    );
  }
}
