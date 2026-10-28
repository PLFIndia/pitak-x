/// GitHub and Cloudflare connection tab of the publish hub.
///
/// GitHub dialog plumbing stays here; Cloudflare has its own isolated section.
/// Both controllers own their business decisions and secret handling.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/publish/application/github_connection_controller.dart';
import 'package:pitaka/features/publish/presentation/widgets/cloudflare_connection_section.dart';
import 'package:pitaka/features/publish/presentation/widgets/github_connection_dialogs.dart';
import 'package:pitaka/features/publish/presentation/widgets/github_tile.dart';
import 'package:pitaka/features/publish/presentation/widgets/publish_card.dart';

/// The hosting-provider and current-site connection surface.
class ConnectionTab extends ConsumerStatefulWidget {
  /// Creates the connection tab.
  const ConnectionTab({super.key});

  @override
  ConsumerState<ConnectionTab> createState() => _ConnectionTabState();
}

class _ConnectionTabState extends ConsumerState<ConnectionTab> {
  bool? _githubInitiallyExpanded;
  bool _codeDialogOpen = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(gitHubConnectionControllerProvider, (prev, next) {
      final before = prev?.valueOrNull;
      final now = next.valueOrNull;
      if (now == null) return;
      if (before?.repoPromptInitialName == null &&
          now.repoPromptInitialName != null) {
        unawaited(_handleRepoPrompt(now.repoPromptInitialName!));
      }
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
        _dismissCodeDialog();
      }
    });

    final async = ref.watch(gitHubConnectionControllerProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (_, _) =>
          const Center(child: Text("Couldn't load your connection status.")),
      data: (ui) {
        _githubInitiallyExpanded ??= !(ui.signedIn && ui.targetRepo != null);
        return _buildTab(ui);
      },
    );
  }

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

  void _dismissCodeDialog() {
    if (!_codeDialogOpen || !mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _signIn() =>
      ref.read(gitHubConnectionControllerProvider.notifier).signIn();

  Future<void> _signOut() =>
      ref.read(gitHubConnectionControllerProvider.notifier).signOut();

  Future<void> _loadRepos() =>
      ref.read(gitHubConnectionControllerProvider.notifier).loadRepos();

  Future<void> _selectRepo(String fullName) => ref
      .read(gitHubConnectionControllerProvider.notifier)
      .selectRepo(fullName);

  void _requestRepoSetup() =>
      ref.read(gitHubConnectionControllerProvider.notifier).requestRepoSetup();

  Widget _buildTab(GitHubConnectionUi ui) {
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
        GitHubTile(
          ui: ui,
          initiallyExpanded: _githubInitiallyExpanded ?? true,
          onSignIn: _signIn,
          onSignOut: _signOut,
          onRequestRepoSetup: _requestRepoSetup,
          onLoadRepos: _loadRepos,
          onSelectRepo: _selectRepo,
        ),
        const CloudflareConnectionSection(),
        const PublishCard(),
        if (ui.statusMessage != null) ...[
          const SizedBox(height: 8),
          Text(ui.statusMessage!),
        ],
      ],
    );
  }
}
