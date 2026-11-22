import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/features/settings/managed_background_storage.dart';

void main() {
  late Directory directory;
  late ManagedBackgroundStorage storage;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('nn4k-background-tests-');
    storage = ManagedBackgroundStorage(
      Directory('${directory.path}/owned'),
      prefix: 'custom_background',
    );
  });
  tearDown(() async => directory.delete(recursive: true));

  test('never deletes an arbitrary path from settings', () async {
    await storage.directory.create();
    final outside = await File('${directory.path}/original.png')
        .writeAsString('original');
    await storage.delete(outside.path);
    expect(await outside.readAsString(), 'original');
  });

  test(
    'copies before replacing, including reimporting its own stored copy',
    () async {
      final original = await File('${directory.path}/original.png')
          .writeAsString('fixture');
      final saved = await storage.import(original.path);
      expect(await storage.import(saved), saved);
      expect(await File(saved).readAsString(), 'fixture');
      expect(await original.readAsString(), 'fixture');
      await storage.delete(saved);
      expect(await File(saved).exists(), false);
      expect(await original.exists(), true);
    },
  );

  test('keeps the old background if copying a new source fails', () async {
    final original = await File('${directory.path}/original.png')
        .writeAsString('old');
    final saved = await storage.import(original.path);
    await expectLater(
      storage.import('${directory.path}/missing.jpg'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File(saved).readAsString(), 'old');
  });

  test('removes old named copies but preserves unrelated files', () async {
    final png = await File('${directory.path}/original.png')
        .writeAsString('png');
    final jpeg = await File('${directory.path}/original.jpg')
        .writeAsString('jpeg');
    final old = await storage.import(png.path);
    final keep = await File('${storage.directory.path}/do-not-delete.txt')
        .writeAsString('keep');
    final saved = await storage.import(jpeg.path);
    expect(await File(old).exists(), false);
    expect(await File(saved).readAsString(), 'jpeg');
    expect(await keep.readAsString(), 'keep');
    await storage.delete(keep.path);
    expect(await keep.exists(), true);
  });
}
