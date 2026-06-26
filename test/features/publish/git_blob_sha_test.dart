import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/git_blob_sha.dart';

void main() {
  group('GitBlobSha.of', () {
    // Reference values from `git hash-object` (verified via the CLI).
    test('matches git hash-object for "hello"', () {
      expect(
        GitBlobSha.of(ascii.encode('hello')),
        'b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0',
      );
    });

    test('matches git hash-object for hello-newline', () {
      expect(
        GitBlobSha.of(ascii.encode('hello\n')),
        'ce013625030ba8dba906f756967f9e9ca394464a',
      );
    });

    test('matches git hash-object for an empty blob', () {
      expect(
        GitBlobSha.of(const []),
        'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391',
      );
    });
  });
}
