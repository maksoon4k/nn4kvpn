import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/widgets/globe/video_background.dart';
import 'package:video_player/video_player.dart';

import '../../support/fake_media_controller.dart';

Widget background(String path, VideoPlayerController Function(String) create) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 320,
        height: 200,
        child: VideoBackground(filePath: path, controllerFactory: create),
      ),
    );

void main() {
  for (final stage in ['initialize', 'loop', 'volume', 'play']) {
    testWidgets(
      'replacement while previous video awaits $stage never restores the previous background',
      (tester) async {
        final hold = Completer<void>();
        final first = FixtureMediaController('D:/old.mp4', audioOnly: false)
          ..holds[stage] = hold.future;
        final second = FixtureMediaController('D:/new.mp4', audioOnly: false);
        VideoPlayerController create(String path) =>
            path == 'D:/old.mp4' ? first : second;
        await tester.pumpWidget(background('D:/old.mp4', create));
        await tester.pumpAndSettle();
        expect(first.calls, contains(stage));
        await tester.pumpWidget(background('D:/new.mp4', create));
        await tester.pumpAndSettle();
        expect(first.disposed, true);
        expect(
          tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
          second,
        );
        expect(second.volumes, [0]);
        expect(second.loops, [true]);
        hold.complete();
        await tester.pumpAndSettle();
        expect(
          tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
          second,
        );
        expect(first.calls.where((call) => call == 'dispose').length, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(second.disposed, true);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'rapid old/middle/new video selection accepts only the latest generation',
    (tester) async {
      final oldHold = Completer<void>();
      final middleHold = Completer<void>();
      final controllers = <String, FixtureMediaController>{
        'old': FixtureMediaController('D:/old.mp4', audioOnly: false)
          ..holds['initialize'] = oldHold.future,
        'middle': FixtureMediaController('D:/middle.mp4', audioOnly: false)
          ..holds['initialize'] = middleHold.future,
        'new': FixtureMediaController('D:/new.mp4', audioOnly: false),
      };
      VideoPlayerController create(String path) => controllers[path]!;
      await tester.pumpWidget(background('old', create));
      await tester.pumpWidget(background('middle', create));
      await tester.pumpWidget(background('new', create));
      await tester.pumpAndSettle();
      oldHold.complete();
      middleHold.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
        controllers['new'],
      );
      expect(controllers['old']!.disposed, true);
      expect(controllers['middle']!.disposed, true);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(
        controllers.values.every((controller) => controller.disposed),
        true,
      );
    },
  );

  testWidgets(
    'factory/decode errors do not crash and a later valid background recovers',
    (tester) async {
      final bad = FixtureMediaController('D:/bad.mp4', audioOnly: false)
        ..failInitialization = true;
      final good = FixtureMediaController('D:/good.mp4', audioOnly: false);
      VideoPlayerController create(String path) {
        if (path == 'throws') throw StateError('Fixture unavailable decoder');
        return path == 'bad' ? bad : good;
      }

      await tester.pumpWidget(background('throws', create));
      await tester.pumpAndSettle();
      expect(find.byType(VideoPlayer), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(background('bad', create));
      await tester.pumpAndSettle();
      expect(bad.disposed, true);
      expect(find.byType(VideoPlayer), findsNothing);
      await tester.pumpWidget(background('good', create));
      await tester.pumpAndSettle();
      expect(
        tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
        good,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disposal during initialization releases once even when initialization finishes later',
    (tester) async {
      final hold = Completer<void>();
      final controller = FixtureMediaController(
        'D:/pending.mp4',
        audioOnly: false,
      )..holds['initialize'] = hold.future;
      await tester.pumpWidget(background('pending', (_) => controller));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(controller.disposed, true);
      hold.complete();
      await tester.pumpAndSettle();
      expect(controller.calls, ['initialize', 'dispose']);
      expect(tester.takeException(), isNull);
    },
  );
}
