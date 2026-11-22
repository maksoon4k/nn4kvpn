import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/core_abstraction/app_settings.dart';
import 'package:flux/core_abstraction/app_settings_provider.dart';
import 'package:flux/core_abstraction/core_config.dart';
import 'package:flux/core_abstraction/core_config_provider.dart';
import 'package:flux/core_abstraction/core_engine.dart';
import 'package:flux/core_abstraction/engine_manager_provider.dart';
import 'package:flux/core_abstraction/proxy_node.dart';
import 'package:flux/core_abstraction/server_config.dart';
import 'package:flux/features/connection/connection_controller.dart';
import 'package:flux/features/connection/connection_state.dart';

import '../updates/app_update_controller_test.dart' show MemorySettings;

const leaf = ServerLeaf(
  id: 'one',
  name: 'Fixture one',
  variants: [
    ConnectionVariant(
      id: 'variant',
      label: 'Fixture',
      config: VlessConfig(
        address: 'fixture.invalid',
        port: 443,
        uuid: 'fixture',
      ),
    ),
  ],
);
final secondLeaf = ServerLeaf(
  id: 'two',
  name: 'Fixture two',
  variants: leaf.variants,
);
final thirdLeaf = ServerLeaf(
  id: 'three',
  name: 'Fixture three',
  variants: leaf.variants,
);

void main() {
  late ProviderContainer container;
  late List<MemoryEngine> engines;
  late List<String> events;
  late Completer<MemoryEngine> engineCreated;
  Completer<void>? nextStartHold;
  var nextStartFails = false;

  setUp(() {
    engines = [];
    events = [];
    engineCreated = Completer<MemoryEngine>();
    nextStartHold = null;
    nextStartFails = false;
    container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWith(
          () => MemorySettings(const AppSettings()),
        ),
        coreConfigProvider.overrideWith(MemoryCoreConfig.new),
        connectionEngineFactoryProvider.overrideWithValue((id, mode, settings) {
          final engine = MemoryEngine(id, engines.length + 1, events)
            ..startHold = nextStartHold?.future
            ..startFails = nextStartFails;
          nextStartHold = null;
          nextStartFails = false;
          engines.add(engine);
          if (!engineCreated.isCompleted) engineCreated.complete(engine);
          return engine;
        }),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    for (final engine in engines) {
      await engine.statuses.close();
    }
  });

  ConnectionController controller() =>
      container.read(connectionControllerProvider.notifier);
  ConnectionUiState state() => container.read(connectionControllerProvider);

  test('disconnect waits for an in-flight start and stops it once', () async {
    final hold = Completer<void>();
    nextStartHold = hold;
    final connecting = controller().connectToServer(leaf);
    await engineCreated.future;
    await engines.first.startCalled.future;
    final disconnecting = controller().disconnect();
    expect(state(), isA<ConnectionStopping>());
    expect(events, ['start:1']);
    hold.complete();
    await Future.wait([connecting, disconnecting]);
    expect(events, ['start:1', 'stop:1']);
    expect(state(), isA<ConnectionIdle>());
    expect(container.read(engineManagerProvider).activeEngines, isEmpty);
  });

  test(
    'update shutdown waits for a pending start and blocks reconnects',
    () async {
      final hold = Completer<void>();
      nextStartHold = hold;
      final connecting = controller().connectToServer(leaf);
      await engineCreated.future;
      await engines.first.startCalled.future;
      final closing = controller().prepareForExit();
      await controller().connectToServer(secondLeaf);
      expect(engines.length, 1);
      expect(events, ['start:1']);
      hold.complete();
      await Future.wait([connecting, closing]);
      expect(events, ['start:1', 'stop:1']);
      expect(state(), isA<ConnectionIdle>());
      await controller().connectToServer(secondLeaf);
      expect(engines.length, 1); // Locked until installation fails/cancels.
      controller().cancelExit();
      await controller().connectToServer(secondLeaf);
      expect(engines.length, 2);
      await controller().prepareForExit();
    },
  );

  test(
    'only the newest server switch can start after the previous start completes',
    () async {
      final hold = Completer<void>();
      nextStartHold = hold;
      final first = controller().connectToServer(leaf);
      await engineCreated.future;
      await engines.first.startCalled.future;
      final second = controller().connectToServer(secondLeaf);
      final third = controller().connectToServer(thirdLeaf);
      hold.complete();
      await Future.wait([first, second, third]);
      expect(engines.length, 2);
      expect(events, ['start:1', 'stop:1', 'start:2']);
      expect((state() as ConnectionConnected).leafId, thirdLeaf.id);
      await controller().prepareForExit();
    },
  );

  test('overlapping disconnect and exit share one in-flight stop', () async {
    await controller().connectToServer(leaf);
    final hold = Completer<void>();
    engines.first.stopHold = hold.future;
    final disconnecting = controller().disconnect();
    await engines.first.stopCalled.future;
    final closing = controller().prepareForExit();
    await controller().connectToServer(secondLeaf);
    expect(engines.first.stopCount, 1);
    expect(engines.length, 1);
    expect(state(), isA<ConnectionStopping>());
    hold.complete();
    await Future.wait([disconnecting, closing]);
    expect(engines.first.stopCount, 1);
    expect(state(), isA<ConnectionIdle>());
  });

  test(
    'a partial start failure is cleaned up without hiding the error',
    () async {
      nextStartFails = true;
      await controller().connectToServer(leaf);
      expect(events, ['start:1', 'stop:1']);
      expect(state(), isA<ConnectionError>());
      expect(container.read(engineManagerProvider).activeEngines, isEmpty);
    },
  );

  test(
    'failed shutdown keeps the engine reachable and allows a cleanup retry',
    () async {
      await controller().connectToServer(leaf);
      engines.first.stopFailures = 1;
      await expectLater(controller().prepareForExit(), throwsStateError);
      expect(container.read(engineManagerProvider).activeEngines.length, 1);
      expect(state(), isA<ConnectionError>());
      await controller().connectToServer(secondLeaf);
      expect(engines.length, 2);
      expect(engines.first.stopCount, 2);
      await controller().prepareForExit();
    },
  );
}

