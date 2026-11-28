/// The notice before a backup and before a restore (backup presentation,
/// backup rework BR9, decisions D5, D49 and D51).
///
/// WHY THIS FILE EXISTS (beginner note): both pages say the same kind of
/// thing before their run starts: how much free storage and memory the run
/// needs, how much this phone has, and whether that will do. So there is
/// ONE dialog, and each page passes in the notice to show and which run it
/// is. On the Restore page the dialog is also the confirmation: it says
/// that the library is replaced, and its button says "Restore" (D49, D51).
///
/// IT NEVER BLOCKS (decision D5). The dialog opens at once and fills in
/// when the figures are read. Both buttons are there in every state: while
/// the figures are still being read, when they could not be read, and
/// whatever the verdict is. The wording lives in
/// `resource_notice_messages.dart`; no business rule lives here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/backup/domain/resource_notice.dart';
import 'package:pitaka/features/backup/presentation/resource_notice_messages.dart';

/// Says what the run needs and what the phone has, and asks whether to go
/// on.
class ResourceNoticeDialog extends ConsumerWidget {
  /// Creates the dialog for [run], showing what [notice] works out.
  const ResourceNoticeDialog({
    required this.notice,
    required this.run,
    super.key,
  });

  /// The key of the button that closes the dialog without starting the run.
  static const Key cancelKey = Key('resource-notice-cancel');

  /// The key of the button that starts the run. (On the Restore page its
  /// label, "Restore", is also the label of the page's own button, so a
  /// test finds it by this key.)
  static const Key confirmKey = Key('resource-notice-confirm');

  /// The provider that works out the notice. Watched here, so the figures
  /// are read when the dialog opens and forgotten when it closes.
  final ProviderListenable<AsyncValue<ResourceNotice>> notice;

  /// Which run the dialog stands in front of.
  final ResourceNoticeRun run;

  /// Shows the dialog and resolves to the user's choice: `true` only for a
  /// tap on the button that starts the run. Cancel, the Back key and a tap
  /// outside the dialog all mean "do not start" (fail closed: a run that
  /// replaces a library starts only on an explicit yes).
  static Future<bool> ask(
    BuildContext context, {
    required ProviderListenable<AsyncValue<ResourceNotice>> notice,
    required ResourceNoticeRun run,
  }) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (_) => ResourceNoticeDialog(notice: notice, run: run),
    );
    return answer ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The three states of the read, each rendered explicitly (AGENTS.md
    // §7). An error cannot come from the app's own providers, which answer
    // "unknown" instead of failing; it is handled all the same.
    final lines = ref
        .watch(notice)
        .when(
          loading: () => const [resourceNoticeCheckingMessage],
          error: (_, _) => resourceNoticeUnreadLines(run),
          data: (notice) => resourceNoticeLines(notice, run),
        );
    return AlertDialog(
      title: Text(resourceNoticeTitle(run)),
      // Scrollable (the title and the sentences together): with a large
      // font they can be taller than the screen, and the two buttons, which
      // do not scroll, must stay reachable.
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (run == ResourceNoticeRun.restore) ...[
            const Text(resourceNoticeReplacesLibraryMessage),
            const SizedBox(height: 12),
          ],
          for (final (index, line) in lines.indexed) ...[
            if (index > 0) const SizedBox(height: 8),
            Text(line),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: cancelKey,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(resourceNoticeCancelLabel),
        ),
        FilledButton(
          key: confirmKey,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(resourceNoticeConfirmLabel(run)),
        ),
      ],
    );
  }
}
