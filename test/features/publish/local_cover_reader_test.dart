import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/features/publish/infrastructure/local_cover_reader.dart';

/// `localCoverReader` had no test before N10-a moved its downscale into a
/// worker isolate. These pin the port's contract: a safe local reference is
/// read + re-encoded at publish size; everything else is null, never a throw.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('local_cover_reader');
  });
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('re-encodes a local cover at the publish size', () async {
    final src = img.encodePng(img.Image(width: 1200, height: 1800));
    File(p.join(tmp.path, 'a.png')).writeAsBytesSync(src);
    final read = localCoverReader(tmp.path);

    final out = await read('covers/a.png');

    expect(out, isNotNull);
    final decoded = img.decodeImage(Uint8List.fromList(out!))!;
    expect(decoded.width, ImageDownscaler.maxWidth);
    expect(decoded.height, ImageDownscaler.maxHeight);
    expect(out[0], 0xFF, reason: 'JPEG magic');
    expect(out[1], 0xD8);
  });

  test('matches the synchronous downscaler byte for byte', () async {
    final src = img.encodePng(img.Image(width: 300, height: 200));
    File(p.join(tmp.path, 'b.png')).writeAsBytesSync(src);

    final out = await localCoverReader(tmp.path)('covers/b.png');

    expect(out, orderedEquals(ImageDownscaler.downscaleJpeg(src)!));
  });

  test('returns null for a reference that is not a safe local cover', () async {
    final read = localCoverReader(tmp.path);
    expect(await read('https://covers.openlibrary.org/x.jpg'), isNull);
    expect(await read('covers/../etc/passwd'), isNull);
    expect(await read(''), isNull);
  });

  test('returns null when the file is missing', () async {
    expect(await localCoverReader(tmp.path)('covers/missing.jpg'), isNull);
  });

  test('returns null (no throw) when the file is not an image', () async {
    File(p.join(tmp.path, 'junk.jpg')).writeAsBytesSync([1, 2, 3, 4]);
    expect(await localCoverReader(tmp.path)('covers/junk.jpg'), isNull);
  });
}
