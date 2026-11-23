import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core_abstraction/app_settings.dart';
import '../../core_abstraction/app_settings_provider.dart';
import '../connection/connection_controller.dart';
import '../connection/connection_state.dart';
import 'github_release.dart';
import 'github_update_service.dart';
import 'windows_update_installer.dart';

enum AppUpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  ready,
  installing,
  error,
}

class AppUpdateState {
  final AppUpdatePhase phase;
  final GitHubRelease? release;
  final UpdateFailure? failure;
  final double progress;
  final bool hasDownloaded;

  const AppUpdateState({
    this.phase = AppUpdatePhase.idle,
    this.release,
    this.failure,
    this.progress = 0,
    this.hasDownloaded = false,
  });

  bool get busy => const {
    AppUpdatePhase.checking,
    AppUpdatePhase.downloading,
    AppUpdatePhase.installing,
  }.contains(phase);
}

/// No UI configuration, saved credential or imported JSON can change this
/// executable publisher. Public metadata/assets are fetched anonymously.
final updateRepositoryProvider = Provider<GitHubRepository>(
  (_) => GitHubRepository.parse(defaultUpdateRepository),
);

final githubUpdateServiceProvider = Provider<GitHubUpdateService>((ref) {
  final service = GitHubUpdateService();
  ref.onDispose(service.close);
  return service;
});

final updateInstallerProvider = Provider<UpdateInstaller>(
  (ref) => WindowsUpdateInstaller(ref.read(githubUpdateServiceProvider)),
);

final updateCurrentVersionProvider = FutureProvider<String>(
  (_) async => (await PackageInfo.fromPlatform()).version,
);

final updateExitAppProvider = Provider<void Function()>(
  (_) =>
      () => exit(0),
);

final updateDownloadDirectoryProvider = Provider<Directory>((_) {
  final root =
      Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
  return Directory('$root/NN4K/updates');
});

final appUpdateControllerProvider =
    NotifierProvider<AppUpdateController, AppUpdateState>(
      AppUpdateController.new,
    );

class AppUpdateController extends Notifier<AppUpdateState> {
  DownloadedUpdate? _downloaded;
  int _generation = 0;
  bool _disposed = false;

  @override
  AppUpdateState build() {
    ref.onDispose(() {
      _disposed = true;
      _generation++;
    });
    ref.listen(updateRepositoryProvider, (previous, next) {
      if (previous?.slug == next.slug) return;
      _generation++;
      _discardDownloaded();
      state = const AppUpdateState();
      ref
          .read(appSettingsProvider.notifier)
          .update((settings) => settings.copyWith(autoInstallUpdates: false));
    });
    return const AppUpdateState();
  }

  GitHubRepository get _repository => ref.read(updateRepositoryProvider);

  bool _current(int generation) {
    if (_disposed || generation != _generation) return false;
    // Provider dependencies may refresh lazily. Flush an internally invalidated
    // publisher before accepting an async result or authorizing Setup, rather
    // than relying on the listener's scheduled refresh to win a race.
    ref.read(updateRepositoryProvider);
    return !_disposed && generation == _generation;
  }

  Future<void> check() async {
    if (state.busy) return;
    final generation = ++_generation;
    state = AppUpdateState(
      phase: AppUpdatePhase.checking,
      release: state.release,
      hasDownloaded: _downloaded != null,
    );
    try {
      final repository = _repository;
      final version = await ref.read(updateCurrentVersionProvider.future);
      if (!_current(generation)) return;
      final release = await ref
          .read(githubUpdateServiceProvider)
          .checkLatest(repository: repository, currentVersion: version);
      if (!_current(generation)) return;
      final cached = _downloaded?.release;
      if (release == null ||
          cached?.repository.slug != release.repository.slug ||
          cached?.version != release.version ||
          cached?.installer.id != release.installer.id ||
          cached?.installer.size != release.installer.size ||
          cached?.installer.sha256 != release.installer.sha256) {
        _discardDownloaded();
      }
      state = AppUpdateState(
        phase: release == null
            ? AppUpdatePhase.upToDate
            : _downloaded == null
            ? AppUpdatePhase.available
            : AppUpdatePhase.ready,
        release: release,
        hasDownloaded: _downloaded != null,
      );
    } catch (error) {
      if (_current(generation)) _fail(_failure(error));
    }
  }

