import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

enum BoundedDownloadFailure {
  invalidUrl,
  insecureRedirect,
  tooLarge,
  truncated,
}

/// Deliberately excludes URLs: subscription paths/queries can contain secrets.
class BoundedDownloadException implements Exception {
  final BoundedDownloadFailure failure;
  const BoundedDownloadException(this.failure);

  @override
  String toString() => switch (failure) {
    BoundedDownloadFailure.invalidUrl => 'Invalid HTTP(S) download URL',
    BoundedDownloadFailure.insecureRedirect => 'Unsafe or excessive redirects',
    BoundedDownloadFailure.tooLarge => 'Download exceeds the size limit',
    BoundedDownloadFailure.truncated => 'Incomplete download',
  };
}

/// For non-executable, user-configured subscription/routing/geo sources.
///
/// Bounds the streamed (decompressed) body, redirects, and total elapsed time.
/// HTTPS sources can never redirect to HTTP. Plain HTTP is accepted only when
/// a caller explicitly opts in for compatibility; it is not authenticated.
/// The executable updater has a separate, stricter host/digest policy.
Future<http.Response> boundedHttpGet(
  Uri source, {
  required int maxBytes,
  Duration timeout = const Duration(seconds: 15),
  bool allowHttp = false,
  http.Client? client,
}) async {
  if (maxBytes < 1) throw RangeError.value(maxBytes, 'maxBytes');
  if (timeout <= Duration.zero) throw ArgumentError.value(timeout, 'timeout');
  final transport = client ?? http.Client();
  final abort = Completer<void>();
  StreamIterator<List<int>>? body;

  Future<http.Response> get() async {
    var uri = source;
    var requireHttps = !allowHttp || source.scheme == 'https';
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (!_validUri(uri, requireHttps: requireHttps)) {
        throw BoundedDownloadException(
          redirects == 0
              ? BoundedDownloadFailure.invalidUrl
              : BoundedDownloadFailure.insecureRedirect,
        );
      }
      // Once a request upgrades to HTTPS, a later downgrade is also forbidden.
      requireHttps = requireHttps || uri.scheme == 'https';
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      )..followRedirects = false;
      final response = await transport.send(request);
      if (abort.isCompleted) {
        await response.stream.listen((_) {}).cancel();
        throw TimeoutException('Download timed out', timeout);
      }
      if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
        await response.stream.listen((_) {}).cancel();
        final location = response.headers['location'];
        if (location == null || redirects == 5) {
          throw const BoundedDownloadException(
            BoundedDownloadFailure.insecureRedirect,
          );
        }
        try {
          uri = uri.resolve(location);
        } on FormatException {
          throw const BoundedDownloadException(
            BoundedDownloadFailure.insecureRedirect,
          );
        }
        continue;
      }
      if (response.statusCode != 200) {
        // Do not read an arbitrarily large/private HTTP error page.
        await response.stream.listen((_) {}).cancel();
        return http.Response(
          '',
          response.statusCode,
          headers: response.headers,
        );
      }
      final expectedLength = response.contentLength;
      if (expectedLength != null && expectedLength > maxBytes) {
        await response.stream.listen((_) {}).cancel();
        throw const BoundedDownloadException(BoundedDownloadFailure.tooLarge);
      }
      final bytes = BytesBuilder(copy: false);
      final iterator = StreamIterator(response.stream);
      body = iterator;
      while (await iterator.moveNext()) {
        if (abort.isCompleted) {
          throw TimeoutException('Download timed out', timeout);
        }
        final chunk = iterator.current;
        if (bytes.length + chunk.length > maxBytes) {
          throw const BoundedDownloadException(BoundedDownloadFailure.tooLarge);
        }
        bytes.add(chunk);
      }
      // Content-Length describes compressed bytes for compressed responses;
      // only compare it when the transport has not decompressed the body.
      final encoding = response.headers['content-encoding'];
      if ((encoding == null || encoding == 'identity') &&
          expectedLength != null &&
          bytes.length != expectedLength) {
        throw const BoundedDownloadException(BoundedDownloadFailure.truncated);
      }
      return http.Response.bytes(
        bytes.takeBytes(),
        200,
        headers: response.headers,
      );
    }
    throw const BoundedDownloadException(
      BoundedDownloadFailure.insecureRedirect,
    );
  }

  try {
    return await get().timeout(timeout);
  } finally {
    // Future.timeout alone does not cancel I/O. Abort the real request as well
    // as the body iterator; injected/shared clients remain usable by callers.
    abort.complete();
    try {
      await body?.cancel();
    } finally {
      if (client == null) transport.close();
    }
  }
}

bool _validUri(Uri uri, {required bool requireHttps}) =>
    (uri.scheme == 'https' || (!requireHttps && uri.scheme == 'http')) &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty &&
    !uri.hasFragment;
