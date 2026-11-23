import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../features/connection/connection_controller.dart';

final closeAppWindowProvider = Provider<Future<void> Function()>(
  (_) => _closeAppWindow,
);

final safeAppExitProvider = Provider<SafeAppExit>((ref) {
  final connection = ref.read(connectionControllerProvider.notifier);
  return SafeAppExit(
    prepare: connection.prepareForExit,
    cancel: connection.cancelExit,
    close: ref.read(closeAppWindowProvider),
  );
});

/// The same ordered shutdown used by the tray/update lifecycle. A failed stop
/// must leave the client open and reconnectable, never orphan a VPN engine.
class SafeAppExit {
  final Future<void> Function() prepare;
  final void Function() cancel;
  final Future<void> Function() close;
  Future<void>? _pending;

  SafeAppExit({
    required this.prepare,
    required this.cancel,
    required this.close,
  });

  Future<void> exit() {
    final pending = _pending;
    if (pending != null) return pending;
    final exiting = _exit();
    _pending = exiting;
    exiting.then(
      (_) => _pending = null,
      onError: (Object error, StackTrace stack) => _pending = null,
    );
    return exiting;
  }

  Future<void> _exit() async {
    try {
      await prepare();
      await close();
    } catch (_) {
      cancel();
      rethrow;
    }
  }
}

Future<void> _closeAppWindow() async {
  if (Platform.isWindows || Platform.isMacOS) {
    await windowManager.setPreventClose(false); // Exit, not hide in the tray.
    try {
      await windowManager.close();
    } catch (_) {
      try {
        await windowManager.setPreventClose(true);
      } catch (_) {
        /* Keep the original close failure. */
      }
      rethrow;
    }
  } else {
    await SystemNavigator.pop();
  }
}
