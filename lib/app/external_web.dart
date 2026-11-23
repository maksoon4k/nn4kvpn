import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

typedef ExternalWebOpener = Future<bool> Function(Uri uri);

/// Open a web address directly through the OS, never cmd / start, PATH, runas,
/// or an interpolated shell command. Called only after an explicit UI action.
Future<bool> openExternalWeb(Uri uri) async {
  if (uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      RegExp(r'[\x00-\x1f]').hasMatch(uri.toString())) {
    throw const FormatException('Ожидается HTTPS-ссылка.');
  }
  if (Platform.isWindows) {
    final address = uri.toString().toNativeUtf16();
    final operation = 'open'.toNativeUtf16();
    try {
      return ShellExecute(
            null,
            PCWSTR(operation),
            PCWSTR(address),
            null,
            null,
            SW_SHOWNORMAL,
          ).address >
          32;
    } finally {
      calloc.free(address);
      calloc.free(operation);
    }
  }
  if (Platform.isMacOS) {
    final result = await Process.run('/usr/bin/open', [uri.toString()]);
    return result.exitCode == 0;
  }
  throw UnsupportedError(
    'Открытие браузера поддерживается в Windows и macOS. Скопируйте ссылку.',
  );
}
