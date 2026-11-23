import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Slider;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/features/connection/parody_tools_menu.dart';
import 'package:flux/widgets/port_ui/port_ui.dart';

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
}

Future<void> openTool(WidgetTester tester, String label) async {
  await tester.pumpWidget(
    const PortApp(
      home: Align(
        alignment: Alignment.bottomRight,
        child: Padding(padding: EdgeInsets.all(24), child: ParodyToolsMenu()),
      ),
    ),
  );
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
  ]) {
    testWidgets('popup physically clicks $label outside the trigger bounds', (
      tester,
    ) async {
      await openTool(tester, label);
      await closeTool(tester);
    });
  }

  testWidgets('outside click and Escape dismiss the popup', (tester) async {
    await tester.pumpWidget(
      const PortApp(
        home: Align(alignment: Alignment.bottomRight, child: ParodyToolsMenu()),
      ),
    );
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
    await tester.pumpWidget(
      const PortApp(
        home: Align(alignment: Alignment.bottomRight, child: ParodyToolsMenu()),
      ),
    );
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
        ('Магнитофон', 'recorder-record', 'Стоп'),
        ('DOOM', 'doom-fire', 'В туннеле замечено демонов: 5'),
        ('Калькулятор', 'calculator-key-7', '77'),
        ('Minecraft', 'minecraft-place', 'Блоков в мире: 1/24 · Трава'),
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
      await tapKey(tester, 'youtube-like');
      expect(find.text('Нравится ♥'), findsOneWidget);
      await closeTool(tester);
    },
  );

  for (final tool in [
    ('Магнитофон', 'recorder-record'),
    ('Ютуб', 'youtube-play-pause'),
  ]) {
    for (final escape in [true, false]) {
      testWidgets(
        '${tool.$1} disposes its active timer on ${escape ? 'Escape' : 'outside click'}',
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

  testWidgets(
    'recorder cassette, elapsed time and rewind controls work without a microphone',
    (tester) async {
      await openTool(tester, 'Магнитофон');
      await tapKey(tester, 'recorder-record');
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('00:02'), findsOneWidget);
      await tapKey(tester, 'recorder-tape');
      expect(find.text('Кассета: Шум шифрования'), findsOneWidget);
      await tapKey(tester, 'recorder-rewind');
      expect(find.text('00:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('00:00'), findsOneWidget);
      await closeTool(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );

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
    'Minecraft places/removes material blocks and changes day/night',
    (tester) async {
      await openTool(tester, 'Minecraft');
      await tapKey(tester, 'minecraft-place');
      expect(find.text('Блоков в мире: 1/24 · Трава'), findsOneWidget);
      await tapKey(tester, 'minecraft-material');
      await tapKey(tester, 'minecraft-cell-0');
      expect(find.text('Блоков в мире: 2/24 · Камень'), findsOneWidget);
      await tapKey(tester, 'minecraft-cell-0');
      expect(find.text('Блоков в мире: 1/24 · Камень'), findsOneWidget);
      await tapKey(tester, 'minecraft-day-night');
      expect(find.text('Сделать день'), findsOneWidget);
      await tapKey(tester, 'minecraft-clear');
      expect(find.text('Блоков в мире: 0/24 · Камень'), findsOneWidget);
      await closeTool(tester);
    },
  );

  testWidgets(
    'offline video parody plays/pauses, seeks, changes clips and likes',
    (tester) async {
      await openTool(tester, 'Ютуб');
      await tapKey(tester, 'youtube-play-pause');
      await tester.pump(const Duration(seconds: 2));
      final slider = find.byKey(const ValueKey('youtube-seek'));
      expect(tester.widget<Slider>(slider).value, 2);
      await tapKey(tester, 'youtube-play-pause');
      await tester.pump(const Duration(seconds: 2));
      expect(tester.widget<Slider>(slider).value, 2);
      await tapKey(tester, 'youtube-like');
      expect(find.text('Нравится ♥'), findsOneWidget);
      await tapKey(tester, 'youtube-next');
      expect(find.textContaining('Сейчас играет: 10 часов'), findsOneWidget);
      await tapKey(tester, 'youtube-clip-2');
      expect(find.textContaining('Сейчас играет: Кот'), findsOneWidget);
      await tester.ensureVisible(slider);
      await tester.drag(slider, const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).value, greaterThan(0));
      await closeTool(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );
}
