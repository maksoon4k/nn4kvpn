import 'dart:io';

import 'package:flutter/services.dart' show EventChannel, MethodChannel;
import 'package:win32_registry/win32_registry.dart';

/// Диплинк-схема приложения — как `vless://`, `sing-box://` и подобные в
/// других клиентах. `flux://add/<url-encoded ссылка>` открывает диалог
/// добавления сервера с уже подставленной ссылкой.
const fluxUriScheme = 'flux';
const maxFluxDeepLinkLength = 32 * 1024;
final _deepLinkControls = RegExp(r'[\x00-\x1f\x7f]');
final _invalidPercentEscape = RegExp(r'%(?![0-9a-fA-F]{2})');

/// Регистрирует `flux://` как обработчик URL-протокола в реестре текущего
/// пользователя (`HKCU\Software\Classes\flux`) — не требует прав
/// администратора. Идемпотентно: перезаписывает путь к .exe при каждом
/// запуске на случай, если приложение переместили/пересобрали.
void registerFluxUriProtocolIfNeeded() {
  if (!Platform.isWindows) return;

  final exePath = Platform.resolvedExecutable;
  final protocolKey = CURRENT_USER.create('Software\\Classes\\$fluxUriScheme');
  try {
    protocolKey
      ..setValue('', const RegistryValue.string('URL:Flux Protocol'))
      ..setValue('URL Protocol', const RegistryValue.string(''));
    final commandKey = protocolKey.create('shell\\open\\command');
    try {
      commandKey.setValue('', RegistryValue.string('"$exePath" "%1"'));
    } finally {
      commandKey.close();
    }
  } finally {
    protocolKey.close();
  }
}

/// Достаёт ссылку (`vless://...` или `https://...`) из аргумента вида
/// `flux://add/<...>` — тело диплинка может быть как обычным URL, так и
/// URL-encoded строкой.
String? parseFluxDeepLink(String raw) {
  if (raw.length > maxFluxDeepLinkLength ||
      _deepLinkControls.hasMatch(raw) ||
      _invalidPercentEscape.hasMatch(raw)) {
    return null;
  }
  try {
    final uri = Uri.parse(raw);
    if (uri.scheme != fluxUriScheme ||
        uri.host != 'add' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort) {
      return null;
    }
    // Query decoding can throw even after Uri.parse succeeds (e.g. %FF).
    // Decode exactly once, and reject ambiguous repeated url parameters.
    final urls = uri.queryParametersAll['url'];
    final String payload;
    if (urls != null) {
      if (urls.length != 1) return null;
      payload = urls.single.trim();
    } else {
      final rest = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
      payload = Uri.decodeComponent(rest).trim();
    }
    if (payload.isEmpty || _deepLinkControls.hasMatch(payload)) return null;
    final target = Uri.tryParse(payload);
    if (target == null ||
        !const {
          'vless',
          'hysteria2',
          'hy2',
          'https',
          'http',
        }.contains(target.scheme)) {
      return null;
    }
    // This only pre-fills an import dialog. No request, import, connection or
    // updater action is authorized by a deep link itself.
    return payload;
  } on FormatException {
    return null;
  }
}

/// Первый аргумент командной строки, похожий на диплинк `flux://...` —
/// Windows передаёт зарегистрированный URL первым (и обычно единственным)
/// аргументом при запуске приложения через протокол.
String? extractFluxDeepLinkFromArgs(List<String> args) {
  for (final arg in args) {
    if (arg.length <= maxFluxDeepLinkLength &&
        arg.toLowerCase().startsWith('$fluxUriScheme://')) {
      return arg;
    }
  }
  return null;
}

// --- Android/macOS -----------------------------------------------------
//
// Регистрация схемы — не в Dart: в `android/app/src/main/AndroidManifest.
// xml` (intent-filter с `android:scheme="flux"` на MainActivity) для
// Android, и в `macos/Runner/Info.plist` (`CFBundleURLTypes`) для macOS. Ни
// у Android, ни у macOS нет Windows-style второго процесса/loopback-IPC
// (см. `single_instance.dart`) — Android переиспользует единственную
// Activity (`launchMode="singleTop"`) и присылает повторные ссылки через
// `onNewIntent` (`MainActivity.kt`), macOS точно так же переиспользует
// единственный процесс (`LSMultipleInstancesProhibited` в Info.plist) и
// присылает их через Apple Event `kAEGetURL`, перехваченный в
// `AppDelegate.swift`. Оба шлют результат в Dart одинаково — через один и
// тот же канал, поэтому обвязка тут общая, а не дублируется по платформе.
const _nativeDeepLinkChannel = MethodChannel('flux/deeplink');
const _nativeDeepLinkEventChannel = EventChannel('flux/deeplink/stream');

Future<String?> nativeInitialDeepLink() async {
  if (!Platform.isAndroid && !Platform.isMacOS) return null;
  try {
    return await _nativeDeepLinkChannel.invokeMethod<String>('getInitialLink');
  } catch (_) {
    return null;
  }
}

Stream<String> get nativeDeepLinkStream {
  if (!Platform.isAndroid && !Platform.isMacOS) return const Stream.empty();
  return _nativeDeepLinkEventChannel.receiveBroadcastStream().map(
    (event) => event as String,
  );
}
