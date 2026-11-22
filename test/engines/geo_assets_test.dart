import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/app/bounded_http.dart';
import 'package:flux/core_abstraction/app_settings.dart';
import 'package:flux/engines/geo_assets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Small protobuf GeoIPList/GeoSiteList fixtures, never real network downloads.
final _geoip = Uint8List.fromList([
  10,
  14,
  10,
  2,
  99,
  110,
  18,
  8,
  10,
  4,
  1,
  2,
  3,
  0,
  16,
  24,
]);
final _geosite = Uint8List.fromList([
  10,
  14,
  10,
  2,
  99,
  110,
  18,
  8,
  8,
  2,
  18,
  4,
  97,
  46,
  99,
  110,
]);

class _AdvertisedOversizeClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        const Stream.empty(),
        200,
        contentLength: maxGeoAssetBytes + 1,
      );
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nn4k-geo-test-');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'validates and atomically replaces only geo data in the isolated directory',
    () async {
      final client = MockClient(
        (request) async => http.Response.bytes(
          request.url.path == '/geoip.dat' ? _geoip : _geosite,
          200,
        ),
      );
      await forceUpdateGeoAssets(
        geoipUrl: 'https://geo.test/geoip.dat',
        geositeUrl: 'https://geo.test/geosite.dat',
        directory: directory,
        client: client,
      );
      expect(await File('${directory.path}/geoip.dat').readAsBytes(), _geoip);
      expect(
        await File('${directory.path}/geosite.dat').readAsBytes(),
        _geosite,
      );
      expect(await directory.list().length, 2);
    },
  );

  test('malformed or empty databases never replace existing files', () async {
    final geoip = File('${directory.path}/geoip.dat');
    final geosite = File('${directory.path}/geosite.dat');
    await geoip.writeAsBytes(_geoip);
    await geosite.writeAsBytes(_geosite);
    for (final body in [
      <int>[10, 5, 1],
      <int>[16, 1],
    ]) {
      final client = MockClient((_) async => http.Response.bytes(body, 200));
      await expectLater(
        forceUpdateGeoAssets(
          geoipUrl: 'https://geo.test/geoip.dat',
          geositeUrl: 'https://geo.test/geosite.dat',
          directory: directory,
          client: client,
        ),
        throwsFormatException,
      );
      expect(await geoip.readAsBytes(), _geoip);
      expect(await geosite.readAsBytes(), _geosite);
      expect(await directory.list().length, 2);
    }
  });

  test(
    'rejects oversized geo assets before reading them or staging files',
    () async {
      final client = _AdvertisedOversizeClient();
      await expectLater(
        forceUpdateGeoAssets(
          geoipUrl: 'https://geo.test/geoip.dat',
          geositeUrl: 'https://geo.test/geosite.dat',
          directory: directory,
          client: client,
        ),
        throwsA(
          isA<BoundedDownloadException>().having(
            (e) => e.failure,
            'failure',
            BoundedDownloadFailure.tooLarge,
          ),
        ),
      );
      expect(await directory.list().length, 0);
    },
  );

  test('failed background refresh preserves cached geo data', () async {
    final geoip = File('${directory.path}/geoip.dat');
    final geosite = File('${directory.path}/geosite.dat');
    await geoip.writeAsBytes(_geoip);
    await geosite.writeAsBytes(_geosite);
    final stale = DateTime.now().subtract(const Duration(days: 8));
    await geoip.setLastModified(stale);
    await geosite.setLastModified(stale);
    final client = MockClient((_) async => http.Response('error', 503));
    await ensureGeoAssets(
      geoipUrl: defaultGeoipUrl,
      geositeUrl: defaultGeositeUrl,
      directory: directory,
      client: client,
    );
    expect(await geoip.readAsBytes(), _geoip);
    expect(await geosite.readAsBytes(), _geosite);
  });

  test('fresh cached assets require no network request', () async {
    await File('${directory.path}/geoip.dat').writeAsBytes(_geoip);
    await File('${directory.path}/geosite.dat').writeAsBytes(_geosite);
    final client = MockClient(
      (_) async => throw StateError('No request expected'),
    );
    await ensureGeoAssets(
      geoipUrl: defaultGeoipUrl,
      geositeUrl: defaultGeositeUrl,
      directory: directory,
      client: client,
    );
  });

  test(
    'HTTP errors do not disclose a geo URL containing private parameters',
    () async {
      final client = MockClient((_) async => http.Response('error', 503));
      await expectLater(
        forceUpdateGeoAssets(
          geoipUrl: 'https://geo.test/geoip.dat?token=secret',
          geositeUrl: 'https://geo.test/geosite.dat?token=secret',
          directory: directory,
          client: client,
        ),
        throwsA(
          isA<HttpException>().having(
            (e) => e.toString().contains('secret'),
            'contains secret',
            isFalse,
          ),
        ),
      );
    },
  );
}
