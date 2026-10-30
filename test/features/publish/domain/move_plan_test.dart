import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/site/move_plan.dart';
import 'package:pitaka/features/publish/domain/site/pending_move.dart';

import '../support/move_fakes.dart';

void main() {
  group('normalizeMovedLibraryName (D6/M9)', () {
    /// The one property that matters: whatever the settings field held, the
    /// pending record must accept the normalized name.
    String normalizedAndRecorded(String raw) {
      final name = normalizeMovedLibraryName(raw);
      final pending = PendingMove.tryCreate(
        oldTarget: moveGitHubTarget,
        newTarget: moveCloudflareTarget,
        sourceAnchor: moveAnchor(moveGitHubTarget),
        indexHtml: const [60, 104, 116, 109, 108, 62],
        notFoundHtml: const [60, 104, 116, 109, 108, 62],
        libraryName: name,
      );
      expect(pending, isNotNull, reason: 'rejected normalized name: $name');
      return pending!.retirement.libraryName;
    }

    test('replaces rejected control units with spaces', () {
      expect(normalizedAndRecorded('\tA\tB'), 'A B');
      expect(normalizedAndRecorded('a\r\nb'), 'a  b');
      expect(normalizedAndRecorded('\u0000'), 'My Library');
      expect(normalizedAndRecorded('\u007f'), 'My Library');
      expect(normalizedAndRecorded(' \t '), 'My Library');
    });

    test('trims surrounding whitespace', () {
      expect(
        normalizedAndRecorded('  Pondicherry Readers  '),
        'Pondicherry Readers',
      );
    });

    test('leaves every currently valid name unchanged', () {
      for (final name in [
        'My Library',
        'My  Library',
        'കേരളം & Co',
        "O'Brien Memorial",
        'Library #2 — 2026',
      ]) {
        expect(normalizedAndRecorded(name), name);
      }
    });

    test('caps at 256 UTF-16 units', () {
      expect(normalizedAndRecorded('a' * 300), 'a' * 256);
    });

    test('never splits a surrogate pair at the cap', () {
      // 255 units, then an emoji's two units: a 256-unit cut would leave a
      // lone high surrogate, which the moved-page renderer cannot encode.
      final raw = '${'a' * 255}😀b';
      final name = normalizedAndRecorded(raw);

      expect(name.length, 255);
      expect(name, 'a' * 255);
    });

    test('caps a name whose 256th unit is the last of a pair', () {
      final raw = '${'a' * 254}😀b';
      final name = normalizedAndRecorded(raw);

      expect(name, '${'a' * 254}😀');
      expect(name.length, 256);
    });
  });
}
