/// Borrower profile screen (presentation layer, AGENTS.md §3.1).
///
/// Port of Kotlin `BorrowerProfileScreen` (D31): name + contact + notes, live
/// stats (total loans, average return days, overdue rate), the currently-out
/// loans, and the returned history. Reads the computed [BorrowerProfile] from
/// the unlocked session; offers Edit and (when no active loans) Delete. Returns
/// a loan inline. All vault work goes through the session controller.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/borrower_profile.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/value_objects/borrower_contact.dart';
import 'package:pitaka/features/vault/presentation/pages/borrower_edit_page.dart';
import 'package:url_launcher/url_launcher.dart';

/// Displays a borrower's details, stats, and loan history.
class BorrowerProfilePage extends ConsumerWidget {
  /// Creates the profile page for the borrower with [borrowerId].
  const BorrowerProfilePage({required this.borrowerId, super.key});

  /// The borrower whose profile to show.
  final int borrowerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(borrowerProfileProvider(borrowerId));
    if (profile == null) {
      // Locked, or the borrower no longer exists.
      return Scaffold(
        appBar: AppBar(title: const Text('Borrower')),
        body: const Center(child: Text('This borrower is not available.')),
      );
    }

    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(profile.borrower.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BorrowerEditPage(existing: profile.borrower),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ContactSection(
            contact: BorrowerContact.decode(profile.borrower.contact),
          ),
          if (profile.borrower.notes != null &&
              profile.borrower.notes!.trim().isNotEmpty)
            _Field(label: 'Notes', value: profile.borrower.notes!),
          const SizedBox(height: 16),
          _StatsCard(stats: profile.stats),
          const SizedBox(height: 24),
          Text('Currently out', style: textTheme.titleMedium),
          if (profile.active.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Nothing out right now.'),
            )
          else
            for (final loan in profile.active) _ActiveLoanTile(loan: loan),
          const SizedBox(height: 16),
          Text('History', style: textTheme.titleMedium),
          if (profile.returned.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No returned loans yet.'),
            )
          else
            for (final loan in profile.returned) _ReturnedLoanTile(loan: loan),
        ],
      ),
    );
  }

  /// Due-date label for a loan row (shared with the loan tiles, N06).
  static String dueLabel(Loan loan) {
    if (loan.dueDate == null) return 'No due date';
    return 'Due ${formatDate(loan.dueDate)}';
  }

  /// YYYY-MM-DD for epoch millis (shared with the loan tiles, N06).
  static String formatDate(int? epochMillis) {
    if (epochMillis == null) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(epochMillis);
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}

/// Resolves a loan's book title through the [bookTitleProvider] read model
/// (N06), falling back to the internal id when the book is gone.
class _LoanTitle extends ConsumerWidget {
  const _LoanTitle({required this.bookId});

  final int bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ref.watch(bookTitleProvider(bookId: bookId)).valueOrNull;
    final text = (title == null || title.trim().isEmpty)
        ? 'Book #$bookId'
        : title;
    return Text(text, overflow: TextOverflow.ellipsis);
  }
}

/// An out-on-loan row (N06): shows the book title, per-return progress, and
/// a typed failure message instead of silently doing nothing. Returning an
/// already-returned loan is a no-op (idempotent).
class _ActiveLoanTile extends ConsumerStatefulWidget {
  const _ActiveLoanTile({required this.loan});

  final Loan loan;

  @override
  ConsumerState<_ActiveLoanTile> createState() => _ActiveLoanTileState();
}

class _ActiveLoanTileState extends ConsumerState<_ActiveLoanTile> {
  bool _busy = false;

  Future<void> _return() async {
    // Idempotent: a loan that is already returned is never written again.
    if (_busy || widget.loan.returnedDate != null) return;
    setState(() => _busy = true);
    final result = await ref
        .read(vaultSessionControllerProvider.notifier)
        .updateLoan(
          widget.loan.copyWith(
            returnedDate: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isLeft()) {
      // Safe message only — the Failure reason is never user-facing (§5).
      final failure = result.swap().toNullable();
      final message = failure is NotFoundFailure
          ? 'That loan no longer exists.'
          : 'Could not return this book. Please try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
    // On success the session state changes, the profile rebuilds, and this
    // loan moves to History on its own.
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: _LoanTitle(bookId: widget.loan.bookId),
      subtitle: Text(BorrowerProfilePage.dueLabel(widget.loan)),
      trailing: TextButton(
        onPressed: _busy ? null : _return,
        child: _busy
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Return'),
      ),
    );
  }
}

/// A returned-loan history row (N06) with the resolved book title.
class _ReturnedLoanTile extends StatelessWidget {
  const _ReturnedLoanTile({required this.loan});

