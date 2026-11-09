/// Vault-gated Borrowed Items destination and reminder share hand-off.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/platform/file_share.dart';
import 'package:pitaka/features/library/presentation/pages/catalogue_item_detail_page.dart';
import 'package:pitaka/features/vault/application/reminder_templates_controller.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/borrowed_items.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/loan_reminder_preparation.dart';
import 'package:pitaka/features/vault/domain/value_objects/borrower_contact.dart';
import 'package:pitaka/features/vault/presentation/pages/vault_page.dart';
import 'package:pitaka/features/vault/presentation/widgets/borrowed_items_content.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows one actionable card per active loan, never stale content when locked.
final class BorrowedItemsPage extends ConsumerStatefulWidget {
  /// Creates the Borrowed Items destination.
  const BorrowedItemsPage({super.key});

  @override
  ConsumerState<BorrowedItemsPage> createState() => _BorrowedItemsPageState();
}

class _BorrowedItemsPageState extends ConsumerState<BorrowedItemsPage> {
  BorrowedItemsFilter _filter = BorrowedItemsFilter.all;
  final Set<int> _busyLoanIds = <int>{};

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(vaultSessionControllerProvider);
    return Scaffold(
      // No app-bar actions: message templates are picked and managed in the
      // ReminderTemplateCard at the top of the unlocked content.
      appBar: AppBar(title: const Text('Borrowed Items')),
      body: session.when(
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (_, _) => _SessionError(
          onRetry: () => ref.invalidate(vaultSessionControllerProvider),
        ),
        data: (state) => switch (state) {
          VaultUninitialized() => const _VaultGate(
            text: 'Set up the borrowers vault to see borrowed items.',
            button: 'Set up the vault',
          ),
          VaultLocked() => const _VaultGate(
            text: 'Unlock the vault to see borrowed items.',
            button: 'Unlock the vault',
          ),
          VaultUnlocked() => BorrowedItemsContent(
            filter: _filter,
            onFilterChanged: (filter) => setState(() => _filter = filter),
            busyLoanIds: _busyLoanIds,
            onOpen: _openItem,
            onCall: _callBorrower,
            onShare: _prepareAndShare,
            onWhatsAppText: _prepareWhatsAppText,
          ),
        },
      ),
    );
  }

  void _openItem(BorrowedLoan entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CatalogueItemDetailPage(
          bookId: entry.item.id,
          initialBook: entry.item,
        ),
      ),
    );
  }

  Future<void> _callBorrower(BorrowedLoan entry) async {
    final raw = BorrowerContact.decode(entry.borrower.contact).telUri;
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri == null) return;
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      opened = false;
    }
    if (mounted && !opened) {
      _show('No app available for that call.');
    }
  }

  Future<void> _prepareAndShare(
    BorrowedLoan entry,
    BuildContext buttonContext,
  ) async {
    final loanId = entry.loan.id;
    if (_busyLoanIds.contains(loanId) || !_canHandOff()) return;
    final origin = _shareOrigin(buttonContext);
    setState(() => _busyLoanIds.add(loanId));
    try {
      // Read the selection at tap time, never a stale build-time template.
      final settingsRead = await ref
          .read(reminderTemplatesControllerProvider.notifier)
          .loaded();
      if (!_canHandOff()) return;
      final settings = settingsRead.toNullable();
      if (settings == null) {
        _show('Choose a valid message template before sharing.');
        return;
      }
      final prepare = await ref.read(prepareLoanReminderUseCaseProvider.future);
      if (!_canHandOff()) return;
      final prepared = await prepare(entry: entry, settings: settings);
      if (!_canHandOff()) return;

      final share = ref.read(fileShareServiceProvider);
      final ShareOutcome? outcome;
      switch (prepared) {
        case LoanReminderImageReady():
          outcome = await share.shareBytes(
            bytes: prepared.bytes,
            fileName: prepared.fileName,
            mimeType: prepared.mimeType,
            text: prepared.caption,
            sharePositionOrigin: origin,
          );
        case LoanReminderTextOnlyEligible(:final caption):
          final confirmed = await _offerTextOnly();
          if (confirmed != true || !_canHandOff()) return;
          outcome = await share.shareText(caption, sharePositionOrigin: origin);
        case LoanReminderPreparationFailure(:final reason):
          _show(switch (reason) {
            LoanReminderPreparationFailureReason.templateUnavailable =>
              'Choose a valid template and keep the reminder under 1,000 '
                  'characters.',
            LoanReminderPreparationFailureReason.coverPreparationFailed =>
              "Couldn't prepare the cover. Fix or remove the local cover, "
                  'then try again.',
          });
          return;
      }
      if (!mounted) return;
      if (outcome == ShareOutcome.unavailable) {
        _show('Sharing is not available on this device.');
      }
      // Dismissed needs no message; success is a hand-off, never "sent".
    } on Object {
      if (mounted) _show("Couldn't prepare or open sharing. Please try again.");
    } finally {
      if (mounted) setState(() => _busyLoanIds.remove(loanId));
    }
  }

  Future<void> _prepareWhatsAppText(BorrowedLoan entry) async {
    final loanId = entry.loan.id;
    if (_busyLoanIds.contains(loanId) || !_canHandOff()) return;
    setState(() => _busyLoanIds.add(loanId));
    try {
      final settingsRead = await ref
          .read(reminderTemplatesControllerProvider.notifier)
          .loaded();
      if (!_canHandOff()) return;
      final settings = settingsRead.toNullable();
      if (settings == null) {
        _show('Choose a valid message template before sharing.');
        return;
      }
      final prepare = await ref.read(prepareLoanReminderUseCaseProvider.future);
      if (!_canHandOff()) return;
      final rendered = await prepare.renderCaption(
        entry: entry,
        settings: settings,
      );
      if (!_canHandOff()) return;
      final caption = rendered.toNullable();
      if (caption == null) {
        _show(
          'Choose a valid template and keep the reminder under 1,000 '
          'characters.',
        );
        return;
      }
      final raw = BorrowerContact.decode(entry.borrower.contact).whatsappUri;
      if (raw == null) return;
      // WhatsApp specifies percent-encoded text. `queryParameters` would use
      // form encoding (`+` for spaces), which is not verified to decode there.
      final uri = Uri.parse(
        raw,
      ).replace(query: 'text=${Uri.encodeComponent(caption)}');
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted && !opened) {
        _show('Could not open WhatsApp on this device.');
      }
      // A successful launch only opens the conversation; it is not a send.
    } on Object {
      if (mounted) _show('Could not open WhatsApp on this device.');
    } finally {
      if (mounted) setState(() => _busyLoanIds.remove(loanId));
    }
  }

  Future<bool?> _offerTextOnly() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Share text only?'),
        content: const Text(
          'There is no usable local cover reference. No cover will be '
          'downloaded. You can share the reminder as text instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Share text only'),
          ),
        ],
      ),
    );
  }

  bool _canHandOff() {
    if (!mounted) return false;
    final session = ref.read(vaultSessionControllerProvider);
    // valueOrNull can contain a PREVIOUS VaultUnlocked while the current
    // session is loading or has failed. Only current data authorizes
    // disclosure.
    return session.unwrapPrevious().valueOrNull is VaultUnlocked;
  }

  Rect? _shareOrigin(BuildContext buttonContext) {
    final box = buttonContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

final class _VaultGate extends StatelessWidget {
  const _VaultGate({required this.text, required this.button});
  final String text;
  final String button;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const VaultPage()),
              ),
              child: Text(button),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SessionError extends StatelessWidget {
  const _SessionError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Couldn't load borrowed items."),
          const SizedBox(height: 8),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
