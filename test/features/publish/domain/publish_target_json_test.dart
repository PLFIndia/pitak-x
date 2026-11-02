import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/publish_target_json.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';

/// The one target JSON shape shared by the host journal and the backup's
/// `publish_state.json` (plan S11). Decoding rebuilds the sealed target from
/// its parts and refuses any stored URL or id that disagrees (C3).
void main() {
  final github = GitHubPublishTarget.create('degt3rt/my-library')!;
  final cloudflare = CloudflarePublishTarget.create(
    accountId: '0123456789abcdef0123456789abcdef',
    workerName: 'Pitak-Library',
    accountSubdomain: 'library',
  )!;

  test('a GitHub target round-trips with its parts and derived facts', () {
    final json = PublishTargetJson.encode(github);
    expect(json, {
      'repo': 'degt3rt/my-library',
      'host': 'github',
      'targetId': 'github:degt3rt/my-library',
      'siteUrl': github.siteUrl,
    });
    final back = PublishTargetJson.decode(json)!;
    expect(back.isSameExactTarget(github), isTrue);
    expect(back, isA<GitHubPublishTarget>());
  });

  test('a Cloudflare target round-trips (Worker name case kept)', () {
    final json = PublishTargetJson.encode(cloudflare);
    expect(json['workerName'], 'Pitak-Library');
    expect(json['accountSubdomain'], 'library');
    final back = PublishTargetJson.decode(json)! as CloudflarePublishTarget;
    expect(back.isSameExactTarget(cloudflare), isTrue);
    expect(back.workerName.value, 'Pitak-Library');
  });

  test('a stored URL or id that disagrees with the parts is refused', () {
    final wrongUrl = {
      ...PublishTargetJson.encode(github),
      'siteUrl': 'https://evil.github.io/x/',
    };
    final wrongId = {
      ...PublishTargetJson.encode(cloudflare),
      'targetId': 'cloudflare:other',
    };
    expect(PublishTargetJson.decode(wrongUrl), isNull);
    expect(PublishTargetJson.decode(wrongId), isNull);
  });

  test('invalid parts, unknown hosts and non-objects are refused', () {
    expect(
      PublishTargetJson.decode({
        ...PublishTargetJson.encode(github),
        'repo': 'not a repo',
      }),
      isNull,
    );
    expect(
      PublishTargetJson.decode({
        ...PublishTargetJson.encode(github),
        'host': 'netlify',
      }),
      isNull,
    );
    expect(PublishTargetJson.decode('github'), isNull);
    expect(PublishTargetJson.decode(null), isNull);
    expect(
      PublishTargetJson.decode({
        ...PublishTargetJson.encode(github),
        'repo': 7,
      }),
      isNull,
    );
  });

  test('expectedHost refuses a target of the other host', () {
    final json = PublishTargetJson.encode(github);
    expect(
      PublishTargetJson.decode(json, expectedHost: PublishHost.cloudflare),
      isNull,
    );
    expect(
      PublishTargetJson.decode(json, expectedHost: PublishHost.github),
      isNotNull,
    );
  });

  test('hostFrom reads only the enum names', () {
    expect(PublishTargetJson.hostFrom('github'), PublishHost.github);
    expect(PublishTargetJson.hostFrom('cloudflare'), PublishHost.cloudflare);
    expect(PublishTargetJson.hostFrom('GitHub'), isNull);
    expect(PublishTargetJson.hostFrom(1), isNull);
  });
}
