/// Settings screen (presentation layer, AGENTS.md §3.1).
///
/// Three tabs: Appearance, Data, Security.
///  - Appearance: theme, library name, maintainer name, remote-cover toggle.
///  - Data: import / export / backup / restore (links to the dedicated pages).
///  - Security: biometric app-lock + change vault passphrase (vault feature
///    entry points).
///
/// The public publish-contact fields (address / GPS / email / phone) moved to
/// the Publish hub's "Basic info" tab — they only matter for publishing.
///
/// Pure presentation — reads [SettingsController] and forwards changes to it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/editable_text_field.dart';
import 'package:pitaka/core/widgets/library_logo.dart';
import 'package:pitaka/core/widgets/lock_suppressor.dart';
import 'package:pitaka/features/backup/presentation/pages/create_backup_page.dart';
import 'package:pitaka/features/backup/presentation/pages/restore_page.dart';
import 'package:pitaka/features/import_export/presentation/pages/export_page.dart';
import 'package:pitaka/features/import_export/presentation/pages/import_page.dart';
import 'package:pitaka/features/import_export/presentation/pages/merge_page.dart';
import 'package:pitaka/features/settings/application/library_logo_controller.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/presentation/widgets/community_library_section.dart';
import 'package:pitaka/features/settings/presentation/widgets/google_books_key_tile.dart';
import 'package:pitaka/features/vault/domain/biometric_unlock.dart';
import 'package:pitaka/features/vault/presentation/pages/biometric_settings_page.dart';
import 'package:pitaka/features/vault/presentation/pages/change_passphrase_page.dart';

/// The app settings screen with four tabs.
class SettingsPage extends ConsumerWidget {
  /// Creates the settings page.
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(settingsControllerProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Appearance'),
              Tab(text: 'Data'),
              Tab(text: 'Security'),
            ],
          ),
        ),
        body: async.when(
          loading: () =>
              const Center(child: CircularProgressIndicator.adaptive()),
          error: (_, _) => const Center(child: Text("Couldn't load settings.")),
          data: (settings) => TabBarView(
            children: [
              _AppearanceTab(settings: settings),
              const _DataTab(),
              const _SecurityTab(),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppearanceTab extends ConsumerWidget {
  const _AppearanceTab({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(settingsControllerProvider.notifier);
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Appearance', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<AppThemeMode>(
          segments: const [
            ButtonSegment(value: AppThemeMode.system, label: Text('System')),
            ButtonSegment(value: AppThemeMode.light, label: Text('Light')),
            ButtonSegment(value: AppThemeMode.dark, label: Text('Dark')),
          ],
          selected: {settings.themeMode},
          onSelectionChanged: (s) => controller.setThemeMode(s.first),
        ),
        const SizedBox(height: 24),
        Text('Library', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        EditableTextField(
          label: 'Library name',
          hint: 'Shown as the title (blank uses the app name)',
          initial: settings.libraryName,
          onCommitted: controller.setLibraryName,
        ),
        const SizedBox(height: 8),
        EditableTextField(
          label: 'Maintainer name',
          hint: 'Stamped onto books you add (the "added by" field)',
          initial: settings.maintainerName,
          onCommitted: controller.setMaintainerName,
        ),
        const SizedBox(height: 16),
        const _LogoRow(),
        const SizedBox(height: 24),
        Text('Network', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Load cover images from the internet'),
          subtitle: const Text(
            'Off by default. When on, a book with a web cover link downloads '
            'that image once (only from Open Library, the Internet Archive '
            'that stores its covers, or Google Books) and keeps it like a '
            'cover you photographed. Your own photos are never replaced.',
          ),
          value: settings.loadRemoteCovers,
          onChanged: (v) => controller.setLoadRemoteCovers(enabled: v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Network map images (OpenStreetMap)'),
          subtitle: const Text(
            'Off by default. When on, the Library network › Map tab downloads '
            'map images from OpenStreetMap while you view it — their servers '
            'see your internet address and the area you look at. Your list '
            'of libraries never leaves the device.',
          ),
          value: settings.networkMapTilesConsent,
          onChanged: (v) => controller.setNetworkMapTilesConsent(enabled: v),
        ),
        const SizedBox(height: 8),
        const GoogleBooksKeyTile(),
      ],
    );
  }
}

class _DataTab extends ConsumerWidget {
  const _DataTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void go(Widget page) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Import, export, and back up your library and wishlist.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Import'),
          subtitle: const Text('Add books from a file (JSON, CSV, bundle)'),
          onTap: () => go(const ImportPage()),
        ),
        ListTile(
          leading: const Icon(Icons.upload_outlined),
          title: const Text('Export'),
          subtitle: const Text('Save your library to a file'),
          onTap: () => go(const ExportPage()),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.merge_type),
          title: const Text('Merge from a file'),
          subtitle: const Text(
            "Combine another maintainer's library with yours",
          ),
          onTap: () => go(const MergePage()),
        ),
        const CommunityLibrarySection(),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: const Text('Create backup'),
          // M06a: the old "Full encrypted" label was false — only the vault
          // inside the archive is encrypted; books/wishlist/covers are plain.
          subtitle: const Text(
            '.pitabak archive — only the borrowers vault inside is encrypted',
          ),
          onTap: () => go(const CreateBackupPage()),
        ),
        ListTile(
          leading: const Icon(Icons.settings_backup_restore),
          title: const Text('Restore backup'),
          subtitle: const Text('Replace local data from a .pitabak archive'),
          onTap: () => go(const RestorePage()),
        ),
      ],
    );
  }
}

