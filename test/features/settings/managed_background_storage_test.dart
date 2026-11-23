import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flux/features/settings/managed_background_storage.dart';
import 'package:flux/core_abstraction/app_settings.dart';
import 'package:flux/features/settings/background_selection.dart';

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
    final outside = await File(
      '${directory.path}/original.png',
    ).writeAsString('original');
    await storage.delete(outside.path);
    expect(await outside.readAsString(), 'original');
  });

  test(
    'copies before replacing, including reimporting its own stored copy',
    () async {
      final original = await File(
        '${directory.path}/original.png',
      ).writeAsString('fixture');
      final saved = await storage.import(original.path);
      final reimported = await storage.import(saved);
      expect(reimported, isNot(saved));
      expect(await File(reimported).readAsString(), 'fixture');
      expect(await File(saved).readAsString(), 'fixture');
      expect(await original.readAsString(), 'fixture');
      await storage.delete(saved);
      expect(await File(saved).exists(), false);
      expect(await original.exists(), true);
    },
  );

  test('keeps the old background if copying a new source fails', () async {
    final original = await File(
      '${directory.path}/original.png',
    ).writeAsString('old');
    final saved = await storage.import(original.path);
    await expectLater(
      storage.import('${directory.path}/missing.jpg'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File(saved).readAsString(), 'old');
  });

  test('retires the previous copy only after committing settings', () async {
    final png = await File(
      '${directory.path}/original.png',
    ).writeAsString('png');
    final jpeg = await File(
      '${directory.path}/original.jpg',
    ).writeAsString('jpeg');
    final old = await storage.import(png.path);
    final keep = await File(
      '${storage.directory.path}/do-not-delete.txt',
    ).writeAsString('keep');
    var settings = AppSettings(
      customImagePath: old,
      homeBackground: HomeBackground.customImage,
    );
    await replaceCustomBackground(
      kind: HomeBackground.customImage,
      sourcePath: jpeg.path,
      import: storage.import,
      delete: storage.delete,
      readSettings: () => settings,
      canCommit: () => true,
      updateSettings: (transform) {
        expect(File(old).existsSync(), true);
        settings = transform(settings);
        expect(File(settings.customImagePath!).readAsStringSync(), 'jpeg');
      },
    );
    final saved = settings.customImagePath!;
    expect(await File(old).exists(), false);
    expect(await File(saved).readAsString(), 'jpeg');
    expect(await keep.readAsString(), 'keep');
    await storage.delete(keep.path);
    expect(await keep.exists(), true);
  });

  test(
    'same-extension replacements have new immutable cache identities',
    () async {
      final original = await File(
        '${directory.path}/original.png',
      ).writeAsString('first');
      final old = await storage.import(original.path);
      await original.writeAsString('second');
      final next = await storage.import(original.path);
      expect(next, isNot(old));
      expect(await File(old).readAsString(), 'first');
      expect(await File(next).readAsString(), 'second');
    },
  );

  test(
    'save failure keeps old bytes and discards only the pending new copy',
    () async {
      final original = await File(
        '${directory.path}/first.png',
      ).writeAsString('old');
      final next = await File(
        '${directory.path}/second.png',
      ).writeAsString('new');
      final old = await storage.import(original.path);
      final settings = AppSettings(
        homeBackground: HomeBackground.customImage,
        customImagePath: old,
      );
      await expectLater(
        replaceCustomBackground(
          kind: HomeBackground.customImage,
          sourcePath: next.path,
          import: storage.import,
          delete: storage.delete,
          readSettings: () => settings,
          canCommit: () => true,
          updateSettings: (_) =>
              throw const FileSystemException('fixture storage failure'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(old).readAsString(), 'old');
      expect(await storage.directory.list().length, 1);
    },
  );

  test(
    'closed picker never commits and cannot remove the previous file',
    () async {
      final original = await File(
        '${directory.path}/first.png',
      ).writeAsString('old');
      final old = await storage.import(original.path);
      final settings = AppSettings(customImagePath: old);
      final changed = await replaceCustomBackground(
        kind: HomeBackground.customImage,
        sourcePath: original.path,
        import: storage.import,
        delete: storage.delete,
        readSettings: () => settings,
        canCommit: () => false,
        updateSettings: (_) => fail('obsolete picker wrote settings'),
      );
      expect(changed, false);
      expect(await File(old).readAsString(), 'old');
      expect(await storage.directory.list().length, 1);
    },
  );

  test(
    'a newer background selection wins while unrelated settings survive',
    () async {
      final original = await File(
        '${directory.path}/first.png',
      ).writeAsString('image');
      var settings = const AppSettings(language: AppLanguage.en);
      final accepted = await replaceCustomBackground(
        kind: HomeBackground.customImage,
        sourcePath: original.path,
        import: (path) async {
          final saved = await storage.import(path);
          settings = settings.copyWith(
            homeBackground: HomeBackground.colorBends,
          );
          return saved;
        },
        delete: storage.delete,
        readSettings: () => settings,
        canCommit: () => true,
        updateSettings: (t) => settings = t(settings),
      );
      expect(accepted, false);
      expect(settings.homeBackground, HomeBackground.colorBends);
      expect(settings.language, AppLanguage.en);
      expect(await storage.directory.list().length, 0);
    },
  );

  test(
    'clear persists before deleting and does not clear another background kind',
    () async {
      final original = await File(
        '${directory.path}/first.png',
      ).writeAsString('image');
      final old = await storage.import(original.path);
      var settings = AppSettings(
        homeBackground: HomeBackground.galaxy,
        customImagePath: old,
      );
      await clearCustomBackground(
        kind: HomeBackground.customImage,
        delete: storage.delete,
        updateSettings: (t) {
          expect(File(old).existsSync(), true);
          settings = t(settings);
        },
      );
      expect(settings.customImagePath, isNull);
      expect(settings.homeBackground, HomeBackground.galaxy);
      expect(await File(old).exists(), false);
    },
  );

  test(
    'legacy owned filenames are deletable, lookalikes and neighbours are not',
    () async {
      await storage.directory.create();
      final legacy = await File(
        '${storage.directory.path}/custom_background.png',
      ).writeAsString('legacy');
      final neighbour = await File(
        '${storage.directory.path}/custom_background-not-owned.png',
      ).writeAsString('keep');
      await storage.delete(legacy.path);
      await storage.delete(neighbour.path);
      expect(await legacy.exists(), false);
      expect(await neighbour.readAsString(), 'keep');
    },
  );

  test(
    'concurrent imports cannot sweep each other and only the newest picker may commit',
    () async {
      final original = await File(
        '${directory.path}/original.png',
      ).writeAsString('old');
      final a = await File('${directory.path}/a.png').writeAsString('a');
      final b = await File('${directory.path}/b.png').writeAsString('b');
      final old = await storage.import(original.path);
      var settings = AppSettings(
        homeBackground: HomeBackground.customImage,
        customImagePath: old,
        language: AppLanguage.en,
      );
      final aReady = Completer<void>();
      final aHold = Completer<void>();
      var currentPicker = 1;
      String? importedA;
      final first = replaceCustomBackground(
        kind: HomeBackground.customImage,
        sourcePath: a.path,
        import: (path) async {
          importedA = await storage.import(path);
          aReady.complete();
          await aHold.future;
          return importedA!;
        },
        delete: storage.delete,
        readSettings: () => settings,
        updateSettings: (transform) => settings = transform(settings),
        canCommit: () => currentPicker == 1,
      );
      await aReady.future;
      currentPicker = 2;
      final second = await replaceCustomBackground(
        kind: HomeBackground.customImage,
        sourcePath: b.path,
        import: storage.import,
        delete: storage.delete,
        readSettings: () => settings,
        updateSettings: (transform) => settings = transform(settings),
        canCommit: () => currentPicker == 2,
      );
      expect(second, true);
      final selected = settings.customImagePath!;
      expect(await File(selected).readAsString(), 'b');
      expect(await File(importedA!).readAsString(), 'a');
      aHold.complete();
      expect(await first, false);
      expect(await File(importedA!).exists(), false);
      expect(await File(selected).readAsString(), 'b');
      expect(settings.language, AppLanguage.en);
    },
  );

  test(
    'unrelated edits made during import are merged, not rolled back',
    () async {
      final source = await File(
        '${directory.path}/original.png',
      ).writeAsString('image');
      var settings = const AppSettings();
      expect(
        await replaceCustomBackground(
          kind: HomeBackground.customImage,
          sourcePath: source.path,
          import: (path) async {
            final stored = await storage.import(path);
            settings = settings.copyWith(language: AppLanguage.en);
            return stored;
          },
          delete: storage.delete,
          readSettings: () => settings,
          updateSettings: (transform) => settings = transform(settings),
          canCommit: () => true,
        ),
        true,
      );
      expect(settings.language, AppLanguage.en);
      expect(settings.homeBackground, HomeBackground.customImage);
    },
  );

  test(
    'clear save failure never deletes the currently selected background',
    () async {
      final source = await File(
        '${directory.path}/original.png',
      ).writeAsString('image');
      final old = await storage.import(source.path);
      await expectLater(
        clearCustomBackground(
          kind: HomeBackground.customImage,
          delete: storage.delete,
          updateSettings: (_) =>
              throw const FileSystemException('Fixture cannot persist clear'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(old).readAsString(), 'image');
    },
  );

  test(
    'retirement failure cannot undo a successful replacement or delete another file',
    () async {
      final source = await File(
        '${directory.path}/original.png',
      ).writeAsString('image');
      var settings = const AppSettings(
        customImagePath: 'D:/fixture-locked.png',
      );
      expect(
        await replaceCustomBackground(
          kind: HomeBackground.customImage,
          sourcePath: source.path,
          import: storage.import,
          delete: (_) async =>
              throw const FileSystemException('Fixture locked by decoder'),
          readSettings: () => settings,
          updateSettings: (transform) => settings = transform(settings),
          canCommit: () => true,
        ),
        true,
      );
      expect(await File(settings.customImagePath!).readAsString(), 'image');
    },
  );
}
