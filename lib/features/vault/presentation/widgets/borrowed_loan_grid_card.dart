/// Wide-screen grid presentation of one active loan.
library;

import 'package:flutter/material.dart';
import 'package:pitaka/core/widgets/item_cover.dart';
import 'package:pitaka/features/vault/domain/borrowed_items.dart';
import 'package:pitaka/features/vault/presentation/widgets/borrowed_loan_shared.dart';

/// A cover-forward card with room for borrower details and actions.
final class BorrowedLoanGridCard extends StatelessWidget {
  /// Creates a wide-screen card for one active loan.
  const BorrowedLoanGridCard({
    required this.entry,
    required this.busy,
    required this.onTap,
    required this.onCall,
    required this.onShare,
    required this.onWhatsAppText,
    super.key,
  });

  /// Complete active-loan read model.
  final BorrowedLoan entry;

  /// Whether this loan's reminder action is busy.
  final bool busy;

  /// Opens catalogue detail.
  final VoidCallback onTap;

  /// Sanitized dialer action, or null when no phone is available.
  final VoidCallback? onCall;

  /// Prepares a generic cover/caption share with the button's global rect.
  final void Function(BuildContext buttonContext) onShare;

  /// Opens the borrower's WhatsApp conversation with text only, when available.
  final VoidCallback? onWhatsAppText;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ItemCover(
                title: entry.item.title,
                coverUrl: entry.coverUrl,
                // Owner-less means local-only display, never a download.
                // ignore: avoid_redundant_argument_values, explicit privacy gate
                owner: null,
                width: 96,
                height: 132,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BorrowedLoanSummary(entry: entry),
                    BorrowedLoanActions(
                      busy: busy,
                      onCall: onCall,
                      onShare: onShare,
                      onWhatsAppText: onWhatsAppText,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
