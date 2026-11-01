import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/availability/availability_request.dart';

/// The availability request (ADR 0019 Decision 6, plan A.6 #33).
void main() {
  /// What a publish does for each request, written as the exhaustive switch
  /// every caller uses: adding a third case must fail to compile here first.
  String describe(AvailabilityRequest request) => switch (request) {
    AvailabilityFromLoanCounts() => 'write from loan counts',
    AvailabilityRemoval() => 'delete a recorded file',
  };

  test('the two cases are distinct and exhaustive', () {
    expect(
      describe(const AvailabilityFromLoanCounts()),
      'write from loan counts',
    );
    expect(describe(const AvailabilityRemoval()), 'delete a recorded file');
  });

  test('a request built at run time behaves like its constant', () {
    // Constructor tear-offs build the objects at run time. The app only ever
    // uses the constants, which coverage cannot observe being constructed.
    const makers = <AvailabilityRequest Function()>[
      AvailabilityFromLoanCounts.new,
      AvailabilityRemoval.new,
    ];
    expect(makers.map((make) => describe(make())), [
      'write from loan counts',
      'delete a recorded file',
    ]);
  });

  test('toString names the case and carries no data', () {
    expect(
      const AvailabilityFromLoanCounts().toString(),
      'AvailabilityFromLoanCounts()',
    );
    expect(const AvailabilityRemoval().toString(), 'AvailabilityRemoval()');
  });
}
