import 'dart:math';

enum MinesweeperPhase { ready, playing, won, lost }

/// Local board only. Losing reveals the mines; it never throws, terminates the
/// application, disconnects a VPN, or invokes any platform operation.
class MinesweeperGame {
  final int width;
  final int height;
  final int mineCount;
  final Random _random;
  late final List<bool> _mines = List.filled(width * height, false);
  late final List<bool> _revealed = List.filled(width * height, false);
  late final List<bool> _flags = List.filled(width * height, false);
  MinesweeperPhase phase = MinesweeperPhase.ready;
  int? explodedCell;

  MinesweeperGame({
    this.width = 9,
    this.height = 9,
    this.mineCount = 10,
    int? seed,
  }) : _random = Random(seed) {
    if (width < 4 ||
        height < 4 ||
        width > 20 ||
        height > 20 ||
        mineCount < 1 ||
        mineCount > width * height - 9) {
      throw ArgumentError('Invalid Minesweeper dimensions or mine count');
    }
  }

  int get cellCount => width * height;
  int get flagCount => _flags.where((v) => v).length;
  int get revealedCount => _revealed.where((v) => v).length;
  bool get ended =>
      phase == MinesweeperPhase.won || phase == MinesweeperPhase.lost;
  bool isRevealed(int cell) => _revealed[cell];
  bool isFlagged(int cell) => _flags[cell];
  bool isMine(int cell) => _mines[cell];
  Set<int> get mineIndices => {
    for (var i = 0; i < cellCount; i++)
      if (_mines[i]) i,
  };

  Iterable<int> neighbours(int cell) sync* {
    final x = cell % width;
    final y = cell ~/ width;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final nx = x + dx;
        final ny = y + dy;
        if ((dx != 0 || dy != 0) &&
            nx >= 0 &&
            nx < width &&
            ny >= 0 &&
            ny < height) {
          yield ny * width + nx;
        }
      }
    }
  }

  int adjacentMines(int cell) =>
      neighbours(cell).where((n) => _mines[n]).length;

  bool toggleFlag(int cell) {
    if (cell < 0 || cell >= cellCount || ended || _revealed[cell]) return false;
    if (!_flags[cell] && flagCount >= mineCount) return false;
    _flags[cell] = !_flags[cell];
    return true;
  }

  bool reveal(int cell) {
    if (cell < 0 || cell >= cellCount || ended || _flags[cell]) return false;
    if (phase == MinesweeperPhase.ready) {
      final safe = {cell, ...neighbours(cell)};
      final candidates = [
        for (var i = 0; i < cellCount; i++)
          if (!safe.contains(i)) i,
      ]..shuffle(_random);
      for (final mine in candidates.take(mineCount)) {
        _mines[mine] = true;
      }
      phase = MinesweeperPhase.playing;
    }
    if (_revealed[cell]) return _chord(cell);
    if (_mines[cell]) {
      _lose(cell);
      return true;
    }
    _flood(cell);
    _checkWin();
    return true;
  }

  bool _chord(int cell) {
    final adjacent = adjacentMines(cell);
    if (adjacent == 0 ||
        neighbours(cell).where((n) => _flags[n]).length != adjacent) {
      return false;
    }
    var changed = false;
    for (final neighbour in neighbours(cell)) {
      if (_flags[neighbour] || _revealed[neighbour]) continue;
      if (_mines[neighbour]) {
        _lose(neighbour);
        return true;
      }
      _flood(neighbour);
      changed = true;
    }
    _checkWin();
    return changed;
  }

  void _flood(int initial) {
    final pending = [initial];
    while (pending.isNotEmpty) {
      final cell = pending.removeLast();
      if (_revealed[cell] || _flags[cell] || _mines[cell]) continue;
      _revealed[cell] = true;
      if (adjacentMines(cell) == 0) {
        pending.addAll(neighbours(cell).where((n) => !_revealed[n]));
      }
    }
  }

  void _lose(int cell) {
    phase = MinesweeperPhase.lost;
    explodedCell = cell;
    for (final mine in mineIndices) {
      _revealed[mine] = true;
    }
  }

  void _checkWin() {
    if (revealedCount != cellCount - mineCount) return;
    phase = MinesweeperPhase.won;
    for (final mine in mineIndices) {
      _flags[mine] = true;
    }
  }
}
