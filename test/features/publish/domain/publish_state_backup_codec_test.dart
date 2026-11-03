import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup.dart';
import 'package:pitaka/features/publish/domain/publish_state_backup_codec.dart';
import 'package:pitaka/features/publish/domain/publish_target.dart';
import 'package:pitaka/features/publish/domain/publish_target_json.dart';
import 'package:pitaka/features/publish/domain/site/publish_host.dart';
import 'package:pitaka/features/publish/domain/site/publish_state.dart';

import '../support/publish_state_fixtures.dart';

/// The `publish_state.json` entry (plan CV6, S11) is HOSTILE input on
/// restore: one bad field makes the whole entry unreadable, which only ever
/// means "adopt nothing" (more uploads, never a wrong delete).
void main() {
  Map<String, dynamic> encoded([PublishStateBackup? state]) =>
      jsonDecode(PublishStateBackupCodec.encode(state ?? archivedState()))
          as Map<String, dynamic>;

  PublishStateBackup? decode(Object json) =>
      PublishStateBackupCodec.decode(jsonEncode(json));

  group('round trip', () {
    test('everything a phone carries survives encode → decode', () {
      final back = PublishStateBackupCodec.decode(
        PublishStateBackupCodec.encode(archivedState()),
      )!;
      expect(back.coverSalt, archiveSalt);
      final gitHub = back.gitHubRecord;
      expect(gitHub.repo, 'degt3rt/my-library');
      expect(gitHub.branch, 'main');
      expect(gitHub.headSha, sha40('1'));
      expect(gitHub.state, PublishState.live);
      expect(gitHub.fileShas, gitHubRecord().fileShas);
      expect(gitHub.coverUrlByBookId, gitHubRecord().coverUrlByBookId);
      expect(gitHub.coverRendition, gitHubRecord().coverRendition);
      expect(gitHub.catalogueKeyed, isTrue, reason: 'adoption clears it');
      final cloudflare = back.cloudflareRecord;
      expect(cloudflare.describes(archiveCloudflare), isTrue);
      expect(cloudflare.files.keys, cloudflareRecord().files.keys);
      expect(cloudflare.publishId, 'a' * 32);
      expect(back.activeHost, PublishHost.github);
      expect(back.verifiedTarget!.isSameExactTarget(archiveGitHub), isTrue);
    });

    test('absent parts are left out and read back as absent', () {
      final minimal = PublishStateBackup.tryCreate(
        coverSalt: archiveSalt,
        gitHubRecord: gitHubRecord(),
      )!;
      final json = encoded(minimal);
      expect(json.keys, {'schemaVersion', 'coverSalt', 'gitHubRecord'});
      final back = decode(json)!;
      expect(back.cloudflareRecord.target, isNull);
      expect(back.activeHost, isNull);
      expect(back.verifiedTarget, isNull);
    });

    test('an active host without a verified address round-trips', () {
      final state = archivedState(verifiedGitHub: false);
      final json = encoded(state);
      expect(json['host'], {'active': 'github'});
      expect(decode(json)!.activeHost, PublishHost.github);
    });

    test('the entry carries only known keys — no token field exists', () {
      final json = encoded();
      expect(json.keys, {
        'schemaVersion',
        'coverSalt',
        'gitHubRecord',
        'cloudflareRecord',
        'host',
      });
      final text = jsonEncode(json).toLowerCase();
      for (final word in ['token', 'secret', 'password', 'jwt', 'bearer']) {
        expect(text, isNot(contains(word)), reason: word);
      }
    });

    test('an unknown extra top-level key is ignored (additive)', () {
      expect(decode({...encoded(), 'later': 1}), isNotNull);
    });
  });

  group('bounds before parsing', () {
    test('text over maxBytes is refused unparsed', () {
      final padded = '${' ' * PublishStateBackupCodec.maxBytes}{}';
      expect(PublishStateBackupCodec.decode(padded), isNull);
    });

    test('nesting deeper than maxJsonDepth is refused unparsed', () {
      final deep = '${'[' * 9}${']' * 9}';
      expect(PublishStateBackupCodec.decode(deep), isNull);
      final legit = PublishStateBackupCodec.encode(archivedState());
      expect(
        PublishStateBackupCodec.decode(legit),
        isNotNull,
        reason: 'a real entry stays within the depth limit',
      );
    });

    test('malformed JSON and non-objects are refused', () {
      expect(PublishStateBackupCodec.decode('{'), isNull);
      expect(PublishStateBackupCodec.decode('[]'), isNull);
      expect(PublishStateBackupCodec.decode('"x"'), isNull);
    });
  });

  group('envelope', () {
    test('only schemaVersion 1 is read', () {
      for (final version in [0, 2, '1', null]) {
        expect(
          decode({...encoded(), 'schemaVersion': version}),
          isNull,
          reason: '$version',
        );
      }
      expect(decode(encoded()..remove('schemaVersion')), isNull);
    });

    test('the salt must be base64 of exactly 16 bytes', () {
      for (final salt in [
        base64Encode(List<int>.filled(15, 1)),
        base64Encode(List<int>.filled(17, 1)),
        'not base64!',
        'A' * 100,
        7,
        null,
      ]) {
        expect(
          decode({...encoded(), 'coverSalt': salt}),
          isNull,
          reason: '$salt',
        );
      }
    });

    test('an entry naming no site is refused', () {
      final json = encoded()
        ..remove('gitHubRecord')
        ..remove('cloudflareRecord')
        ..remove('host');
      expect(decode(json), isNull);
    });
  });

  group('the GitHub record is checked field by field', () {
    Map<String, dynamic> withGitHub(Map<String, Object?> changes) {
      final json = encoded();
      final record = Map<String, dynamic>.of(
        json['gitHubRecord'] as Map<String, dynamic>,
      )..addAll(changes);
      return {...json, 'gitHubRecord': record};
    }

    Map<String, dynamic> withoutGitHubKey(String key) {
      final json = encoded();
      final record = Map<String, dynamic>.of(
        json['gitHubRecord'] as Map<String, dynamic>,
      )..remove(key);
      return {...json, 'gitHubRecord': record};
    }

    test('a record that is not an object', () {
      expect(decode({...encoded(), 'gitHubRecord': 'x'}), isNull);
    });

    test('a missing or invalid repository', () {
      expect(decode(withoutGitHubKey('repo')), isNull);
      expect(decode(withGitHub({'repo': 'no-slash'})), isNull);
      expect(decode(withGitHub({'repo': 3})), isNull);
    });

    test('a branch the app could not publish to', () {
      expect(decode(withGitHub({'branch': '../main'})), isNull);
      expect(decode(withGitHub({'branch': 'a b'})), isNull);
      expect(decode(withGitHub({'branch': 1})), isNull);
      expect(decode(withoutGitHubKey('branch')), isNotNull);
    });

    test('a head that is not a 40-hex sha', () {
      expect(decode(withGitHub({'headSha': 'abc'})), isNull);
      expect(decode(withGitHub({'headSha': 'A' * 40})), isNull);
      expect(decode(withoutGitHubKey('headSha')), isNotNull);
    });

    test('ownershipConfirmed of the wrong type', () {
      expect(decode(withGitHub({'ownershipConfirmed': 'true'})), isNull);
    });

    test('an unknown state', () {
      expect(decode(withGitHub({'state': 'published'})), isNull);
    });

    test('a commit time that is not a whole, non-negative number (SP1)', () {
      expect(decode(withGitHub({'committedAt': '1700000000000'})), isNull);
      expect(decode(withGitHub({'committedAt': 1.5})), isNull);
      expect(decode(withGitHub({'committedAt': -1})), isNull);
      final kept = decode(withGitHub({'committedAt': 1700000000000}));
      expect(kept?.gitHubRecord.committedAt, 1700000000000);
      expect(decode(withoutGitHubKey('committedAt')), isNotNull);
    });

    test('a claimed path that is not Pitak-owned or not safe', () {
      for (final path in [
        'notes/private.txt',
        'README.md',
        '../books.json',
        '/books.json',
        'covers/../x.jpg',
      ]) {
        expect(
          decode(
            withGitHub({
              'fileShas': {path: sha40('a')},
            }),
          ),
          isNull,
          reason: path,
        );
      }
    });

    test("GitHub's .nojekyll is a Pitak-owned path (plan SP5)", () {
      final kept = decode(
        withGitHub({
          'fileShas': {'books.json': sha40('a'), '.nojekyll': sha40('b')},
        }),
      );
      expect(kept?.gitHubRecord.shaFor('.nojekyll'), sha40('b'));
    });

    test('a claimed path whose sha is not 40-hex', () {
      expect(
        decode(
          withGitHub({
            'fileShas': {'books.json': 'short'},
          }),
        ),
        isNull,
      );
      expect(
        decode(
          withGitHub({
            'fileShas': {'books.json': 5},
          }),
        ),
        isNull,
      );
      expect(decode(withGitHub({'fileShas': 'books.json'})), isNull);
    });

    test('more claimed paths than a record may hold', () {
      final many = {
        for (var i = 0; i <= PublishStateBackupCodec.maxRecordFiles; i++)
          'covers/${i.toRadixString(16).padLeft(16, '0')}.jpg': sha40('a'),
      };
      expect(decode(withGitHub({'fileShas': many})), isNull);
    });

    test('cover sources of the wrong shape or size', () {
      for (final covers in [
        'x',
        {'1': 7},
        {'': 'covers/a.jpg'},
        {'k' * 257: 'covers/a.jpg'},
        {'1': 'h' * 4097},
      ]) {
        expect(
          decode(withGitHub({'coverUrlByBookId': covers})),
          isNull,
          reason: '$covers',
        );
      }
    });
  });

  group('the Cloudflare record', () {
    test('a record its own strict decoder empties is refused', () {
      final json = encoded();
      final record = Map<String, dynamic>.of(
        json['cloudflareRecord'] as Map<String, dynamic>,
      )..['publishId'] = 'not-an-id';
      expect(decode({...json, 'cloudflareRecord': record}), isNull);
      expect(decode({...json, 'cloudflareRecord': 'x'}), isNull);
    });

    test('oversized cover sources are refused', () {
      final json = encoded();
      final record = Map<String, dynamic>.of(
        json['cloudflareRecord'] as Map<String, dynamic>,
      )..['coverUrlByBookId'] = {'1': 'h' * 4097};
      expect(decode({...json, 'cloudflareRecord': record}), isNull);
    });
  });

  group('the host', () {
    test('a host that is not an object or names no known host', () {
      expect(decode({...encoded(), 'host': 'github'}), isNull);
      expect(
        decode({
          ...encoded(),
          'host': {'active': 'netlify'},
        }),
        isNull,
      );
      expect(decode({...encoded(), 'host': <String, Object?>{}}), isNull);
    });

    test('a verified address that is invalid or of the other host', () {
      expect(
        decode({
          ...encoded(),
          'host': {
            'active': 'github',
            'verifiedTarget': {
              ...PublishTargetJson.encode(archiveGitHub),
              'siteUrl': 'https://evil.github.io/',
            },
          },
        }),
        isNull,
      );
      expect(
        decode({
          ...encoded(),
          'host': {
            'active': 'cloudflare',
            'verifiedTarget': PublishTargetJson.encode(archiveGitHub),
          },
        }),
        isNull,
      );
    });
  });
}
