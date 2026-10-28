import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/infrastructure/file_publish_artifact_store.dart';

import '../support/cloudflare_fakes.dart';
import '../support/cloudflare_s8_fakes.dart';

void main() {
  test(
    'artifact spool and public manifest contain no token or JWT material',
    () async {
      final dir = await Directory.systemTemp.createTemp('pitaka_s8_secret_');
      final store = FilePublishArtifactStore(baseDir: dir.path);
      addTearDown(() async {
        await store.dispose();
        if (dir.existsSync()) await dir.delete(recursive: true);
      });
      await store.spool(s8File('books.json', utf8.encode('{"public":true}')));
      final manifest = s8Manifest(
        target: cloudflareTestConnection().status.target!,
        publishId: cloudflareTestPublishId,
      );

      final serialized = StringBuffer(jsonEncode(manifest.toJson()));
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        serialized
          ..write(file.path)
          ..write(utf8.decode(file.readAsBytesSync(), allowMalformed: true));
      }
      for (final secret in [
        'cfut_',
        'synthetic-upload-jwt',
        'synthetic-completion-jwt',
      ]) {
        expect(serialized.toString(), isNot(contains(secret)));
      }
    },
  );
}
