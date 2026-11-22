import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/app/bounded_http.dart';
import 'package:http/http.dart' as http;

class _Client extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  final requests = <http.BaseRequest>[];
  bool closed = false;

  _Client(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return handler(request);
  }

  @override
  void close() => closed = true;
}

http.StreamedResponse _response(
  List<List<int>> chunks, {
  int status = 200,
  int? contentLength,
  Map<String, String> headers = const {},
}) => http.StreamedResponse(
  Stream.fromIterable(chunks),
  status,
  contentLength: contentLength,
  headers: headers,
);

Matcher _failure(BoundedDownloadFailure failure) => throwsA(
  isA<BoundedDownloadException>().having((e) => e.failure, 'failure', failure),
);

void main() {
  final source = Uri.https('example.test', '/private-subscription');

  test(
    'collects a bounded streamed response without closing a shared client',
    () async {
      final client = _Client(
        (_) async => _response([
          [1, 2],
          [3],
        ], contentLength: 3),
      );
      final result = await boundedHttpGet(source, maxBytes: 3, client: client);

      expect(result.bodyBytes, [1, 2, 3]);
      expect(client.closed, isFalse);
      expect(client.requests.single, isA<http.AbortableRequest>());
      expect(client.requests.single.followRedirects, isFalse);
    },
  );

  test('rejects advertised oversize without reading the body', () async {
    var canceled = false;
    final body = StreamController<List<int>>(onCancel: () => canceled = true);
    final client = _Client(
      (_) async => http.StreamedResponse(body.stream, 200, contentLength: 4),
    );

    await expectLater(
      boundedHttpGet(source, maxBytes: 3, client: client),
      _failure(BoundedDownloadFailure.tooLarge),
    );
    expect(canceled, isTrue);
    await body.close();
  });

  test('enforces the size limit even without Content-Length', () async {
    final client = _Client(
      (_) async => _response([
        [1, 2],
        [3, 4],
      ]),
    );
    await expectLater(
      boundedHttpGet(source, maxBytes: 3, client: client),
      _failure(BoundedDownloadFailure.tooLarge),
    );
  });

  test('enforces the decompressed body limit', () async {
    final client = _Client(
      (_) async => _response(
        [
          [1, 2, 3, 4],
        ],
        contentLength: 1,
        headers: {'content-encoding': 'gzip'},
      ),
    );
    await expectLater(
      boundedHttpGet(source, maxBytes: 3, client: client),
      _failure(BoundedDownloadFailure.tooLarge),
    );
  });

  test('does not compare compressed length with decompressed length', () async {
    final client = _Client(
      (_) async => _response(
        [
          [1, 2, 3],
        ],
        contentLength: 1,
        headers: {'content-encoding': 'gzip'},
      ),
    );
    final result = await boundedHttpGet(source, maxBytes: 3, client: client);
    expect(result.bodyBytes, [1, 2, 3]);
  });

  test('rejects a truncated uncompressed body', () async {
    final client = _Client(
      (_) async => _response([
        [1],
      ], contentLength: 2),
    );
    await expectLater(
      boundedHttpGet(source, maxBytes: 3, client: client),
      _failure(BoundedDownloadFailure.truncated),
    );
  });

  test('does not read private or unbounded HTTP error pages', () async {
    var canceled = false;
    final body = StreamController<List<int>>(onCancel: () => canceled = true);
    final client = _Client(
      (_) async => http.StreamedResponse(body.stream, 503),
    );
    final result = await boundedHttpGet(source, maxBytes: 3, client: client);
    expect(result.statusCode, 503);
    expect(result.body, isEmpty);
    expect(canceled, isTrue);
    await body.close();
  });

  test('follows relative and cross-host HTTPS redirects manually', () async {
    final client = _Client(
      (request) async => switch (request.url.path) {
        '/private-subscription' => _response(
          [],
          status: 302,
          headers: {'location': '/next'},
        ),
        '/next' => _response(
          [],
          status: 307,
          headers: {'location': 'https://mirror.test/final'},
        ),
        _ => _response([
          [1],
        ]),
      },
    );
    final result = await boundedHttpGet(source, maxBytes: 3, client: client);
    expect(result.bodyBytes, [1]);
    expect(client.requests.map((r) => r.url.toString()), [
      source.toString(),
      'https://example.test/next',
      'https://mirror.test/final',
    ]);
    expect(client.requests.every((r) => !r.followRedirects), isTrue);
  });

  test('bounds a redirect loop to five redirects', () async {
    final client = _Client(
      (_) async => _response([], status: 302, headers: {'location': '/loop'}),
    );
    await expectLater(
      boundedHttpGet(source, maxBytes: 3, client: client),
      _failure(BoundedDownloadFailure.insecureRedirect),
    );
    expect(client.requests, hasLength(6));
  });

  test(
    'never downgrades an HTTPS source even with HTTP compatibility enabled',
    () async {
      final client = _Client(
        (_) async => _response(
          [],
          status: 302,
          headers: {'location': 'http://mirror.test/sub'},
        ),
      );
      await expectLater(
        boundedHttpGet(source, maxBytes: 3, allowHttp: true, client: client),
        _failure(BoundedDownloadFailure.insecureRedirect),
      );
      expect(client.requests, hasLength(1));
    },
  );

  test('never downgrades after an HTTP source upgrades to HTTPS', () async {
    final client = _Client(
      (request) async => _response(
        [],
        status: 302,
        headers: {
          'location': request.url.scheme == 'http'
              ? 'https://mirror.test/sub'
              : 'http://mirror.test/sub',
        },
      ),
    );
    await expectLater(
      boundedHttpGet(
        Uri.http('example.test', '/sub'),
        maxBytes: 3,
        allowHttp: true,
        client: client,
      ),
      _failure(BoundedDownloadFailure.insecureRedirect),
    );
    expect(client.requests, hasLength(2));
  });

  for (final url in [
    'file:///private.txt',
    'http://example.test/sub',
    'https:///sub',
    'https://user:secret@example.test/sub',
    'https://example.test/sub#fragment',
  ]) {
    test('rejects invalid or unauthenticated URL: $url', () async {
      final client = _Client(
        (_) async => _response([
          [1],
        ]),
      );
      await expectLater(
        boundedHttpGet(Uri.parse(url), maxBytes: 3, client: client),
        _failure(BoundedDownloadFailure.invalidUrl),
      );
      expect(client.requests, isEmpty);
    });
  }

  test('accepts explicitly configured HTTP data sources', () async {
    final client = _Client(
      (_) async => _response([
        [1],
      ]),
    );
    final result = await boundedHttpGet(
      Uri.http('example.test', '/sub'),
      maxBytes: 3,
      allowHttp: true,
      client: client,
    );
    expect(result.bodyBytes, [1]);
  });

  test('the total deadline aborts a request waiting for headers', () async {
    final aborted = Completer<void>();
    final client = _Client((request) {
      final result = Completer<http.StreamedResponse>();
      (request as http.AbortableRequest).abortTrigger!.then((_) {
        aborted.complete();
        result.completeError(http.RequestAbortedException(request.url));
      });
      return result.future;
    });
    await expectLater(
      boundedHttpGet(
        source,
        maxBytes: 3,
        client: client,
        timeout: const Duration(milliseconds: 30),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await aborted.future;
    expect(client.closed, isFalse);
  });

  test('the total deadline cancels a stalled response body', () async {
    var canceled = false;
    final body = StreamController<List<int>>(onCancel: () => canceled = true);
    body.add([1]);
    final client = _Client(
      (_) async => http.StreamedResponse(body.stream, 200),
    );
    await expectLater(
      boundedHttpGet(
        source,
        maxBytes: 3,
        client: client,
        timeout: const Duration(milliseconds: 30),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(canceled, isTrue);
    expect(client.closed, isFalse);
    await body.close();
  });

  test('validation messages do not expose secret URLs', () {
    for (final failure in BoundedDownloadFailure.values) {
      expect(
        BoundedDownloadException(failure).toString(),
        isNot(contains(source.toString())),
      );
      expect(
        BoundedDownloadException(failure).toString(),
        isNot(contains('private-subscription')),
      );
    }
  });
}
