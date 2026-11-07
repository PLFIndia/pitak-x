/// Device-local borrower lending rules; contains no borrower or loan data.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/features/vault/application/lending_rules_controller.dart';
import 'package:pitaka/features/vault/domain/borrower_limit_policy.dart';

/// Editor for the optional per-borrower active-loan cap and its action.
final class LendingRulesPage extends ConsumerWidget {
  /// Creates the lending-rules editor.
  const LendingRulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lendingRulesControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Lending rules')),
      body: async.when(
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (_, _) => const _LendingRulesForm(
          key: ValueKey('unreadable-lending-rules'),
          initialPolicy: BorrowerLimitPolicy.off,
          unreadable: true,
        ),
        data: (policy) => _LendingRulesForm(
          // A failed save keeps this identity and therefore the entered values.
          key: ObjectKey(policy),
          initialPolicy: policy,
        ),
      ),
    );
  }
}

class _LendingRulesForm extends ConsumerStatefulWidget {
  const _LendingRulesForm({
    required this.initialPolicy,
    this.unreadable = false,
    super.key,
  });

  final BorrowerLimitPolicy initialPolicy;
  final bool unreadable;

  @override
  ConsumerState<_LendingRulesForm> createState() => _LendingRulesFormState();
}

class _LendingRulesFormState extends ConsumerState<_LendingRulesForm> {
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
      child: ListView(
        padding: const EdgeInsets.all(16),
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
