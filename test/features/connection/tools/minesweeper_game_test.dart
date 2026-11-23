import 'package:flutter_test/flutter_test.dart';
import 'package:flux/features/connection/tools/minesweeper_game.dart';

void main() {
  test('all first-click positions and their immediate neighbours are safe', () {
    for (var first = 0; first < 81; first++) {
      final game = MinesweeperGame(seed: first);
      expect(game.mineIndices, isEmpty);
      expect(game.reveal(first), true);
      expect(game.isMine(first), false);
      expect(game.neighbours(first).any(game.isMine), false);
      expect(game.adjacentMines(first), 0);
      expect(game.mineIndices.length, 10);
      expect(game.phase, isNot(MinesweeperPhase.lost));
    }
  });

  test('iterative flood reveal, counts and corner neighbours are correct', () {
    final game = MinesweeperGame(seed: 13)..reveal(40);
    expect(game.neighbours(0).toSet(), {1, 9, 10});
    expect(game.neighbours(40).length, 8);
    expect(game.revealedCount, greaterThan(1));
    for (var cell = 0; cell < game.cellCount; cell++) {
      expect(
        game.adjacentMines(cell),
        game.neighbours(cell).where(game.isMine).length,
      );
    }
  });

  test(
    'flags persist until toggled, are bounded and protect unopened cells',
    () {
      final game = MinesweeperGame(seed: 7);
      for (var i = 0; i < game.mineCount; i++) {
        expect(game.toggleFlag(i), true);
      }
      expect(game.toggleFlag(10), false);
      expect(game.reveal(0), false);
      expect(game.phase, MinesweeperPhase.ready);
      expect(game.toggleFlag(0), true);
      expect(game.reveal(0), true);
      expect(game.toggleFlag(0), false);
    },
  );

  test('mine hit reveals every mine and ends only the pure game model', () {
    final game = MinesweeperGame(seed: 19)..reveal(40);
    final mine = game.mineIndices.first;
    expect(game.reveal(mine), true);
    expect(game.phase, MinesweeperPhase.lost);
    expect(game.explodedCell, mine);
    expect(game.mineIndices.every(game.isRevealed), true);
    expect(game.reveal(0), false);
    expect(game.toggleFlag(0), false);
  });

  test('revealing every safe cell wins and marks all mines', () {
    final game = MinesweeperGame(seed: 19)..reveal(40);
    for (var cell = 0; cell < game.cellCount; cell++) {
      if (!game.isMine(cell)) game.reveal(cell);
    }
    expect(game.phase, MinesweeperPhase.won);
    expect(game.revealedCount, 71);
    expect(game.mineIndices.every(game.isFlagged), true);
  });

  test('correctly flagged number chords reveal its actual neighbours', () {
    final game = MinesweeperGame(seed: 91)..reveal(40);
    for (final mine in game.mineIndices) {
      game.toggleFlag(mine);
    }
    final numbered = List.generate(game.cellCount, (i) => i).firstWhere(
      (cell) =>
          game.isRevealed(cell) &&
          game.adjacentMines(cell) > 0 &&
          game
              .neighbours(cell)
              .any((n) => !game.isRevealed(n) && !game.isMine(n)),
    );
    final neighbours = game.neighbours(numbered).toList();
    expect(game.reveal(numbered), true);
    expect(
      neighbours.where((n) => !game.isMine(n)).every(game.isRevealed),
      true,
    );
    expect(game.phase, isNot(MinesweeperPhase.lost));
  });

  test(
    'invalid sizes and out-of-board clicks cannot produce an endless game',
    () {
      expect(() => MinesweeperGame(width: 1), throwsArgumentError);
      expect(() => MinesweeperGame(mineCount: 81), throwsArgumentError);
      final game = MinesweeperGame();
      expect(game.reveal(-1), false);
      expect(game.reveal(81), false);
      expect(game.toggleFlag(-1), false);
    },
  );
}
