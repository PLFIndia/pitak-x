import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/application/cloudflare/cloudflare_bucket_uploader.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_account_id.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_api_models.dart';
import 'package:pitaka/features/publish/domain/cloudflare/cloudflare_content_type.dart';

/// The one bucket loop shared by publish, verification and both move sides.
/// The J.7 smoke (2026-10-29) proved Cloudflare acknowledges non-final
/// buckets WITHOUT a completion token; these tests pin the resulting rule.
void main() {
  final account = CloudflareAccountId.tryParse(
    '0123456789abcdef0123456789abcdef',
  )!;
  final hashA = 'a' * 32;
  final hashB = 'b' * 32;
  final hashC = 'c' * 32;

  CloudflareBucketAsset asset(String hash) => CloudflareBucketAsset(
    hash: hash,
    type: CloudflareContentType.json,
    size: 1,
    openBytes: () => Stream.value(const [1]),
  );

  CloudflareUploadSession session(List<List<String>> buckets) =>
      CloudflareUploadSession.tryCreate(
        uploadJwt: 'session-jwt',
        buckets: buckets,
      )!;

  CloudflareCompletionToken token(String value) =>
      CloudflareCompletionToken.tryParse(value)!;

  test('a fully deduplicated session deploys with its own token and uploads '
      'nothing', () async {
    final api = _ScriptedBucketApi([]);
    var before = 0;

    final result = await CloudflareBucketUploader(api).upload(
      accountId: account,
      session: session(const []),
      assetForHash: asset,
      beforeBucketUpload: () => before++,
    );

    final uploaded = result as CloudflareBucketsUploaded;
    expect(uploaded.completion.use((value) => value), 'session-jwt');
    expect(uploaded.uploadedHashes, isEmpty);
    expect(api.uploads, isEmpty);
    expect(before, 0);
  });

  test('non-final buckets may be acknowledged without a token; the final '
      "bucket's token is the result", () async {
    final api = _ScriptedBucketApi([null, null, token('final-jwt')]);
    var before = 0;

    final result = await CloudflareBucketUploader(api).upload(
      accountId: account,
      session: session([
        [hashA],
        [hashB],
        [hashC],
      ]),
      assetForHash: asset,
      beforeBucketUpload: () => before++,
    );

    final uploaded = result as CloudflareBucketsUploaded;
    expect(uploaded.completion.use((value) => value), 'final-jwt');
    expect(uploaded.uploadedHashes, [hashA, hashB, hashC]);
    expect(api.uploads, [
      [hashA],
      [hashB],
      [hashC],
    ], reason: 'buckets upload serially in the requested order');
    expect(before, 3);
  });

  test(
    'an early token is not a fallback when the final bucket has none',
    () async {
      final api = _ScriptedBucketApi([token('early-jwt'), null]);

      final result = await CloudflareBucketUploader(api).upload(
        accountId: account,
        session: session([
          [hashA],
          [hashB],
        ]),
        assetForHash: asset,
      );

      expect(result, isA<CloudflareUploadNotConfirmed>());
      expect(api.uploads, hasLength(2));
    },
  );

  test('a missing hash stops before that bucket sends any bytes', () async {
    final api = _ScriptedBucketApi([null]);
    var before = 0;

    final result = await CloudflareBucketUploader(api).upload(
      accountId: account,
      session: session([
        [hashA],
        [hashB, hashC],
      ]),
      assetForHash: (hash) => hash == hashC ? null : asset(hash),
      beforeBucketUpload: () => before++,
    );

    expect((result as CloudflareBucketHashMissing).hash, hashC);
    expect(api.uploads, [
      [hashA],
    ], reason: 'the bucket holding the missing hash is never sent');
    expect(before, 1);
  });

  test('API failures propagate unchanged for stage-specific mapping', () async {
    final api = _ScriptedBucketApi([])
      ..error = CloudflareApiException(CloudflareApiExceptionKind.server);

    await expectLater(
      CloudflareBucketUploader(api).upload(
        accountId: account,
        session: session([
          [hashA],
        ]),
        assetForHash: asset,
      ),
      throwsA(
        isA<CloudflareApiException>().having(
          (e) => e.kind,
          'kind',
          CloudflareApiExceptionKind.server,
        ),
      ),
    );
  });
}

/// Returns one scripted bucket response per call; every other port method is
/// unused by the uploader and fails loudly if reached.
final class _ScriptedBucketApi implements CloudflareDeployApi {
  _ScriptedBucketApi(this._responses);

  final List<CloudflareCompletionToken?> _responses;
  final List<List<String>> uploads = [];
  CloudflareApiException? error;

  @override
  Future<CloudflareCompletionToken?> uploadBucket({
    required CloudflareAccountId accountId,
    required CloudflareUploadSession session,
    required List<CloudflareBucketAsset> assets,
  }) async {
    final failure = error;
    if (failure != null) throw failure;
    uploads.add([for (final asset in assets) asset.hash]);
    return _responses[uploads.length - 1];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
}
