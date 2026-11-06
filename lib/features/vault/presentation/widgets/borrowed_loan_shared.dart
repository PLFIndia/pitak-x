/// Shared details and actions for Borrowed Items row/grid cards.
library;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pitaka/features/library/domain/value_objects/item_kind.dart';
import 'package:pitaka/features/vault/domain/borrowed_items.dart';
import 'package:pitaka/features/vault/domain/loan_status.dart';
import 'package:pitaka/features/vault/domain/value_objects/borrower_contact.dart';

/// Title, author, badges, due date, borrower and decoded phone.
final class BorrowedLoanSummary extends StatelessWidget {
  /// Creates the textual summary for [entry].
  const BorrowedLoanSummary({required this.entry, super.key});

  /// Complete active-loan read model.
  final BorrowedLoan entry;

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final contact = BorrowerContact.decode(entry.borrower.contact);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (item.author?.trim().isNotEmpty ?? false)
          Text(
            item.author!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            if (_kindLabel(item.kind, entry) case final label?)
              _Badge(label: label, tone: _BadgeTone.neutral),
            _Badge(
              label: _urgencyLabel(entry.urgency),
              tone: _tone(entry.urgency),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(_dueLabel(entry)),
        Text('Borrower: ${entry.borrower.name}'),
        if (contact.phone.trim().isNotEmpty) Text('Phone: ${contact.phone}'),
      ],
    );
  }
}

/// Call, generic share, and direct WhatsApp text actions for one loan.
final class BorrowedLoanActions extends StatelessWidget {
  /// Creates call/share actions for one loan.
  const BorrowedLoanActions({
    required this.busy,
    required this.onCall,
    required this.onShare,
    required this.onWhatsAppText,
    super.key,
  });

  /// Whether this loan's reminder action is busy.
  final bool busy;

  /// Sanitized dialer action, or null when no phone is available.
  final VoidCallback? onCall;

  /// Prepares a generic cover/caption share with the button's global rect.
  final void Function(BuildContext buttonContext) onShare;

  /// Opens the borrower's WhatsApp conversation with text only, or null when
  /// no sanitized phone number is available.
  final VoidCallback? onWhatsAppText;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (onCall != null)
          IconButton(
            tooltip: 'Call borrower',
            onPressed: busy ? null : onCall,
            icon: const Icon(Icons.call_outlined),
          ),
        // A disabled IconButton can otherwise let the parent card's InkWell
        // open details on a duplicate tap. Consume only this busy action.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: busy ? () {} : null,
          child: Builder(
            builder: (buttonContext) => IconButton(
              tooltip: 'Share loan reminder',
              onPressed: busy ? null : () => onShare(buttonContext),
              icon: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share, size: 20),
            ),
          ),
        ),
        if (onWhatsAppText != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: busy ? () {} : null,
            child: IconButton(
              tooltip: 'WhatsApp borrower (text only)',
              onPressed: busy ? null : onWhatsAppText,
              icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 20),
            ),
          ),
      ],
    );
  }
}

String? _kindLabel(ItemKind kind, BorrowedLoan entry) => switch (kind) {
  ItemKind.book => null,
  ItemKind.magazineIssue =>
    entry.item.issue?.isBound ?? false ? 'Bound volume' : 'Issue',
  ItemKind.other => 'Other',
};

String _urgencyLabel(LoanUrgency urgency) => switch (urgency) {
  LoanUrgency.overdue => 'Overdue',
  LoanUrgency.dueSoon => 'Due soon',
  LoanUrgency.dueLater => 'Due later',
  LoanUrgency.noDueDate => 'No due date',
};

String _dueLabel(BorrowedLoan entry) {
  final due = entry.loan.dueDate;
  return due == null ? 'No return date set' : 'Due ${formatLoanDate(due)}';
}

enum _BadgeTone { neutral, overdue, soon, later }

_BadgeTone _tone(LoanUrgency urgency) => switch (urgency) {
  LoanUrgency.overdue => _BadgeTone.overdue,
  LoanUrgency.dueSoon => _BadgeTone.soon,
  LoanUrgency.dueLater => _BadgeTone.later,
  LoanUrgency.noDueDate => _BadgeTone.neutral,
};

final class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.tone});
  final String label;
  final _BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      _BadgeTone.overdue => (scheme.errorContainer, scheme.onErrorContainer),
      _BadgeTone.soon => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _BadgeTone.later => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      _BadgeTone.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}
