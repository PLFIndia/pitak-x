/// Dialogs of the GitHub connection tab (presentation, AGENTS §7).
///
/// WHEN a dialog appears is a controller decision (driven by
/// `GitHubConnectionUi` state); these functions only render the dialog and
/// return the user's answer. Kept out of the page file so `publish_page.dart`
/// stays a thin renderer (SOLID-PLAN S1).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pitaka/features/publish/domain/github_oauth_app.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows the "authorize in your browser" instructions for the device flow.
///
/// The device flow keeps polling in the controller while this dialog is up —
/// nothing here suspends it. The page pops the dialog itself when the flow
/// reaches a terminal state (the controller clears the code from its state).
Future<void> showGitHubUserCodeDialog(
  BuildContext context, {
  required String userCode,
  required String verificationUri,
}) async {
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
          const SizedBox(height: 8),
          // Escape hatch for devices whose OS still kills the app while
          // the user is off in the browser (aggressive OEM app freezers):
          // entering the code on a SECOND device needs no app switch at
          // all, so polling here is never interrupted.
          Builder(
            builder: (ctx) => Text(
              'Tip: sign-in not completing? Keep this screen open and '
              'enter the code in a browser on another device (like a '
              'computer) instead.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
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

/// Prompts for a repository name, pre-filled with [initial]. Returns the
/// trimmed name, or null when the user backed out ("Later" / barrier).
Future<String?> showGitHubRepoNameDialog(
  BuildContext context, {
  required String initial,
}) {
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
