import 'dart:async';

import 'package:flutter/material.dart' show Slider;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/features/connection/tools/recorder_tool.dart';
import 'package:flux/widgets/port_ui/port_ui.dart';

import '../../../support/fake_media_controller.dart';
import '../../../support/tool_host.dart';

void main() {
  testWidgets(
    'audio-only controllers really receive play/pause/seek/volume/loop, without a microphone',
    (tester) async {
      final source = MemoryCassetteSource();
      final controllers = <FixtureMediaController>[];
      await tester.pumpWidget(
        toolHost(
          RecorderTool(
            sourceFactory: () => source,
            controllerFactory: (path) {
              final controller = FixtureMediaController(path);
              controllers.add(controller);
              return controller;
            },
            pickFile: () async => null,
          ),
        ),
      );
      expect(source.prepared, isEmpty);
      expect(controllers, isEmpty);
      await tapToolKey(tester, 'recorder-play');
      final controller = controllers.single;
      expect(controller.value.size, Size.zero);
      expect(controller.calls, ['initialize', 'loop', 'volume', 'play']);
      expect(controller.volumes, [.6]);
      expect(controller.loops, [true]);
      expect(controller.value.isPlaying, true);
      controller.advance(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('00:05 / 00:16'), findsOneWidget);
      await tapToolKey(tester, 'recorder-play');
      expect(controller.value.isPlaying, false);

      final volume = tester.widget<Slider>(
        find.byKey(const ValueKey('recorder-volume')),
      );
      volume.onChanged!(.35);
      await tester.pump();
      volume.onChangeEnd!(.35);
      await tester.pumpAndSettle();
      expect(controller.volumes.last, .35);
      tester
          .widget<PortSwitch>(find.byKey(const ValueKey('recorder-loop')))
          .onChanged!(false);
      await tester.pumpAndSettle();
      expect(controller.loops.last, false);
      final seek = tester.widget<Slider>(
        find.byKey(const ValueKey('recorder-seek')),
      );
      seek.onChanged!(4000);
      await tester.pump();
      expect(find.text('00:04 / 00:16'), findsOneWidget);
      seek.onChangeEnd!(4000);
      await tester.pumpAndSettle();
      expect(controller.seeks.last, const Duration(seconds: 4));
      await tapToolKey(tester, 'recorder-rewind');
      expect(controller.seeks.last, Duration.zero);
      expect(controller.value.isPlaying, false);
      expect(find.text('00:00 / 00:16'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(controller.disposed, true);
      expect(source.disposed, true);
      expect(controller.calls.where((call) => call == 'dispose').length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing tape disposes the old player, keeps volume and preserves play/pause',
    (tester) async {
      final source = MemoryCassetteSource();
      final controllers = <FixtureMediaController>[];
      await tester.pumpWidget(
        toolHost(
          RecorderTool(
            sourceFactory: () => source,
            controllerFactory: (path) {
              final controller = FixtureMediaController(path);
              controllers.add(controller);
              return controller;
            },
            pickFile: () async => null,
          ),
        ),
      );
      await tapToolKey(tester, 'recorder-play');
      await tapToolKey(tester, 'recorder-tape');
      expect(source.prepared, [0, 1]);
      expect(controllers.first.disposed, true);
      expect(controllers[1].value.isPlaying, true);
      expect(find.text('Кассета: Шум шифрования'), findsOneWidget);
      await tapToolKey(tester, 'recorder-play');
      await tapToolKey(tester, 'recorder-tape');
      expect(source.prepared, [0, 1, 2]);
      expect(controllers[1].disposed, true);
      expect(controllers[2].value.isPlaying, false);
      expect(controllers[2].calls.contains('play'), false);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(controllers.every((controller) => controller.disposed), true);
    },
  );

  testWidgets(
    'selected user audio is opened directly, not recorded, copied or removed',
    (tester) async {
      final source = MemoryCassetteSource();
      final paths = <String>[];
      final controllers = <FixtureMediaController>[];
      await tester.pumpWidget(
        toolHost(
          RecorderTool(
            sourceFactory: () => source,
            controllerFactory: (path) {
              paths.add(path);
              final controller = FixtureMediaController(path);
              controllers.add(controller);
              return controller;
            },
            pickFile: () async => 'D:/fixtures/my music.mp3',
          ),
        ),
      );
      await tapToolKey(tester, 'recorder-file');
      expect(paths, ['D:/fixtures/my music.mp3']);
      expect(source.prepared, isEmpty);
      expect(find.text('Кассета: my music.mp3'), findsOneWidget);
      expect(controllers.single.value.isPlaying, true);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(source.disposed, true);
    },
  );

  testWidgets(
    'decode errors show a useful message and a retry creates a fresh player',
    (tester) async {
      final controllers = <FixtureMediaController>[];
      await tester.pumpWidget(
        toolHost(
          RecorderTool(
            sourceFactory: MemoryCassetteSource.new,
            controllerFactory: (path) {
              final controller = FixtureMediaController(path)
                ..failInitialization = controllers.isEmpty;
              controllers.add(controller);
              return controller;
            },
            pickFile: () async => null,
          ),
        ),
      );
      await tapToolKey(tester, 'recorder-play');
      expect(find.textContaining('Не удалось воспроизвести:'), findsOneWidget);
      expect(controllers.single.disposed, true);
      expect(controllers.single.calls.contains('play'), false);
      await tapToolKey(tester, 'recorder-play');
      expect(controllers.length, 2);
      expect(controllers.last.value.isPlaying, true);
      expect(find.textContaining('Не удалось воспроизвести:'), findsNothing);
      controllers.last.failStages.add('seek');
      await tapToolKey(tester, 'recorder-rewind');
      expect(find.textContaining('Ошибка воспроизведения:'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final stage in ['initialize', 'loop', 'volume', 'play']) {
    testWidgets(
      'closing during $stage releases the decoder exactly once and never starts late sound',
      (tester) async {
        final source = MemoryCassetteSource();
        final hold = Completer<void>();
        final controller = FixtureMediaController('D:/fixture.wav')
          ..holds[stage] = hold.future;
        await tester.pumpWidget(
          toolHost(
            RecorderTool(
              sourceFactory: () => source,
              controllerFactory: (_) => controller,
              pickFile: () async => null,
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('recorder-play')));
        await tester.pumpAndSettle();
        expect(controller.calls, contains(stage));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(controller.disposed, true);
        expect(source.disposed, true);
        hold.complete();
        await tester.pumpAndSettle();
        expect(controller.calls.where((call) => call == 'dispose').length, 1);
        expect(
          controller.calls.where((call) => call == 'play').length,
          stage == 'play' ? 1 : 0,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'closing during source preparation cannot construct a late player',
    (tester) async {
      final hold = Completer<String>();
      final source = MemoryCassetteSource()..hold = hold.future;
      var created = 0;
      await tester.pumpWidget(
        toolHost(
          RecorderTool(
            sourceFactory: () => source,
            controllerFactory: (path) {
              created++;
              return FixtureMediaController(path);
            },
            pickFile: () async => null,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('recorder-play')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      hold.complete('D:/fixture.wav');
      await tester.pumpAndSettle();
      expect(created, 0);
      expect(source.disposed, true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closing the picker or cancelling selection never starts a player',
    (tester) async {
      final hold = Completer<String?>();
      var created = 0;
      await tester.pumpWidget(
        toolHost(
          RecorderTool(
            sourceFactory: MemoryCassetteSource.new,
            controllerFactory: (path) {
              created++;
              return FixtureMediaController(path);
            },
            pickFile: () => hold.future,
          ),
        ),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('recorder-file')));
      await tester.tap(find.byKey(const ValueKey('recorder-file')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      hold.complete('D:/fixture.mp3');
      await tester.pumpAndSettle();
      expect(created, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelling a live picker preserves the current cassette, decoder, position and playback',
    (tester) async {
      final controller = FixtureMediaController('D:/fixture.wav');
      var created = 0;
      await tester.pumpWidget(
        toolHost(
          RecorderTool(
            sourceFactory: MemoryCassetteSource.new,
            controllerFactory: (_) {
              created++;
              return controller;
            },
            pickFile: () async => null,
          ),
        ),
      );
      await tapToolKey(tester, 'recorder-play');
      controller.advance(const Duration(seconds: 7));
      await tester.pump();
      await tapToolKey(tester, 'recorder-file');
      expect(created, 1);
      expect(controller.disposed, false);
      expect(controller.value.isPlaying, true);
      expect(find.text('00:07 / 00:16'), findsOneWidget);
      expect(find.text('Кассета: Ночной маршрут'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  for (final fail in [false, true]) {
    testWidgets(
      'a newer cassette choice ignores a stale picker ${fail ? 'error' : 'result'}',
      (tester) async {
        final selection = Completer<String?>();
        final paths = <String>[];
        await tester.pumpWidget(
          toolHost(
            RecorderTool(
              sourceFactory: MemoryCassetteSource.new,
              controllerFactory: (path) {
                paths.add(path);
                return FixtureMediaController(path);
              },
              pickFile: () => selection.future,
            ),
          ),
        );
        await tapToolKey(tester, 'recorder-play');
        await tapToolKey(tester, 'recorder-file');
        await tapToolKey(tester, 'recorder-tape');
        expect(find.text('Кассета: Шум шифрования'), findsOneWidget);
        if (fail) {
          selection.completeError(StateError('Obsolete picker error'));
        } else {
          selection.complete('D:/stale-selection.mp3');
        }
        await tester.pumpAndSettle();
        expect(paths, ['D:/fixtures/tape-0.wav', 'D:/fixtures/tape-1.wav']);
        expect(
          find.textContaining('Не удалось открыть аудиофайл'),
          findsNothing,
        );
        expect(find.text('Кассета: Шум шифрования'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a picker error is visible, leaves playback intact, and a subsequent selection can recover',
    (tester) async {
      var picks = 0;
      final controllers = <FixtureMediaController>[];
      await tester.pumpWidget(
        toolHost(
          RecorderTool(
            sourceFactory: MemoryCassetteSource.new,
            controllerFactory: (path) {
              final controller = FixtureMediaController(path);
              controllers.add(controller);
              return controller;
            },
            pickFile: () async {
              if (picks++ == 0) throw StateError('Fixture picker unavailable');
              return 'D:/valid.mp3';
            },
          ),
        ),
      );
      await tapToolKey(tester, 'recorder-play');
      await tapToolKey(tester, 'recorder-file');
      expect(
        find.textContaining('Не удалось открыть аудиофайл:'),
        findsOneWidget,
      );
      expect(controllers.single.value.isPlaying, true);
      await tapToolKey(tester, 'recorder-file');
      expect(
        find.textContaining('Не удалось открыть аудиофайл:'),
        findsNothing,
      );
      expect(controllers.first.disposed, true);
      expect(controllers.last.value.isPlaying, true);
      expect(find.text('Кассета: valid.mp3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'completed audio rewinds before replay, while repeated clicks during a pending command are disabled',
    (tester) async {
      final controller = FixtureMediaController('D:/fixture.wav');
      await tester.pumpWidget(
        toolHost(
          RecorderTool(
            sourceFactory: MemoryCassetteSource.new,
            controllerFactory: (_) => controller,
            pickFile: () async => null,
          ),
        ),
      );
      await tapToolKey(tester, 'recorder-play');
      controller.value = controller.value.copyWith(
        position: controller.value.duration,
        isPlaying: false,
        isCompleted: true,
      );
      await tester.pump();
      final hold = Completer<void>();
      controller.holds['seek'] = hold.future;
      await tapToolKey(tester, 'recorder-play');
      expect(controller.seeks, [Duration.zero]);
      expect(
        tester
            .widget<PortButton>(find.byKey(const ValueKey('recorder-play')))
            .onPressed,
        isNull,
      );
      hold.complete();
      await tester.pumpAndSettle();
      expect(controller.value.isPlaying, true);
      expect(controller.calls.where((call) => call == 'play').length, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a narrow tool with a long local filename keeps controls scrollable and releases playback',
    (tester) async {
      tester.view.physicalSize = const Size(320, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = FixtureMediaController('D:/fixture.mp3');
      await tester.pumpWidget(
        toolHost(
          RecorderTool(
            sourceFactory: MemoryCassetteSource.new,
            controllerFactory: (_) => controller,
            pickFile: () async => 'D:/Music/${'long name ' * 12}.mp3',
          ),
          width: 280,
        ),
      );
      await tapToolKey(tester, 'recorder-file');
      expect(controller.value.isPlaying, true);
      await tapToolKey(tester, 'recorder-rewind');
      expect(controller.value.isPlaying, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(controller.disposed, true);
    },
  );
}
