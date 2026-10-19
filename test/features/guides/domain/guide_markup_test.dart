import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/guides/domain/guide_markup.dart';

void main() {
  group('parseGuideMarkup', () {
    test('empty string → no runs', () {
      expect(parseGuideMarkup(''), isEmpty);
    });

    test('plain text → one plain run', () {
      expect(parseGuideMarkup('Tap the button.'), [
        plainRun('Tap the button.'),
      ]);
    });

    test('bold run in the middle of a sentence', () {
      expect(parseGuideMarkup('Tap **Publish catalogue now**.'), [
        plainRun('Tap '),
        boldRun('Publish catalogue now'),
        plainRun('.'),
      ]);
    });

    test('code run', () {
      expect(parseGuideMarkup('a short name like `my-library`, tap'), [
        plainRun('a short name like '),
        codeRun('my-library'),
        plainRun(', tap'),
      ]);
    });

    test('adjacent markers produce adjacent runs, no empty plain run', () {
      expect(parseGuideMarkup('**Copy link****Share**'), [
        boldRun('Copy link'),
        boldRun('Share'),
      ]);
    });

    test('bold then code with text between', () {
      expect(parseGuideMarkup('**Create backup** → a `.pitabak` file'), [
        boldRun('Create backup'),
        plainRun(' → a '),
        codeRun('.pitabak'),
        plainRun(' file'),
      ]);
    });

    test('a string that is one bold run', () {
      expect(parseGuideMarkup('**☰ → Settings → Data → Create backup**'), [
        boldRun('☰ → Settings → Data → Create backup'),
      ]);
    });

    test('unmatched ** is kept as literal text (never throws)', () {
      expect(parseGuideMarkup('a ** b'), [plainRun('a ** b')]);
      expect(parseGuideMarkup('**open'), [plainRun('**open')]);
    });

    test('unmatched backtick is kept as literal text', () {
      expect(parseGuideMarkup('it`s fine'), [plainRun('it`s fine')]);
    });

    test('empty markers (**** and ``) stay literal', () {
      expect(parseGuideMarkup('x **** y'), [plainRun('x **** y')]);
      expect(parseGuideMarkup('x `` y'), [plainRun('x `` y')]);
    });

    test('a single * is not a marker', () {
      expect(parseGuideMarkup('Export is for *sharing*'), [
        plainRun('Export is for *sharing*'),
      ]);
    });

    test('no nesting: a backtick inside bold is part of the bold text', () {
      expect(parseGuideMarkup('**tap `x` now**'), [boldRun('tap `x` now')]);
    });

    test(
      'with balanced markers the runs reassemble to the stripped source',
      () {
        const samples = [
          'Open **☰ → Publish to web**.',
          '`12.9716, 77.5946` — copy them.',
          '**Basic info** tab adds `github.io` and **Share**.',
          'no markers at all',
          '',
        ];
        for (final s in samples) {
          final joined = parseGuideMarkup(s).map((r) => r.text).join();
          expect(joined, stripGuideMarkup(s), reason: 'source: "$s"');
        }
      },
    );

    test('run helpers set exactly one flag', () {
      expect(plainRun('a'), (text: 'a', bold: false, code: false));
      expect(boldRun('a'), (text: 'a', bold: true, code: false));
      expect(codeRun('a'), (text: 'a', bold: false, code: true));
    });
  });
}
