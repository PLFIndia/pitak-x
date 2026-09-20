import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/value_objects/language_merge_plan.dart';

void main() {
  group('LanguageMergePlan.plan', () {
    test('clean data → no renames', () {
      expect(LanguageMergePlan.plan({'English': 3, 'Hindi': 2}), isEmpty);
      expect(LanguageMergePlan.plan(const {}), isEmpty);
    });

    test('the most-used spelling wins; the others are renamed to it', () {
      final plan = LanguageMergePlan.plan({
        'English': 12,
        'english': 3,
        'ENGLISH': 1,
        'Hindi': 4,
      });
      expect(plan, [
        (from: 'ENGLISH', to: 'English'),
        (from: 'english', to: 'English'),
      ]);
    });

    test('a lowercase spelling wins when it is the most used', () {
      // We never "fix" the user's choice — the library's dominant spelling
      // is kept, whatever its case.
      final plan = LanguageMergePlan.plan({'english': 5, 'English': 1});
      expect(plan, [(from: 'English', to: 'english')]);
    });

    test(
      'a bare ISO code always loses to a real name, even with more books',
      () {
        final plan = LanguageMergePlan.plan({'en': 9, 'english': 1});
        expect(plan, [(from: 'en', to: 'english')]);
      },
    );

    test('a group made only of codes is renamed to the table name', () {
      final plan = LanguageMergePlan.plan({'en': 2, 'EN': 1, 'en-GB': 1});
      expect(plan, [
        (from: 'EN', to: 'English'),
        (from: 'en', to: 'English'),
        (from: 'en-GB', to: 'English'),
      ]);
    });

    test('count tie → case-insensitive A→Z, then binary, deterministic', () {
      final plan = LanguageMergePlan.plan({'hindi': 2, 'Hindi': 2});
      // 'Hindi' < 'hindi' in binary order after the fold ties.
      expect(plan, [(from: 'hindi', to: 'Hindi')]);
    });

    test('non-Latin spellings group by Unicode case', () {
      final plan = LanguageMergePlan.plan({'Ελληνικά': 3, 'ΕΛΛΗΝΙΚΆ': 1});
      expect(plan, [(from: 'ΕΛΛΗΝΙΚΆ', to: 'Ελληνικά')]);
    });

    test('blank spellings are ignored', () {
      expect(LanguageMergePlan.plan({'': 2, '  ': 1, 'Hindi': 1}), isEmpty);
    });

    test(
      'is idempotent: applying the plan then re-planning yields nothing',
      () {
        final usage = {'English': 2, 'english': 3, 'en': 1, 'Hindi': 1};
        final plan = LanguageMergePlan.plan(usage);
        final after = <String, int>{};
        for (final entry in usage.entries) {
          final rename = plan.where((r) => r.from == entry.key);
          final to = rename.isEmpty ? entry.key : rename.first.to;
          after[to] = (after[to] ?? 0) + entry.value;
        }
        expect(after, {'english': 6, 'Hindi': 1});
        expect(LanguageMergePlan.plan(after), isEmpty);
      },
    );
  });
}
