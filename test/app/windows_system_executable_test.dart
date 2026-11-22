import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/app/windows_system_executable.dart';

void main() {
  for (final name in ['schtasks.exe', 'ping.exe', 'explorer.exe']) {
    test(
      'resolves $name in the Windows system directory without launching it',
      () {
        if (!Platform.isWindows) {
          expect(() => windowsSystemExecutable(name), throwsUnsupportedError);
          return;
        }
        final path = windowsSystemExecutable(name);
        expect(
          path.toLowerCase(),
          endsWith(name == 'explorer.exe' ? '\\$name' : '\\system32\\$name'),
        );
        expect(File(path).isAbsolute, isTrue);
        expect(File(path).existsSync(), isTrue);
        expect(path.startsWith(Directory.current.path), isFalse);
      },
    );
  }

  for (final name in [
    '',
    '.',
    '..',
    '../schtasks.exe',
    r'..\schtasks.exe',
    r'C:\other\schtasks.exe',
    'schtasks.exe /create',
    'schtasks.exe\n',
    'schtasks',
  ]) {
    test(
      'rejects paths and arguments rather than passing them to Windows: $name',
      () {
        expect(() => windowsSystemExecutable(name), throwsArgumentError);
      },
    );
  }
}
