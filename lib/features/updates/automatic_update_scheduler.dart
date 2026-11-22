import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core_abstraction/app_settings.dart';
import '../../core_abstraction/app_settings_provider.dart';
import '../connection/connection_controller.dart';
import '../connection/connection_state.dart';
import 'app_update_controller.dart';

/// Checks on startup and every six hours. Silent installation is opt-in and
/// deferred while a VPN connection is active, starting or stopping.
class AutomaticUpdateScheduler {
  final ProviderContainer container;
  Timer? _initial;
  Timer? _periodic;
  ProviderSubscription<AppSettings>? _settings;
  ProviderSubscription<ConnectionUiState>? _connection;
  bool _busy = false;
  bool _disposed = false;

  AutomaticUpdateScheduler(this.container);

  void start() {
    if (_disposed || _periodic != null) return;
    _initial = Timer(const Duration(seconds: 10), () => unawaited(_tick()));
    _periodic = Timer.periodic(
      const Duration(hours: 6),
      (_) => unawaited(_tick()),
    );
    _settings = container.listen(appSettingsProvider, (previous, next) {
      if (previous?.updateRepository != next.updateRepository ||
          previous?.checkForUpdatesOnStartup != next.checkForUpdatesOnStartup ||
          previous?.autoInstallUpdates != next.autoInstallUpdates) {
        _initial?.cancel();
        _initial = Timer(const Duration(seconds: 1), () => unawaited(_tick()));
      }
    });
    _connection = container.listen(connectionControllerProvider, (_, next) {
      if (next is ConnectionIdle) unawaited(_installIfIdle());
    });
  }

  Future<void> _tick() async {
    if (_busy || _disposed) return;
    final settings = container.read(appSettingsProvider);
    if ((!settings.checkForUpdatesOnStartup && !settings.autoInstallUpdates) ||
        settings.updateRepository.isEmpty) {
      return;
    }
    _busy = true;
    try {
      final controller = container.read(appUpdateControllerProvider.notifier);
      await controller.check();
      if (_disposed ||
          !container.read(appSettingsProvider).autoInstallUpdates ||
          !const {
            AppUpdatePhase.available,
            AppUpdatePhase.ready,
          }.contains(container.read(appUpdateControllerProvider).phase)) {
        return;
      }
      await controller.download();
    } finally {
      _busy = false;
    }
    if (!_disposed) await _installIfIdle();
  }

  Future<void> _installIfIdle() async {
    if (_busy || _disposed) return;
    if (!container.read(appSettingsProvider).autoInstallUpdates ||
        container.read(connectionControllerProvider) is! ConnectionIdle ||
        container.read(appUpdateControllerProvider).phase !=
            AppUpdatePhase.ready) {
      return;
    }
    _busy = true;
    try {
      await container
          .read(appUpdateControllerProvider.notifier)
          .install(automatic: true);
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _disposed = true;
    _initial?.cancel();
    _periodic?.cancel();
    _settings?.close();
    _connection?.close();
  }
}
