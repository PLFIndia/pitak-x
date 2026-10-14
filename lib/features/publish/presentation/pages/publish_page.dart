/// Publish hub (presentation, AGENTS.md §3.1, #32 / #events).
///
/// A 3-tab home for everything that lands on the published site:
///   1. Connection — the hosting providers as collapsible tiles (S35):
///      GitHub Pages (account + target repo) and Cloudflare Pages (a
///      "coming soon" placeholder; real upload is a later stage). With both
///      tiles collapsed the tab fits one screen; each header carries its
///      configuration status (green/amber/red, D3) and the GitHub tile
///      auto-expands unless fully configured (D4). Both ways of getting a
///      target — one-tap create and the advanced picker — run through
///      `SetupGitHubRepo`, so a stored target is always owned by the
///      signed-in account and serves GitHub Pages from a branch root
///      (N09). Sign-out forgets the target with the token.
///   2. Basic Info — library name + public address / GPS / email / phone (the
///      info shown on the published page). These moved here from Settings.
///   3. Events — the poster editor (embedded EventsView); the library campaign
///      action deep-links to this tab so there is a single Events surface.
///
/// Pure presentation (SOLID-PLAN S1): all Connection-tab orchestration — the
/// device flow, token persistence, repo setup, publishing — lives in
/// `GitHubConnectionController`. This widget only renders the controller's
/// state, forwards intents to it, and owns the dialogs (which are UI).
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/events/presentation/pages/events_page.dart';
import 'package:pitaka/features/publish/application/github_connection_controller.dart';
import 'package:pitaka/features/publish/presentation/widgets/basic_info_tab.dart';
import 'package:pitaka/features/publish/presentation/widgets/github_connection_dialogs.dart';
import 'package:pitaka/features/publish/presentation/widgets/provider_tile.dart';
import 'package:pitaka/features/publish/presentation/widgets/share_library_sheet.dart';

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
          children: [_ConnectionTab(), BasicInfoTab(), EventsView()],
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

/// Renders [GitHubConnectionUi] and forwards intents to
/// [GitHubConnectionController] (AGENTS §7: no business logic in widgets).
/// The only local state is pure UI bookkeeping: the D4 expansion latch and
/// whether the authorization dialog is currently on screen (so a terminal
/// state can dismiss it).
class _ConnectionTabState extends ConsumerState<_ConnectionTab> {
  /// D4 latch (S35): the GitHub tile's INITIAL expansion, decided ONCE from
  /// the first loaded state — auto-expand unless fully configured (signed in
  /// AND repo set). Later status changes never yank the tile open or shut
  /// while the user works in it; they can always toggle it manually.
  bool? _githubInitiallyExpanded;

  /// True while the "authorize in your browser" dialog is on screen, so a
  /// terminal device-flow state can dismiss it (see the ref.listen below).
  bool _codeDialogOpen = false;

  @override
  Widget build(BuildContext context) {
    // Dialogs are driven by STATE TRANSITIONS, not action handlers: the
    // controller decides when a prompt should appear; the widget shows it
    // and forwards the answer back as an intent.
    ref.listen(gitHubConnectionControllerProvider, (prev, next) {
      final before = prev?.valueOrNull;
      final now = next.valueOrNull;
      if (now == null) return;
      // The repo-name prompt was requested → ask, then forward the answer.
      if (before?.repoPromptInitialName == null &&
          now.repoPromptInitialName != null) {
        unawaited(_handleRepoPrompt(now.repoPromptInitialName!));
      }
      // The authorization dialog appears while the controller keeps polling
      // in the background — showing it must NOT be awaited here (awaiting
      // the dialog was the old regression that suspended token polling until
      // the dialog closed).
      //
      // Both branches are TRANSITION-guarded (code appeared / code cleared),
      // not level-guarded: a level check would fire on EVERY later state
      // without a code and its pop would kill an unrelated dialog that was
      // pushed in the meantime (the repo-name prompt opens right after a
      // first sign-in).
      final hadCode = before?.awaitingUserCode != null;
      final hasCode = now.awaitingUserCode != null;
      if (!hadCode && hasCode) {
        unawaited(
          _showCodeDialog(
            userCode: now.awaitingUserCode!,
            verificationUri: now.awaitingVerificationUri ?? '',
          ),
        );
      } else if (hadCode && !hasCode) {
        // Terminal state: the controller cleared the code → pop the dialog
        // if it is still open.
        _dismissCodeDialog();
      }
    });

    final async = ref.watch(gitHubConnectionControllerProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (_, _) =>
          const Center(child: Text("Couldn't load your connection status.")),
      data: (ui) {
        // D4 latch, decided once from the first loaded state. Assignment to
        // a plain field (no setState): the value is consumed by the tile
        // built right below in this same frame.
        _githubInitiallyExpanded ??= !(ui.signedIn && ui.targetRepo != null);
        return _buildTab(ui);
      },
    );
  }

