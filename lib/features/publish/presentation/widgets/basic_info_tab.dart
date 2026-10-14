/// "Basic info" tab of the publish hub (presentation, AGENTS §7).
///
/// Library name + public address / GPS / email / phone — the info shown on
/// the published page. Moved verbatim out of `publish_page.dart`
/// (SOLID-PLAN S1) so the page file stays a thin renderer. Local state is
/// UI-only: the text controllers and the edit/view toggle; persistence goes
/// through `settingsControllerProvider`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/widgets/labeled_value_field.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

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
              'optional — leave blank to show nothing.',
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
              hint: 'Coordinates as "lat, lng" — shown as a precise map pin',
              controller: _gps,
              editing: _editing,
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
