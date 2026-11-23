import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/app/safe_app_exit.dart';
import 'package:flux/core_abstraction/app_settings.dart';
import 'package:flux/core_abstraction/app_settings_provider.dart';
import 'package:flux/core_abstraction/connection_session.dart';
import 'package:flux/core_abstraction/core_config.dart';
import 'package:flux/core_abstraction/core_config_provider.dart';
import 'package:flux/core_abstraction/engine_manager_provider.dart';
import 'package:flux/core_abstraction/tun_application_routing.dart';
import 'package:flux/features/connection/connection_controller.dart';
import 'package:flux/features/connection/connection_state.dart';

import 'connection_controller_test.dart' show MemoryEngine, leaf, secondLeaf;
import '../updates/app_update_controller_test.dart' show MemorySettings;

class RoutingFixtureCoreConfig extends CoreConfigController {
  @override
  CoreConfig build() => CoreConfig(standaloneNodes: [leaf, secondLeaf]);
}

class RoutingMemoryEngine extends MemoryEngine {
  final finishedStart = Completer<void>();
  RoutingMemoryEngine(super.id, super.index, super.events);
  @override
  Future<void> start(
    CoreConfig config, {
    String defaultOutboundTag = 'proxy',
    String routingLabel = 'server-routing',
  }) async {
    try {
      await super.start(
        config,
        defaultOutboundTag: defaultOutboundTag,
        routingLabel: routingLabel,
      );
    } finally {
      finishedStart.complete();
    }
  }
}

TunApplicationRouting fixturePolicy(String name) =>
    TunApplicationRouting.fromJson({
      'enabled': true,
      'mode': 'whitelist',
      'rules': [
        {'processName': '$name.exe', 'action': 'proxy'},
      ],
    });

