import 'package:flutter_test/flutter_test.dart';

import '../../../../integration_test/cloudflare_memory_scenario.dart';

void main() {
  test('a skewed 410-file bucket streams through production code without '
      'whole-bucket buffering', () async {
    final result = await runCloudflareMemoryScenario();

    expect(result.fileCount, 413);
    expect(result.rawSpoolBytes, greaterThan(41984000));
    expect(result.uploadedAssets, 413);
    expect(result.requestCount, 1);
    expect(result.requestBytes, greaterThan(result.rawSpoolBytes));
    expect(result.peakRssBytes, greaterThan(0));
    expect(result.metadataOnlyBuild, isTrue);
  });
}