  // --- Dialog plumbing (UI-owned) -----------------------------------------

  /// Shows the repo-name prompt and forwards the answer to the controller:
  /// a name goes to `createRepo`, a back-out to `skipRepoSetup`. The retry
  /// loop for invalid names is also controller-driven (the controller
  /// re-arms [GitHubConnectionUi.repoPromptInitialName], which re-triggers
  /// this via the listener above).
  Future<void> _handleRepoPrompt(String initial) async {
    final name = await showGitHubRepoNameDialog(context, initial: initial);
    if (!mounted) return;
    final controller = ref.read(gitHubConnectionControllerProvider.notifier);
    if (name == null) {
      controller.skipRepoSetup();
    } else {
      await controller.createRepo(name);
    }
  }

  /// Opens the authorization dialog (fire-and-forget from the listener; the
  /// controller owns the flow's progress).
  Future<void> _showCodeDialog({
    required String userCode,
    required String verificationUri,
  }) async {
    _codeDialogOpen = true;
    await showGitHubUserCodeDialog(
      context,
      userCode: userCode,
      verificationUri: verificationUri,
    );
    _codeDialogOpen = false;
  }

  /// Closes the user-code dialog if it is still open (the flow reached a
  /// terminal state while the user had it on screen).
  void _dismissCodeDialog() {
    if (!_codeDialogOpen || !mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  // --- Intent forwarders (AGENTS §7): each hands a user action straight to
  // --- the controller; no decisions are made here.

  Future<void> _signIn() =>
      ref.read(gitHubConnectionControllerProvider.notifier).signIn();

  Future<void> _signOut() =>
      ref.read(gitHubConnectionControllerProvider.notifier).signOut();

  Future<void> _loadRepos() =>
      ref.read(gitHubConnectionControllerProvider.notifier).loadRepos();

  Future<void> _publish() =>
      ref.read(gitHubConnectionControllerProvider.notifier).publish();

  Future<void> _selectRepo(String fullName) => ref
      .read(gitHubConnectionControllerProvider.notifier)
      .selectRepo(fullName);

  void _requestRepoSetup() =>
      ref.read(gitHubConnectionControllerProvider.notifier).requestRepoSetup();

  Future<void> _copyPublishedUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  Future<void> _sharePublishedUrl(String url) async {
    // The sheet offers the visiting-card PNG or the plain link; both go
    // through the FileShareService seam so widget tests can fake them.
    await showShareLibrarySheet(context, url: url);
  }

  // --- Renderers -----------------------------------------------------------

  /// The GitHub tile's status (D3): green only when fully configured
  /// (signed in AND a target repo set — ready to publish), amber when
  /// signed in but the repo is missing, red when not signed in.
  ProviderConfig _githubStatus(GitHubConnectionUi ui) {
    if (!ui.signedIn) return ProviderConfig.notConfigured;
    return ui.targetRepo == null
        ? ProviderConfig.partial
        : ProviderConfig.configured;
  }

  /// The GitHub account section of the tile body.
  Widget _githubAccountSection(GitHubConnectionUi ui, {required bool idle}) {
    return ui.signedIn
        ? Row(
            children: [
              // Success state must read as CONFIRMED at a glance, not
              // as a plain label. Green isn't in the Material scheme,
              // so pick a brightness-aware shade: 400 on dark surfaces
              // (700 is too dim there), 700 on light (400 fails
              // contrast on white). N12: Flexible + ellipsis keep this
              // row from overflowing at 320px / large text.
              Expanded(
                child: Builder(
                  builder: (ctx) {
                    final green = Theme.of(ctx).brightness == Brightness.dark
                        ? Colors.green.shade400
                        : Colors.green.shade700;
                    return Row(
                      children: [
                        Icon(Icons.check_circle, size: 18, color: green),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Signed in',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              TextButton(
                onPressed: idle ? _signOut : null,
                child: const Text('Sign out'),
              ),
            ],
          )
        : FilledButton.icon(
            onPressed: idle ? _signIn : null,
            icon: const Icon(Icons.login),
            label: const Text('Sign in to GitHub'),
          );
  }

  /// The target-repository section; rendered only while signed in.
  Widget _targetRepoSection(GitHubConnectionUi ui, {required bool idle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ui.targetRepo != null) ...[
          Text('Current: ${ui.targetRepo}'),
          const SizedBox(height: 8),
        ],
        // Always available: create (or adopt) a public repo by name,
        // Pages enabled automatically — no GitHub dashboard needed.
        FilledButton.icon(
          onPressed: idle ? _requestRepoSetup : null,
          icon: const Icon(Icons.add),
          label: Text(
            ui.targetRepo == null
                ? 'Set up a repository'
                : 'Create a new repository',
          ),
        ),
        const SizedBox(height: 8),
        // Advanced path: pick one of your existing repos instead.
        OutlinedButton(
          onPressed: idle ? _loadRepos : null,
          child: const Text('Choose an existing repo (advanced)'),
        ),
        for (final r in ui.repos)
          ListTile(
            dense: true,
            enabled: idle,
            leading: Icon(
              r.fullName == ui.targetRepo
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(r.fullName),
            subtitle: r.isPrivate
                ? const Text('private (Pages needs a paid plan)')
                : null,
            onTap: () => _selectRepo(r.fullName),
          ),
        if (ui.reposTruncated)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Showing your ${ui.repos.length} most recently updated '
              'repositories. If yours is not listed, use "Create a '
              'new repository" instead.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _buildTab(GitHubConnectionUi ui) {
    final idle = ui.phase == GitHubConnectionPhase.idle;
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
        // S35: hosting providers are collapsible tiles — with both collapsed
        // the tab fits one screen (the point of the redesign). The status
        // badge (D3) reads configured / partial / not at a glance, and the
        // GitHub tile auto-expands unless fully configured (D4) so sign-in
        // and repo setup are never hidden behind a tap.
        ProviderTile(
          title: 'GitHub Pages',
          status: _githubStatus(ui),
          initiallyExpanded: _githubInitiallyExpanded ?? true,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _githubAccountSection(ui, idle: idle),
              if (ui.signedIn) ...[
                const SizedBox(height: 16),
                Text(
                  'Target repository',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                _targetRepoSection(ui, idle: idle),
              ],
            ],
          ),
        ),
        const CloudflareTile(),
        if (ui.signedIn)
          _SectionCard(
            title: 'Publish',
            child: FilledButton.icon(
              onPressed: (!idle || ui.targetRepo == null) ? null : _publish,
              icon: ui.phase == GitHubConnectionPhase.busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload),
              label: const Text('Publish catalogue now'),
            ),
          ),
        if (ui.publishedUrl != null)
          _SectionCard(
            title: 'Your site',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(ui.publishedUrl!),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _copyPublishedUrl(ui.publishedUrl!),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy link'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _sharePublishedUrl(ui.publishedUrl!),
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Share'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (ui.statusMessage != null) ...[
          const SizedBox(height: 8),
          Text(ui.statusMessage!),
        ],
      ],
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
