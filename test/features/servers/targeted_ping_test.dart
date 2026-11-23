import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/core_abstraction/app_settings.dart';
import 'package:flux/core_abstraction/app_settings_provider.dart';
import 'package:flux/core_abstraction/connection_session.dart';
import 'package:flux/core_abstraction/core_config.dart';
import 'package:flux/core_abstraction/core_config_provider.dart';
import 'package:flux/core_abstraction/proxy_node.dart';
import 'package:flux/core_abstraction/subscription.dart';
import 'package:flux/features/connection/connection_controller.dart';
import 'package:flux/features/connection/connection_state.dart';
import 'package:flux/features/ping/ping_all.dart';
import 'package:flux/features/ping/ping_cache.dart';
import 'package:flux/features/servers/proxy_tree_list.dart';
import 'package:flux/features/servers/selected_server_provider.dart';
import 'package:flux/features/servers/server_list_panel.dart';
import 'package:flux/features/servers/server_row.dart';
import 'package:flux/features/servers/subscription_info_panel.dart';
import 'package:flux/widgets/port_ui/port_ui.dart';

import '../ping/server_ping_queue_test.dart' show PendingPingService, fixture;
import '../updates/app_update_controller_test.dart'
    show FakeConnection, MemorySettings;

const leaf = ServerLeaf(id: 'one', name: 'One fixture', variants: []);
const second = ServerLeaf(id: 'two', name: 'Two fixture', variants: []);