/// Outcome of evaluating an app-lock toggle request (pure, testable).
enum AppLockToggleOutcome {
  /// Persist the lock as enabled (auth succeeded).
  enable,

  /// Persist the lock as disabled (user turned it off).
  disable,

  /// Leave the setting unchanged; the device has no biometric/credential.
  rejectedNotAvailable,

  /// Leave the setting unchanged; the prompt was cancelled or failed.
  rejectedAuthFailed,
}

/// Pure policy for the app-lock toggle, isolated from UI so it can be unit
/// tested. Turning ON requires availability + a successful prompt; turning OFF
/// is unguarded. [authenticate] is only invoked when enabling on an available
/// device. Fail-closed: anything but a clean success leaves the lock OFF.
Future<AppLockToggleOutcome> evaluateAppLockToggle({
  required bool enabled,
  required BiometricAvailability availability,
  required Future<bool> Function() authenticate,
}) async {
  if (!enabled) return AppLockToggleOutcome.disable;
  if (availability != BiometricAvailability.available) {
    return AppLockToggleOutcome.rejectedNotAvailable;
  }
  final ok = await authenticate();
  return ok
      ? AppLockToggleOutcome.enable
      : AppLockToggleOutcome.rejectedAuthFailed;
}

/// Handles the app-lock toggle. Turning it ON first requires a SUCCESSFUL
/// biometric/device-credential auth, so a user can never arm a lock they
/// cannot satisfy (and it confirms intent). If the device has nothing
/// enrolled, or the prompt is cancelled/fails, the toggle stays OFF. Turning
/// it OFF is unguarded.
Future<void> _onAppLockChanged(
  BuildContext context,
  WidgetRef ref, {
  required bool enabled,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(settingsControllerProvider.notifier);
  final auth = ref.read(biometricAuthenticatorProvider);

  final outcome = await evaluateAppLockToggle(
    enabled: enabled,
    availability: enabled
        ? await auth.availability()
        : BiometricAvailability.available,
    authenticate: () => auth.authenticate(
      reason: 'Confirm it is you to turn on the Pitak app lock',
    ),
  );

  switch (outcome) {
    case AppLockToggleOutcome.enable:
      await controller.setAppLockBiometric(enabled: true);
    case AppLockToggleOutcome.disable:
      await controller.setAppLockBiometric(enabled: false);
    case AppLockToggleOutcome.rejectedNotAvailable:
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Set up a fingerprint, face unlock, or device PIN first, then '
            'try again.',
          ),
        ),
      );
    case AppLockToggleOutcome.rejectedAuthFailed:
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'App lock not enabled — authentication was cancelled or failed.',
          ),
        ),
      );
  }
}

