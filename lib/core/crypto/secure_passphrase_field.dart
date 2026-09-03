/// A passphrase input that never retains the full secret as a `String`
/// (AGENTS.md §6.1, §6.6).
///
/// Flutter's text stack is `String`-based, which §6.1 forbids for secrets held
/// longer than the immediate parse step. This widget therefore does NOT use a
/// `TextEditingController`'s text as the source of truth. Instead it keeps a
/// growable wipeable byte buffer ([_PassphraseBuffer]) and only a bullet mask
/// in the visible field. Each keystroke delta is converted to UTF-8 bytes
/// immediately (the §6.1-permitted parse step) and appended to the buffer; the
/// delta `String` is the only transient `String`, and we never reconstruct the
/// whole passphrase as one.
///
/// Honest residual (documented, framework limit — AGENTS.md §3a): a single
/// typed character transits as a transient `String`, and IME composition of
/// complex scripts (e.g. Devanagari conjuncts) may briefly hold more than one.
/// This is best-effort on a GC VM, the same caveat that applies to
/// [SecretBytes] itself. The vault key never lives here regardless.
///
/// Design adapted from the Kotlin `VaultPassphrase` (exact-size byte holder,
/// zero-on-close) and the SecureMemory two-pass-wipe pattern referenced by
/// [SecretBytes].
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pitaka/core/crypto/secret_bytes.dart';
import 'package:pitaka/core/platform/secret_on_screen.dart';

/// A growable, wipeable UTF-8 byte buffer for passphrase entry.
///
/// Grows by copying into a larger buffer and wiping the old one, so no
/// intermediate copy is left un-zeroed. [takeSecret] hands ownership of an
/// exact-size [SecretBytes] to the caller and resets this buffer.
class _PassphraseBuffer {
  Uint8List _bytes = Uint8List(0);
  int _len = 0;

  int get length => _len;
  bool get isEmpty => _len == 0;

  void _ensure(int extra) {
    if (_len + extra <= _bytes.length) return;
    var cap = _bytes.isEmpty ? 16 : _bytes.length;
    while (cap < _len + extra) {
      cap *= 2;
    }
    final grown = Uint8List(cap)..setRange(0, _len, _bytes);
    _wipe(_bytes);
    _bytes = grown;
  }

  /// Appends [s] as UTF-8. [s] is the single transient String (documented
  /// residual); we encode it immediately and do not store it.
  void append(String s) {
    if (s.isEmpty) return;
    final encoded = utf8.encode(s);
    _ensure(encoded.length);
    _bytes.setRange(_len, _len + encoded.length, encoded);
    _len += encoded.length;
    _wipe(encoded);
  }

  /// Wipes everything (e.g. on clear / dispose). Idempotent.
  void clear() {
    _wipe(_bytes);
    _len = 0;
  }

  /// Hands an exact-size [SecretBytes] to the caller and resets this buffer.
  /// The caller owns the returned secret and must dispose it.
  SecretBytes takeSecret() {
    final out = Uint8List(_len)..setRange(0, _len, _bytes);
    clear();
    return SecretBytes(out);
  }

  static void _wipe(Uint8List b) {
    for (var i = 0; i < b.length; i++) {
      b[i] = 0;
    }
  }
}

/// Controls a [SecurePassphraseField]: owns the wipeable buffer, exposes the
/// current length, and yields a [SecretBytes] on submit. Dispose it (or call
/// [clear]) to wipe the buffer.
class SecurePassphraseController extends ChangeNotifier {
  final _PassphraseBuffer _buffer = _PassphraseBuffer();
  bool _disposed = false;

  /// Number of UTF-8 bytes entered so far (length is not secret).
  int get length => _buffer.length;

  /// Whether anything has been entered.
  bool get isEmpty => _buffer.isEmpty;

  void _append(String delta) {
    _buffer.append(delta);
    notifyListeners();
  }

  /// Appends an input delta directly. Exposed only so tests can exercise the
  /// byte-encoding path without driving the platform text input pipeline.
  @visibleForTesting
  void debugAppend(String delta) => _append(delta);

  void _clearInternal() {
    _buffer.clear();
    notifyListeners();
  }

  /// Wipes the entered bytes.
  void clear() => _clearInternal();

  /// Hands an exact-size [SecretBytes] to the caller (who must dispose it) and
  /// resets the buffer. Returns null when empty.
  SecretBytes? takeSecret() {
    if (_buffer.isEmpty) return null;
    final secret = _buffer.takeSecret();
    notifyListeners();
    return secret;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _buffer.clear();
    _disposed = true;
    super.dispose();
  }
}

