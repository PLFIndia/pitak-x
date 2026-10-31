import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the forbidden destructive-publish phrase never reaches lib/', () {
    final violations = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      if (file.readAsStringSync().contains('Publish everything')) {
        violations.add(file.path);
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Unknown-state replacement needs explicit reviewed consent, not '
          'the phrase "Publish everything".',
    );
  });
}
