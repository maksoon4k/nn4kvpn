import 'package:pub_semver/pub_semver.dart';

enum UpdateFailure {
  busy,
  repositoryNotConfigured,
  invalidRepository,
  accessDenied,
  noRelease,
  rateLimited,
  network,
  invalidRelease,
  missingInstaller,
  missingChecksum,
  checksumMismatch,
  unexpectedSize,
  insecureRedirect,
  storage,
  credentials,
  elevated,
  unsupportedPlatform,
  installFailed,
}

/// Never includes server response bodies, credentials or signed download URLs.
class UpdateException implements Exception {
  final UpdateFailure failure;
  const UpdateException(this.failure);

  @override
  String toString() => 'Update failed: ${failure.name}';
}

class GitHubRepository {
  final String owner;
  final String name;

  const GitHubRepository._(this.owner, this.name);

  factory GitHubRepository.parse(String input) {
    var value = input.trim();
    if (value.isEmpty) {
      throw const UpdateException(UpdateFailure.repositoryNotConfigured);
    }
    if (value.startsWith('https://')) {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.host != 'github.com' ||
          uri.port != 443 ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw const UpdateException(UpdateFailure.invalidRepository);
      }
      value = uri.path.replaceFirst(RegExp(r'^/'), '');
      value = value.replaceFirst(RegExp(r'/$'), '');
      value = value.replaceFirst(RegExp(r'\.git$'), '');
    }
    final parts = value.split('/');
    if (parts.length != 2 ||
        !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9-]{0,38}$').hasMatch(parts[0]) ||
        !RegExp(r'^[a-zA-Z0-9_.-]{1,100}$').hasMatch(parts[1]) ||
        parts[1] == '.' ||
        parts[1] == '..') {
      throw const UpdateException(UpdateFailure.invalidRepository);
    }
    return GitHubRepository._(parts[0].toLowerCase(), parts[1].toLowerCase());
  }

  String get slug => '$owner/$name';

  Uri get latestReleaseUri =>
      Uri.https('api.github.com', '/repos/$slug/releases/latest');

  Uri assetUri(int id) =>
      Uri.https('api.github.com', '/repos/$slug/releases/assets/$id');
}

const maxInstallerBytes = 512 * 1024 * 1024;

class GitHubReleaseAsset {
  final int id;
  final String name;
  final int size;
  final String sha256;

  const GitHubReleaseAsset({
    required this.id,
    required this.name,
    required this.size,
    required this.sha256,
  });
}

class GitHubRelease {
  final GitHubRepository repository;
  final Version version;
  final String notes;
  final GitHubReleaseAsset installer;

  const GitHubRelease({
    required this.repository,
    required this.version,
    required this.notes,
    required this.installer,
  });

  factory GitHubRelease.fromJson(
    GitHubRepository repository,
    Map<String, dynamic> json,
  ) {
    final tag = json['tag_name'];
    if (json['draft'] != false ||
        json['prerelease'] != false ||
        tag is! String ||
        !RegExp(r'^v?[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}$').hasMatch(tag)) {
      throw const UpdateException(UpdateFailure.invalidRelease);
    }
    final version = Version.parse(tag.replaceFirst(RegExp(r'^v'), ''));
    final expectedName = 'NN4KSetup-$version.exe';
    final assets = json['assets'];
    if (assets is! List) {
      throw const UpdateException(UpdateFailure.missingInstaller);
    }
    final matches = assets
        .whereType<Map>()
        .where((asset) => asset['name'] == expectedName)
        .toList();
    if (matches.length != 1) {
      throw const UpdateException(UpdateFailure.missingInstaller);
    }
    final asset = matches.single;
    final id = asset['id'];
    final size = asset['size'];
    if (id is! int || id <= 0 || asset['state'] != 'uploaded') {
      throw const UpdateException(UpdateFailure.invalidRelease);
    }
    if (size is! int || size < 2 || size > maxInstallerBytes) {
      throw const UpdateException(UpdateFailure.unexpectedSize);
    }
    final digest = asset['digest'];
    if (digest is! String ||
        !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)) {
      throw const UpdateException(UpdateFailure.missingChecksum);
    }
    final body = json['body'];
    final notes = body is String ? body : '';
    return GitHubRelease(
      repository: repository,
      version: version,
      notes: notes.length > 20000 ? notes.substring(0, 20000) : notes,
      installer: GitHubReleaseAsset(
        id: id,
        name: expectedName,
        size: size,
        sha256: digest.substring(7).toLowerCase(),
      ),
    );
  }
}
