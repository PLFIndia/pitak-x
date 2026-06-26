/// Lend-a-book screen (presentation layer, AGENTS.md §3.1).
///
/// Mirrors Kotlin `LendBookUseCase` (D25): lend a specific book to either an
/// existing borrower or a newly-created one, with an optional due date and
/// notes. Requires the vault to be UNLOCKED (it reads borrowers from the
/// session and writes the loan through it). Creating a borrower inline is done
/// via the session's `addBorrower`, then the loan via `addLoan`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';

/// Screen to lend the book with [bookId] (and [bookTitle] for display).
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

  static String _fmtDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

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
    setState(() {
      _busy = true;
      _error = null;
    });
    final notifier = ref.read(vaultSessionControllerProvider.notifier);

    // Resolve the borrower id: existing selection, or create one inline.
    var borrowerId = _borrowerId;
    if (borrowerId == null) {
      final name = _newName.text.trim();
      if (name.isEmpty) {
        setState(() {
          _busy = false;
          _error = 'Pick a borrower or enter a new name.';
        });
        return;
      }
      final created = await notifier.addBorrower(Borrower(name: name));
      if (!mounted) return;
      final failed = created.fold((f) => f, (_) => null);
      if (failed != null) {
        setState(() {
          _busy = false;
          _error = _messageFor(failed);
        });
        return;
      }
      // After addBorrower the session re-read; find the new borrower by name.
      final refreshed = ref.read(vaultSessionControllerProvider).valueOrNull;
      if (refreshed is VaultUnlocked) {
        final match = refreshed.data.borrowers
            .where((b) => b.name == name)
            .fold<Borrower?>(null, (a, b) => b.id > (a?.id ?? -1) ? b : a);
        borrowerId = match?.id;
      }
      if (borrowerId == null) {
        setState(() {
          _busy = false;
          _error = 'Could not create the borrower.';
        });
        return;
      }
    }

    final loan = Loan(
      bookId: widget.bookId,
      borrowerId: borrowerId,
      lentDate: DateTime.now().millisecondsSinceEpoch,
      dueDate: _dueDate?.millisecondsSinceEpoch,
      notes: _trimOrNull(_notes.text),
    );
    final result = await notifier.addLoan(loan);
    if (!mounted) return;
    result.match(
      (f) => setState(() {
        _busy = false;
        _error = _messageFor(f);
      }),
      (_) => Navigator.of(context).pop(),
    );
  }

  static String _messageFor(Failure f) => switch (f) {
    ValidationFailure(:final message) => message,
    NotFoundFailure() => 'That borrower no longer exists.',
    _ => 'Could not lend the book. Please try again.',
  };

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(vaultSessionControllerProvider).valueOrNull;
    final scheme = Theme.of(context).colorScheme;

    if (session is! VaultUnlocked) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lend book')),
        body: const Center(child: Text('Unlock the vault to lend a book.')),
      );
    }
    final borrowers = session.data.borrowers;

    return Scaffold(
      appBar: AppBar(title: const Text('Lend book')),
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
              decoration: const InputDecoration(
                labelText: 'Existing borrower',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(child: Text('New borrower…')),
                for (final b in borrowers)
                  DropdownMenuItem(value: b.id, child: Text(b.name)),
              ],
              onChanged: (v) => setState(() => _borrowerId = v),
            ),
          if (_borrowerId == null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _newName,
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
              onPressed: _pickDueDate,
              child: const Text('Pick'),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
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
