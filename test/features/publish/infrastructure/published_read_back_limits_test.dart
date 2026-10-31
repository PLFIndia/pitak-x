import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/network/infrastructure/published_catalogue_codec.dart';
import 'package:pitaka/features/publish/domain/site/published_site_verifier.dart';

void main() {
  // Two files, one number: the publish read-back cap must be the same bound
  // the viewer applies to a catalogue, or a body could pass one and fail the
  // other. This test is the drift alarm.
  test('the publish read-back cap matches the published catalogue cap', () {
    expect(
      publishedCatalogueReadBackMaxBytes,
      PublishedCatalogueCodec.defaultMaxBodyBytes,
    );
  });
}
