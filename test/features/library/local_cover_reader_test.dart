import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pitaka/core/images/image_downscaler.dart';
import 'package:pitaka/features/library/domain/local_cover_reader.dart';
import 'package:pitaka/features/library/infrastructure/local_cover_reader.dart';

void main() {
  late Directory tmp;
  late LocalCoverReader reader;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('shared_local_cover_reader');
    reader = LocalCoverReader(coversDir: tmp.path);
  });
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test(
    'safe local input returns sanitized JPEG at the publish rendition',
    () async {
      final source = img.encodePng(img.Image(width: 1200, height: 1800));
      File(p.join(tmp.path, 'cover.png')).writeAsBytesSync(source);

      final result = await reader('covers/cover.png');

      final success = result as LocalCoverReadSuccess;
      final decoded = img.decodeImage(success.bytes)!;
      expect(decoded.width, ImageDownscaler.maxWidth);
      expect(decoded.height, ImageDownscaler.maxHeight);
      expect(success.bytes[0], 0xFF);
      expect(success.bytes[1], 0xD8);
    },
  );

  test('unsafe, missing and corrupt inputs have typed refusals', () async {
    expect(
      (await reader('covers/../secret')).runtimeType,
      LocalCoverReadFailure,
    );
    expect(
      (await reader('covers/missing.jpg') as LocalCoverReadFailure).reason,
      LocalCoverReadFailureReason.missing,
    );
    File(p.join(tmp.path, 'junk.jpg')).writeAsBytesSync([1, 2, 3]);
    expect(
      (await reader('covers/junk.jpg') as LocalCoverReadFailure).reason,
      LocalCoverReadFailureReason.unreadable,
    );
  });

  test('source over 8 MiB is refused before image decoding', () async {
    File(
      p.join(tmp.path, 'huge.jpg'),
    ).writeAsBytesSync(List<int>.filled(maxLocalCoverSourceBytes + 1, 1));
    final result = await reader('covers/huge.jpg');
    expect(
      (result as LocalCoverReadFailure).reason,
      LocalCoverReadFailureReason.tooLarge,
    );
  });
}
