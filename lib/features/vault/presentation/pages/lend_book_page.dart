/// Lend-a-book screen (presentation layer, AGENTS.md §3.1).
///
/// Mirrors Kotlin `LendBookUseCase` (D25): lend a specific book to either an
/// existing borrower or a newly-created one, with an optional due date and
/// notes. Requires the vault to be UNLOCKED (it reads borrowers from the
/// session). The decision + writes live in the application-layer
/// `LendBookUseCase`, which refuses a removed or fully-lent book with a
/// plain-language reason that this screen shows verbatim.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/core/text/display_date.dart';
import 'package:pitaka/features/vault/application/lend_book_use_case.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';

/// Screen to lend the item with [bookId] (and [bookTitle] for display).
class LendBookPage extends ConsumerStatefulWidget {
  /// Creates the lend screen for the given library book.
  const LendBookPage({
    required this.bookId,
    required this.bookTitle,
    super.key,
  });

  /// The library book id being lent.
  final int bookId;

  /// The book title (display only).
  final String bookTitle;

  @override
  ConsumerState<LendBookPage> createState() => _LendBookPageState();
}

final class _LendSubmission {
  const _LendSubmission({
    required this.target,
    required this.borrowerName,
    required this.lentDate,
    required this.dueDate,
    required this.notes,
  });

  final LendTarget target;
  final String? borrowerName;
  final int lentDate;
  final int? dueDate;
  final String? notes;
}

class _LendBookPageState extends ConsumerState<LendBookPage> {
  /// Selected existing borrower id, or null when creating a new borrower.
  int? _borrowerId;
  final TextEditingController _newName = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  DateTime? _dueDate;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _newName.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _trimOrNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  static String _fmtDate(DateTime d) => formatDisplayDateTime(d);

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _lend(List<Borrower> borrowers) async {
    // Capture WHO and WHAT once. A Warn confirmation retries this exact
    // submission, never values that could change during an asynchronous gap.
    final LendTarget target;
    String? borrowerName;
    final borrowerId = _borrowerId;
    if (borrowerId != null) {
      target = ExistingBorrower(borrowerId);
      for (final borrower in borrowers) {
        if (borrower.id == borrowerId) {
          borrowerName = borrower.name;
          break;
        }
      }
    } else {
      final name = _newName.text.trim();
      if (name.isEmpty) {
        setState(() => _error = 'Pick a borrower or enter a new name.');
        return;
      }
      target = NewBorrower(name);
    }
    await _submit(
      _LendSubmission(
        target: target,
        borrowerName: borrowerName,
        lentDate: DateTime.now().millisecondsSinceEpoch,
        dueDate: _dueDate?.millisecondsSinceEpoch,
        notes: _trimOrNull(_notes.text),
      ),
    );
  }

  Future<void> _submit(
    _LendSubmission submission, {
    bool limitWarningAcknowledged = false,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final useCase = await ref.read(lendBookUseCaseProvider.future);
    final result = await useCase(
      bookId: widget.bookId,
      target: submission.target,
      lentDate: submission.lentDate,
      dueDate: submission.dueDate,
      notes: submission.notes,
      limitWarningAcknowledged: limitWarningAcknowledged,
    );
    if (!mounted) return;
    final failure = result.swap().toNullable();
    if (failure != null) {
      setState(() {
        _busy = false;
        _error = _messageFor(failure);
      });
      return;
    }
    switch (result.toNullable()!) {
      case LoanRecorded():
        Navigator.of(context).pop();
      case LimitConfirmationNeeded(:final limit, :final active):
        final confirmed = await _confirmLimit(
          submission.borrowerName,
          limit,
          active,
        );
        if (!mounted) return;
        if (confirmed != true) {
          setState(() => _busy = false);
          return;
        }
        await _submit(submission, limitWarningAcknowledged: true);
    }
  }

  Future<bool?> _confirmLimit(String? borrowerName, int limit, int active) {
    final subject = borrowerName == null
        ? 'This borrower'
        : 'Borrower $borrowerName';
    final noun = active == 1 ? 'item' : 'items';
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Borrower limit reached'),
        content: Text(
          '$subject has $active $noun out; your limit is $limit. Lend anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Lend anyway'),
          ),
        ],
      ),
    );
  }

  static String _messageFor(Failure f) => switch (f) {
    ValidationFailure(:final message) => message,
    NotFoundFailure() => 'That item or borrower no longer exists.',
    _ => 'Could not lend the item. Please try again.',
  };

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(vaultSessionControllerProvider).valueOrNull;
    final scheme = Theme.of(context).colorScheme;

    if (session is! VaultUnlocked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lend item')),
        body: const Center(child: Text('Unlock the vault to lend an item.')),
      );
    }
    final borrowers = session.data.borrowers;

    return Scaffold(
      appBar: AppBar(title: const Text('Lend item')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Lending: ${widget.bookTitle}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Text('Borrower', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (borrowers.isNotEmpty)
            DropdownButtonFormField<int?>(
              initialValue: _borrowerId,
              // N12: long borrower names must ellipsize inside the field
              // instead of overflowing it (320px / large text).
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Existing borrower',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(
                  child: Text('New borrower…', overflow: TextOverflow.ellipsis),
                ),
                for (final b in borrowers)
                  DropdownMenuItem(
                    value: b.id,
                    child: Text(b.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _busy ? null : (v) => setState(() => _borrowerId = v),
            ),
          if (_borrowerId == null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _newName,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'New borrower name',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Due date (optional)'),
            subtitle: Text(
              _dueDate == null ? 'No due date' : _fmtDate(_dueDate!),
            ),
            trailing: TextButton(
              onPressed: _busy ? null : _pickDueDate,
              child: const Text('Pick'),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            enabled: !_busy,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : () => _lend(borrowers),
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Lend'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
    );
  }
}