  Future<void> download() async {
    if (state.busy || state.release == null || _downloaded != null) return;
    final generation = ++_generation;
    final release = state.release!;
    state = AppUpdateState(phase: AppUpdatePhase.downloading, release: release);
    try {
      final service = ref.read(githubUpdateServiceProvider);
      final downloaded = await service.download(
        release: release,
        directory: ref.read(updateDownloadDirectoryProvider),
        onProgress: (progress) {
          if (!_current(generation)) return;
          state = AppUpdateState(
            phase: AppUpdatePhase.downloading,
            release: release,
            progress: progress,
          );
        },
      );
      if (!_current(generation)) {
        await service.discardDownloaded(downloaded);
        return;
      }
      _downloaded = downloaded;
      state = AppUpdateState(
        phase: AppUpdatePhase.ready,
        release: release,
        progress: 1,
        hasDownloaded: true,
      );
    } catch (error) {
      if (_current(generation)) _fail(_failure(error));
    }
  }

  Future<void> install({bool automatic = false}) async {
    if (state.busy) return;
    if (automatic && !ref.read(appSettingsProvider).autoInstallUpdates) return;
    if (_downloaded == null) await download();
    final update = _downloaded;
    if (update == null || _disposed || state.busy) return;
    if (automatic && !_canAutoInstall()) return;
    final generation = ++_generation;
    final installer = ref.read(updateInstallerProvider);
    final exitApp = ref.read(updateExitAppProvider);
    state = AppUpdateState(
      phase: AppUpdatePhase.installing,
      release: update.release,
      progress: 1,
      hasDownloaded: true,
    );
    var shutdownStarted = false;
    var installerLaunched = false;
    ConnectionController? connection;
    try {
      await installer.validate(update);
      if (!_current(generation)) return;
      if (automatic && !_canAutoInstall()) {
        state = AppUpdateState(
          phase: AppUpdatePhase.ready,
          release: update.release,
          progress: 1,
          hasDownloaded: true,
        );
        return;
      }
      // Stop our engines and restore the system proxy BEFORE quitting. The
      // installer waits for this PID and restarts the updated application.
      shutdownStarted = true;
      final activeConnection = ref.read(connectionControllerProvider.notifier);
      connection = activeConnection;
      await activeConnection.prepareForExit();
      if (!_current(generation)) return;
      installerLaunched = await installer.launch(
        update,
        shouldLaunch: () =>
            _current(generation) && (!automatic || _canAutoInstall()),
      );
      if (!installerLaunched) {
        if (_current(generation)) {
          state = AppUpdateState(
            phase: AppUpdatePhase.ready,
            release: update.release,
            progress: 1,
            hasDownloaded: true,
          );
        }
        return;
      }
      // Once Setup has been launched it is waiting for this PID; leaving the
      // caller open because a preference changed would strand the installer.
      exitApp();
    } catch (error) {
      if (_current(generation)) {
        _fail(
          error is UpdateException
              ? error.failure
              : UpdateFailure.installFailed,
        );
      }
    } finally {
      // Also unlock when the repository changed/disposed during shutdown,
      // not only on an exception. A canceled update must not lock VPN forever.
      if (shutdownStarted && !installerLaunched) connection?.cancelExit();
    }
  }

  bool _canAutoInstall() =>
      ref.read(appSettingsProvider).autoInstallUpdates &&
      ref.read(connectionControllerProvider) is ConnectionIdle;

  static UpdateFailure _failure(Object error) =>
      error is UpdateException ? error.failure : UpdateFailure.network;

  void _fail(UpdateFailure failure) {
    if (const {
      UpdateFailure.checksumMismatch,
      UpdateFailure.unexpectedSize,
      UpdateFailure.storage,
    }.contains(failure)) {
      _discardDownloaded();
    }
    state = AppUpdateState(
      phase: AppUpdatePhase.error,
      failure: failure,
      release: state.release,
      hasDownloaded: _downloaded != null,
    );
  }

  void _discardDownloaded() {
    final update = _downloaded;
    _downloaded = null;
    if (update != null) {
      // Discard only the file/directory created for this specific download.
      // The service swallows cleanup failures; a discarded file is never run.
      unawaited(
        ref.read(githubUpdateServiceProvider).discardDownloaded(update),
      );
    }
  }
}
