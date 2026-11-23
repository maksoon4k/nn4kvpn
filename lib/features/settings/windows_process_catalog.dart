import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:win32/win32.dart';

class RunningApplication {
  final String name;
  final List<String> paths;
  final int processCount;

  const RunningApplication({
    required this.name,
    required this.paths,
    required this.processCount,
  });
}

abstract class ApplicationProcessSource {
  Future<List<RunningApplication>> list();
}

final applicationProcessSourceProvider = Provider<ApplicationProcessSource>(
  (_) => WindowsProcessCatalog(),
);

/// Read-only snapshot with the minimum process-query rights. No PowerShell,
/// command lines, elevation, termination, background polling or persisted PIDs.
class WindowsProcessCatalog implements ApplicationProcessSource {
  @override
  Future<List<RunningApplication>> list() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Список процессов доступен в Windows.');
    }
    return Isolate.run(_snapshot);
  }

  static List<RunningApplication> _snapshot() {
    const capacity = 65536;
    const pathCapacity = 32768;
    final ids = calloc<Uint32>(capacity);
    final bytes = calloc<Uint32>();
    final length = calloc<Uint32>();
    final buffer = calloc<Uint16>(pathCapacity);
    try {
      final enumerated = EnumProcesses(ids, capacity * sizeOf<Uint32>(), bytes);
      if (!enumerated.value) {
        throw WindowsException(enumerated.error.toHRESULT());
      }
      if (bytes.value >= capacity * sizeOf<Uint32>()) {
        throw StateError(
          'Список процессов слишком большой. Обновите его повторно.',
        );
      }
      final paths = <String, Set<String>>{};
      final names = <String, String>{};
      final counts = <String, int>{};
      for (var i = 0; i < bytes.value ~/ sizeOf<Uint32>(); i++) {
        final opened = OpenProcess(
          PROCESS_QUERY_LIMITED_INFORMATION,
          false,
          ids[i],
        );
        final handle = opened.value;
        if (!handle.isValid) {
          continue; // Protected/exited processes are optional.
        }
        try {
          length.value = pathCapacity;
          final queried = QueryFullProcessImageName(
            handle,
            PROCESS_NAME_FORMAT(0),
            PWSTR(buffer.cast()),
            length,
          );
          if (!queried.value ||
              length.value == 0 ||
              length.value >= pathCapacity) {
            continue;
          }
          final path = buffer.cast<Utf16>().toDartString(length: length.value);
          final name = path.split('\\').last;
          if (!name.toLowerCase().endsWith('.exe')) continue;
          final key = name.toLowerCase();
          names[key] = name;
          (paths[key] ??= {}).add(path);
          counts[key] = (counts[key] ?? 0) + 1;
        } finally {
          CloseHandle(handle);
        }
      }
      final keys = names.keys.toList()..sort();
      return [
        for (final key in keys)
          RunningApplication(
            name: names[key]!,
            paths: List.unmodifiable(paths[key]!),
            processCount: counts[key]!,
          ),
      ];
    } finally {
      calloc.free(ids);
      calloc.free(bytes);
      calloc.free(length);
      calloc.free(buffer);
    }
  }
}