/// A masked passphrase field backed by a wipeable byte buffer.
///
/// The visible [TextField] only ever shows bullets; its text is never the
/// secret. We intercept input deltas, encode them to the controller's buffer,
/// and re-render the mask.
///
/// EDIT CONTRACT ("append-only", review 2026-09-03 Blocker): the mask holds
/// no characters, only bullets, so the ONLY edit we can translate back into
/// bytes is "new characters typed at the very END". Anything else — a
/// backspace, a tap that moves the caret into the middle, a paste over a
/// selection — clears the whole buffer and shows a short note asking the user
/// to type the passphrase again. Before this rule existed, a mid-string edit
/// silently appended the trailing BULLET character's bytes instead of the
/// typed letter, so the vault could be created under a passphrase nobody
/// knew. Selection is disabled so the caret cannot be moved by tapping.
///
/// While at least one of these fields is mounted, the app window is
/// screen-capture-protected (Android FLAG_SECURE) via [SecretOnScreen] —
/// every passphrase flow (create, unlock, change, restore) runs before any
/// unlock, so vault-state alone can't cover them (REVIEW_FINDINGS_2 S2).
/// Registering HERE, at the single shared field, means no screen can forget
/// to opt in.
class SecurePassphraseField extends StatefulWidget {
  /// Creates the field bound to [controller].
  const SecurePassphraseField({
    required this.controller,
    this.label = 'Passphrase',
    this.autofocus = false,
    this.onSubmitted,
    super.key,
  });

  /// Owns the wipeable buffer; provided by the parent so it reads the secret.
  final SecurePassphraseController controller;

  /// Field label.
  final String label;

  /// Whether to autofocus on first build.
  final bool autofocus;

  /// Called when the user submits from the keyboard.
  final VoidCallback? onSubmitted;

  @override
  State<SecurePassphraseField> createState() => _SecurePassphraseFieldState();
}

class _SecurePassphraseFieldState extends State<SecurePassphraseField> {
  final TextEditingController _masked = TextEditingController();

  /// Number of mask bullets currently shown. Tracked separately from the
  /// controller because, by the time `onChanged` fires, the controller's text
  /// has already been updated — so we compare the new value against this.
  int _prevMaskLen = 0;

  /// Shown under the field after a non-append edit cleared the buffer.
  String? _note;

  @override
  void dispose() {
    _masked.dispose();
    super.dispose();
  }

  /// The one mask character. Any occurrence of it in a typed DELTA means the
  /// delta is not fresh input (it is our own mask text being moved around).
  static const String _bullet = '•';

  void _onChanged(String value) {
    final prefix = _prevMaskLen <= value.length
        ? value.substring(0, _prevMaskLen)
        : null;
    final isPureAppend =
        prefix != null &&
        prefix == _bullet * _prevMaskLen &&
        !value.substring(_prevMaskLen).contains(_bullet);
    if (isPureAppend && value.length > _prevMaskLen) {
      // Genuine new characters typed at the end: the only edit we can turn
      // back into passphrase bytes.
      widget.controller._append(value.substring(_prevMaskLen));
      _note = null;
    } else if (value.length != _prevMaskLen || !isPureAppend) {
      // Deletion, mid-string insertion, replacement, paste-over-selection…
      // We cannot know which byte(s) the user meant, so fail closed: wipe and
      // ask for a fresh entry. Never guess.
      final hadText = widget.controller.length > 0;
      widget.controller._clearInternal();
      _note = hadText
          ? 'Edits are only possible at the end of the passphrase, so the '
                'field was cleared. Please type it again.'
          : null;
    }
    // Re-render the mask to match the byte length, caret pinned at the end.
    final masked = _bullet * widget.controller.length;
    _prevMaskLen = masked.length;
    _masked.value = TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // SecretOnScreen: FLAG_SECURE while this field is mounted (class doc).
    return SecretOnScreen(
      child: TextField(
        controller: _masked,
        autofocus: widget.autofocus,
        autocorrect: false,
        enableSuggestions: false,
        // No selection handles / caret moves: the caret must stay at the end so
        // every edit is an append (see the class doc). Long-press paste still
        // arrives through onChanged and is handled by the same rule.
        enableInteractiveSelection: false,
        keyboardType: TextInputType.visiblePassword,
        // Defense in depth: ask the platform not to learn this text.
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        onChanged: _onChanged,
        onSubmitted: (_) => widget.onSubmitted?.call(),
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
          // `helperText` (not errorText): this is guidance, the entry itself is
          // not invalid. Reserve a line so the layout does not jump.
          helperText: _note,
          helperMaxLines: 3,
          suffixIcon: IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Clear',
            onPressed: () {
              widget.controller._clearInternal();
              _masked.clear();
              _prevMaskLen = 0;
              setState(() => _note = null);
            },
          ),
        ),
      ),
    );
  }
}