void main() {
  late ProviderContainer container;
  late List<RoutingMemoryEngine> engines;
  late List<AppSettings> capturedSettings;
  late List<ConnectionMode> capturedModes;
  late List<String> events;
  late Map<int, Completer<RoutingMemoryEngine>> created;
  Future<void>? nextStartHold;
  setUp(() {
    engines = [];
    capturedSettings = [];
    capturedModes = [];
    events = [];
    created = {};
    nextStartHold = null;
    container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWith(
          () => MemorySettings(const AppSettings()),
        ),
        coreConfigProvider.overrideWith(RoutingFixtureCoreConfig.new),
        closeAppWindowProvider.overrideWithValue(() async {
          events.add('close-window');
        }),
        connectionEngineFactoryProvider.overrideWithValue((id, mode, settings) {
          final engine = RoutingMemoryEngine(id, engines.length + 1, events)
            ..startHold = nextStartHold;
          nextStartHold = null;
          engines.add(engine);
          capturedSettings.add(settings);
          capturedModes.add(mode);
          (created[engines.length] ??= Completer<RoutingMemoryEngine>())
              .complete(engine);
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
  void updatePolicy(TunApplicationRouting policy) => container
      .read(appSettingsProvider.notifier)
      .update((settings) => settings.copyWith(tunApplicationRouting: policy));
  Future<RoutingMemoryEngine> waitForEngine(int number) async {
    final engine =
        await (created[number] ??= Completer<RoutingMemoryEngine>()).future;
    await engine.finishedStart.future;
    await container.pump();
    return engine;
  }

  test(
    'persisted Windows TUN application edits reconnect exactly once with the latest settings',
    () async {
      final first = fixturePolicy('browser');
      updatePolicy(first);
      expect(engines, isEmpty);
      await controller().connectToServer(leaf, mode: ConnectionMode.tun);
      expect(capturedSettings.single.tunApplicationRouting, first);
      final second = fixturePolicy('player');
      updatePolicy(second);
      await waitForEngine(2);
      expect(events, ['start:1', 'stop:1', 'start:2']);
      expect(capturedSettings.last.tunApplicationRouting, second);
      expect(capturedModes, [ConnectionMode.tun, ConnectionMode.tun]);
      expect(
        (container.read(connectionControllerProvider) as ConnectionConnected)
            .mode,
        ConnectionMode.tun,
      );
      updatePolicy(TunApplicationRouting.fromJson(second.toJson()));
      container
          .read(appSettingsProvider.notifier)
          .update((settings) => settings.copyWith(language: AppLanguage.en));
      await container.pump();
      expect(engines.length, 2);
      await controller().prepareForExit();
    },
    skip: !Platform.isWindows,
  );

  test(
    'application edits do not restart Proxy connections or start idle connections',
    () async {
      updatePolicy(fixturePolicy('browser'));
      expect(engines, isEmpty);
      await controller().connectToServer(leaf);
      updatePolicy(fixturePolicy('player'));
      await container.pump();
      expect(engines.length, 1);
      expect(capturedModes, [ConnectionMode.proxy]);
      await controller().prepareForExit();
    },
  );

  test(
    'edits arriving during TUN startup are reconciled after startup, not lost',
    () async {
      final hold = Completer<void>();
      nextStartHold = hold.future;
      updatePolicy(fixturePolicy('old'));
      final connecting = controller().connectToServer(
        leaf,
        mode: ConnectionMode.tun,
      );
      final first =
          await (created[1] ??= Completer<RoutingMemoryEngine>()).future;
      await first.startCalled.future;
      final latest = fixturePolicy('latest');
      updatePolicy(latest);
      expect(engines.length, 1);
      hold.complete();
      await connecting;
      await waitForEngine(2);
      expect(capturedSettings.last.tunApplicationRouting, latest);
      expect(events, ['start:1', 'stop:1', 'start:2']);
      await controller().prepareForExit();
    },
    skip: !Platform.isWindows,
  );

  test(
    'multiple edits during the serialized reconnect stop are coalesced into the newest policy',
    () async {
      await controller().connectToServer(leaf, mode: ConnectionMode.tun);
      final stopHold = Completer<void>();
      engines.single.stopHold = stopHold.future;
      updatePolicy(fixturePolicy('middle'));
      await engines.single.stopCalled.future;
      final latest = fixturePolicy('latest');
      updatePolicy(latest);
      stopHold.complete();
      await waitForEngine(2);
      expect(engines.length, 2);
      expect(capturedSettings.last.tunApplicationRouting, latest);
      await controller().prepareForExit();
    },
    skip: !Platform.isWindows,
  );

  test(
    'exit during startup cancels routing reconciliation and closes only after the fake engine stops',
    () async {
      final hold = Completer<void>();
      nextStartHold = hold.future;
      final connecting = controller().connectToServer(
        leaf,
        mode: ConnectionMode.tun,
      );
      final first =
          await (created[1] ??= Completer<RoutingMemoryEngine>()).future;
      await first.startCalled.future;
      final exiting = container.read(safeAppExitProvider).exit();
      updatePolicy(fixturePolicy('new'));
      expect(events, ['start:1']);
      hold.complete();
      await Future.wait([connecting, exiting]);
      expect(events, ['start:1', 'stop:1', 'close-window']);
      expect(engines.length, 1);
      expect(container.read(engineManagerProvider).activeEngines, isEmpty);
      await controller().connectToServer(secondLeaf);
      expect(engines.length, 1);
    },
  );

  test(
    'failed safe exit never closes a window and a cleanup retry can succeed',
    () async {
      await controller().connectToServer(leaf, mode: ConnectionMode.tun);
      engines.single.stopFailures = 1;
      await expectLater(
        container.read(safeAppExitProvider).exit(),
        throwsStateError,
      );
      expect(events, ['start:1', 'stop:1']);
      expect(container.read(engineManagerProvider).activeEngines.length, 1);
      await container.read(safeAppExitProvider).exit();
      expect(events, ['start:1', 'stop:1', 'stop:1', 'close-window']);
    },
  );
}
