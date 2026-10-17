/// The Google Books API key settings entry (presentation).
///
/// Extracted from `settings_page.dart` to keep that file under the
/// architecture test's size ratchet — the tile is self-contained (its own
/// masked-key state and edit dialog), so it moves unchanged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitaka/core/di/providers.dart';
import 'package:pitaka/features/settings/presentation/widgets/google_books_key_dialog.dart';

/// Entry for the user's own Google Books API key (optional).
///
/// Why this exists: keyless Google Books calls run on a quota pool shared by
/// every anonymous client worldwide and are often rejected with "quota
/// exceeded". A free personal key gives the user a dedicated daily quota.
/// The key is a quota-bearing credential → stored in the OS secure store
/// (never plain prefs, §6.3) and never shown back in full — only a masked
/// tail, same idea as the vault's redaction rules.
class GoogleBooksKeyTile extends ConsumerStatefulWidget {
  /// Creates the tile.
  const GoogleBooksKeyTile({super.key});

  @override
  ConsumerState<GoogleBooksKeyTile> createState() => _GoogleBooksKeyTileState();
}

class _GoogleBooksKeyTileState extends ConsumerState<GoogleBooksKeyTile> {
  /// Masked tail of the stored key (e.g. "…Wk3c"), or null when none is set.
  String? _maskedKey;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final key = await ref.read(lookupKeyStoreProvider).googleBooksApiKey();
    if (!mounted) return;
    setState(() {
      // Defensive: a foreign/legacy short value must not throw RangeError.
      _maskedKey = key == null
          ? null
          : '…${key.length > 4 ? key.substring(key.length - 4) : key}';
      _loaded = true;
    });
  }

  Future<void> _edit() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const GoogleBooksKeyDialog(),
    );
    if (saved ?? false) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final hasKey = _maskedKey != null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.key_outlined),
      title: const Text('Google Books API key'),
      subtitle: Text(
        hasKey
            ? 'Your key $_maskedKey is used for ISBN lookups.'
            : 'Optional. Without a key, lookups share a public quota that '
                  'often runs out. A free personal key from Google gives '
                  'you your own.',
      ),
      trailing: TextButton(
        onPressed: _edit,
        child: Text(hasKey ? 'Change' : 'Add'),
      ),
      onTap: _edit,
    );
  }
}
