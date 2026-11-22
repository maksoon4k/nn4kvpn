import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

import 'github_release.dart';

class DownloadedUpdate {
  final File file;
  final GitHubRelease release;

  const DownloadedUpdate._(this.file, this.release);
}

/// All URLs are constructed locally. browser_download_url and arbitrary links
/// in release notes are deliberately NOT used as executable download sources.
class GitHubUpdateService {
  final http.Client _client;

  GitHubUpdateService({http.Client? client})
    : _client = client ?? http.Client();

  void close() => _client.close();

  Future<void> discardDownloaded(DownloadedUpdate update) async {
    try {
      if (await update.file.exists()) await update.file.delete();
      // Non-recursive: do not remove any unrelated files added to this folder.
      await update.file.parent.delete();
    } catch (_) {
      // Cleanup failure never makes an installer valid or executable.
    }
  }

  Future<GitHubRelease?> checkLatest({
    required GitHubRepository repository,
    required String currentVersion,
    String? token,
  }) async {
    try {
      final response = await _get(repository.latestReleaseUri, token: token);
      _checkStatus(response);
      final bytes = <int>[];
      final stopwatch = Stopwatch()..start();
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (bytes.length + chunk.length > 2 * 1024 * 1024 ||
            stopwatch.elapsed > const Duration(minutes: 1)) {
          throw const UpdateException(UpdateFailure.invalidRelease);
        }
        bytes.addAll(chunk);
      }
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, dynamic>) {
        throw const UpdateException(UpdateFailure.invalidRelease);
      }
      final release = GitHubRelease.fromJson(repository, json);
      // Semver, not lexicographic ordering: 1.10.0 is newer than 1.9.0.
      if (release.version <= Version.parse(currentVersion)) return null;
      return release;
    } on UpdateException {
      rethrow;
    } on FormatException {
      throw const UpdateException(UpdateFailure.invalidRelease);
    } catch (_) {
      throw const UpdateException(UpdateFailure.network);
    }
  }

  Future<DownloadedUpdate> download({
    required GitHubRelease release,
    required Directory directory,
    String? token,
    void Function(double progress)? onProgress,
  }) async {
    Directory? staging;
    RandomAccessFile? output;
    try {
      await directory.create(recursive: true);
      staging = await directory.createTemp('nn4k-update-');
      final partial = File('${staging.path}/installer.part');
      final response = await _get(
        release.repository.assetUri(release.installer.id),
        token: token,
        download: true,
      );
      _checkStatus(response);
      final length = response.contentLength;
      if (length != null && length != release.installer.size) {
        await response.stream.listen((_) {}).cancel();
        throw const UpdateException(UpdateFailure.unexpectedSize);
      }
      output = await partial.open(mode: FileMode.write);
      final digest = _DigestSink();
      final hash = sha256.startChunkedConversion(digest);
      var received = 0;
      final header = <int>[];
      final stopwatch = Stopwatch()..start();
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        received += chunk.length;
        if (received > release.installer.size || received > maxInstallerBytes) {
          throw const UpdateException(UpdateFailure.unexpectedSize);
        }
        if (stopwatch.elapsed > const Duration(minutes: 15)) {
          throw const UpdateException(UpdateFailure.network);
        }
        for (var i = 0; i < chunk.length && header.length < 2; i++) {
          header.add(chunk[i]);
        }
        hash.add(chunk);
        // Await disk writes: a fast network cannot queue the entire installer
        // in RAM as it could with unbounded IOSink.add calls.
        await output.writeFrom(chunk);
        onProgress?.call(received / release.installer.size);
      }
      hash.close();
      await output.flush();
      await output.close();
      output = null;
      if (received != release.installer.size) {
        throw const UpdateException(UpdateFailure.unexpectedSize);
      }
      if (digest.value?.toString() != release.installer.sha256) {
        throw const UpdateException(UpdateFailure.checksumMismatch);
      }
      if (header.length != 2 || header[0] != 0x4d || header[1] != 0x5a) {
        throw const UpdateException(UpdateFailure.invalidRelease);
      }
      final installer = await partial.rename(
        '${staging.path}/${release.installer.name}',
      );
      return DownloadedUpdate._(installer, release);
    } catch (error) {
      if (output != null) {
        try {
          await output.close();
        } catch (_) {
          // Preserve the original failure.
        }
      }
      if (staging != null) {
        try {
          // Only the uniquely created staging folder belongs to this attempt.
          await staging.delete(recursive: true);
        } catch (_) {
          // A locked failed download is never returned or executed.
        }
      }
      if (error is UpdateException) rethrow;
      if (error is FileSystemException) {
        throw const UpdateException(UpdateFailure.storage);
      }
      throw const UpdateException(UpdateFailure.network);
    }
  }

  /// Re-check immediately before launch, not only when the download completed.
  Future<void> verifyDownloaded(DownloadedUpdate update) async {
    try {
      if (await update.file.length() != update.release.installer.size) {
        throw const UpdateException(UpdateFailure.unexpectedSize);
      }
      final digest = await sha256.bind(update.file.openRead()).first;
      if (digest.toString() != update.release.installer.sha256) {
        throw const UpdateException(UpdateFailure.checksumMismatch);
      }
    } on UpdateException {
      rethrow;
    } catch (_) {
      throw const UpdateException(UpdateFailure.storage);
    }
  }

  Future<http.StreamedResponse> _get(
    Uri uri, {
    String? token,
    bool download = false,
  }) async {
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (!_trustedUri(uri)) {
        throw const UpdateException(UpdateFailure.insecureRedirect);
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers['User-Agent'] = 'NN4K-Updater';
      request.headers['Accept'] = download
          ? 'application/octet-stream'
          : 'application/vnd.github+json';
      if (uri.host == 'api.github.com') {
        request.headers['X-GitHub-Api-Version'] = '2022-11-28';
        if (token != null && token.isNotEmpty) {
          // Never forward a private-repository token to a CDN redirect.
          request.headers['Authorization'] = 'Bearer $token';
        }
      }
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (![301, 302, 303, 307, 308].contains(response.statusCode)) {
        return response;
      }
      await response.stream.listen((_) {}).cancel();
      final location = response.headers['location'];
      if (!download || location == null || redirects == 5) {
        throw const UpdateException(UpdateFailure.insecureRedirect);
      }
      try {
        final next = uri.resolve(location);
        // Credentials are permanently stripped on an origin change. A CDN
        // must not be able to redirect back to the API and regain the token.
        if (next.host != uri.host) token = null;
        uri = next;
      } on FormatException {
        throw const UpdateException(UpdateFailure.insecureRedirect);
      }
    }
    throw const UpdateException(UpdateFailure.insecureRedirect);
  }

  static bool _trustedUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      const {
        'api.github.com',
        'github.com',
        'release-assets.githubusercontent.com',
        'objects.githubusercontent.com',
      }.contains(uri.host);

  static void _checkStatus(http.StreamedResponse response) {
    if (response.statusCode == 200) return;
    // Cancel instead of reading/logging potentially sensitive error bodies.
    unawaited(response.stream.listen((_) {}).cancel());
    if ((response.statusCode == 403 || response.statusCode == 429) &&
        response.headers['x-ratelimit-remaining'] == '0') {
      throw const UpdateException(UpdateFailure.rateLimited);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const UpdateException(UpdateFailure.accessDenied);
    }
    if (response.statusCode == 404) {
      throw const UpdateException(UpdateFailure.noRelease);
    }
    throw const UpdateException(UpdateFailure.network);
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
