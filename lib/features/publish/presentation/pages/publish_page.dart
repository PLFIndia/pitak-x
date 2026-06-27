/// Publish hub (presentation, AGENTS.md §3.1, #32 / #events).
///
/// A 3-tab home for everything that lands on the published site:
///   1. Connection — GitHub account + target repo (Cloudflare is shown as a
///      disabled "coming soon" target; real upload is a later stage).
///   2. Basic Info — library name + public address / GPS / email / phone (the
///      info shown on the published page). These moved here from Settings.
///   3. Events — the poster editor (embedded EventsView); the library campaign
///      action deep-links to this tab so there is a single Events surface.
///
/// Pure presentation. Credentials live in the secure store behind the
/// controller; this widget only collects input and renders state.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/widgets/labeled_value_field.dart';
import 'package:pitaka/features/events/presentation/pages/events_page.dart';
import 'package:pitaka/features/publish/application/github_device_flow.dart';
import 'package:pitaka/features/publish/application/publish_controller.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';

/// Tabs of the publish hub, in order.
enum PublishTab {
  /// GitHub / Cloudflare connection + target.
  connection,

  /// Library name + public contact info.
  basicInfo,

  /// Event posters.
  events,
}

/// The publish hub screen.
class PublishPage extends StatelessWidget {
  /// Creates the publish hub, optionally opening on [initialTab].
  const PublishPage({this.initialTab = PublishTab.connection, super.key});

  /// Which tab to show first.
  final PublishTab initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: PublishTab.values.length,
      initialIndex: initialTab.index,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Publish to web'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Connection'),
              Tab(text: 'Basic info'),
              Tab(text: 'Events'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_ConnectionTab(), _BasicInfoTab(), EventsView()],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1: Connection
// ---------------------------------------------------------------------------

class _ConnectionTab extends ConsumerStatefulWidget {
  const _ConnectionTab();

  @override
  ConsumerState<_ConnectionTab> createState() => _ConnectionTabState();
}

