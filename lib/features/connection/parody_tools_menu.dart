import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Colors, Icons, Material, Slider;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../widgets/port_ui/port_ui.dart';

/// A deliberately small set of "totally essential" VPN utilities.
/// Everything is local UI state: no permissions, media devices or web views.
class ParodyToolsMenu extends StatefulWidget {
  const ParodyToolsMenu({super.key});

  @override
  State<ParodyToolsMenu> createState() => _ParodyToolsMenuState();
}

class _ParodyToolsMenuState extends State<ParodyToolsMenu> {
  final _overlay = OverlayPortalController();
  final _link = LayerLink();

  void _closeMenu() {
    _overlay.hide();
    if (mounted) setState(() {});
  }

  void _show(String title, Widget body) {
    _closeMenu();
    showPortDialog<void>(
      context: context,
      builder: (dialogContext) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(dialogContext).pop(),
        },
        child: Focus(
          autofocus: true,
          child: PortDialog(
            title: Text(title),
            description: const Text(
              'Пасхалка NN4K. Никаких лишних процессов — только вайб.',
            ),
            actions: [
              PortButton.outline(
                key: const ValueKey('close-parody-tool'),
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Закрыть'),
              ),
            ],
            child: Material(
              color: Colors.transparent,
              textStyle: PortText.p,
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = <_ToolEntry>[
      _ToolEntry(
        'Фонарик',
        Icons.flashlight_on,
        () => _show('Фонарик дальнего действия', const _Flashlight()),
      ),
      _ToolEntry(
        'Магнитофон',
        Icons.radio,
        () => _show('Магнитофон', const _Recorder()),
      ),
      _ToolEntry(
        'DOOM',
        Icons.sports_esports,
        () => _show('DOOM, но в VPN', const _Doom()),
      ),
      _ToolEntry(
        'Калькулятор',
        Icons.calculate,
        () => _show('Калькулятор', const _Calculator()),
      ),
      _ToolEntry(
        'Minecraft',
        Icons.terrain,
        () => _show('Minecraft Lite', const _Minecraft()),
      ),
      _ToolEntry(
        'Ютуб',
        Icons.play_circle_fill,
        () => _show('Ютуб без рекламы (почти)', const _Youtube()),
      ),
    ];

    // An overflowing Stack can paint outside a 40px trigger, but Flutter will
    // not hit-test that overflow. Put the list in the full-screen Overlay and
    // follow the trigger instead; rows now work with mouse, touch and keyboard.
    return OverlayPortal(
      controller: _overlay,
      overlayChildBuilder: (context) => Positioned.fill(
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          },
          child: Actions(
            actions: {
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) {
                  _closeMenu();
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      key: const ValueKey('parody-menu-dismiss'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _closeMenu,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    width: math.min(184, MediaQuery.sizeOf(context).width - 32),
                    child: CompositedTransformFollower(
                      link: _link,
                      showWhenUnlinked: false,
                      targetAnchor: Alignment.topRight,
                      followerAnchor: Alignment.bottomRight,
                      offset: const Offset(0, -8),
                      child: Container(
                        constraints: BoxConstraints(
                          maxHeight: math.max(
                            48,
                            MediaQuery.sizeOf(context).height - 100,
                          ),
                        ),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: PortColors.popover,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: PortColors.border),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x55000000),
                              blurRadius: 18,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final entry in entries)
                                _MenuRow(entry: entry),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: PortIconButton.secondary(
          key: const ValueKey('parody-menu-toggle'),
          size: 40,
          icon: Icon(
            _overlay.isShowing ? Icons.close : Icons.grid_view,
            size: 18,
          ),
          onPressed: () {
            _overlay.toggle();
            setState(() {});
          },
        ),
      ),
    );
  }
}

class _ToolEntry {
  final String label;
  final IconData icon;
  final VoidCallback action;
  const _ToolEntry(this.label, this.icon, this.action);
}

class _MenuRow extends StatelessWidget {
  final _ToolEntry entry;
  const _MenuRow({required this.entry});

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    },
    child: Actions(
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            entry.action();
            return null;
          },
        ),
      },
      child: PortButton.ghost(
        key: ValueKey('parody-tool-${entry.label}'),
        onPressed: entry.action,
        leading: Icon(entry.icon, size: 16, color: PortColors.mutedForeground),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(entry.label, style: PortText.small),
        ),
      ),
    ),
  );
}

