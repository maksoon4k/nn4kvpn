import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/core_abstraction/app_settings.dart';
import 'package:flux/core_abstraction/connection_session.dart';
import 'package:flux/core_abstraction/proxy_node.dart';
import 'package:flux/core_abstraction/server_config.dart';
import 'package:flux/features/connection/connection_state.dart';
import 'package:flux/features/ping/ping_all.dart';
import 'package:flux/features/ping/ping_service.dart';

ServerLeaf fixture(String id) => ServerLeaf(
  id: id,
  name: id,
  variants: [
    ConnectionVariant(
      id: '$id-v',
      label: 'fixture',
      config: VlessConfig(address: '$id.invalid', port: 443, uuid: 'fixture'),
    ),
  ],
);

class PendingPingService extends PingService {
  final calls = <String>[];
  final answers = <Completer<int?>>[];
  final modes = <PingMode>[];
  final urls = <String>[];
  final started = StreamController<int>.broadcast(sync: true);
  @override
  Future<int?> ping(
    ServerConfig config, {
    required PingMode mode,
    required String pingTestUrl,
  }) {
    calls.add(config.address);
    modes.add(mode);
    urls.add(pingTestUrl);
    final answer = Completer<int?>();
    answers.add(answer);
    started.add(answers.length);
    return answer.future;
  }
}

