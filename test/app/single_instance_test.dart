import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/app/single_instance.dart';

Future<PrimaryInstance> _primary({
  Duration timeout = const Duration(seconds: 2),
}) async =>
    await acquireSingleInstance(port: 0, messageTimeout: timeout)
        as PrimaryInstance;

Future<void> _send(PrimaryInstance primary, List<int> bytes) async {
  final socket = await Socket.connect(
    InternetAddress.loopbackIPv4,
    primary.port,
  );
  try {
    socket.add(bytes);
    await socket.flush();
    await socket.close();
  } finally {
    socket.destroy();
  }
}

void main() {
  test(
    'forwards one UTF-8 deep link through an isolated loopback port',
    () async {
      final primary = await _primary();
      addTearDown(primary.close);
      final received = primary.incomingDeepLinks.first;
      final result = await acquireSingleInstance(
        port: primary.port,
        deepLink: 'flux://add/привет',
      );
      expect(result, isA<SecondaryInstance>());
      expect(
        await received.timeout(const Duration(seconds: 2)),
        'flux://add/привет',
      );
    },
  );

  test('an empty message focuses the existing application', () async {
    final primary = await _primary();
    addTearDown(primary.close);
    final received = primary.incomingDeepLinks.first;
    await acquireSingleInstance(port: primary.port);
    expect(await received.timeout(const Duration(seconds: 2)), '');
  });

  test(
    'accepts fragmented messages and CRLF, but only one line per peer',
    () async {
      final primary = await _primary();
      addTearDown(primary.close);
      final messages = <String>[];
      final subscription = primary.incomingDeepLinks.listen(messages.add);
      addTearDown(subscription.cancel);
      final received = primary.incomingDeepLinks.first;
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        primary.port,
      );
      socket.add(utf8.encode('flux://add/'));
      await socket.flush();
      socket.add(utf8.encode('one\r\nflux://add/two\n'));
      await socket.flush();
      await socket.close();
      expect(
        await received.timeout(const Duration(seconds: 2)),
        'flux://add/one',
      );
      await primary.close();
      expect(messages, ['flux://add/one']);
    },
  );

  test('rejects oversized, invalid UTF-8, and non-protocol messages', () async {
    final primary = await _primary();
    addTearDown(primary.close);
    final messages = <String>[];
    final subscription = primary.incomingDeepLinks.listen(messages.add);
    addTearDown(subscription.cancel);
    await _send(primary, [
      ...List.filled(maxSingleInstanceMessageBytes + 1, 65),
      10,
    ]);
    await _send(primary, [0xff, 10]);
    await _send(primary, utf8.encode('https://example.test/not-a-deep-link\n'));
    final received = primary.incomingDeepLinks.first;
    await _send(primary, utf8.encode('flux://add/valid\n'));
    expect(
      await received.timeout(const Duration(seconds: 2)),
      'flux://add/valid',
    );
    expect(messages, ['flux://add/valid']);
  });

  test('a fixed deadline closes an incomplete message', () async {
    final primary = await _primary(timeout: const Duration(milliseconds: 50));
    addTearDown(primary.close);
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      primary.port,
    );
    final disconnected = Completer<void>();
    socket.listen(
      (_) {},
      onDone: disconnected.complete,
      onError: (Object _) => disconnected.complete(),
    );
    socket.write('flux://add/incomplete');
    await socket.flush();
    await disconnected.future.timeout(const Duration(seconds: 2));
    socket.destroy();
  });

  test('bounds live peers and releases the port on close', () async {
    final primary = await _primary();
    addTearDown(primary.close);
    final peers = <Socket>[];
    for (var i = 0; i < maxSingleInstanceConnections; i++) {
      peers.add(
        await Socket.connect(InternetAddress.loopbackIPv4, primary.port),
      );
    }
    final extra = await Socket.connect(
      InternetAddress.loopbackIPv4,
      primary.port,
    );
    final disconnected = Completer<void>();
    extra.listen(
      (_) {},
      onDone: disconnected.complete,
      onError: (Object _) => disconnected.complete(),
    );
    await disconnected.future.timeout(const Duration(seconds: 2));
    await primary.close();
    await primary.close();
    for (final peer in [...peers, extra]) {
      peer.destroy();
    }
    final next =
        await acquireSingleInstance(port: primary.port) as PrimaryInstance;
    await next.close();
  });
}