class _Flashlight extends StatefulWidget {
  const _Flashlight();
  @override
  State<_Flashlight> createState() => _FlashlightState();
}

class _FlashlightState extends State<_Flashlight> {
  double _distance = 10000;
  double _width = 180;
  double _height = 120;
  bool _enabled = true;
  int _found = 0;
  int _color = 0;
  static const _colors = [
    Color(0xFFFFF5AA),
    Color(0xFF80FFDA),
    Color(0xFFB8C8FF),
  ];
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _beamPreview(_distance, _width, _height),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PortButton.outline(
            key: const ValueKey('flashlight-toggle'),
            onPressed: () => setState(() => _enabled = !_enabled),
            child: Text(_enabled ? 'Выключить' : 'Включить'),
          ),
          PortButton.outline(
            key: const ValueKey('flashlight-color'),
            onPressed: () =>
                setState(() => _color = (_color + 1) % _colors.length),
            child: Text(['Тёплый луч', 'Неоновый луч', 'Лунный луч'][_color]),
          ),
          PortButton(
            key: const ValueKey('flashlight-scan'),
            onPressed: !_enabled
                ? null
                : () => setState(() {
                    _found += math.max(1, (_width * _height / 1000).round());
                  }),
            child: const Text('Сканировать'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text('Подсвечено пакетов: $_found', style: PortText.small),
      const SizedBox(height: 12),
      Text('Дальность: ${_distance.round()} км', style: PortText.small),
      Slider(
        key: const ValueKey('flashlight-distance'),
        value: _distance,
        min: 1,
        max: 10000,
        onChanged: (v) => setState(() => _distance = v),
      ),
      Text('Ширина луча: ${_width.round()}°', style: PortText.small),
      Slider(
        key: const ValueKey('flashlight-width'),
        value: _width,
        min: 10,
        max: 360,
        onChanged: (v) => setState(() => _width = v),
      ),
      Text('Высота луча: ${_height.round()} м', style: PortText.small),
      Slider(
        key: const ValueKey('flashlight-height'),
        value: _height,
        min: 5,
        max: 300,
        onChanged: (v) => setState(() => _height = v),
      ),
      Text(
        'Расчёт: можно подсветить примерно ${(_distance * _width * _height / 1500).round()} подозрительных пакетов.',
        style: PortText.muted,
      ),
    ],
  );

  Widget _beamPreview(double distance, double width, double height) =>
      Container(
        height: 126,
        decoration: BoxDecoration(
          color: const Color(0xFF071018),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: PortColors.border),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 18,
              top: 50,
              child: Icon(
                Icons.flashlight_on,
                color: PortColors.foreground,
                size: 32,
              ),
            ),
            if (_enabled)
              Positioned(
                left: 50,
                top: 24 + (150 - height.clamp(5, 150)) * .2,
                child: Transform.rotate(
                  angle: 0.0,
                  child: ClipPath(
                    clipper: _BeamClipper(width / 360),
                    child: Container(
                      width: 320,
                      height: height.clamp(20, 110).toDouble(),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _colors[_color].withValues(alpha: .8),
                            _colors[_color].withValues(alpha: .02),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 12,
              bottom: 8,
              child: Text('${distance.round()} км', style: PortText.muted),
            ),
          ],
        ),
      );
}

class _BeamClipper extends CustomClipper<Path> {
  final double openness;
  const _BeamClipper(this.openness);
  @override
  Path getClip(Size s) {
    final h = s.height * openness.clamp(.15, 1).toDouble();
    return Path()
      ..moveTo(0, s.height / 2)
      ..lineTo(s.width, s.height / 2 - h / 2)
      ..lineTo(s.width, s.height / 2 + h / 2)
      ..close();
  }

  @override
  bool shouldReclip(_BeamClipper old) => old.openness != openness;
}

class _Recorder extends StatefulWidget {
  const _Recorder();
  @override
  State<_Recorder> createState() => _RecorderState();
}

