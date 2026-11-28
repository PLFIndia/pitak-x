import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Library list's state is nobody's signal: only the Library screen's
/// own code names `libraryControllerProvider` (review findings P3-M4, P4-M2
/// and P4-m13; decision D155; ADR 0031).
///
/// WHY THIS GATE EXISTS (beginner note): until November 2026 the Library
/// list's state doubled as the app's "catalogue changed" signal. A flow that
/// wrote catalogue data invalidated the list, and everything that shows
/// catalogue data (an item's page, the language chips, the Magazines list,
/// the availability updater, ...) watched the list. But the list's state
/// also changes when the user only scrolls (a page is loaded) or types (a
/// search runs), so all of them read again each time, with nothing written;
/// and a write could tell the others only by making the list say "loading",
/// which lost the user's place in it.
///
/// Now there is a signal of its own, `catalogueChangesProvider`
/// (`lib/features/library/application/catalogue_changes.dart`). Writers say
/// `changed()` to it; whoever shows catalogue data watches it; the Library
/// list is one of those listeners. The old pattern is one line away
/// (`ref.watch(libraryControllerProvider)` in a new provider, or
/// `ref.invalidate(libraryControllerProvider)` after a new write), and no
/// test of an existing screen would notice it coming back.
///
/// So the rule is the simplest one that cannot be walked around: outside
/// the files listed below, no code line under `lib/` names the list's
/// provider at all. One rule covers watching, listening and invalidating.
///
/// What this gate cannot hold, and ADR 0031 says so: that a write path of
/// the future remembers to say `changed()`.
///
/// Same style as the other architecture tests: plain source scanning, no
/// extra tooling.
void main() {
  const listProvider = 'libraryControllerProvider';

  /// The Library screen's own code, with why each file names the provider.
  const ownFiles = <String, String>{
    // The list's own source file is not here: it names its provider in
    // comments only, and it has no reason to watch or invalidate itself by
    // name (`ref.invalidateSelf()` is how it reads again).
    'lib/features/library/application/library_controller.g.dart':
        "the list's generated provider",
    'lib/features/library/presentation/pages/library_page.dart':
        'the screen that draws the list',
    'lib/features/library/presentation/widgets/catalogue_item_actions.dart':
        "Remove and Restore on an item's page call the list's own "
        'remove() and restoreRemoved()',
  };

  /// Whether [line] is code that names the list's provider.
  ///
  /// A comment line does not count: files may say in words what the signal
  /// used to be. A code line with the name in a trailing comment DOES
  /// count; reword the comment.
  bool namesTheList(String line) =>
      !line.trimLeft().startsWith('//') && line.contains(listProvider);

  /// Every Dart file under `lib/`. Both tests below ask this ONE function,
  /// so that the second can say whether the first looked at anything.
  List<File> libFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test("only the Library screen's own code names the list's provider", () {
    final violations = <String>[
      for (final file in libFiles())
        if (!ownFiles.containsKey(file.path))
          for (final (index, line) in file.readAsLinesSync().indexed)
            if (namesTheList(line)) '${file.path}:${index + 1}: ${line.trim()}',
    ];
    expect(
      violations,
      isEmpty,
      reason:
          'The Library list is not the "catalogue changed" signal. To hear '
          'that catalogue data changed: ref.watch(catalogueChangesProvider). '
          'To say it after a write: '
          'ref.read(catalogueChangesProvider.notifier).changed(). '
          'Violations:\n${violations.join('\n')}',
    );
  });

  test('the scan sees the files it is about', () {
    // A scan that looked at nothing would pass as well. So: every file of
    // the list above was read and does name the provider in code (an entry
    // that no longer does is taken out), and the signal's own file is
    // there and is heard by code outside the Library screen.
    final scanned = {for (final file in libFiles()) file.path: file};
    for (final path in ownFiles.keys) {
      expect(scanned, contains(path));
      expect(
        scanned[path]!.readAsLinesSync().where(namesTheList),
        isNotEmpty,
        reason: '$path no longer names the provider: take it off the list',
      );
    }
    expect(
      scanned,
      contains('lib/features/library/application/catalogue_changes.dart'),
    );
    final listeners = [
      for (final file in scanned.values)
        if (!ownFiles.containsKey(file.path) && !file.path.endsWith('.g.dart'))
          if (file.readAsLinesSync().any(
            (line) =>
                !line.trimLeft().startsWith('//') &&
                RegExp(
                  r'\b(watch|listen)\(\s*catalogueChangesProvider\b',
                ).hasMatch(line),
          ))
            file.path,
    ];
    expect(
      listeners,
      hasLength(greaterThanOrEqualTo(6)),
      reason: 'the files that hear the signal: $listeners',
    );
  });

  group('the rule, tried on made-up lines', () {
    test('watching, listening, invalidating and calling it are seen', () {
      for (final line in [
        '  ref.watch(libraryControllerProvider);',
        '    ..watch(libraryControllerProvider)',
        '      ..listen(libraryControllerProvider, (_, _) {',
        '    ref.invalidate(libraryControllerProvider);',
        '      ..invalidate(libraryControllerProvider)',
        '    await ref.read(libraryControllerProvider.notifier).remove(id);',
        '    final rows = ref.watch(libraryControllerProvider).valueOrNull;',
        '  save(); // then libraryControllerProvider reloads',
      ]) {
        expect(namesTheList(line), isTrue, reason: line);
      }
    });

    test('a comment, the signal and another list pass', () {
      for (final line in [
        '/// Until 2026-11 this watched [libraryControllerProvider].',
        '    // ref.invalidate(libraryControllerProvider);',
        '  ref.watch(catalogueChangesProvider);',
        '    ref.read(catalogueChangesProvider.notifier).changed();',
        '      ..invalidate(wishlistControllerProvider)',
        '    ..watch(periodicalsControllerProvider)',
      ]) {
        expect(namesTheList(line), isFalse, reason: line);
      }
    });
  });
}
