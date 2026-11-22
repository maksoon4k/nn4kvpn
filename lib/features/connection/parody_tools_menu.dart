import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Colors, Icons, Slider;
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
  bool _open = false;

  void _show(String title, Widget body) {
    setState(() => _open = false);
    showPortDialog<void>(
      context: context,
      builder: (_) => PortDialog(
        title: Text(title),
        description: const Text(
          'Пасхалка NN4K. Никаких лишних процессов — только вайб.',
        ),
        child: body,
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

    return SizedBox(
      width: 184,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomRight,
        children: [
          if (_open)
            Positioned(
              right: 0,
              bottom: 48,
              child: Container(
                width: 184,
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in entries) _MenuRow(entry: entry),
                  ],
                ),
              ),
            ),
          PortIconButton.secondary(
            size: 40,
            icon: Icon(_open ? Icons.close : Icons.grid_view, size: 18),
            onPressed: () => setState(() => _open = !_open),
          ),
        ],
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
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: entry.action,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          Icon(entry.icon, size: 16, color: PortColors.mutedForeground),
          const SizedBox(width: 10),
          Text(entry.label, style: PortText.small),
        ],
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
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _beamPreview(_distance, _width, _height),
      const SizedBox(height: 12),
      Text('Дальность: ${_distance.round()} км', style: PortText.small),
      Slider(
        value: _distance,
        min: 1,
        max: 10000,
        onChanged: (v) => setState(() => _distance = v),
      ),
      Text('Ширина луча: ${_width.round()}°', style: PortText.small),
      Slider(
        value: _width,
        min: 10,
        max: 360,
        onChanged: (v) => setState(() => _width = v),
      ),
      Text('Высота луча: ${_height.round()} м', style: PortText.small),
      Slider(
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
                          const Color(0xFFFFF5AA).withValues(alpha: .8),
                          const Color(0xFFFFF5AA).withValues(alpha: .02),
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
  void _toggle() {
    setState(() => _recording = !_recording);
    _timer?.cancel();
    if (_recording)
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
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
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          PortButton(
            child: Text(_recording ? 'Стоп' : 'Запись'),
            leading: Icon(_recording ? Icons.stop : Icons.fiber_manual_record),
            onPressed: _toggle,
          ),
          PortButton.outline(
            child: const Text('Перемотать'),
            leading: const Icon(Icons.fast_rewind),
            onPressed: () => setState(() => _seconds = 0),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        _recording
            ? 'Ш-ш-ш... записываем звук шифрования.'
            : 'Вставьте кассету или представьте, что вставили.',
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
  void _fire() => setState(() {
    if (_demons > 0) _demons--;
    _health = math.max(1, _health - 3).toInt();
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        height: 145,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A0A0A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'D O O M  //  VPN edition',
              style: TextStyle(letterSpacing: 2, color: Color(0xFFFF6A45)),
            ),
            const Spacer(),
            Text(
              _demons == 0
                  ? 'Сеть очищена. Демоны разлогинились.'
                  : 'В туннеле замечено демонов: $_demons',
            ),
            Text('Здоровье роутера: $_health%', style: PortText.muted),
          ],
        ),
      ),
      const SizedBox(height: 12),
      PortButton(
        child: const Text('ПЫЩ'),
        leading: const Icon(Icons.gps_fixed),
        onPressed: _fire,
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
  void _tap(String key) => setState(() {
    if ('+-×÷'.contains(key)) {
      _left = double.tryParse(_screen);
      _op = key;
      _screen = '0';
      return;
    }
    if (key == 'C') {
      _screen = '0';
      return;
    }
    if (key != '=') {
      _screen = _screen == '0' ? key : _screen + key;
      return;
    }
    final right = double.tryParse(_screen);
    if (_left == null || right == null) return;
    final result = switch (_op) {
      '+' => _left! + right,
      '-' => _left! - right,
      '×' => _left! * right,
      '÷' => right == 0 ? double.nan : _left! / right,
      _ => right,
    };
    _screen = result.isNaN
        ? 'ну нельзя'
        : result == result.roundToDouble()
        ? result.round().toString()
        : result.toStringAsFixed(2);
    _left = null;
  });
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
          _screen,
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 28),
        ),
      ),
      const SizedBox(height: 8),
      for (final row in const [
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
                      child: Text(key),
                      onPressed: () => _tap(key),
                    ),
                  ),
                ),
            ],
          ),
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
  int _blocks = 0;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        height: 130,
        decoration: BoxDecoration(
          color: const Color(0xFF87CEEB),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          children: [
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Wrap(
                children: List.generate(
                  18,
                  (i) => Container(
                    width: 24,
                    height: 30 + (i % 3) * 12,
                    color: i.isEven
                        ? const Color(0xFF4E9138)
                        : const Color(0xFF795548),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text('Блоков поставлено: $_blocks', style: PortText.small),
      const SizedBox(height: 8),
      PortButton(
        child: const Text('Поставить блок'),
        leading: const Icon(Icons.add_box),
        onPressed: () => setState(() => _blocks++),
      ),
      const SizedBox(height: 8),
      Text(
        _blocks > 8
            ? 'Крипер увидел ваш трафик и одобряет.'
            : 'Строим приватный кубический туннель.',
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
  final titles = const [
    'Как настроить VPN за 47 секунд',
    '10 часов звука стабильного пинга',
    'Кот тестирует прокси-сервер',
  ];
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
        child: const Icon(
          Icons.play_circle_fill,
          color: Color(0xFFFF3030),
          size: 52,
        ),
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < titles.length; i++)
        GestureDetector(
          onTap: () => setState(() => _playing = i),
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
      Text('Сейчас играет: ${titles[_playing]}', style: PortText.muted),
    ],
  );
}