class _SecurityTab extends ConsumerWidget {
  const _SecurityTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void go(Widget page) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));

    final appLock = ref.watch(
      settingsControllerProvider.select(
        (s) => s.valueOrNull?.appLockBiometric ?? false,
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'App lock gates the whole app behind a biometric prompt. It deters '
          'casual access on an unlocked phone, but does not encrypt your data '
          'on disk — the borrowers vault below remains the encrypted store for '
          'sensitive records.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.lock_outline),
          title: const Text('Require biometric to open Pitak'),
          subtitle: const Text(
            'Off by default. When on, you must unlock with your biometric (or '
            'device PIN) each time you open or return to the app.',
          ),
          value: appLock,
          onChanged: (v) => _onAppLockChanged(context, ref, enabled: v),
        ),
        const Divider(),
        Text(
          'These options apply to the encrypted vault that holds borrowers and '
          'loans.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.fingerprint),
          title: const Text('Biometric unlock'),
          subtitle: const Text('Unlock the vault with biometrics (opt-in)'),
          onTap: () => go(const BiometricSettingsPage()),
        ),
        ListTile(
          leading: const Icon(Icons.password),
          title: const Text('Change vault passphrase'),
          subtitle: const Text('Re-wrap the vault under a new passphrase'),
          onTap: () => go(const ChangePassphrasePage()),
        ),
      ],
    );
  }
}

/// Library-logo picker (Appearance tab). Lets the user choose a custom library
/// icon from the gallery; it is downscaled and stored on-device like a cover
/// (`covers/<uuid>.jpg`) and shown in the splash, drawer, and app-bar button.
/// Picking nothing leaves the default Pitak icon in place.
class _LogoRow extends ConsumerStatefulWidget {
  const _LogoRow();

  @override
  ConsumerState<_LogoRow> createState() => _LogoRowState();
}

class _LogoRowState extends ConsumerState<_LogoRow> {
  bool _busy = false;

  Future<void> _pick() async {
    setState(() => _busy = true);
    try {
      // Suppress the app lock: the gallery picker is a separate OS activity
      // that backgrounds us and would otherwise trip the biometric gate.
      final shot = await ref
          .read(lockSuppressorProvider.notifier)
          .guard(
            () => ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 1024,
              maxHeight: 1024,
            ),
          );
      if (shot == null) return; // user cancelled
      final raw = await shot.readAsBytes();
      // Downscale → store → persist runs in the application layer (§7); the
      // widget only owns the plugin pick above and renders the outcome. A
      // failed save now surfaces a message instead of vanishing silently.
      final result = await ref
          .read(libraryLogoControllerProvider.notifier)
          .setLogo(raw);
      if (!mounted) return;
      result.match(
        (_) => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save that image.")),
        ),
        (_) {},
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final result = await ref
        .read(libraryLogoControllerProvider.notifier)
        .clearLogo();
    if (!mounted) return;
    result.match(
      (_) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't clear the logo."))),
      (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLogo = ref.watch(
      settingsControllerProvider.select(
        (s) => (s.valueOrNull?.libraryLogo ?? '').isNotEmpty,
      ),
    );
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        const LibraryLogo(size: 48, borderRadius: 12),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Library icon', style: textTheme.bodyMedium),
              Text(
                'Shown on the launch screen, the menu, and the toolbar. '
                'Defaults to the Pitak icon.',
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else ...[
          TextButton(onPressed: _pick, child: const Text('Choose')),
          if (hasLogo)
            TextButton(onPressed: _clear, child: const Text('Clear')),
        ],
      ],
    );
  }
}