class _RecorderState extends State<_Recorder> {
  bool _recording = false;
  int _seconds = 0;
  Timer? _timer;
  int _tape = 0;
  static const _tapes = ['Ночной маршрут', 'Шум шифрования', 'Лоу-фай пакеты'];
  void _toggle() {
    setState(() => _recording = !_recording);
    _timer?.cancel();
    if (_recording) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        height: 82,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: PortColors.secondary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 30),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          15,
          (i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Container(
              width: 7,
              height: _recording
                  ? 8 + ((_seconds * 7 + i * 11) % 30).toDouble()
                  : 8,
              color: _recording ? PortColors.primary : PortColors.border,
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          PortButton(
            key: const ValueKey('recorder-record'),
            leading: Icon(_recording ? Icons.stop : Icons.fiber_manual_record),
            onPressed: _toggle,
            child: Text(_recording ? 'Стоп' : 'Запись'),
          ),
          PortButton.outline(
            key: const ValueKey('recorder-rewind'),
            leading: const Icon(Icons.fast_rewind),
            onPressed: () {
              _timer?.cancel();
              setState(() {
                _seconds = 0;
                _recording = false;
              });
            },
            child: const Text('Перемотать'),
          ),
          PortButton.outline(
            key: const ValueKey('recorder-tape'),
            onPressed: () =>
                setState(() => _tape = (_tape + 1) % _tapes.length),
            child: const Text('Сменить кассету'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text('Кассета: ${_tapes[_tape]}', style: PortText.small),
      const SizedBox(height: 6),
      Text(
        _recording
            ? 'Ш-ш-ш... воображаемый звук шифрования. Микрофон не используется.'
            : 'Локальная кассета: ни микрофона, ни аудиозаписи.',
        style: PortText.muted,
      ),
    ],
  );
}

class _Doom extends StatefulWidget {
  const _Doom();
  @override
  State<_Doom> createState() => _DoomState();
}

class _DoomState extends State<_Doom> {
  int _health = 100;
  int _demons = 6;
  int _wave = 1;
  int _score = 0;
  int _medkits = 2;
  void _fire() => setState(() {
    if (_demons == 0) return;
    _demons--;
    _score += 10;
    _health = math.max(1, _health - 3).toInt();
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        constraints: const BoxConstraints(minHeight: 145),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A0A0A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'D O O M  //  VPN edition',
              style: TextStyle(letterSpacing: 2, color: Color(0xFFFF6A45)),
            ),
            const SizedBox(height: 24),
            Text(
              _demons == 0
                  ? 'Сеть очищена. Демоны разлогинились.'
                  : 'В туннеле замечено демонов: $_demons',
            ),
            Text('Здоровье роутера: $_health%', style: PortText.muted),
            Text('Волна: $_wave · Очки: $_score', style: PortText.muted),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PortButton(
            key: const ValueKey('doom-fire'),
            leading: const Icon(Icons.gps_fixed),
            onPressed: _demons == 0 ? null : _fire,
            child: const Text('ПЫЩ'),
          ),
          PortButton.outline(
            key: const ValueKey('doom-medkit'),
            onPressed: _health == 100 || _medkits == 0
                ? null
                : () => setState(() {
                    _health = math.min(100, _health + 15);
                    _medkits--;
                  }),
            child: Text('Аптечка ($_medkits)'),
          ),
          PortButton.outline(
            key: const ValueKey('doom-next-wave'),
            onPressed: _demons != 0
                ? null
                : () => setState(() {
                    _wave++;
                    _demons = math.min(20, 5 + _wave);
                    _medkits = 2;
                  }),
            child: const Text('Новая волна'),
          ),
        ],
      ),
    ],
  );
}

class _Calculator extends StatefulWidget {
  const _Calculator();
  @override
  State<_Calculator> createState() => _CalculatorState();
}