class MemoryCoreConfig extends CoreConfigController {
  @override
  CoreConfig build() => const CoreConfig();
}

/// Pure in-memory lifecycle. It never spawns a process, opens a VPN socket,
/// writes registry values, or requests administrator/TUN privileges.
class MemoryEngine implements CoreEngine {
  @override
  final String id;
  final int index;
  final List<String> events;
  final statuses = StreamController<EngineStatus>.broadcast(sync: true);
  final startCalled = Completer<void>();
  final stopCalled = Completer<void>();
  Future<void>? startHold;
  Future<void>? stopHold;
  bool startFails = false;
  int stopFailures = 0;
  int stopCount = 0;

  MemoryEngine(this.id, this.index, this.events);
  @override
  CoreType get type => CoreType.xray;
  @override
  Stream<EngineStatus> get statusStream => statuses.stream;
  @override
  Stream<EngineStats> get statsStream => const Stream.empty();
  @override
  Future<EngineStats> currentStats() async =>
      const EngineStats(uploadBytes: 0, downloadBytes: 0);
  @override
  Future<void> start(
    CoreConfig config, {
    String defaultOutboundTag = 'proxy',
    String routingLabel = 'server-routing',
  }) async {
    events.add('start:$index');
    startCalled.complete();
    statuses.add(EngineStatus.starting);
    if (startFails) throw StateError('Injected start failure');
    await startHold;
    statuses.add(EngineStatus.connected);
  }

  @override
  Future<void> stop() async {
    events.add('stop:$index');
    stopCount++;
    if (!stopCalled.isCompleted) stopCalled.complete();
    if (stopFailures > 0) {
      stopFailures--;
      throw StateError('Injected stop failure');
    }
    statuses.add(EngineStatus.stopping);
    await stopHold;
    statuses.add(EngineStatus.stopped);
  }
}
