/// Settings → Library switch controlling whether an ISBN scan also performs
/// an online lookup. Extracted so the Settings page stays below the file-size
/// ratchet; behavior and copy live in one cohesive tile.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/presentation/settings_write.dart';

/// Persisted "Look up ISBN after scanning" switch (default off).
class IsbnLookupSettingsTile extends ConsumerWidget {
  /// Creates the tile.
  const IsbnLookupSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      settingsControllerProvider.select(
        (state) => state.valueOrNull?.lookupIsbnAfterScan ?? false,
      ),
    );
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Look up ISBN after scanning'),
      subtitle: const Text(
        'Off: scanning only fills the ISBN; tap Lookup to search. '
        'On: scanning also sends the ISBN to the lookup service to find '
        'book details. Nothing is saved automatically.',
      ),
      value: enabled,
      onChanged: (value) => saveSetting(
        context,
        ref
            .read(settingsControllerProvider.notifier)
            .setLookupIsbnAfterScan(enabled: value),
      ),
    );
  }
}