class _CalculatorState extends State<_Calculator> {
  String _screen = '0';
  double? _left;
  String? _op;
  bool _replace = false;
  void _tap(String key) => setState(() {
    if (key == 'C') {
      _screen = '0';
      _left = null;
      _op = null;
      _replace = false;
      return;
    }
    if (key == '⌫') {
      _screen = _screen.length > 1 && double.tryParse(_screen) != null
          ? _screen.substring(0, _screen.length - 1)
          : '0';
      _replace = false;
      return;
    }
    if (key == '±' || key == '÷8') {
      final value = double.tryParse(_screen);
      if (value == null) return;
      _screen = _format(key == '±' ? -value : value / 8);
      if (key == '÷8') {
        _left = null;
        _op = null;
        _replace = true;
      }
      return;
    }
    if ('+-×÷'.contains(key)) {
      if (_op != null && !_replace) _calculate();
      _left = double.tryParse(_screen);
      _op = _left == null ? null : key;
      _replace = true;
      return;
    }
    if (key != '=') {
      if (_replace || double.tryParse(_screen) == null) _screen = '0';
      _replace = false;
      if (key == '.') {
        if (!_screen.contains('.')) _screen += '.';
      } else if (_screen.length < 16) {
        _screen = _screen == '0' ? key : _screen + key;
      }
      return;
    }
    _calculate();
    _replace = true;
  });

  void _calculate() {
    final right = double.tryParse(_screen);
    if (_left == null || _op == null || right == null) return;
    final result = switch (_op) {
      '+' => _left! + right,
      '-' => _left! - right,
      '×' => _left! * right,
      '÷' => right == 0 ? double.nan : _left! / right,
      _ => right,
    };
    _screen = _format(result);
    _left = null;
    _op = null;
  }

  String _format(double result) {
    if (!result.isFinite) return 'ну нельзя';
    if (result.abs() >= 1e12) return result.toStringAsExponential(5);
    return result == result.roundToDouble()
        ? result.toStringAsFixed(0)
        : result
              .toStringAsFixed(8)
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: PortColors.secondary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          key: const ValueKey('calculator-screen'),
          _screen,
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 28),
        ),
      ),
      const SizedBox(height: 8),
      for (final row in const [
        ['⌫', '.', '±', '÷8'],
        ['7', '8', '9', '÷'],
        ['4', '5', '6', '×'],
        ['1', '2', '3', '-'],
        ['C', '0', '=', '+'],
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              for (final key in row)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: PortButton.outline(
                      key: ValueKey('calculator-key-$key'),
                      onPressed: () => _tap(key),
                      child: Text(key),
                    ),
                  ),
                ),
            ],
          ),
        ),
      Text(
        '÷8: Мбит/с → МБ/с. Без округления до целого пакета.',
        style: PortText.muted,
      ),
    ],
  );
}

class _Minecraft extends StatefulWidget {
  const _Minecraft();
  @override
  State<_Minecraft> createState() => _MinecraftState();
}

