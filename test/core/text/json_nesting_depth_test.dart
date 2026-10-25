import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/core/text/json_nesting_depth.dart';

/// The shared, string-aware JSON nesting scan (viewer plan S1). These cases
/// used to live inside `LibraryDescriptorCodec`; they moved here so both wire
/// readers are pinned by ONE suite.
void main() {
  group('JsonNestingDepth.maxDepthOf', () {
    test('a flat object is depth 1', () {
      expect(JsonNestingDepth.maxDepthOf('{"a": 1}'), 1);
    });

    test('root -> array -> object is depth 3', () {
      expect(JsonNestingDepth.maxDepthOf('{"books": [{"title": "x"}]}'), 3);
    });

    test('an empty document is depth 0', () {
      expect(JsonNestingDepth.maxDepthOf(''), 0);
      expect(JsonNestingDepth.maxDepthOf('42'), 0);
    });

    test('brackets inside a quoted value do not count', () {
      // The real-world case: a library named "Books {{{{" or a title with
      // brackets must not be refused as a nesting bomb.
      expect(JsonNestingDepth.maxDepthOf('{"name": "Books {{{{ [[[["}'), 1);
    });

    test('an escaped quote inside a string does not end the string', () {
      // `{"t": "a\"[[[[[[[[[[[[[[[[[["}` has one JSON level; the escapes are
      // string content, so the scan must report 1.
      expect(
        JsonNestingDepth.maxDepthOf(r'{"t": "a\"[[[[[[[[[[[[[[[[[[["}'),
        1,
      );
    });

    test('escaped backslashes before a quote still close the string', () {
      // "a\\\\" (a literal backslash) then the closing quote. A naive scanner
      // that only looks at the previous character would treat the quote as
      // escaped and count the following brackets as nesting.
      expect(JsonNestingDepth.maxDepthOf(r'{"t": "a\\\\", "u": 1}'), 1);
    });

    test('an unterminated string stops the count conservatively', () {
      // jsonDecode rejects this right after; the scan must not crash or count
      // the brackets that are really inside the (unterminated) string.
      expect(JsonNestingDepth.maxDepthOf('{"t": "[[[[[['), 1);
    });

    test('a stray closing bracket never goes below zero', () {
      expect(JsonNestingDepth.maxDepthOf(']]]]]'), 0);
      expect(JsonNestingDepth.maxDepthOf('{"a": 1}}}}}'), 1);
    });

    test('the exact boundary is reported (32 accepted, 33 rejected)', () {
      String nested(int depth) => '${'[' * depth}${']' * depth}';
      expect(JsonNestingDepth.maxDepthOf(nested(32)), 32);
      expect(JsonNestingDepth.maxDepthOf(nested(33)), 33);
    });

    test('an alternating object/array nest counts every level', () {
      expect(JsonNestingDepth.maxDepthOf('{"a":[{"b":[{"c":[]}]}]}'), 6);
    });
  });
}