  final Loan loan;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: _LoanTitle(bookId: loan.bookId),
      subtitle: Text(
        'Returned ${BorrowerProfilePage.formatDate(loan.returnedDate)}',
      ),
      trailing: const Icon(Icons.check_circle_outline),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final BorrowerStats stats;

  @override
  Widget build(BuildContext context) {
    final avg = stats.averageReturnDays;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        // N12: a Wrap instead of a fixed Row — at 320px or large text the
        // stats flow onto a second line instead of overflowing.
        child: Wrap(
          alignment: WrapAlignment.spaceAround,
          runAlignment: WrapAlignment.spaceAround,
          spacing: 16,
          runSpacing: 12,
          children: [
            _Stat(label: 'Loans', value: '${stats.totalLoans}'),
            _Stat(
              label: 'Avg return',
              value: avg == null ? '—' : '${avg.toStringAsFixed(1)}d',
            ),
            _Stat(
              label: 'Overdue',
              value: '${(stats.overdueRate * 100).round()}%',
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(value, style: textTheme.titleLarge),
        Text(label, style: textTheme.labelMedium),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.labelMedium),
          Text(value, style: textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// Renders the borrower's contact with action buttons: call + WhatsApp next to
/// a phone, email next to an email. Each button fires a device intent via an
/// external app; the value is never auto-dialled or logged. Nothing renders
/// when there is no contact at all.
class _ContactSection extends StatelessWidget {
  const _ContactSection({required this.contact});

  final BorrowerContact contact;

  // Per-kind actions ONLY (REVIEW_FINDINGS_2 S9): there is deliberately no
  // general "launch this string" helper on this page — each action asks
  // [BorrowerContact] for its own validated URI, so a future caller cannot
  // launch an arbitrary/injected URI by mistake.
  Future<void> _openCall(BuildContext context) =>
      _open(context, contact.telUri);

  Future<void> _openWhatsApp(BuildContext context) =>
      _open(context, contact.whatsappUri);

  Future<void> _openEmail(BuildContext context) =>
      _open(context, contact.mailtoUri);

  /// Launches a URI constructed by [BorrowerContact]'s validated builders
  /// (digit-filtered tel/wa.me parts, regex-validated mailto) — never an
  /// arbitrary caller-supplied string. Null means the contact part was
  /// missing/invalid; the buttons aren't rendered then, so this is defensive.
  Future<void> _open(BuildContext context, String? uri) async {
    final parsed = uri == null ? null : Uri.tryParse(uri);
    if (parsed == null) return;
    final ok = await launchUrl(parsed, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No app available for that action.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (contact.isEmpty) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    final tel = contact.telUri;
    final wa = contact.whatsappUri;
    final mail = contact.mailtoUri;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Contact', style: textTheme.labelMedium),
        const SizedBox(height: 4),
        if (contact.phone.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(contact.phone, style: textTheme.bodyLarge),
                ),
                if (tel != null)
                  IconButton(
                    icon: const Icon(Icons.call),
                    tooltip: 'Call',
                    onPressed: () => _openCall(context),
                  ),
                if (wa != null)
                  IconButton(
                    icon: const FaIcon(
                      FontAwesomeIcons.whatsapp,
                      color: Color(0xFF25D366), // WhatsApp brand green
                    ),
                    tooltip: 'WhatsApp',
                    onPressed: () => _openWhatsApp(context),
                  ),
              ],
            ),
          ),
        if (contact.email.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(contact.email, style: textTheme.bodyLarge),
                ),
                if (mail != null)
                  IconButton(
                    icon: const Icon(Icons.email_outlined),
                    tooltip: 'Email',
                    onPressed: () => _openEmail(context),
                  ),
              ],
            ),
          ),
        if (contact.other.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(contact.other, style: textTheme.bodyLarge),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}