class _MinecraftState extends State<_Minecraft> {
  final _blocks = <int, int>{};
  int _material = 0;
  bool _night = false;
  static const _materials = [
    ('Трава', Color(0xFF4E9138)),
    ('Камень', Color(0xFF778899)),
    ('Дерево', Color(0xFF795548)),
  ];
  void _place() => setState(() {
    for (var i = 18; i >= 0; i -= 6) {
      for (var x = 0; x < 6; x++) {
        final cell = i + x;
        if (!_blocks.containsKey(cell)) {
          _blocks[cell] = _material;
          return;
        }
      }
    }
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        height: 130,
        decoration: BoxDecoration(
          color: _night ? const Color(0xFF101A38) : const Color(0xFF87CEEB),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            for (var y = 0; y < 4; y++)
              Expanded(
                child: Row(
                  children: [
                    for (var x = 0; x < 6; x++)
                      Expanded(
                        child: GestureDetector(
                          key: ValueKey('minecraft-cell-${y * 6 + x}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() {
                            final cell = y * 6 + x;
                            if (_blocks.containsKey(cell)) {
                              _blocks.remove(cell);
                            } else {
                              _blocks[cell] = _material;
                            }
                          }),
                          child: Container(
                            margin: const EdgeInsets.all(1),
                            color: _blocks.containsKey(y * 6 + x)
                                ? _materials[_blocks[y * 6 + x]!].$2
                                : Colors.transparent,
                            child: Icon(
                              _blocks.containsKey(y * 6 + x)
                                  ? Icons.view_in_ar
                                  : (_night ? Icons.star_outline : Icons.add),
                              size: 14,
                              color: _night
                                  ? const Color(0xFFB8C8FF)
                                  : const Color(0x55000000),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Блоков в мире: ${_blocks.length}/24 · ${_materials[_material].$1}',
        style: PortText.small,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PortButton(
            key: const ValueKey('minecraft-place'),
            leading: const Icon(Icons.add_box),
            onPressed: _blocks.length == 24 ? null : _place,
            child: const Text('Поставить блок'),
          ),
          PortButton.outline(
            key: const ValueKey('minecraft-material'),
            onPressed: () =>
                setState(() => _material = (_material + 1) % _materials.length),
            child: const Text('Материал'),
          ),
          PortButton.outline(
            key: const ValueKey('minecraft-day-night'),
            onPressed: () => setState(() => _night = !_night),
            child: Text(_night ? 'Сделать день' : 'Сделать ночь'),
          ),
          PortButton.outline(
            key: const ValueKey('minecraft-clear'),
            onPressed: () => setState(_blocks.clear),
            child: const Text('Новый мир'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        _blocks.length > 8
            ? 'Крипер увидел ваш трафик и одобряет.'
            : 'Строим кубический туннель. Клик по клетке ставит или убирает блок.',
        style: PortText.muted,
      ),
    ],
  );
}

class _Youtube extends StatefulWidget {
  const _Youtube();
  @override
  State<_Youtube> createState() => _YoutubeState();
}

class _YoutubeState extends State<_Youtube> {
  int _playing = 0;
  bool _paused = true;
  int _position = 0;
  final _likes = <int>{};
  Timer? _timer;
  static const _durations = [47, 30, 20];
  final titles = const [
    'Как настроить VPN за 47 секунд',
    '10 часов звука стабильного пинга',
    'Кот тестирует прокси-сервер',
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _paused) return;
      setState(() {
        if (++_position >= _durations[_playing]) {
          _position = _durations[_playing];
          _paused = true;
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _select(int index) => setState(() {
    _playing = index;
    _position = 0;
    _paused = false;
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF181818),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: GestureDetector(
          key: const ValueKey('youtube-player'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            if (_position == _durations[_playing]) _position = 0;
            _paused = !_paused;
          }),
          child: SizedBox.expand(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _paused
                        ? Icons.play_circle_fill
                        : [
                            Icons.security,
                            Icons.graphic_eq,
                            Icons.pets,
                          ][_playing],
                    color: const Color(0xFFFF3030),
                    size: 44,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _paused
                        ? 'Пауза'
                        : [
                            'Пакеты надевают шифрование: $_position/47',
                            'Стабильность пинга: ${10 + _position % 3} мс',
                            _position.isEven
                                ? 'Кот: мур-прокси'
                                : 'Кот проверяет пакеты…',
                          ][_playing],
                    style: PortText.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Офлайн-пародия: локальные мини-клипы, без сети и настоящего видео.',
        style: PortText.muted,
      ),
      Slider(
        key: const ValueKey('youtube-seek'),
        value: _position.toDouble(),
        max: _durations[_playing].toDouble(),
        onChanged: (value) => setState(() => _position = value.round()),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          PortButton.outline(
            key: const ValueKey('youtube-play-pause'),
            onPressed: () => setState(() {
              if (_position == _durations[_playing]) _position = 0;
              _paused = !_paused;
            }),
            child: Text(_paused ? 'Смотреть' : 'Пауза'),
          ),
          PortButton.outline(
            key: const ValueKey('youtube-next'),
            onPressed: () => _select((_playing + 1) % titles.length),
            child: const Text('Следующий'),
          ),
          PortButton.outline(
            key: const ValueKey('youtube-like'),
            onPressed: () => setState(() {
              if (!_likes.add(_playing)) _likes.remove(_playing);
            }),
            child: Text(
              _likes.contains(_playing) ? 'Нравится ♥' : 'Нравится ♡',
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < titles.length; i++)
        GestureDetector(
          key: ValueKey('youtube-clip-$i'),
          onTap: () => _select(i),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 5),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _playing == i ? PortColors.secondary : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              children: [
                Icon(
                  _playing == i ? Icons.volume_up : Icons.play_arrow,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(titles[i], style: PortText.small)),
              ],
            ),
          ),
        ),
      const SizedBox(height: 8),
      Text(
        '${_paused ? 'На паузе' : 'Сейчас играет'}: ${titles[_playing]} '
        '· $_position/${_durations[_playing]} с',
        style: PortText.muted,
      ),
    ],
  );
}
