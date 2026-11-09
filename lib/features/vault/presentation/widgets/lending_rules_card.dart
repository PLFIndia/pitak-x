/// Lending rules as an expandable card on the Borrowers vault screen.
///
/// Why a card and not an app-bar icon: a bare "rule" icon told users nothing
/// about what was in force. The card header always shows the current rule
/// ("Off" or "Max 3 · Warn") so the answer is visible without opening
/// anything; expanding reveals the editor (the same form the former
/// Lending rules page had — moved here, behaviour unchanged).
///
/// Device-local rules; contains no borrower or loan data.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/vault/application/lending_rules_controller.dart';
import 'package:pitaka/features/vault/domain/borrower_limit_policy.dart';

/// The expandable lending-rules card. Collapsed by default.
final class LendingRulesCard extends ConsumerStatefulWidget {
  /// Creates the card.
  const LendingRulesCard({super.key});

  /// Test hook for the expand/collapse header.
  static const headerKey = ValueKey('lending-rules-card-header');

  @override
  ConsumerState<LendingRulesCard> createState() => _LendingRulesCardState();
}

class _LendingRulesCardState extends ConsumerState<LendingRulesCard> {
  /// Mirrors the tile's state so the chevron can rotate: `ExpansionTile`
  /// draws its own arrow only when `trailing` is null, and the status pill
  /// occupies `trailing`.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(lendingRulesControllerProvider);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: LendingRulesCard.headerKey,
        onExpansionChanged: (open) => setState(() => _expanded = open),
        leading: const Icon(Icons.rule),
        title: const Text('Lending rules'),
        subtitle: const Text('One rule for every borrower'),
        // The status pill is the whole point of the card: the rule in force
        // is readable without expanding.
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusPill(
              label: async.when(
                loading: () => '…',
                error: (_, _) => 'Unreadable',
                data: _statusLabel,
              ),
              error: async.hasError,
            ),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.expand_more),
            ),
          ],
        ),
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
            error: (_, _) => const LendingRulesForm(
              key: ValueKey('unreadable-lending-rules'),
              initialPolicy: BorrowerLimitPolicy.off,
              unreadable: true,
            ),
            data: (policy) => LendingRulesForm(
              // A failed save keeps this identity and therefore the entered
              // values.
              key: ObjectKey(policy),
              initialPolicy: policy,
            ),
          ),
        ],
      ),
    );
  }

  /// Plain words for the rule in force, e.g. "Off" or "Max 3 · Refuse".
  static String _statusLabel(BorrowerLimitPolicy policy) {
    final limit = policy.maxActiveLoans;
    if (limit == null) return 'Off';
    final action = switch (policy.action) {
      BorrowerLimitAction.warn => 'Warn',
      BorrowerLimitAction.refuse => 'Refuse',
    };
    return 'Max $limit · $action';
  }
}

final class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.error});

  final String label;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: error ? scheme.errorContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: error ? scheme.onErrorContainer : scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// Editor for the optional per-borrower active-loan cap and its action.
///
/// Formerly `_LendingRulesForm` on the Lending rules page; public now so the
/// card can host it. Validation, save and error copy are unchanged.
final class LendingRulesForm extends ConsumerStatefulWidget {
  /// Creates the form seeded with [initialPolicy]; [unreadable] shows the
  /// recovery message for a document that could not be read.
  const LendingRulesForm({
    required this.initialPolicy,
    this.unreadable = false,
    super.key,
  });

  /// The policy the fields start from.
  final BorrowerLimitPolicy initialPolicy;

  /// True when the stored document failed to load.
  final bool unreadable;

  @override
  ConsumerState<LendingRulesForm> createState() => _LendingRulesFormState();
}

class _LendingRulesFormState extends ConsumerState<LendingRulesForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _limit;
  late bool _enabled;
  late BorrowerLimitAction _action;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final policy = widget.initialPolicy;
    _enabled = policy.isOn;
    _action = policy.action;
    _limit = TextEditingController(text: '${policy.maxActiveLoans ?? 3}');
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  String? _validateLimit(String? value) {
    if (!_enabled) return null;
    final parsed = int.tryParse(value ?? '');
    if (parsed == null ||
        parsed < BorrowerLimitPolicy.minLimit ||
        parsed > BorrowerLimitPolicy.maxLimit) {
      return 'Enter a whole number from 1 to 99.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final validated = BorrowerLimitPolicy.validate(
      maxActiveLoans: _enabled ? int.parse(_limit.text) : null,
      action: _action,
    );
    final policy = validated.toNullable();
    if (policy == null) {
      setState(() => _saveError = validated.swap().toNullable()!.message);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final result = await ref
        .read(lendingRulesControllerProvider.notifier)
        .save(policy);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saveError = result.isLeft()
          ? 'Could not save lending rules. Please try again.'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.unreadable) ...[
            Text(
              'Lending rules could not be read. Save to set them again.',
              style: TextStyle(color: scheme.error),
            ),
            const SizedBox(height: 16),
          ],
          const Text(
            'Set one rule for every borrower. Returned loans do not count.',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Limit items per borrower'),
            subtitle: const Text('Off allows any number of active loans.'),
            value: _enabled,
            onChanged: _saving
                ? null
                : (value) => setState(() {
                    _enabled = value;
                    _saveError = null;
                  }),
          ),
          if (_enabled) ...[
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('borrower-limit-field'),
              controller: _limit,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 2,
              decoration: const InputDecoration(
                labelText: 'Maximum active loans',
                border: OutlineInputBorder(),
              ),
              validator: _validateLimit,
            ),
            const SizedBox(height: 16),
            SegmentedButton<BorrowerLimitAction>(
              segments: const [
                ButtonSegment(
                  value: BorrowerLimitAction.warn,
                  label: Text('Warn'),
                ),
                ButtonSegment(
                  value: BorrowerLimitAction.refuse,
                  label: Text('Refuse'),
                ),
              ],
              selected: {_action},
              onSelectionChanged: _saving
                  ? null
                  : (selection) => setState(() => _action = selection.first),
            ),
            const SizedBox(height: 8),
            Text(switch (_action) {
              BorrowerLimitAction.warn =>
                'At the limit, ask before lending. You can still lend anyway.',
              BorrowerLimitAction.refuse =>
                'At the limit, refuse until an item is marked returned.',
            }),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('lending-rules-save'),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
          if (_saveError != null) ...[
            const SizedBox(height: 16),
            Text(_saveError!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
    );
  }
}
