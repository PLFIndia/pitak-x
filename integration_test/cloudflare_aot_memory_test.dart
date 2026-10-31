/// Android release/AOT memory evidence for S8 Cloudflare publishing.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'cloudflare_memory_scenario.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('production Cloudflare upload memory scenario', () async {
    final result = await runCloudflareMemoryScenario();
    // Fixed fields only: no token, JWT, header, path, or response body.
    debugPrint('S8_AOT_MEMORY=${jsonEncode(result.toJson())}');

    expect(result.fileCount, 413);
    expect(result.rawSpoolBytes, greaterThan(41984000));
    expect(result.uploadedAssets, 413);
    expect(result.requestCount, 1);
    expect(result.requestBytes, greaterThan(result.rawSpoolBytes));
    expect(result.metadataOnlyBuild, isTrue);
  });
}
