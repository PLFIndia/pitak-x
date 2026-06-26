/// Publish-to-GitHub-Pages screen (presentation, AGENTS.md §3.1, #32).
///
/// One screen that walks the user through: (1) sign in to GitHub via Device
/// Flow using their own OAuth App client id, (2) pick a target repo, (3)
/// optionally set the public contact line, then (4) publish. All credentials
/// live in the secure store behind the controller; this widget only collects
/// input and renders state.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/publish/application/github_device_flow.dart';
import 'package:pitaka/features/publish/application/publish_controller.dart';
import 'package:pitaka/features/publish/application/publish_library_use_case.dart';
import 'package:pitaka/features/publish/domain/github_api.dart';
import 'package:pitaka/features/publish/domain/github_models.dart';

/// The publish screen.
class PublishPage extends ConsumerStatefulWidget {
  /// Creates the publish page.
  const PublishPage({super.key});

  @override
  ConsumerState<PublishPage> createState() => _PublishPageState();
}

class _PublishPageState extends ConsumerState<PublishPage> {
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

  // --- sign in (device flow) ---------------------------------------------

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

  // --- repos --------------------------------------------------------------

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

  // --- publish ------------------------------------------------------------

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
    return Scaffold(
      appBar: AppBar(title: const Text('Publish to web')),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Publish a public, read-only catalogue of your library to '
                  'GitHub Pages. Borrower data, notes, shelf locations and '
                  'private details are never included.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                _SectionCard(
                  title: '1. GitHub account',
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
                if (_signedIn) ...[
                  _SectionCard(
                    title: '2. Target repository',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_targetRepo != null) Text('Current: $_targetRepo'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            OutlinedButton(
                              onPressed: _busy ? null : _loadRepos,
                              child: const Text('Load my repos'),
                            ),
                          ],
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
                                ? const Text(
                                    'private (Pages needs a paid plan)',
                                  )
                                : null,
                            onTap: () => _pickRepo(r.fullName),
                          ),
                      ],
                    ),
                  ),
                  _SectionCard(
                    title: '3. Publish',
                    child: FilledButton.icon(
                      onPressed: (_busy || _targetRepo == null)
                          ? null
                          : _publish,
                      icon: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload),
                      label: const Text('Publish now'),
                    ),
                  ),
                ],
                if (_status != null) ...[
                  const SizedBox(height: 8),
                  Text(_status!),
                ],
              ],
            ),
    );
  }
}

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