void main() {
  test(
    'row/folder requests serialize globally and duplicate clicks share a job',
    () async {
      final service = PendingPingService();
      final busy = <String>{};
      final results = <String, int>{};
      final queue = ServerPingQueue(
        service: service,
        settings: () => const AppSettings(),
        canPing: () => true,
        onStart: busy.add,
        onFinish: busy.remove,
        onResult: (id, ms) => results[id] = ms,
      );
      final firstStarted = service.started.stream.first;
      final first = queue.ping(fixture('a'));
      final duplicate = queue.ping(fixture('a'));
      final second = queue.ping(fixture('b'));
      expect(identical(first, duplicate), true);
      expect(busy, {'a', 'b'});
      await firstStarted;
      expect(service.calls, ['a.invalid']);
      final secondStarted = service.started.stream.first;
      service.answers.first.complete(27);
      await secondStarted;
      expect(service.calls, ['a.invalid', 'b.invalid']);
      service.answers.last.complete(40);
      await Future.wait([first, duplicate, second]);
      expect(results, {'a': 27, 'b': 40});
      expect(busy, isEmpty);
      queue.dispose();
      await service.started.close();
    },
  );

  test(
    'VPN transition stops queued measurements and discards an obsolete result',
    () async {
      final service = PendingPingService();
      var allowed = true;
      final busy = <String>{};
      var results = 0;
      final queue = ServerPingQueue(
        service: service,
        settings: () => const AppSettings(),
        canPing: () => allowed,
        onStart: busy.add,
        onFinish: busy.remove,
        onResult: (_, _) => results++,
      );
      final started = service.started.stream.first;
      final first = queue.ping(fixture('a'));
      final second = queue.ping(fixture('b'));
      await started;
      allowed = false;
      service.answers.first.complete(20);
      await Future.wait([first, second]);
      expect(service.calls, ['a.invalid']);
      expect(results, 0);
      expect(busy, isEmpty);
      await queue.ping(fixture('c'));
      expect(service.calls.length, 1);
      queue.dispose();
      await service.started.close();
    },
  );

  test('service errors clear busy state and do not poison the queue', () async {
    final service = PendingPingService();
    final busy = <String>{};
    final queue = ServerPingQueue(
      service: service,
      settings: () => const AppSettings(),
      canPing: () => true,
      onStart: busy.add,
      onFinish: busy.remove,
      onResult: (_, _) {},
    );
    final started = service.started.stream.first;
    final first = queue.ping(fixture('a'));
    final second = queue.ping(fixture('b'));
    await started;
    final nextStarted = service.started.stream.first;
    service.answers.first.completeError(StateError('fixture failure'));
    await nextStarted;
    service.answers.last.complete(null);
    await Future.wait([first, second]);
    expect(service.calls.length, 2);
    expect(busy, isEmpty);
    queue.dispose();
    await service.started.close();
  });

  test(
    'a completed connection transition invalidates old results and queued scope even after ping is allowed again',
    () async {
      final service = PendingPingService();
      final busy = <String>{};
      final results = <String, int>{};
      final queue = ServerPingQueue(
        service: service,
        settings: () => const AppSettings(),
        canPing: () => true,
        onStart: busy.add,
        onFinish: busy.remove,
        onResult: (id, ms) => results[id] = ms,
      );
      final started = service.started.stream.first;
      final first = queue.ping(fixture('a'));
      final queued = queue.ping(fixture('b'));
      await started;
      queue.invalidate();
      service.answers.first.complete(20);
      await Future.wait([first, queued]);
      expect(service.calls, ['a.invalid']);
      expect(results, isEmpty);
      expect(busy, isEmpty);
      final nextStarted = service.started.stream.first;
      final retried = queue.ping(fixture('b'));
      await nextStarted;
      service.answers.last.complete(35);
      await retried;
      expect(results, {'b': 35});
      queue.dispose();
      await service.started.close();
    },
  );

  test(
    'disposing with pending results never invokes callbacks or starts another measurement',
    () async {
      final service = PendingPingService();
      var finished = 0;
      var results = 0;
      final queue = ServerPingQueue(
        service: service,
        settings: () => const AppSettings(),
        canPing: () => true,
        onStart: (_) {},
        onFinish: (_) => finished++,
        onResult: (_, _) => results++,
      );
      final started = service.started.stream.first;
      final first = queue.ping(fixture('a'));
      final second = queue.ping(fixture('b'));
      await started;
      queue.dispose();
      service.answers.first.complete(10);
      await Future.wait([first, second]);
      await queue.ping(fixture('c'));
      expect(service.calls, ['a.invalid']);
      expect(results, 0);
      expect(finished, 0);
      await service.started.close();
    },
  );

  test(
    'missing configurations do not become busy, and each job uses settings at its own start',
    () async {
      final service = PendingPingService();
      final busy = <String>{};
      var settings = const AppSettings(
        pingMode: PingMode.tcp,
        pingTestUrl: 'https://first.invalid/',
      );
      final queue = ServerPingQueue(
        service: service,
        settings: () => settings,
        canPing: () => true,
        onStart: busy.add,
        onFinish: busy.remove,
        onResult: (_, _) {},
      );
      await queue.ping(
        const ServerLeaf(id: 'empty', name: 'Empty', variants: []),
      );
      expect(busy, isEmpty);
      expect(service.calls, isEmpty);
      final started = service.started.stream.first;
      final first = queue.ping(fixture('a'));
      final second = queue.ping(fixture('b'));
      await started;
      settings = settings.copyWith(
        pingMode: PingMode.viaProxy,
        pingTestUrl: 'https://second.invalid/',
      );
      final nextStarted = service.started.stream.first;
      service.answers.first.complete(null);
      await nextStarted;
      service.answers.last.complete(null);
      await Future.wait([first, second]);
      expect(service.modes, [PingMode.tcp, PingMode.viaProxy]);
      expect(service.urls, [
        'https://first.invalid/',
        'https://second.invalid/',
      ]);
      expect(busy, isEmpty);
      queue.dispose();
      await service.started.close();
    },
  );

  test(
    'cache failure cannot poison a later server job or strand its busy marker',
    () async {
      final service = PendingPingService();
      final busy = <String>{};
      var cached = 0;
      final queue = ServerPingQueue(
        service: service,
        settings: () => const AppSettings(),
        canPing: () => true,
        onStart: busy.add,
        onFinish: busy.remove,
        onResult: (_, _) {
          cached++;
          if (cached == 1) throw StateError('Fixture cache write failure');
        },
      );
      final started = service.started.stream.first;
      final first = queue.ping(fixture('a'));
      final second = queue.ping(fixture('b'));
      await started;
      final nextStarted = service.started.stream.first;
      service.answers.first.complete(10);
      await nextStarted;
      service.answers.last.complete(20);
      await Future.wait([first, second]);
      expect(cached, 2);
      expect(busy, isEmpty);
      queue.dispose();
      await service.started.close();
    },
  );

  test(
    'busy transitions and active TUN are disallowed; idle/error/Proxy remain eligible',
    () {
      expect(isPingAllowed(const ConnectionIdle()), true);
      expect(isPingAllowed(const ConnectionError('fixture')), true);
      expect(isPingAllowed(const ConnectionConnecting()), false);
      expect(isPingAllowed(const ConnectionStopping()), false);
      for (final mode in ConnectionMode.values) {
        expect(
          isPingAllowed(
            ConnectionConnected(
              leafId: 'a',
              variantId: 'v',
              serverName: 'Fixture',
              connectedAt: DateTime(2026),
              mode: mode,
            ),
          ),
          mode != ConnectionMode.tun,
        );
      }
    },
  );
}