class _ConnectionTabState extends ConsumerState<_ConnectionTab> {
  bool _loading = true;
  bool _signedIn = false;
  String? _clientId;
  String? _targetRepo;
  List<GitHubRepo> _repos = const [];
  String? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final creds = ref.read(publishCredentialStoreProvider);
    final token = await creds.token();
    final clientId = await creds.clientId();
    final repo = await creds.targetRepo();
    if (!mounted) return;
    setState(() {
      _signedIn = token != null;
      _clientId = clientId;
      _targetRepo = repo;
      _loading = false;
    });
  }

  Future<void> _signIn() async {
    final clientId = await _promptClientId();
    if (clientId == null || clientId.trim().isEmpty) return;
    await ref.read(publishCredentialStoreProvider).setClientId(clientId.trim());
    if (!mounted) return;

    final flow = ref.read(gitHubDeviceFlowProvider);
    await for (final s in flow.start(clientId.trim())) {
      if (!mounted) return;
      switch (s) {
        case DeviceFlowStarting():
          setState(() => _status = 'Starting…');
        case DeviceFlowAwaitingUser(:final userCode, :final verificationUri):
          await _showUserCodeDialog(userCode, verificationUri);
        case DeviceFlowSuccess(:final accessToken):
          await ref.read(publishCredentialStoreProvider).setToken(accessToken);
          if (!mounted) return;
          setState(() => _status = 'Signed in.');
          await _refresh();
          await _loadRepos();
        case DeviceFlowDenied():
          setState(() => _status = 'Authorization denied.');
        case DeviceFlowExpired():
          setState(() => _status = 'The code expired. Please try again.');
        case DeviceFlowFailed(:final reason):
          setState(() => _status = 'Sign-in failed: $reason');
      }
    }
  }

  Future<String?> _promptClientId() {
    final controller = TextEditingController(text: _clientId ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('GitHub OAuth client id'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Register your own OAuth App at github.com (Settings → '
              'Developer settings → OAuth Apps), enable Device Flow, and '
              'paste its Client ID here. Pitak ships no credentials of '
              'its own.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Client ID',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _showUserCodeDialog(String userCode, String verificationUri) {
    setState(() => _status = 'Enter code $userCode at $verificationUri');
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Authorize in your browser'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1. Open this URL in your browser:'),
            const SizedBox(height: 4),
            SelectableText(verificationUri),
            const SizedBox(height: 12),
            const Text('2. Enter this code:'),
            const SizedBox(height: 4),
            Row(
              children: [
                SelectableText(
                  userCode,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy code',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: userCode)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Waiting for you to authorize… this dialog can stay open.',
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

  Future<void> _signOut() async {
    await ref.read(publishCredentialStoreProvider).clearToken();
    if (!mounted) return;
    setState(() {
      _signedIn = false;
      _repos = const [];
      _status = 'Signed out.';
    });
  }

  Future<void> _loadRepos() async {
    final creds = ref.read(publishCredentialStoreProvider);
    final token = await creds.token();
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final repos = await ref.read(gitHubApiProvider).userRepos(token);
      if (!mounted) return;
      setState(() => _repos = repos);
    } on GitHubApiException catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Could not list repos: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickRepo(String fullName) async {
    await ref.read(publishCredentialStoreProvider).setTargetRepo(fullName);
    if (!mounted) return;
    setState(() => _targetRepo = fullName);
  }

  Future<void> _publish() async {
    setState(() {
      _busy = true;
      _status = 'Publishing…';
    });
    final result = await ref.read(publishControllerProvider.notifier).publish();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = switch (result) {
        PublishSuccess(:final pagesUrl, :final pagesLive) =>
          (pagesLive ?? false)
              ? 'Published! Live at $pagesUrl'
              : 'Published! It may take a minute to go live at $pagesUrl',
        PublishFailure(:final reason) => 'Publish failed: $reason',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Publish a public, read-only catalogue of your library to the web. '
          'Borrower data, notes, shelf locations and private details are never '
          'included.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'GitHub account',
          child: _signedIn
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Signed in'),
                    TextButton(
                      onPressed: _busy ? null : _signOut,
                      child: const Text('Sign out'),
                    ),
                  ],
                )
              : FilledButton.icon(
                  onPressed: _busy ? null : _signIn,
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in to GitHub'),
                ),
        ),
        if (_signedIn)
          _SectionCard(
            title: 'Target repository',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_targetRepo != null) Text('Current: $_targetRepo'),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _loadRepos,
                  child: const Text('Load my repos'),
                ),
                for (final r in _repos)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      r.fullName == _targetRepo
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(r.fullName),
                    subtitle: r.isPrivate
                        ? const Text('private (Pages needs a paid plan)')
                        : null,
                    onTap: () => _pickRepo(r.fullName),
                  ),
              ],
            ),
          ),
        const _CloudflareComingSoon(),
        if (_signedIn)
          _SectionCard(
            title: 'Publish',
            child: FilledButton.icon(
              onPressed: (_busy || _targetRepo == null) ? null : _publish,
              icon: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload),
              label: const Text('Publish catalogue now'),
            ),
          ),
        if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
      ],
    );
  }
}

/// Disabled Cloudflare target — a placeholder until the real Direct-Upload
/// integration lands. Greyed out so it never looks publishable yet.
class _CloudflareComingSoon extends StatelessWidget {
  const _CloudflareComingSoon();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: 0.55,
      child: IgnorePointer(
        child: _SectionCard(
          title: 'Cloudflare Pages',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.cloud_outlined, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Text('Coming soon'),
                ],
              ),
              const SizedBox(height: 8),
              const TextField(
                enabled: false,
                decoration: InputDecoration(
                  labelText: 'Cloudflare API token',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const TextField(
                enabled: false,
                decoration: InputDecoration(
                  labelText: 'Account ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const TextField(
                enabled: false,
                decoration: InputDecoration(
                  labelText: 'Pages project name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'For now, you can host the same GitHub repo on Cloudflare '
                'Pages by connecting it in the Cloudflare dashboard. Direct '
                'upload from the app is on the way.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2: Basic Info
// ---------------------------------------------------------------------------

class _BasicInfoTab extends ConsumerStatefulWidget {
  const _BasicInfoTab();

  @override
  ConsumerState<_BasicInfoTab> createState() => _BasicInfoTabState();
}

class _BasicInfoTabState extends ConsumerState<_BasicInfoTab> {
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

// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
