/// Borrower profile screen (presentation layer, AGENTS.md §3.1).
///
/// Shows: name + contact + notes, live
/// stats (total loans, average return days, overdue rate), the currently-out
/// loans, and the returned history. Reads the computed [BorrowerProfile] from
/// the unlocked session; offers Edit and (when no active loans) Delete. Marks
/// a loan returned inline, and takes a return back from the History. All
/// vault work goes through the session controller.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/text/display_date.dart';
import 'package:pitaka/features/vault/domain/borrower_profile.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/value_objects/borrower_contact.dart';
import 'package:pitaka/features/vault/presentation/pages/borrower_edit_page.dart';
import 'package:pitaka/features/vault/presentation/widgets/loan_return_action.dart';
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
            for (final loan in profile.active)
              // The key ties a row, and the busy state of its button, to
              // its LOAN. Without it Flutter matches rows by their place,
              // and when the first row goes the next takes over its state.
              _ActiveLoanTile(
                key: ValueKey('profile-loan-${loan.id}'),
                loan: loan,
              ),
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
  static String formatDate(int? epochMillis) =>
      formatDisplayDateOrNull(epochMillis) ?? '—';
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
        ? 'Item #$bookId'
        : title;
    return Text(text, overflow: TextOverflow.ellipsis);
  }
}

/// An out-on-loan row (N06): the item's title, its due date, and "Mark
/// returned". The button, its busy state, the bar with "Undo" and the
/// failure sentences are the shared ones of loan_return_action.dart (review
/// finding P4-M3), so this row holds no rule and no state of its own. On
/// success the session changes, the profile rebuilds, and the loan moves to
/// History by itself.
class _ActiveLoanTile extends StatelessWidget {
  const _ActiveLoanTile({required this.loan, super.key});

  final Loan loan;

  @override
  Widget build(BuildContext context) {
    return _LoanRow(
      bookId: loan.itemId,
      line: BorrowerProfilePage.dueLabel(loan),
      action: MarkReturnedButton(loanId: loan.id),
    );
  }
}

/// One loan as a row: the item's title, one line under it, and one button.
///
/// A `Wrap`, not a `ListTile` (beginner note): a `ListTile` refuses to lay
/// out a trailing widget that needs the whole width, and "Mark returned" at
/// twice the text size does. In a `Wrap` the button stands beside the text
/// while both fit and moves under it when they do not: the same idea as the
/// stats card above (N12). The words stay whole either way (D109).
class _LoanRow extends StatelessWidget {
  const _LoanRow({
    required this.bookId,
    required this.line,
    required this.action,
  });

  final int bookId;
  final String line;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle.merge(
                style: theme.textTheme.bodyLarge,
                child: _LoanTitle(bookId: bookId),
              ),
              Text(
                line,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          action,
        ],
      ),
    );
  }
}

/// A returned-loan history row (N06) with the resolved book title, and the
/// lasting way to take a return back: "Not returned" asks first, then puts
/// the loan back under "Currently out" with the dates it had (D114).
class _ReturnedLoanTile extends StatelessWidget {
  const _ReturnedLoanTile({required this.loan});

  final Loan loan;

  @override
  Widget build(BuildContext context) {
    return _LoanRow(
      bookId: loan.itemId,
      line: 'Returned ${BorrowerProfilePage.formatDate(loan.returnedDate)}',
      action: TextButton(
        onPressed: () => confirmAndReopenLoan(context, loanId: loan.id),
        child: const Text(notReturnedLabel),
      ),
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
