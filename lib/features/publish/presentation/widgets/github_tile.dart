/// The GitHub Pages provider tile of the publish Connection tab (S35, D3/D4).
///
/// Extracted verbatim out of `publish_page.dart` (Cloudflare plan S0: widget
/// extraction before new behavior). It is render-only: every user action is
/// forwarded through the callbacks the page supplies, so the widget holds no
/// state and makes no decisions (AGENTS §7).
library;

import 'package:flutter/material.dart';
import 'package:pitaka/features/publish/application/github_connection_controller.dart';
import 'package:pitaka/features/publish/presentation/widgets/provider_tile.dart';

/// Hosting status for the GitHub tile (D3): green only when fully configured
/// (signed in AND a target repo set — ready to publish), amber when signed in
/// but the repo is missing, red when not signed in.
ProviderConfig gitHubProviderConfig(GitHubConnectionUi ui) {
  if (!ui.signedIn) return ProviderConfig.notConfigured;
  return ui.targetRepo == null
      ? ProviderConfig.partial
      : ProviderConfig.configured;
}

/// The GitHub Pages tile: account section plus (while signed in) the target
/// repository section, all inside one collapsible [ProviderTile].
class GitHubTile extends StatelessWidget {
  /// Creates the tile over the controller's current [ui] snapshot.
  const GitHubTile({
    required this.ui,
    required this.initiallyExpanded,
    required this.onSignIn,
    required this.onSignOut,
    required this.onRequestRepoSetup,
    required this.onLoadRepos,
    required this.onSelectRepo,
    super.key,
  });

  /// The controller's rendered state (D3 status + sections).
  final GitHubConnectionUi ui;

  /// D4 latch: the tile's INITIAL expansion, decided once by the page from
  /// the first loaded state (auto-expand unless fully configured).
  final bool initiallyExpanded;

  /// Starts the device flow.
  final VoidCallback onSignIn;

  /// Forgets the token (and target) on this device.
  final VoidCallback onSignOut;

  /// Opens the repo-name prompt (create/adopt a repository).
  final VoidCallback onRequestRepoSetup;

  /// Loads the advanced repo picker list.
  final VoidCallback onLoadRepos;

  /// Picks one of the listed repositories.
  final void Function(String fullName) onSelectRepo;

  @override
  Widget build(BuildContext context) {
    final idle = ui.phase == GitHubConnectionPhase.idle;
    return ProviderTile(
      title: 'GitHub Pages',
      status: gitHubProviderConfig(ui),
      initiallyExpanded: initiallyExpanded,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _accountSection(context, idle: idle),
          if (ui.signedIn) ...[
            const SizedBox(height: 16),
            Text(
              'Target repository',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _targetRepoSection(context, idle: idle),
          ],
        ],
      ),
    );
  }

  /// The GitHub account section of the tile body.
  Widget _accountSection(BuildContext context, {required bool idle}) {
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
                onPressed: idle ? onSignOut : null,
                child: const Text('Sign out'),
              ),
            ],
          )
        : FilledButton.icon(
            onPressed: idle ? onSignIn : null,
            icon: const Icon(Icons.login),
            label: const Text('Sign in to GitHub'),
          );
  }

  /// The target-repository section; rendered only while signed in.
  Widget _targetRepoSection(BuildContext context, {required bool idle}) {
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
          onPressed: idle ? onRequestRepoSetup : null,
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
          onPressed: idle ? onLoadRepos : null,
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
            onTap: () => onSelectRepo(r.fullName),
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
}
