import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/features/updates/github_release.dart';
import 'package:flux/features/updates/github_update_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'github_release_test.dart' show releaseFixture, updateFailure;

const fixtureInstaller = [0x4d, 0x5a, 1, 2, 3, 4, 5, 6];

GitHubRelease downloadableFixture({List<int> bytes = fixtureInstaller}) {
  final fixture = releaseFixture();
  final asset = (fixture['assets'] as List).first;
  asset['size'] = bytes.length;
  asset['digest'] = 'sha256:${sha256.convert(bytes)}';
  return GitHubRelease.fromJson(GitHubRepository.parse('owner/nn4k'), fixture);
}

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('nn4k-update-tests-'),
  );
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'uses /releases/latest, semver ordering and private-repository authentication',
    () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.github.com/repos/owner/nn4k/releases/latest',
        );
        expect(request.headers['Authorization'], 'Bearer test_token');
        expect(request.followRedirects, false);
        return http.Response(jsonEncode(releaseFixture()), 200);
      });
      final service = GitHubUpdateService(client: client);
      addTearDown(service.close);
      final repository = GitHubRepository.parse('owner/nn4k');
      expect(
        await service.checkLatest(
          repository: repository,
          currentVersion: '1.9.0',
          token: 'test_token',
        ),
        isNotNull,
      );
      expect(
        await service.checkLatest(
          repository: repository,
          currentVersion: '1.10.0',
          token: 'test_token',
        ),
        isNull,
      );
      expect(
        await service.checkLatest(
          repository: repository,
          currentVersion: '1.11.0',
          token: 'test_token',
        ),
        isNull,
      );
    },
  );

  test(
    'downloads from asset API, strips credentials on CDN redirects and verifies bytes',
    () async {
      final release = downloadableFixture();
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        if (requests == 1) {
          expect(request.url, release.repository.assetUri(123));
          expect(request.headers['Authorization'], 'Bearer test_token');
          return http.Response(
            '',
            302,
            headers: {
              'location':
                  'https://release-assets.githubusercontent.com/file?signature=fixture',
            },
          );
        }
        expect(request.url.host, 'release-assets.githubusercontent.com');
        expect(request.headers.containsKey('Authorization'), false);
        return http.Response.bytes(fixtureInstaller, 200);
      });
      final service = GitHubUpdateService(client: client);
      addTearDown(service.close);
      final progress = <double>[];
      final downloaded = await service.download(
        release: release,
        directory: directory,
        token: 'test_token',
        onProgress: progress.add,
      );
      expect(await downloaded.file.readAsBytes(), fixtureInstaller);
      expect(downloaded.file.uri.pathSegments.last, 'NN4KSetup-1.10.0.exe');
      expect(progress.last, 1);
      await service.verifyDownloaded(downloaded);
      expect(requests, 2);
    },
  );

  for (final location in [
    'http://release-assets.githubusercontent.com/file',
    'https://attacker.invalid/file',
    'https://release-assets.githubusercontent.com.attacker.invalid/file',
    'https://user:password@github.com/file',
    'https://github.com:444/file',
  ]) {
    test('blocks unsafe redirect: $location', () async {
      var requests = 0;
      final service = GitHubUpdateService(
        client: MockClient((request) async {
          requests++;
          return http.Response('', 302, headers: {'location': location});
        }),
      );
      addTearDown(service.close);
      await expectLater(
        service.download(
          release: downloadableFixture(),
          directory: directory,
          token: 'test_token',
        ),
        throwsA(updateFailure(UpdateFailure.insecureRedirect)),
      );
      expect(requests, 1);
      expect(await directory.list().toList(), isEmpty);
    });
  }

  test(
    'rejects a checksum mismatch and removes only its staging folder',
    () async {
      final keep = await File(
        '${directory.path}/user-file.txt',
      ).writeAsString('keep');
      final service = GitHubUpdateService(
        client: MockClient(
          (_) async => http.Response.bytes([0x4d, 0x5a, 9, 9, 9, 9, 9, 9], 200),
        ),
      );
      addTearDown(service.close);
      await expectLater(
        service.download(release: downloadableFixture(), directory: directory),
        throwsA(updateFailure(UpdateFailure.checksumMismatch)),
      );
      expect(await keep.readAsString(), 'keep');
      expect((await directory.list().toList()).length, 1);
    },
  );

  test(
    'a CDN redirect back to the GitHub API cannot regain credentials',
    () async {
      var requests = 0;
      final service = GitHubUpdateService(
        client: MockClient((request) async {
          requests++;
          if (requests == 1) {
            expect(request.headers['Authorization'], 'Bearer test_token');
            return http.Response(
              '',
              302,
              headers: {
                'location': 'https://release-assets.githubusercontent.com/file',
              },
            );
          }
          expect(request.headers.containsKey('Authorization'), false);
          if (requests == 2) {
            return http.Response(
              '',
              302,
              headers: {
                'location':
                    'https://api.github.com/repos/owner/nn4k/releases/assets/123',
              },
            );
          }
          return http.Response.bytes(fixtureInstaller, 200);
        }),
      );
      addTearDown(service.close);
      await service.download(
        release: downloadableFixture(),
        directory: directory,
        token: 'test_token',
      );
      expect(requests, 3);
    },
  );

  test('rejects a truncated response', () async {
    final service = GitHubUpdateService(
      client: MockClient((_) async => http.Response.bytes([0x4d, 0x5a], 200)),
    );
    addTearDown(service.close);
    await expectLater(
      service.download(release: downloadableFixture(), directory: directory),
      throwsA(updateFailure(UpdateFailure.unexpectedSize)),
    );
    expect(await directory.list().toList(), isEmpty);
  });

  test('rejects an oversized response', () async {
    final service = GitHubUpdateService(
      client: MockClient(
        (_) async => http.Response.bytes([...fixtureInstaller, 9], 200),
      ),
    );
    addTearDown(service.close);
    await expectLater(
      service.download(release: downloadableFixture(), directory: directory),
      throwsA(updateFailure(UpdateFailure.unexpectedSize)),
    );
  });

  test(
    'rejects non-executable content even with a matching checksum',
    () async {
      final bytes = utf8.encode('<html>not an executable</html>');
      final service = GitHubUpdateService(
        client: MockClient((_) async => http.Response.bytes(bytes, 200)),
      );
      addTearDown(service.close);
      await expectLater(
        service.download(
          release: downloadableFixture(bytes: bytes),
          directory: directory,
        ),
        throwsA(updateFailure(UpdateFailure.invalidRelease)),
      );
    },
  );

  test('re-checks a completed file before installation', () async {
    final service = GitHubUpdateService(
      client: MockClient(
        (_) async => http.Response.bytes(fixtureInstaller, 200),
      ),
    );
    addTearDown(service.close);
    final update = await service.download(
      release: downloadableFixture(),
      directory: directory,
    );
    await update.file.writeAsBytes([0x4d, 0x5a, 9, 9, 9, 9, 9, 9]);
    await expectLater(
      service.verifyDownloaded(update),
      throwsA(updateFailure(UpdateFailure.checksumMismatch)),
    );
  });

  test(
    'does not expose private error bodies or signed URLs in exceptions',
    () async {
      final service = GitHubUpdateService(
        client: MockClient(
          (_) async => http.Response('private_token_and_signed_url', 401),
        ),
      );
      addTearDown(service.close);
      try {
        await service.checkLatest(
          repository: GitHubRepository.parse('owner/nn4k'),
          currentVersion: '1.0.0',
        );
        fail('Expected access denial');
      } on UpdateException catch (error) {
        expect(error.failure, UpdateFailure.accessDenied);
        expect(error.toString(), isNot(contains('private_token')));
      }
    },
  );

  test('distinguishes rate limiting', () async {
    final service = GitHubUpdateService(
      client: MockClient(
        (_) async =>
            http.Response('', 403, headers: {'x-ratelimit-remaining': '0'}),
      ),
    );
    addTearDown(service.close);
    await expectLater(
      service.checkLatest(
        repository: GitHubRepository.parse('owner/nn4k'),
        currentVersion: '1.0.0',
      ),
      throwsA(updateFailure(UpdateFailure.rateLimited)),
    );
  });
}
