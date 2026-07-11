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

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/widgets/labeled_value_field.dart';
import 'package:pitaka/features/events/presentation/pages/events_page.dart';
import 'package:pitaka/features/publish/application/github_device_flow.dart';
import 'package:pitaka/features/publish/application/publish_controller.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';
import 'package:pitaka/features/publish/domain/github_oauth_app.dart';
import 'package:pitaka/features/settings/application/settings_controller.dart';
import 'package:pitaka/features/settings/domain/app_settings.dart';
import 'package:url_launcher/url_launcher.dart';

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
  String? _targetRepo;

  /// Set after a successful publish — drives the "your site" card with
  /// copy + share actions.
  String? _publishedUrl;
  List<GitHubRepo> _repos = const [];
  String? _status;
  bool _busy = false;

  /// True while the "authorize in your browser" dialog is on screen, so a
  /// terminal device-flow state can dismiss it (see [_signIn]).
  bool _codeDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final creds = ref.read(publishCredentialStoreProvider);
    final token = await creds.token();
    final repo = await creds.targetRepo();
    if (!mounted) return;
    setState(() {
      _signedIn = token != null;
      _targetRepo = repo;
      _loading = false;
    });
  }

  Future<void> _signIn() async {
    // No client-id prompt: Pitak ships its own public Device-Flow client id
    // (github_oauth_app.dart), so sign-in starts immediately.
    final flow = ref.read(gitHubDeviceFlowProvider);
    // The flow is an async GENERATOR: it is suspended at `yield` until this
    // loop asks for the next state. Awaiting the user-code dialog here would
    // therefore pause token polling until the dialog closes — sign-in could
    // never complete while the user follows the on-screen instructions. So
    // the dialog is fired unawaited and dismissed when a terminal state
    // arrives (same pattern as gh CLI: poll in the background, UI on top).
    await for (final s in flow.start()) {
      if (!mounted) return;
      switch (s) {
        case DeviceFlowStarting():
          setState(() => _status = 'Starting…');
        case DeviceFlowAwaitingUser(:final userCode, :final verificationUri):
          unawaited(_showUserCodeDialog(userCode, verificationUri));
        case DeviceFlowSuccess(:final accessToken):
          await ref.read(publishCredentialStoreProvider).setToken(accessToken);
          if (!mounted) return;
          _dismissCodeDialog();
          setState(() => _status = 'Signed in.');
          await _refresh();
          // One-tap setup (mirrors Localcart Orange): brand-new users get a
          // publish-ready repo right away. Existing users keep their stored
          // target untouched — setup only runs when none is set.
          if (_targetRepo == null) {
            await _setUpNewRepo();
          }
        case DeviceFlowDenied():
          _dismissCodeDialog();
          setState(() => _status = 'Authorization denied.');
        case DeviceFlowExpired():
          _dismissCodeDialog();
          setState(() => _status = 'The code expired. Please try again.');
        case DeviceFlowFailed():
          _dismissCodeDialog();
          // Fixed message (§5): the reason can carry transport/API text that
          // must not reach the UI verbatim.
          setState(
            () => _status =
                'Sign-in failed. Check your connection and try again.',
          );
      }
    }
  }

  /// Closes the user-code dialog if it is still open (the flow reached a
  /// terminal state while the user had it on screen).
  void _dismissCodeDialog() {
    if (!_codeDialogOpen || !mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _showUserCodeDialog(
    String userCode,
    String verificationUri,
  ) async {
    setState(() => _status = 'Enter code $userCode at $verificationUri');
    _codeDialogOpen = true;
    // Validated in the domain (safeGithubVerificationUri) so the check is
    // unit-tested; null means "could not validate → show text, don't launch".
    final safeUri = safeGithubVerificationUri(verificationUri);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Authorize in your browser'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1. Open this page:'),
            const SizedBox(height: 4),
            if (safeUri != null)
              FilledButton.icon(
                icon: const Icon(Icons.open_in_browser),
                label: Text(safeUri.host + safeUri.path),
                // Opened EXTERNALLY (never an in-app webview), matching the
                // bookmarks pattern — the user authorizes in their own
                // browser session, and the app never sees their password.
                onPressed: () =>
                    launchUrl(safeUri, mode: LaunchMode.externalApplication),
              )
            else
              // Unexpected URI shape: fall back to copyable text rather
              // than launching something we could not validate.
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
    _codeDialogOpen = false;
  }

  /// Prompts for a repo name, then creates/adopts it and enables Pages in
  /// one go (SetupGitHubRepo). Loops on validation errors so a typo doesn't
  /// dead-end the flow.
  Future<void> _setUpNewRepo() async {
    final creds = ref.read(publishCredentialStoreProvider);
    final token = await creds.token();
    if (token == null || !mounted) return;

    var suggestion = 'my-library';
    while (mounted) {
      final name = await _promptRepoName(initial: suggestion);
      if (name == null) {
        // User backed out. With a target already stored nothing changes;
        // otherwise nudge — the advanced picker below can also set one.
        setState(
          () => _status = _targetRepo == null
              ? 'Signed in. Set up a repository to publish.'
              : null,
        );
        return;
      }
      suggestion = name;
      setState(() {
        _busy = true;
        _status = 'Setting up "$name" on GitHub…';
      });
      final result = await ref
          .read(setupGitHubRepoProvider)
          .call(token: token, repoName: name);
      if (!mounted) return;
      setState(() => _busy = false);
      // .match maps Either→outcome (codebase convention, §5): a validation
      // failure re-prompts with the rejected name; anything else ends the
      // attempt with a safe, fixed message.
      final retry = result.match(
        (failure) {
          if (failure is ValidationFailure) {
            setState(() => _status = failure.message);
            return true; // loop → re-prompt so the user can fix the name
          }
          setState(
            () => _status =
                'Could not set up the repository. Check your connection '
                'and try again.',
          );
          return false;
        },
        (r) {
          setState(
            () => _status = r.created
                ? 'Repository ${r.fullName} created — ready to publish!'
                : 'Connected to your existing ${r.fullName} — ready to '
                      'publish!',
          );
          return false;
        },
      );
      if (!retry) {
        await _refresh();
        return;
      }
    }
  }

  Future<String?> _promptRepoName({required String initial}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name your library repository'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pitak will create this public repository on your GitHub '
              'account and turn on GitHub Pages — no dashboard visit '
              'needed. The name becomes part of your public web address.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Repository name',
                helperText: 'Letters, numbers, dots, dashes, underscores',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Create'),
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
    } on GitHubApiException {
      if (!mounted) return;
      // Fixed message (§5): exception text can carry transport/API detail.
      setState(() => _status = 'Could not list your repositories. Try again.');
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
    // try/finally: _busy MUST clear on every path. Without this, any
    // exception escaping publish() (the controller rethrows) killed this
    // method mid-flight and the spinner ran forever (fail closed, §7).
    PublishResult? result;
    try {
      result = await ref.read(publishControllerProvider.notifier).publish();
    } on Exception {
      // Fixed message (§5): exception text can carry transport/API detail.
      result = const PublishFailure('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          switch (result) {
            case PublishSuccess(:final pagesUrl, :final pagesLive):
              _publishedUrl = pagesUrl;
              _status = (pagesLive ?? false)
                  ? 'Published! Your site is live.'
                  : 'Published! The commit is pushed — the site can take a '
                        'minute to update.';
              // The drawer's "Share Library Website" entry reads the
              // published URL from the manifest — refresh it now.
              ref.invalidate(publishedSiteUrlProvider);
            case PublishFailure(:final reason):
              _publishedUrl = null;
              _status = 'Publish failed: $reason';
            case null:
              // Non-Exception Error escaped: still unfreeze the button.
              _status = 'Something went wrong. Please try again.';
          }
        });
      }
    }
  }

  Future<void> _copyPublishedUrl() async {
    final url = _publishedUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  Future<void> _sharePublishedUrl() async {
    final url = _publishedUrl;
    if (url == null) return;
    // Through the FileShareService seam (not share_plus directly) so widget
    // tests can fake it — same pattern as PDF/backup export.
    await ref.read(fileShareServiceProvider).shareText(url);
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
                if (_targetRepo != null) ...[
                  Text('Current: $_targetRepo'),
                  const SizedBox(height: 8),
                ],
                // Always available: create (or adopt) a public repo by name,
                // Pages enabled automatically — no GitHub dashboard needed.
                FilledButton.icon(
                  onPressed: _busy ? null : _setUpNewRepo,
                  icon: const Icon(Icons.add),
                  label: Text(
                    _targetRepo == null
                        ? 'Set up a repository'
                        : 'Create a new repository',
                  ),
                ),
                const SizedBox(height: 8),
                // Advanced path: pick one of your existing repos instead.
                OutlinedButton(
                  onPressed: _busy ? null : _loadRepos,
                  child: const Text('Choose an existing repo (advanced)'),
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
        if (_publishedUrl != null)
          _SectionCard(
            title: 'Your site',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(_publishedUrl!),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _copyPublishedUrl,
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy link'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _sharePublishedUrl,
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Share'),
                    ),
                  ],
                ),
              ],
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
