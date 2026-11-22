import 'package:flutter_test/flutter_test.dart';
import 'package:flux/features/updates/github_release.dart';

Map<String, dynamic> releaseFixture({String version = '1.10.0'}) => {
  'tag_name': 'v$version',
  'draft': false,
  'prerelease': false,
  'body': 'Fixture release notes',
  'assets': [
    <String, dynamic>{
      'id': 123,
      'name': 'NN4KSetup-$version.exe',
      'state': 'uploaded',
      'size': 16,
      'digest': 'sha256:${'a' * 64}',
      'browser_download_url': 'https://attacker.invalid/not-used.exe',
    },
  ],
};

Matcher updateFailure(UpdateFailure failure) =>
    isA<UpdateException>().having((error) => error.failure, 'failure', failure);

void main() {
  group('GitHubRepository', () {
    test('normalizes a slug and official repository URL', () {
      expect(GitHubRepository.parse(' Owner/NN4K ').slug, 'owner/nn4k');
      expect(
        GitHubRepository.parse('https://github.com/Owner/NN4K.git/').slug,
        'owner/nn4k',
      );
      expect(
        GitHubRepository.parse('owner/nn4k').assetUri(7).toString(),
        'https://api.github.com/repos/owner/nn4k/releases/assets/7',
      );
    });

    test('rejects missing configuration separately', () {
      expect(
        () => GitHubRepository.parse('  '),
        throwsA(updateFailure(UpdateFailure.repositoryNotConfigured)),
      );
    });

    for (final input in [
      'https://github.com.attacker.invalid/owner/repo',
      'http://github.com/owner/repo',
      'https://token@github.com/owner/repo',
      'https://github.com:444/owner/repo',
      'https://github.com/owner/repo?token=secret',
      'owner/repo/releases/latest',
      'owner/..',
      '../repo',
      'owner/repo\nother/repo',
    ]) {
      test('rejects untrusted repository input: $input', () {
        expect(
          () => GitHubRepository.parse(input),
          throwsA(updateFailure(UpdateFailure.invalidRepository)),
        );
      });
    }
  });

  group('GitHubRelease', () {
    final repository = GitHubRepository.parse('owner/nn4k');

    test('selects the exact installer and ignores supplied download URLs', () {
      final release = GitHubRelease.fromJson(repository, releaseFixture());
      expect(release.version.toString(), '1.10.0');
      expect(release.installer.name, 'NN4KSetup-1.10.0.exe');
      expect(release.installer.sha256, 'a' * 64);
    });

    test('requires a stable, published version', () {
      for (final key in ['draft', 'prerelease']) {
        final fixture = releaseFixture()..[key] = true;
        expect(
          () => GitHubRelease.fromJson(repository, fixture),
          throwsA(updateFailure(UpdateFailure.invalidRelease)),
        );
      }
      for (final tag in ['v1.10.0-beta', 'v1.10.0+8', '../../file', 'latest']) {
        final fixture = releaseFixture()..['tag_name'] = tag;
        expect(
          () => GitHubRelease.fromJson(repository, fixture),
          throwsA(updateFailure(UpdateFailure.invalidRelease)),
        );
      }
    });

    test('requires exactly one correctly named Windows installer', () {
      final missing = releaseFixture()..['assets'] = [];
      expect(
        () => GitHubRelease.fromJson(repository, missing),
        throwsA(updateFailure(UpdateFailure.missingInstaller)),
      );
      final duplicate = releaseFixture();
      (duplicate['assets'] as List).add((duplicate['assets'] as List).first);
      expect(
        () => GitHubRelease.fromJson(repository, duplicate),
        throwsA(updateFailure(UpdateFailure.missingInstaller)),
      );
    });

    test('requires GitHub SHA-256 metadata and bounded size', () {
      for (final digest in [null, '', 'sha1:${'a' * 40}', 'sha256:wrong']) {
        final fixture = releaseFixture();
        (fixture['assets'] as List).first['digest'] = digest;
        expect(
          () => GitHubRelease.fromJson(repository, fixture),
          throwsA(updateFailure(UpdateFailure.missingChecksum)),
        );
      }
      for (final size in [0, 1, maxInstallerBytes + 1, -1, '16']) {
        final fixture = releaseFixture();
        (fixture['assets'] as List).first['size'] = size;
        expect(
          () => GitHubRelease.fromJson(repository, fixture),
          throwsA(updateFailure(UpdateFailure.unexpectedSize)),
        );
      }
    });

    test('limits notes without interpreting them', () {
      final fixture = releaseFixture()..['body'] = 'x' * 25000;
      expect(GitHubRelease.fromJson(repository, fixture).notes.length, 20000);
    });
  });
}
