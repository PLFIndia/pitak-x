/// Borrower add/edit screen (presentation layer, AGENTS.md §3.1).
///
/// Adds a new borrower or edits an existing one through
/// [VaultSessionController]. Name is required (mirrors the vault's NOT NULL
/// `name` column and the Kotlin `AddBorrowerUseCase` validation); contact and
/// notes are optional. The controller re-reads the vault after a successful
/// write, so the list updates when this page pops.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/error/failure.dart';
import 'package:pitaka/features/vault/application/vault_session_controller.dart';
import 'package:pitaka/features/vault/domain/entities/borrower.dart';
import 'package:pitaka/features/vault/domain/entities/vault_session_state.dart';
import 'package:pitaka/features/vault/domain/value_objects/borrower_contact.dart';

/// Screen to create or edit a [Borrower].
class BorrowerEditPage extends ConsumerStatefulWidget {
  /// Creates the editor. [existing] non-null edits that borrower; null adds.
  const BorrowerEditPage({this.existing, super.key});

  /// The borrower being edited, or null when adding a new one.
  final Borrower? existing;

  @override
  ConsumerState<BorrowerEditPage> createState() => _BorrowerEditPageState();
}

class _BorrowerEditPageState extends ConsumerState<BorrowerEditPage> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _contactOther;
  late final TextEditingController _notes;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    // Decode the single stored `contact` string into typed phone/email/other.
    final contact = BorrowerContact.decode(e?.contact);
    _name = TextEditingController(text: e?.name ?? '');
    _phone = TextEditingController(text: contact.phone);
    _email = TextEditingController(text: contact.email);
    _contactOther = TextEditingController(text: contact.other);
    _notes = TextEditingController(text: e?.notes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _contactOther.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _trimOrNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'A name is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // Re-encode the typed parts back into the single `contact` column (the
    // vault schema is unchanged; A2). encode() returns null when all blank.
    final contact = BorrowerContact(
      phone: _phone.text,
      email: _email.text,
      other: _contactOther.text,
    ).encode();
    final borrower = Borrower(
      id: widget.existing?.id ?? Borrower.emptyId,
      name: name,
      contact: contact,
      notes: _trimOrNull(_notes.text),
    );
    final notifier = ref.read(vaultSessionControllerProvider.notifier);
    final result = _isEdit
        ? await notifier.updateBorrower(borrower)
        : await notifier.addBorrower(borrower);
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
    _ => 'Could not save. Please try again.',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit borrower' : 'Add borrower')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone (optional)',
              helperText: 'Adds call + WhatsApp buttons on their profile',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email (optional)',
              helperText: 'Adds an email button on their profile',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _contactOther,
            decoration: const InputDecoration(
              labelText: 'Other contact (optional)',
              helperText: 'Anything else — e.g. “ask at the front desk”',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
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
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEdit ? 'Save' : 'Add'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          if (_isEdit) _LoansSection(borrowerId: widget.existing!.id),
        ],
      ),
    );
  }
}

/// Shows the borrower's loans (from the unlocked session) with a Return action
/// on active ones. Returning sets `returnedDate` via the session controller.
class _LoansSection extends ConsumerWidget {
  const _LoansSection({required this.borrowerId});

  final int borrowerId;

  Future<void> _return(BuildContext context, WidgetRef ref, Loan loan) async {
    final returned = loan.copyWith(
      returnedDate: DateTime.now().millisecondsSinceEpoch,
    );
    final result = await ref
        .read(vaultSessionControllerProvider.notifier)
        .updateLoan(returned);
    if (!context.mounted) return;
    result.match(
      (_) => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not mark as returned.')),
      ),
      (_) {},
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(vaultSessionControllerProvider).valueOrNull;
    if (session is! VaultUnlocked) return const SizedBox.shrink();
    final loans = session.data.loans
        .where((l) => l.borrowerId == borrowerId)
        .toList();
    if (loans.isEmpty) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('Loans', style: textTheme.titleSmall),
        for (final loan in loans)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Book #${loan.bookId}'),
            subtitle: Text(loan.isReturned ? 'Returned' : 'Out'),
            trailing: loan.isReturned
                ? const Icon(Icons.check_circle_outline)
                : TextButton(
                    onPressed: () => _return(context, ref, loan),
                    child: const Text('Return'),
                  ),
          ),
      ],
    );
  }
}
