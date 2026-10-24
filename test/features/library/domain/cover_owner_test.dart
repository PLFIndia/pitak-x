import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/library/domain/cover_owner.dart';

void main() {
  test('cover owners use structural kind-and-id equality', () {
    final first = CoverOwners.item(7);
    final rebuilt = CoverOwners.item(7);

    expect(first, rebuilt);
    expect({first, rebuilt}, hasLength(1));
    expect(CoverOwners.item(7), isNot(CoverOwners.item(8)));
    expect(CoverOwners.item(7), isNot(CoverOwners.periodical('7')));
    expect(CoverOwners.periodical('per-1'), CoverOwners.periodical('per-1'));
  });
}
