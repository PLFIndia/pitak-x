import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A form asks before Back throws away unsaved input (review finding P4-M1,
/// ADR 0028; decision D98 of `PLAN.md`).
///
/// Why this gate exists: Back used to close a half-filled form at once, and
/// what was typed was gone. Nine forms now stand inside
/// `DiscardChangesGuard` (`lib/core/widgets/discard_changes_guard.dart`),
/// which asks "Discard changes?" first. Nothing but this test would notice
/// a TENTH form that is written without it.
///
/// How it looks for a form: a file under `lib/` that creates a text
/// controller (`TextEditingController(`) holds text the user types. Such a
/// file either uses the guard, or it is on the list `notForms` below with
/// the reason why it is not a form. What the gate cannot see: a form that
/// would keep its text some other way than in a text controller (none does
/// today).
///
/// How to move on:
///  - a new form: put its page inside `DiscardChangesGuard`, as the nine
///    forms do;
///  - a new search field, or a dialog with its own Cancel: add the file to
///    `notForms`, with its reason;
///  - never give a passphrase to the guard: its `OpenedValues` keeps a copy
///    of a form's values, and nothing may keep a typed passphrase (AGENTS.md
///    §6.1). The last test holds that.
///
/// Same style as the other architecture tests: plain source scanning, no
/// extra tooling. The rules are small functions, so that the second group
/// can try each of them on made-up files.
void main() {
  final createsController = RegExp(r'\bTextEditingController\(');
  final usesGuard = RegExp(r'\bDiscardChangesGuard\(');
  final keepsValues = RegExp(r'\bOpenedValues\b');
  final handlesPassphrase = RegExp(r'\bSecurePassphrase(Field|Controller)\b');

  // The files under `lib/` that create a text controller and are NOT forms,
  // each with its reason. Every file here was read in full (2026-11-20).
  const notForms = <String, String>{
    'lib/core/crypto/secure_passphrase_field.dart':
        'a passphrase: nothing may keep it or ask about it',
    'lib/core/widgets/editable_text_field.dart': 'one field with its own Save',
    'lib/features/events/presentation/pages/events_page.dart':
        'a dialog for one short description, with Cancel',
    'lib/features/import_export/presentation/pages/import_page.dart':
        'a box for pasted text, not typed work',
    'lib/features/library/presentation/pages/library_page.dart':
        'the search field',
    'lib/features/network/presentation/widgets/add_library_dialog.dart':
        'a dialog with Cancel',
    'lib/features/network/presentation/widgets/'
            'published_catalogue_controls.dart':
        'a search field',
    'lib/features/publish/presentation/widgets/cloudflare_name_dialogs.dart':
        'dialogs for one name, with Cancel',
    'lib/features/publish/presentation/widgets/cloudflare_token_dialog.dart':
        'a dialog for a token: a secret, not to be kept',
    'lib/features/publish/presentation/widgets/'
            'github_connection_dialogs.dart':
        'a dialog for one repository name, with "Later"',
    'lib/features/settings/presentation/widgets/google_books_key_dialog.dart':
        'a dialog for a key: a secret, not to be kept',
    'lib/features/vault/presentation/widgets/lending_rules_card.dart':
        'three small settings on a card with its own Save',
  };

  // A file's code without its comment lines: a comment that only NAMES the
  // guard or a controller must not count as using or creating one.
  String code(String source) => source
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  // Rule 1: the files that create a text controller, use no guard and are
  // not on the list.
  List<String> formsWithoutGuard(
    Map<String, String> sources,
    Set<String> listed,
  ) => [
    for (final file in sources.entries)
      if (createsController.hasMatch(code(file.value)) &&
          !usesGuard.hasMatch(code(file.value)) &&
          !listed.contains(file.key))
        file.key,
  ]..sort();

  // Rule 2: the entries of the list that no longer say something true, each
  // with what is wrong. A list that is not kept true would hide a form.
  List<String> staleEntries(Map<String, String> sources, Set<String> listed) =>
      [
        for (final path in listed)
          if (sources[path] case final source?) ...[
            if (!createsController.hasMatch(code(source)))
              '$path: creates no text controller any more',
            if (usesGuard.hasMatch(code(source))) '$path: uses the guard now',
          ] else
            '$path: no such file',
      ];

  // Rule 3: the files that handle a passphrase and keep form values.
  List<String> passphraseFilesKeepingValues(Map<String, String> sources) => [
    for (final file in sources.entries)
      if (handlesPassphrase.hasMatch(code(file.value)) &&
          keepsValues.hasMatch(code(file.value)))
        file.key,
  ]..sort();

  // Every Dart file under `lib/`, by its path.
  Map<String, String> libSources() => {
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')))
      file.path: file.readAsStringSync(),
  };

  group('under lib/', () {
    late Map<String, String> sources;

    setUpAll(() => sources = libSources());

    test('the scan sees the app: files that create a text controller, and '
        'forms inside the guard', () {
      // Fail closed: a scan that finds nothing (run from another folder, a
      // renamed class) must not pass as "every form is guarded".
      final creators = [
        for (final file in sources.entries)
          if (createsController.hasMatch(code(file.value))) file.key,
      ];
      expect(creators, isNotEmpty);
      expect(
        creators.where((path) => usesGuard.hasMatch(code(sources[path]!))),
        isNotEmpty,
      );
    });

    test('every file that creates a text controller uses the guard or is '
        'listed as not a form', () {
      final found = formsWithoutGuard(sources, notForms.keys.toSet());
      expect(
        found,
        isEmpty,
        reason:
            'A form must ask before Back throws away what was typed: put '
            'its page inside DiscardChangesGuard '
            '(lib/core/widgets/discard_changes_guard.dart). If the file is '
            'not a form, add it to notForms in this test, with the reason. '
            'Files:\n${found.join('\n')}',
      );
    });

    test('the list of files that are not forms is true: each exists, '
        'creates a text controller, uses no guard, and has a reason', () {
      expect(staleEntries(sources, notForms.keys.toSet()), isEmpty);
      expect(notForms.values.where((reason) => reason.trim().isEmpty), isEmpty);
    });

    test('no file that handles a passphrase keeps form values', () {
      final found = passphraseFilesKeepingValues(sources);
      expect(
        found,
        isEmpty,
        reason:
            'OpenedValues keeps a copy of what a form holds. A typed '
            'passphrase is kept by nothing (AGENTS.md §6.1). Files:\n'
            '${found.join('\n')}',
      );
    });
  });

  // The rules tried on made-up files: a gate that cannot fail holds nothing.
  group('the rules, on made-up files', () {
    const form = 'final name = TextEditingController();';
    const guarded =
        'final name = TextEditingController();\n'
        'return DiscardChangesGuard(child: page);';

    test('a file that creates a text controller and has no guard is found', () {
      expect(formsWithoutGuard({'lib/new_form.dart': form}, {}), [
        'lib/new_form.dart',
      ]);
    });

    test('with the guard it is not found', () {
      expect(formsWithoutGuard({'lib/new_form.dart': guarded}, {}), isEmpty);
    });

    test('on the list it is not found', () {
      expect(
        formsWithoutGuard({'lib/search.dart': form}, {'lib/search.dart'}),
        isEmpty,
      );
    });

    test('a file without a text controller is not found', () {
      expect(
        formsWithoutGuard({'lib/page.dart': 'const Text("hello");'}, {}),
        isEmpty,
      );
    });

    test('a guard that is only named in a comment does not count', () {
      const commented =
          'final name = TextEditingController();\n'
          '  // return DiscardChangesGuard(child: page);';
      expect(formsWithoutGuard({'lib/new_form.dart': commented}, {}), [
        'lib/new_form.dart',
      ]);
    });

    test('a controller that is only named in a comment does not count', () {
      expect(
        formsWithoutGuard({
          'lib/page.dart': '/// Like `TextEditingController()`, but smaller.',
        }, {}),
        isEmpty,
      );
    });

    test('a listed file that is gone is stale', () {
      expect(staleEntries({}, {'lib/gone.dart'}), [
        'lib/gone.dart: no such file',
      ]);
    });

    test('a listed file that creates no text controller any more is stale', () {
      expect(
        staleEntries(
          {'lib/search.dart': 'const Text("hello");'},
          {'lib/search.dart'},
        ),
        ['lib/search.dart: creates no text controller any more'],
      );
    });

    test('a listed file that uses the guard is stale', () {
      expect(staleEntries({'lib/form.dart': guarded}, {'lib/form.dart'}), [
        'lib/form.dart: uses the guard now',
      ]);
    });

    test('a listed file that is as the list says is not stale', () {
      expect(
        staleEntries({'lib/search.dart': form}, {'lib/search.dart'}),
        isEmpty,
      );
    });

    test('a passphrase file that keeps form values is found', () {
      expect(
        passphraseFilesKeepingValues({
          'lib/unlock.dart':
              'final pass = SecurePassphraseController();\n'
              'late final OpenedValues opened;',
        }),
        ['lib/unlock.dart'],
      );
    });

    test('a passphrase file without them, and a form with them, are not '
        'found', () {
      expect(
        passphraseFilesKeepingValues({
          'lib/unlock.dart': 'SecurePassphraseField(controller: pass)',
          'lib/form.dart': 'late final OpenedValues opened;',
        }),
        isEmpty,
      );
    });
  });
}
