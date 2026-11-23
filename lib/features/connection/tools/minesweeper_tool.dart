import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../../widgets/port_ui/port_ui.dart';
import 'minesweeper_game.dart';

class MinesweeperTool extends StatefulWidget {
  final MinesweeperGame Function()? createGame;
  final Future<void> Function()? onLoss;
  const MinesweeperTool({super.key, this.createGame, this.onLoss});
  @override
  State<MinesweeperTool> createState() => _MinesweeperToolState();
}

class _MinesweeperToolState extends State<MinesweeperTool> {
  late var _game = widget.createGame?.call() ?? MinesweeperGame();
  bool _flagMode = false;
  late bool _closeOnLoss = widget.onLoss != null;
  bool _lossHandled = false;
  bool _closing = false;
  String? _exitError;
  int _difficulty = 0;
  int _seconds = 0;
  Timer? _timer;
  static const _sizes = [(9, 9, 10), (12, 12, 22), (16, 16, 40)];
  void _newGame() {
    _timer?.cancel();
    _timer = null;
    final size = _sizes[_difficulty];
    setState(() {
      _seconds = 0;
      _lossHandled = false;
      _exitError = null;
      _game =
          widget.createGame?.call() ??
          MinesweeperGame(width: size.$1, height: size.$2, mineCount: size.$3);
    });
  }

  void _reveal(int cell) {
    if (_flagMode) {
      _flag(cell);
      return;
    }
    setState(() => _game.reveal(cell));
    if (_game.phase == MinesweeperPhase.playing && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
    }
    if (_game.ended) {
      _timer?.cancel();
      _timer = null;
    }
    if (_game.phase == MinesweeperPhase.lost && !_lossHandled) {
      _lossHandled = true;
      if (_closeOnLoss) unawaited(_exitAfterLoss());
    }
  }

  Future<void> _exitAfterLoss() async {
    final onLoss = widget.onLoss;
    if (onLoss == null || _closing) return;
    setState(() {
      _closing = true;
      _exitError = null;
    });
    try {
      await onLoss();
    } catch (error) {
      if (mounted) {
        setState(
          () => _exitError =
              'Не удалось безопасно закрыть NN4K: $error. Клиент остаётся открытым.',
        );
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  void _flag(int cell) => setState(() => _game.toggleFlag(cell));
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.onLoss != null) ...[
        PortSwitch(
          key: const ValueKey('minesweeper-close-on-loss'),
          value: _closeOnLoss,
          label: const Text('Закрывать NN4K при проигрыше'),
          onChanged: _closing || _game.ended
              ? null
              : (value) => setState(() => _closeOnLoss = value),
        ),
        const SizedBox(height: 6),
        Text(
          _closeOnLoss
              ? 'Внимание: при попадании на мину NN4K сначала остановит соединение, затем штатно закроется.'
              : 'Тренировочный режим: поражение завершает только игру.',
          style: PortText.muted,
        ),
        const SizedBox(height: 10),
      ],
      Text(
        'Мины: ${_game.mineCount - _game.flagCount} · Время: $_seconds с',
        style: PortText.small,
      ),
      const SizedBox(height: 10),
      GridView.builder(
        key: const ValueKey('minesweeper-board'),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _game.width,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: _game.cellCount,
        itemBuilder: (context, cell) {
          final revealed = _game.isRevealed(cell);
          final mine = _game.isMine(cell);
          final flag = _game.isFlagged(cell);
          final count = _game.adjacentMines(cell);
          return Semantics(
            label: 'Клетка ${cell + 1}${flag ? ', флаг' : ''}',
            button: true,
            child: GestureDetector(
              key: ValueKey('minesweeper-cell-$cell'),
              onTap: () => _reveal(cell),
              onSecondaryTap: () => _flag(cell),
              onLongPress: () => _flag(cell),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _game.explodedCell == cell
                      ? const Color(0xFFBA3030)
                      : revealed
                      ? PortColors.background
                      : PortColors.secondary,
                  border: Border.all(color: PortColors.border),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: LayoutBuilder(
                  builder: (_, constraints) {
                    final size = (constraints.maxWidth * .6).clamp(8.0, 18.0);
                    if (revealed && mine) {
                      return Icon(
                        Icons.brightness_7,
                        size: size,
                        color: PortColors.foreground,
                      );
                    }
                    if (flag) {
                      return Icon(
                        Icons.flag,
                        size: size,
                        color: PortColors.primary,
                      );
                    }
                    return Text(
                      revealed && count > 0 ? '$count' : '',
                      style: TextStyle(
                        fontSize: size,
                        fontWeight: FontWeight.w700,
                        color: _numberColor(count),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 10),
      Text(
        switch (_game.phase) {
          MinesweeperPhase.ready =>
            'Первый ход безопасен. ЛКМ — открыть, ПКМ — флаг.',
          MinesweeperPhase.playing =>
            'Повторный клик по числу открывает соседей, если все мины отмечены.',
          MinesweeperPhase.won => 'Победа! Все безопасные клетки открыты.',
          MinesweeperPhase.lost =>
            _closing
                ? 'Бум! Останавливаем соединение и закрываем NN4K…'
                : _closeOnLoss
                ? 'Бум! Игра окончена.'
                : 'Бум! Поражение только в игре — NN4K продолжает работать.',
        },
        key: const ValueKey('minesweeper-status'),
        style: PortText.muted,
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PortButton(
            key: const ValueKey('minesweeper-new'),
            onPressed: _closing ? null : _newGame,
            child: const Text('Новая игра'),
          ),
          PortButton.outline(
            key: const ValueKey('minesweeper-flags'),
            onPressed: () => setState(() => _flagMode = !_flagMode),
            child: Text(_flagMode ? 'Режим: флаги' : 'Режим: открыть'),
          ),
          PortSelect<int>(
            initialValue: _difficulty,
            options: const [
              PortSelectOption(value: 0, child: Text('Легко')),
              PortSelectOption(value: 1, child: Text('Средне')),
              PortSelectOption(value: 2, child: Text('Сложно')),
            ],
            selectedOptionBuilder: (_, value) =>
                Text(['Легко', 'Средне', 'Сложно'][value]),
            onChanged: (value) {
              if (value != null && !_closing) {
                _difficulty = value;
                _newGame();
              }
            },
          ),
        ],
      ),
      if (_exitError != null) ...[
        const SizedBox(height: 10),
        Text(
          _exitError!,
          style: PortText.small.copyWith(color: PortColors.destructive),
        ),
        const SizedBox(height: 8),
        PortButton.outline(
          key: const ValueKey('minesweeper-exit-retry'),
          onPressed: _closing ? null : _exitAfterLoss,
          child: const Text('Повторить безопасный выход'),
        ),
      ],
    ],
  );

  Color _numberColor(int count) => const [
    Color(0xFFB8C8FF),
    Color(0xFF71AAFF),
    Color(0xFF69CE7A),
    Color(0xFFFF756D),
    Color(0xFFA39FFF),
    Color(0xFFFFBE6A),
    Color(0xFF64D9D6),
    Color(0xFFD0D0D0),
    Color(0xFFFFA6ED),
  ][count];
}
