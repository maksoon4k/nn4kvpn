import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core_abstraction/app_settings.dart';
import '../../core_abstraction/app_settings_provider.dart';
import '../../core_abstraction/connection_session.dart';
import '../../core_abstraction/proxy_node.dart';
import '../connection/connection_controller.dart';
import '../connection/connection_state.dart';
import 'ping_cache.dart';
import 'ping_service.dart';

/// Пинг во время активного TUN мешает соединению — режим `viaProxy` поднимает
/// свой временный xray-процесс, который конкурирует за сетевые ресурсы с уже
/// работающим TUN-мостом (xray+sing-box, см. `tun_bridge_engine.dart`); TCP/
/// ICMP-пинг тоже не запускаем в это время — не ради самого пинга, а чтобы
/// не создавать у пользователя впечатление, что в TUN-режиме измерение вообще
/// уместно (см. ROADMAP.md, трек 11).
bool isTunActive(WidgetRef ref) {
  final state = ref.read(connectionControllerProvider);
  return state is ConnectionConnected && state.mode == ConnectionMode.tun;
}

bool isPingAllowed(ConnectionUiState state) =>
    state is ConnectionIdle ||
    state is ConnectionError ||
    (state is ConnectionConnected && state.mode != ConnectionMode.tun);

final pingServiceProvider = Provider<PingService>((_) => pingService);

final serverPingQueueProvider = Provider<ServerPingQueue>((ref) {
  final queue = ServerPingQueue(
    service: ref.read(pingServiceProvider),
    settings: () => ref.read(appSettingsProvider),
    canPing: () {
      if (!ref.mounted) return false;
      final state = ref.read(connectionControllerProvider);
      return isPingAllowed(state);
    },
    onStart: (id) => ref.read(pingingLeafIdsProvider.notifier).start(id),
    onFinish: (id) => ref.read(pingingLeafIdsProvider.notifier).finish(id),
    onResult: (id, latency) =>
        ref.read(pingCacheProvider.notifier).setResult(id, latency),
  );
  ref.onDispose(queue.dispose);
  ref.listen(connectionControllerProvider, (previous, next) {
    if (previous != next) queue.invalidate();
  });
  return queue;
});

/// One queue for row, folder, startup and all-server requests. Different
/// folders must not start competing temporary proxy cores; repeated clicks
/// share the same job. No WidgetRef is retained across an await.
class ServerPingQueue {
  final PingService service;
  final AppSettings Function() settings;
  final bool Function() canPing;
  final void Function(String) onStart;
  final void Function(String) onFinish;
  final void Function(String, int) onResult;
  final _pending = <String, Future<void>>{};
  Future<void> _tail = Future.value();
  bool _disposed = false;
  int _generation = 0;

  ServerPingQueue({
    required this.service,
    required this.settings,
    required this.canPing,
    required this.onStart,
    required this.onFinish,
    required this.onResult,
  });

  Future<void> ping(ServerLeaf leaf) {
    final existing = _pending[leaf.id];
    if (existing != null) return existing;
    final config = leaf.activeVariant?.config;
    if (_disposed || !canPing() || config == null) return Future.value();
    final generation = _generation;
    onStart(leaf.id);
    final job = _tail.then((_) async {
      try {
        if (_disposed || generation != _generation || !canPing()) return;
        final selected = settings();
        final latency = await service.ping(
          config,
          mode: selected.pingMode,
          pingTestUrl: selected.pingTestUrl,
        );
        if (!_disposed &&
            generation == _generation &&
            canPing() &&
            latency != null) {
          onResult(leaf.id, latency);
        }
      } catch (_) {
        // A failed measurement or cache write must not strand the busy state
        // or prevent the remaining servers in this folder from being measured.
      } finally {
        _pending.remove(leaf.id);
        if (!_disposed) onFinish(leaf.id);
      }
    });
    _pending[leaf.id] = job;
    _tail = job.catchError((Object error) {});
    return job;
  }

  /// Discard measurements spanning a connection change, even if that change
  /// already ended before the outstanding service call returns.
  void invalidate() => _generation++;

  void dispose() {
    _disposed = true;
    invalidate();
  }
}

/// Пингует один сервер и, при успехе, сохраняет результат в кэш — общая
/// логика для кнопки "Пинг" на строке сервера, "Пинг всех" и автопинга при
/// запуске (см. ROADMAP.md, трек 4). Тихий no-op при активном TUN — вызывающая
/// UI-сторона (`server_row.dart`, `server_list_panel.dart`) сама показывает
/// тост при явном клике, здесь только защита от самого запуска.
Future<void> pingLeaf(WidgetRef ref, ServerLeaf leaf) async {
  await ref.read(serverPingQueueProvider).ping(leaf);
}

/// Пингует список серверов последовательно — параллельный запуск N
/// временных xray-процессов разом (один на сервер, см. `ping_service.dart`)
/// неоправданно грузит систему при большом списке серверов.
Future<void> pingAllLeaves(WidgetRef ref, List<ServerLeaf> leaves) async {
  final queue = ref.read(serverPingQueueProvider);
  await Future.wait(leaves.map(queue.ping));
}
