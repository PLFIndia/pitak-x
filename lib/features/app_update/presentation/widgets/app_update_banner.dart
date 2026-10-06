/// The flexible-update banner (presentation, S35).
///
/// Renders ONLY the two active statuses — a background download in progress
/// and a finished download awaiting restart — and zero-height silence for
/// everything else (ineligible/idle), so it never affects layout on
/// F-Droid/desktop or when there is no update. Pure reaction to
/// [AppUpdateController]; no logic here (§7).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/app_update/application/app_update_controller.dart';
import 'package:pitaka/features/app_update/domain/app_update_policy.dart';

/// Sits at the top of the library page while a Play update downloads or
/// waits for its restart.
class AppUpdateBanner extends ConsumerWidget {
  /// Creates the banner.
  const AppUpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(appUpdateControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      AppUpdateStatus.downloading => MaterialBanner(
        backgroundColor: scheme.secondaryContainer,
        content: const Row(
          children: [
            SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Update downloading in the background…')),
          ],
        ),
        actions: [
          TextButton(
            // ref.read inside the callback, never in build (§7).
            onPressed: () =>
                ref.read(appUpdateControllerProvider.notifier).dismiss(),
            child: const Text('Hide'),
          ),
        ],
      ),
      AppUpdateStatus.downloaded => MaterialBanner(
        backgroundColor: scheme.secondaryContainer,
        leading: Icon(Icons.system_update, color: scheme.onSecondaryContainer),
        content: const Text('Update ready — restart the app to install it.'),
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(appUpdateControllerProvider.notifier).dismiss(),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => ref
                .read(appUpdateControllerProvider.notifier)
                .restartToUpdate(),
            child: const Text('Restart'),
          ),
        ],
      ),
      // Silence: not eligible (fdroid/iOS/desktop/tests) or nothing to do.
      AppUpdateStatus.ineligible ||
      AppUpdateStatus.idle => const SizedBox.shrink(),
    };
  }
}
