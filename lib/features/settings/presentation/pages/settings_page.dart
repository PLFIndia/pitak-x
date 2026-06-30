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
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/core/widgets/editable_text_field.dart';
import 'package:pitaka/core/widgets/library_logo.dart';
import 'package:pitaka/core/widgets/lock_suppressor.dart';
import 'package:pitaka/core/widgets/qr_view.dart';
import 'package:pitaka/features/backup/presentation/pages/create_backup_page.dart';
import 'package:pitaka/features/backup/presentation/pages/restore_page.dart';
import 'package:pitaka/features/import_export/presentation/pages/export_page.dart';
import 'package:pitaka/features/import_export/presentation/pages/import_page.dart';
import 'package:pitaka/features/import_export/presentation/pages/merge_page.dart';
import 'package:pitaka/features/library/domain/value_objects/library_qr_payload.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:pitaka/features/settings/presentation/pages/scan_library_qr_page.dart';
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
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('System')),
            ButtonSegment(value: ThemeMode.light, label: Text('Light')),
            ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
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
            'Off by default. When on, books with a web cover link will fetch '
            'that image, telling the host which books you view. Your own saved '
            'covers always stay on this device.',
          ),
          value: settings.loadRemoteCovers,
          onChanged: (v) => controller.setLoadRemoteCovers(enabled: v),
        ),
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
        const _CommunityLibrarySection(),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: const Text('Create backup'),
          subtitle: const Text('Full encrypted .pitabak archive'),
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

/// "Community library" section (PLAN-merge.md D40): shows this device's library
/// ID + a pairing QR, lets the user scan another device's QR to adopt its ID,
/// and start a fresh library ID. Pairing is in-person only (QR), no network.
class _CommunityLibrarySection extends ConsumerWidget {
  const _CommunityLibrarySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(settingsControllerProvider.notifier);

    Future<void> showQr() async {
      // Mint the ID on demand so a never-exported device can still pair.
      final id = await controller.getOrCreateLibraryId();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Your library QR'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Have another maintainer scan this to join your library.',
              ),
              const SizedBox(height: 16),
              Center(child: QrView(data: LibraryQrPayload.forId(id))),
              const SizedBox(height: 12),
              SelectableText(
                id,
                style: Theme.of(ctx).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }

    Future<void> scanQr() async {
      final id = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const ScanLibraryQrPage()),
      );
      if (id == null || !context.mounted) return;
      await controller.setLibraryId(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Joined library — now merge their file.')),
      );
    }

    Future<void> regenerate() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Start a new library?'),
          content: const Text(
            'This gives this device a brand-new library identity. Files you '
            'export afterwards will no longer match maintainers you previously '
            'paired with. Your books are not changed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Start new'),
            ),
          ],
        ),
      );
      if (ok ?? false) await controller.regenerateLibraryId();
    }

    return Column(
      children: [
        const Divider(),
        ListTile(
          leading: const Icon(Icons.qr_code_2),
          title: const Text('Show library QR'),
          subtitle: const Text('Let another maintainer scan to join you'),
          onTap: showQr,
        ),
        ListTile(
          leading: const Icon(Icons.qr_code_scanner),
          title: const Text('Scan a library QR'),
          subtitle: const Text("Join another maintainer's library"),
          onTap: scanQr,
        ),
        ListTile(
          leading: const Icon(Icons.autorenew),
          title: const Text('Start a new library'),
          subtitle: const Text('Give this device a fresh library identity'),
          onTap: regenerate,
        ),
      ],
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
          onChanged: (v) => ref
              .read(settingsControllerProvider.notifier)
              .setAppLockBiometric(enabled: v),
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
      final jpeg = ImageDownscaler.downscaleJpeg(raw);
      if (jpeg == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Couldn't read that image.")),
          );
        }
        return;
      }
      final store = await ref.read(coverStoreProvider.future);
      final reference = await store.saveJpeg(jpeg);
      await ref
          .read(settingsControllerProvider.notifier)
          .setLibraryLogo(reference);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() =>
      ref.read(settingsControllerProvider.notifier).setLibraryLogo('');

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
