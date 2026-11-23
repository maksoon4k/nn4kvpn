import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flux/features/connection/tools/minesweeper_game.dart';
import 'package:flux/features/connection/tools/minesweeper_tool.dart';
import 'package:flux/widgets/port_ui/port_ui.dart';

import '../../../support/tool_host.dart';

void main() {
  testWidgets(
    'safe exit on loss defaults on, waits once and blocks a new game while closing',
    (tester) async {
      final game = MinesweeperGame(seed: 19);
      final hold = Completer<void>();
      var exits = 0;
      await tester.pumpWidget(
        toolHost(
          MinesweeperTool(
            createGame: () => game,
            onLoss: () {
              exits++;
              return hold.future;
            },
          ),
          width: 460,
        ),
      );
      expect(
        tester
            .widget<PortSwitch>(
              find.byKey(const ValueKey('minesweeper-close-on-loss')),
            )
            .value,
        true,
      );
      await tapToolKey(tester, 'minesweeper-cell-40');
      expect(exits, 0);
      final mine = game.mineIndices.first;
      await tapToolKey(tester, 'minesweeper-cell-$mine');
      expect(exits, 1);
      expect(
        find.textContaining('Останавливаем соединение и закрываем NN4K'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<PortButton>(find.byKey(const ValueKey('minesweeper-new')))
            .onPressed,
        isNull,
      );
      await tapToolKey(tester, 'minesweeper-cell-$mine');
      expect(exits, 1);
      hold.complete();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'training mode shows defeat without exit and stops only the game timer',
    (tester) async {
      final game = MinesweeperGame(seed: 19);
      var exits = 0;
      await tester.pumpWidget(
        toolHost(
          MinesweeperTool(
            createGame: () => game,
            onLoss: () async {
              exits++;
            },
          ),
          width: 460,
        ),
      );
      tester
          .widget<PortSwitch>(
            find.byKey(const ValueKey('minesweeper-close-on-loss')),
          )
          .onChanged!(false);
      await tester.pump();
      await tapToolKey(tester, 'minesweeper-cell-40');
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('Время: 2 с'), findsOneWidget);
      await tapToolKey(tester, 'minesweeper-cell-${game.mineIndices.first}');
      expect(game.phase, MinesweeperPhase.lost);
      expect(exits, 0);
      expect(find.textContaining('NN4K продолжает работать'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('Время: 2 с'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'failed shutdown remains visible and can be retried, never forced into a crash',
    (tester) async {
      final game = MinesweeperGame(seed: 19);
      var exits = 0;
      await tester.pumpWidget(
        toolHost(
          MinesweeperTool(
            createGame: () => game,
            onLoss: () async {
              exits++;
              if (exits == 1) throw StateError('Fixture engine did not stop');
            },
          ),
          width: 460,
        ),
      );
      await tapToolKey(tester, 'minesweeper-cell-40');
      await tapToolKey(tester, 'minesweeper-cell-${game.mineIndices.first}');
      expect(find.textContaining('Клиент остаётся открытым'), findsOneWidget);
      await tapToolKey(tester, 'minesweeper-exit-retry');
      expect(exits, 2);
      expect(find.textContaining('Клиент остаётся открытым'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'right click flags, first reveal is safe, and closing cancels the timer',
    (tester) async {
      final game = MinesweeperGame(seed: 19);
      await tester.pumpWidget(
        toolHost(MinesweeperTool(createGame: () => game), width: 460),
      );
      final cell = find.byKey(const ValueKey('minesweeper-cell-0'));
      await tester.tap(
        cell,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      expect(game.isFlagged(0), true);
      await tester.tap(
        cell,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      expect(game.isFlagged(0), false);
      await tapToolKey(tester, 'minesweeper-cell-40');
      expect(game.phase, MinesweeperPhase.playing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late shutdown failure after closing the dialog does not setState on a disposed game',
    (tester) async {
      final hold = Completer<void>();
      final game = MinesweeperGame(seed: 19);
      await tester.pumpWidget(
        toolHost(
          MinesweeperTool(createGame: () => game, onLoss: () => hold.future),
          width: 460,
        ),
      );
      await tapToolKey(tester, 'minesweeper-cell-40');
      await tapToolKey(tester, 'minesweeper-cell-${game.mineIndices.first}');
      await tester.pumpWidget(const SizedBox.shrink());
      hold.completeError(StateError('Fixture shutdown failure'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