void main() {
  testWidgets('standalone server right-click offers ping without select/hide', (
    tester,
  ) async {
    var pings = 0;
    var selections = 0;
    await tester.pumpWidget(
      PortApp(
        home: Center(
          child: SizedBox(
            width: 300,
            child: ServerRow(
              leaf: leaf,
              depth: 0,
              selected: false,
              expanded: false,
              onSelect: () => selections++,
              onToggleExpand: () {},
              onPing: () => pings++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(
      find.text(leaf.name),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Пинг сервера'), findsOneWidget);
    await tester.tap(find.text('Пинг сервера'));
    await tester.pumpAndSettle();
    expect(pings, 1);
    expect(selections, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('folder button pings only its nested leaves without expanding', (
    tester,
  ) async {
    List<ServerLeaf>? requested;
    await tester.pumpWidget(
      ProviderScope(
        child: PortApp(
          home: Center(
            child: SizedBox(
              width: 320,
              child: ProxyTreeList(
                nodes: const [
                  ServerGroup(
                    id: 'folder',
                    name: 'Folder fixture',
                    children: [
                      leaf,
                      ServerGroup(
                        id: 'nested',
                        name: 'Nested',
                        children: [
                          second,
                          AutoSelectMarker(id: 'auto'),
                        ],
                      ),
                    ],
                  ),
                  ServerLeaf(id: 'outside', name: 'Outside', variants: []),
                ],
                selectedLeafId: null,
                onSelectLeaf: (_) {},
                onSelectVariant: (_, _) {},
                onPingGroup: (leaves) => requested = leaves,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('ping-group-folder')));
    await tester.pumpAndSettle();
    expect(requested?.map((l) => l.id), ['one', 'two']);
    expect(
      find.text('One fixture'),
      findsNothing,
    ); // Ping did not expand/select.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group(
    'the full panel delegates to the shared queue without real probes or profile access',
    () {
      late ProviderContainer container;
      late PendingPingService service;
      late FakeConnection connection;
      late CoreConfig config;

      setUp(() {
        service = PendingPingService();
        connection = FakeConnection([]);
        config = CoreConfig(
          standaloneNodes: [
            ServerGroup(
              id: 'standalone-folder',
              name: 'Standalone folder',
              children: [
                fixture('standalone-a'),
                ServerGroup(
                  id: 'nested-folder',
                  name: 'Nested folder',
                  children: [
                    fixture('standalone-b'),
                    const AutoSelectMarker(id: 'auto-nested'),
                  ],
                ),
              ],
            ),
            fixture('outside'),
          ],
          subscriptions: [
            Subscription(
              id: 'sub-one',
              name: 'First subscription',
              url: 'https://first.invalid/',
              root: ServerGroup(
                id: 'sub-root',
                name: 'Root',
                children: [
                  ServerGroup(
                    id: 'sub-folder',
                    name: 'Subscription folder',
                    children: [fixture('sub-a'), fixture('sub-b')],
                  ),
                  fixture('sub-outside'),
                ],
              ),
            ),
            Subscription(
              id: 'sub-two',
              name: 'Other subscription',
              url: 'https://other.invalid/',
              root: fixture('other-sub'),
            ),
          ],
        );
        container = ProviderContainer(
          overrides: [
            appSettingsProvider.overrideWith(
              () => MemorySettings(
                const AppSettings(lastSelectedServerId: 'outside'),
              ),
            ),
            coreConfigProvider.overrideWith(() => FixturePanelConfig(config)),
            connectionControllerProvider.overrideWith(() => connection),
            connectionEngineFactoryProvider.overrideWithValue(
              (id, mode, settings) => throw StateError(
                'A targeted ping must never select or start a real connection',
              ),
            ),
            pingServiceProvider.overrideWithValue(service),
            pingCacheProvider.overrideWith(FixturePingCache.new),
          ],
        );
        // An overridden notifier is initialized on first read; setState before
        // that would fail in the tests that begin in a blocked state.
        container.read(connectionControllerProvider);
      });

      tearDown(() async {
        container.dispose();
        await service.started.close();
      });

      Future<void> host(WidgetTester tester) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const PortApp(
              home: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 340,
                  height: 560,
                  child: ServerListContent(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> tap(WidgetTester tester, String key) async {
        final finder = find.byKey(ValueKey(key));
        await tester.ensureVisible(finder);
        await tester.tap(finder, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
      }

      Future<void> answerScope(WidgetTester tester, List<String> ids) async {
        expect(container.read(pingingLeafIdsProvider), ids.toSet());
        for (var i = 0; i < ids.length; i++) {
          expect(service.calls, [
            for (final id in ids.take(i + 1)) '$id.invalid',
          ]);
          service.answers[i].complete(20 + i);
          await tester.pumpAndSettle();
        }
        expect(container.read(pingingLeafIdsProvider), isEmpty);
        expect(container.read(pingCacheProvider).keys, ids);
        expect(container.read(selectedServerIdProvider), 'outside');
        expect(identical(container.read(coreConfigProvider), config), true);
        expect(find.byType(SubscriptionInfoPanel), findsNothing);
        expect(find.byType(PortDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }

      testWidgets(
        'standalone folder measures only nested leaves and locks only its own busy button',
        (tester) async {
          await host(tester);
          await tap(tester, 'ping-group-standalone-folder');
          expect(
            tester
                .widget<PortIconButton>(
                  find.byKey(const ValueKey('ping-group-standalone-folder')),
                )
                .onPressed,
            isNull,
          );
          expect(
            tester
                .widget<PortIconButton>(
                  find.byKey(const ValueKey('ping-subscription-sub-one')),
                )
                .onPressed,
            isNotNull,
          );
          expect(find.text('standalone-a'), findsNothing);
          await answerScope(tester, ['standalone-a', 'standalone-b']);
        },
      );

      testWidgets(
        'subscription header measures its own tree without opening subscription information',
        (tester) async {
          await host(tester);
          await tap(tester, 'ping-subscription-sub-one');
          await answerScope(tester, ['sub-a', 'sub-b', 'sub-outside']);
        },
      );

      testWidgets(
        'a subscription folder excludes siblings and other subscriptions',
        (tester) async {
          await host(tester);
          await tap(tester, 'ping-group-sub-folder');
          await answerScope(tester, ['sub-a', 'sub-b']);
        },
      );

      testWidgets(
        'a subscription server context menu measures only that server, not a selection or hide action',
        (tester) async {
          await host(tester);
          await tester.ensureVisible(find.text('other-sub'));
          await tester.tap(
            find.text('other-sub'),
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await tester.pumpAndSettle();
          expect(find.text('Пинг сервера'), findsOneWidget);
          await tester.tap(find.text('Пинг сервера'));
          await tester.pumpAndSettle();
          await answerScope(tester, ['other-sub']);
        },
      );

      testWidgets(
        'the global button retains the complete scope while using the same serialized queue',
        (tester) async {
          await host(tester);
          await tap(tester, 'ping-all-servers');
          await answerScope(tester, [
            'standalone-a',
            'standalone-b',
            'outside',
            'sub-a',
            'sub-b',
            'sub-outside',
            'other-sub',
          ]);
        },
      );

      testWidgets(
        'even an already-finished connection transition invalidates an outstanding folder measurement',
        (tester) async {
          await host(tester);
          await tap(tester, 'ping-group-standalone-folder');
          connection.setState(const ConnectionConnecting());
          connection.setState(const ConnectionIdle());
          service.answers.single.complete(30);
          await tester.pumpAndSettle();
          expect(service.calls, ['standalone-a.invalid']);
          expect(container.read(pingCacheProvider), isEmpty);
          expect(container.read(pingingLeafIdsProvider), isEmpty);
          await tap(tester, 'ping-subscription-sub-two');
          expect(service.calls, ['standalone-a.invalid', 'other-sub.invalid']);
          service.answers.last.complete(40);
          await tester.pumpAndSettle();
          expect(container.read(pingCacheProvider).keys, ['other-sub']);
          expect(container.read(selectedServerIdProvider), 'outside');
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );

      for (final blocked in <ConnectionUiState>[
        const ConnectionConnecting(),
        const ConnectionStopping(),
        ConnectionConnected(
          leafId: 'outside',
          variantId: 'outside-v',
          serverName: 'Fixture',
          connectedAt: DateTime(2026),
          mode: ConnectionMode.tun,
        ),
      ]) {
        testWidgets(
          '${blocked.runtimeType} cannot launch server/folder/subscription/global measurements',
          (tester) async {
            await host(tester);
            connection.setState(blocked);
            await tap(tester, 'ping-group-standalone-folder');
            await tap(tester, 'ping-subscription-sub-one');
            await tap(tester, 'ping-all-servers');
            await tester.tap(
              find.text('outside'),
              kind: PointerDeviceKind.mouse,
              buttons: kSecondaryMouseButton,
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Пинг сервера'));
            await tester.pumpAndSettle();
            expect(service.calls, isEmpty);
            expect(container.read(pingingLeafIdsProvider), isEmpty);
            expect(container.read(pingCacheProvider), isEmpty);
            expect(container.read(selectedServerIdProvider), 'outside');
            await tester.pump(const Duration(seconds: 5));
            await tester.pumpWidget(const SizedBox.shrink());
            expect(tester.takeException(), isNull);
          },
        );
      }
    },
  );
}

class FixturePanelConfig extends CoreConfigController {
  final CoreConfig initial;
  FixturePanelConfig(this.initial);
  @override
  CoreConfig build() => initial;
}

class FixturePingCache extends PingCacheController {
  @override
  Map<String, PingCacheEntry> build() => {};
  @override
  void setResult(String id, int latencyMs) => state = {
    ...state,
    id: PingCacheEntry(latencyMs: latencyMs, measuredAt: DateTime(2026)),
  };
}
