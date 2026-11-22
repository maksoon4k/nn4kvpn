import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Resolve Windows tools through the OS API, never PATH, the working directory
/// or a caller-controlled SystemRoot environment variable. This is especially
/// important before asking UAC to elevate schtasks.exe.
String windowsSystemExecutable(String name) {
  if (!RegExp(r'^[a-zA-Z0-9_-]+\.exe$').hasMatch(name)) {
    throw ArgumentError.value(name, 'name', 'Expected an executable basename');
  }
  if (!Platform.isWindows) throw UnsupportedError('Windows system executable');
  const capacity = 32768;
  final buffer = calloc<Uint16>(capacity);
  try {
    final result = GetSystemDirectory(PWSTR(buffer.cast()), capacity);
    if (result.value == 0 || result.value >= capacity) {
      throw WindowsException(result.error.toHRESULT());
    }
    final directory = buffer.cast<Utf16>().toDartString(length: result.value);
    // Explorer belongs to the Windows directory, one level above System32.
    final root = name.toLowerCase() == 'explorer.exe'
        ? Directory(directory).parent.path
        : directory;
    return '$root\\$name';
  } finally {
    calloc.free(buffer);
  }
}
