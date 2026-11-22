import 'dart:io';

import '../../engines/xray/windows_elevation.dart';
import 'github_release.dart';
import 'github_update_service.dart';

abstract interface class UpdateInstaller {
  Future<void> validate(DownloadedUpdate update);

  /// Returns false when the caller canceled during final asynchronous checks.
  Future<bool> launch(DownloadedUpdate update, {bool Function()? shouldLaunch});
}

class WindowsUpdateInstaller implements UpdateInstaller {
  final GitHubUpdateService service;

  const WindowsUpdateInstaller(this.service);

  @override
  Future<void> validate(DownloadedUpdate update) async {
    if (!Platform.isWindows) {
      throw const UpdateException(UpdateFailure.unsupportedPlatform);
    }
    // A per-user update must not inherit TUN/admin privileges. The user can
    // restart normally and update without granting a downloaded EXE elevation.
    if (isRunningElevated()) {
      throw const UpdateException(UpdateFailure.elevated);
    }
    await service.verifyDownloaded(update);
  }

  @override
  Future<bool> launch(
    DownloadedUpdate update, {
    bool Function()? shouldLaunch,
  }) async {
    await validate(update);
    // Re-check cancellation/consent after hashing and immediately before the
    // process is started. There must be no await between this guard and start.
    if (shouldLaunch != null && !shouldLaunch()) return false;
    final installDirectory = File(Platform.resolvedExecutable).parent.path;
    try {
      await Process.start(
        update.file.path,
        [
          '/VERYSILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          '/NN4KUPDATE=1',
          '/WAITPID=$pid',
          '/DIR=$installDirectory',
        ],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      return true;
    } catch (_) {
      throw const UpdateException(UpdateFailure.installFailed);
    }
  }
}
