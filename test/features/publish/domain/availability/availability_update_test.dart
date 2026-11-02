import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/availability/availability_snapshot.dart';
import 'package:pitaka/features/publish/domain/availability/availability_update.dart';
import '../../support/key_set_fixtures.dart';

/// The lane's instruction to an availability-only publish (plan S4): a write
/// carries the saved set; a removal carries nothing, so it can never be read
/// as "an empty set".
void main() {
  final set = AvailabilitySnapshot.tryCreate(
    keySet: testKeySetId,
    keys: const ['00000000000000aa'],
    asOfMillis: 120000,
  )!;

  test('a write carries exactly the saved snapshot', () {
    final update = AvailabilityWrite(set);
    expect(identical(update.snapshot, set), isTrue);
  });

  test('both cases describe themselves without any key', () {
    expect(
      AvailabilityWrite(set).toString(),
      'AvailabilityWrite(AvailabilitySnapshot(1 out, asOf 120000))',
    );
    expect(const AvailabilityDelete().toString(), 'AvailabilityDelete()');
    expect(AvailabilityWrite(set).toString(), isNot(contains('00000000')));
  });

  test('every host must handle both cases (sealed)', () {
    String describe(AvailabilityUpdate update) => switch (update) {
      AvailabilityWrite() => 'write',
      AvailabilityDelete() => 'delete',
    };
    expect(describe(AvailabilityWrite(set)), 'write');
    expect(describe(const AvailabilityDelete()), 'delete');
  });
}
