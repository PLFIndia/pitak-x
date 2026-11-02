/// Settings → Data → **Publishing**: the automatic availability switch
/// (presentation; ADR 0019, plan P3/C.8).
///
/// Its own file because `settings_page.dart` sits near the 500-line ratchet
/// (plan G5). Pure presentation: it reads the setting and forwards changes
/// to `SettingsController`, which saves them; the lane reacts by itself.
///
/// Shown only when this build runs the lane (`availabilityLaneActivated`,
/// true since plan S8; the build's kill switch): a switch that promises
/// automatic updates must not appear in a build that does not make them
/// (AV16).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/presentation/settings_write.dart';

/// The Publishing group of the Data tab.
class PublishingSettingsGroup extends ConsumerWidget {
  /// Creates the group.
  const PublishingSettingsGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(availabilityLaneActivatedProvider)) {
      return const SizedBox.shrink();
    }
    final enabled = ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.valueOrNull?.autoPublishAvailability ?? true,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Text('Publishing', style: Theme.of(context).textTheme.titleSmall),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.event_available_outlined),
          title: const Text('Update availability on my site automatically'),
          subtitle: const Text(
            'After you lend or return an item. Only Available / Not '
            'available is published.',
          ),
          value: enabled,
          onChanged: (value) => saveSetting(
            context,
            ref
                .read(settingsControllerProvider.notifier)
                .setAutoPublishAvailability(enabled: value),
          ),
        ),
      ],
    );
  }
}
