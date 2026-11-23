import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Slider;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/app/external_web.dart';
import 'package:flux/app/safe_app_exit.dart';
import 'package:flux/features/connection/parody_tools_menu.dart';
import 'package:flux/features/connection/tools/minecraft_tool.dart';
import 'package:flux/features/connection/tools/recorder_tool.dart';
import 'package:flux/features/connection/tools/voxel_renderer.dart';
import 'package:flux/widgets/port_ui/port_ui.dart';

import '../../support/fake_media_controller.dart';

Future<bool> fixtureBrowser(Uri uri) async => true;

Widget menuHost({ExternalWebOpener openBrowser = fixtureBrowser}) =>
    ProviderScope(
      overrides: [
        safeAppExitProvider.overrideWithValue(
          SafeAppExit(prepare: () async {}, cancel: () {}, close: () async {}),
        ),
      ],
      child: PortApp(
        home: Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ParodyToolsMenu(
              openBrowser: openBrowser,
              recorderFactory: () => RecorderTool(
                sourceFactory: MemoryCassetteSource.new,
                controllerFactory: FixtureMediaController.new,
                pickFile: () async => null,
              ),
            ),
          ),
        ),
      ),
    );

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
}

Future<void> openTool(
  WidgetTester tester,
  String label, {
  ExternalWebOpener openBrowser = fixtureBrowser,
}) async {
  await tester.pumpWidget(menuHost(openBrowser: openBrowser));
  final trigger = tester.getRect(
    find.byKey(const ValueKey('parody-menu-toggle')),
  );
  await tapKey(tester, 'parody-menu-toggle');
  final row = find.byKey(ValueKey('parody-tool-$label'));
  await tester.ensureVisible(row);
  expect(tester.getCenter(row).dy, lessThan(trigger.top));
  // A real hit test outside the trigger's 40px bounds, not onPressed() called
  // directly. This reproduces the original visible-but-unclickable popup bug.
  await tester.tap(row, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
  expect(find.byType(PortDialog), findsOneWidget);
  expect(find.byKey(const ValueKey('parody-menu-dismiss')), findsNothing);
  expect(tester.takeException(), isNull);
}

Future<void> closeTool(WidgetTester tester) async {
  await tapKey(tester, 'close-parody-tool');
  expect(find.byType(PortDialog), findsNothing);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  for (final label in [
    'Фонарик',
    'Магнитофон',
    'DOOM',
    'Калькулятор',
    'Minecraft',
    'Ютуб',
    'Сапёр',
  ]) {
    testWidgets('popup physically clicks $label outside the trigger bounds', (
      tester,
    ) async {
      await openTool(tester, label);
      await closeTool(tester);
    });
  }

  testWidgets('outside click and Escape dismiss the popup', (tester) async {
    await tester.pumpWidget(menuHost());
    await tapKey(tester, 'parody-menu-toggle');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Фонарик'), findsNothing);
    await tapKey(tester, 'parody-menu-toggle');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Фонарик'), findsNothing);
  });

  testWidgets('menu rows can be reached by keyboard and activated with Enter', (
    tester,
  ) async {
    await tester.pumpWidget(menuHost());
    await tapKey(tester, 'parody-menu-toggle');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Фонарик дальнего действия'), findsOneWidget);
    await closeTool(tester);
  });

  testWidgets(
    'small windows keep all popup rows scrollable and tools bounded',
    (tester) async {
      tester.view.physicalSize = const Size(320, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final tool in [
        ('Фонарик', 'flashlight-color', 'Неоновый луч'),
        ('Магнитофон', 'recorder-play', 'Пауза'),
        ('DOOM', 'doom-fire', 'В туннеле замечено демонов: 5'),
        ('Калькулятор', 'calculator-key-7', '77'),
        ('Minecraft', 'minecraft-day-night', 'Сделать день'),
        ('Сапёр', 'minesweeper-flags', 'Режим: флаги'),
      ]) {
        await openTool(tester, tool.$1);
        await tapKey(tester, tool.$2);
        if (tool.$1 == 'Калькулятор') await tapKey(tester, tool.$2);
        expect(find.text(tool.$3), findsOneWidget);
        await closeTool(tester);
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      }
      await openTool(tester, 'Ютуб');
      await tapKey(tester, 'youtube-home');
      expect(find.text('YouTube открыт в браузере.'), findsOneWidget);
      await closeTool(tester);
    },
  );

  for (final tool in [
    ('Магнитофон', 'recorder-play'),
    ('Ютуб', 'youtube-home'),
    ('Сапёр', 'minesweeper-cell-0'),
  ]) {
    for (final escape in [true, false]) {
      testWidgets(
        '${tool.$1} closes active work on ${escape ? 'Escape' : 'outside click'}',
        (tester) async {
          await openTool(tester, tool.$1);
          await tapKey(tester, tool.$2);
          if (escape) {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          } else {
            await tester.tapAt(const Offset(10, 10));
          }
          await tester.pumpAndSettle();
          expect(find.byType(PortDialog), findsNothing);
          await tester.pump(const Duration(seconds: 3));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('flashlight toggles, changes color, adjusts and scans locally', (
    tester,
  ) async {
    await openTool(tester, 'Фонарик');
    await tapKey(tester, 'flashlight-scan');
    expect(find.text('Подсвечено пакетов: 22'), findsOneWidget);
    await tapKey(tester, 'flashlight-color');
    expect(find.text('Неоновый луч'), findsOneWidget);
    await tapKey(tester, 'flashlight-toggle');
    expect(
      tester
          .widget<PortButton>(find.byKey(const ValueKey('flashlight-scan')))
          .onPressed,
      isNull,
    );
    await tapKey(tester, 'flashlight-toggle');
    final slider = find.byKey(const ValueKey('flashlight-distance'));
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, lessThan(10000));
    await closeTool(tester);
  });

  testWidgets('DOOM has shots, medkits, score and successive waves', (
    tester,
  ) async {
    await openTool(tester, 'DOOM');
    await tapKey(tester, 'doom-fire');
    expect(find.text('В туннеле замечено демонов: 5'), findsOneWidget);
    await tapKey(tester, 'doom-medkit');
    expect(find.text('Здоровье роутера: 100%'), findsOneWidget);
    for (var shot = 0; shot < 5; shot++) {
      await tapKey(tester, 'doom-fire');
    }
    expect(find.text('Волна: 1 · Очки: 60'), findsOneWidget);
    expect(
      tester
          .widget<PortButton>(find.byKey(const ValueKey('doom-fire')))
          .onPressed,
      isNull,
    );
    await tapKey(tester, 'doom-next-wave');
    expect(find.text('Волна: 2 · Очки: 60'), findsOneWidget);
    expect(find.text('В туннеле замечено демонов: 7'), findsOneWidget);
    await closeTool(tester);
  });

  testWidgets(
    'calculator supports decimal arithmetic, clear, backspace and speed conversion',
    (tester) async {
      await openTool(tester, 'Калькулятор');
      Future<void> keys(List<String> values) async {
        for (final value in values) {
          await tapKey(tester, 'calculator-key-$value');
        }
      }

      String screen() => tester
          .widget<Text>(find.byKey(const ValueKey('calculator-screen')))
          .data!;
      await keys(['2', '.', '5', '×', '4', '=']);
      expect(screen(), '10');
      await keys(['C', '8', '÷', '0', '=']);
      expect(screen(), 'ну нельзя');
      await keys(['C', '8', '+', 'C', '2', '=']);
      expect(screen(), '2');
      await keys(['C', '1', '0', '0', '÷8']);
      expect(screen(), '12.5');
      await keys(['C', '1', '2', '⌫', '±']);
      expect(screen(), '-1');
      await closeTool(tester);
    },
  );

  testWidgets(
    'Minecraft menu opens a perspective 3D world rather than the old 2D grid',
    (tester) async {
      await openTool(tester, 'Minecraft');
      expect(find.byType(MinecraftTool), findsOneWidget);
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('minecraft-3d-render')),
                  )
                  .painter!
              as VoxelWorldPainter;
      expect(painter.world.blockCount, greaterThan(1000));
      expect(find.byKey(const ValueKey('minecraft-cell-0')), findsNothing);
      await tapKey(tester, 'minecraft-material');
      expect(find.textContaining('· Камень ·'), findsOneWidget);
      await tapKey(tester, 'minecraft-day-night');
      expect(find.text('Сделать день'), findsOneWidget);
      await tapKey(tester, 'minecraft-clear');
      expect(find.textContaining('· Камень ·'), findsOneWidget);
      await closeTool(tester);
    },
  );

  testWidgets(
    'YouTube selection opens the actual website once through an injected opener',
    (tester) async {
      final addresses = <Uri>[];
      await openTool(
        tester,
        'Ютуб',
        openBrowser: (uri) async {
          addresses.add(uri);
          return true;
        },
      );
      expect(addresses, [Uri.https('www.youtube.com', '/')]);
      expect(find.byKey(const ValueKey('youtube-clip-0')), findsNothing);
      await tapKey(tester, 'youtube-home');
      expect(addresses.length, 2);
      await closeTool(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );
}
