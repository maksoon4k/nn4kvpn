import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../widgets/port_ui/port_ui.dart';
import 'voxel_renderer.dart';
import 'voxel_world.dart';

class MinecraftTool extends StatefulWidget {
  final VoxelSandbox Function()? createSandbox;
  const MinecraftTool({super.key, this.createSandbox});
  @override
  State<MinecraftTool> createState() => _MinecraftToolState();
}

class _MinecraftToolState extends State<MinecraftTool>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late var _sandbox = widget.createSandbox?.call() ?? VoxelSandbox();
  final _focus = FocusNode();
  final _keys = <LogicalKeyboardKey>{};
  late final Ticker _ticker;
  Duration? _lastFrame;
  Offset? _pointerStart;
  bool _dragged = false;
  bool _appActive = true;
  int _pointerButtons = 0;
  int _seed = 1337;
  String? _message;
  static final _movementKeys = {
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
  };
  static const materialNames = [
    'Трава',
    'Камень',
    'Дерево',
    'Листва',
    'Песок',
    'Кирпич',
  ];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keys.clear();
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (!_appActive) {
      _keys.clear();
      _ticker.stop();
    } else if (_focus.hasFocus && !_sandbox.player.grounded(_sandbox.world)) {
      _startTicking();
    }
  }

  void _startTicking() {
    if (_ticker.isActive || !_appActive) return;
    _lastFrame = null;
    _ticker.start();
  }

  int _axis(LogicalKeyboardKey positive, LogicalKeyboardKey negative) =>
      (_keys.contains(positive) ? 1 : 0) - (_keys.contains(negative) ? 1 : 0);
  void _tick(Duration elapsed) {
    if (!_focus.hasFocus || !_appActive) {
      _keys.clear();
      _ticker.stop();
      return;
    }
    final dt = _lastFrame == null
        ? 1 / 60
        : ((elapsed - _lastFrame!).inMicroseconds / 1000000).clamp(0.0, .05);
    _lastFrame = elapsed;
    setState(() {
      _sandbox.player.look(
        _axis(LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowLeft) *
            dt *
            1.8,
        _axis(LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown) *
            dt *
            1.8,
      );
      _sandbox.player.step(
        _sandbox.world,
        dt,
        forwardInput: _axis(
          LogicalKeyboardKey.keyW,
          LogicalKeyboardKey.keyS,
        ).toDouble(),
        strafeInput: _axis(
          LogicalKeyboardKey.keyD,
          LogicalKeyboardKey.keyA,
        ).toDouble(),
      );
    });
    if (_keys.isEmpty &&
        _sandbox.player.grounded(_sandbox.world) &&
        _sandbox.player.verticalVelocity == 0) {
      _ticker.stop();
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (_movementKeys.contains(key)) {
      if (event is KeyUpEvent) {
        _keys.remove(key);
      } else {
        _keys.add(key);
        _startTicking();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent && _sandbox.player.jump(_sandbox.world)) {
        _startTicking();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.keyE) {
        _block(true);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyQ) {
        _block(false);
        return KeyEventResult.handled;
      }
      final number = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
      ].indexOf(key);
      if (number >= 0) {
        setState(() => _sandbox.material = VoxelMaterial.values[number]);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored; // Escape belongs to the surrounding dialog.
  }

  void _block(bool remove) {
    setState(() {
      final changed = remove ? _sandbox.removeTarget() : _sandbox.placeTarget();
      _message = changed
          ? (remove ? 'Блок убран.' : 'Блок поставлен.')
          : 'Наведитесь на близкий блок. Нельзя строить внутри игрока или убирать основание мира.';
    });
    if (!_sandbox.player.grounded(_sandbox.world)) _startTicking();
  }

  void _pointerDown(PointerDownEvent event) {
    _focus.requestFocus();
    _pointerStart = event.localPosition;
    _pointerButtons = event.buttons;
    _dragged = false;
  }

  void _pointerMove(PointerMoveEvent event) {
    final start = _pointerStart;
    if (start == null) return;
    if ((event.localPosition - start).distance > 3) _dragged = true;
    if (_dragged) {
      setState(
        () =>
            _sandbox.player.look(event.delta.dx * .006, -event.delta.dy * .006),
      );
    }
  }

  void _pointerUp(PointerUpEvent event) {
    if (!_dragged && _pointerStart != null) {
      if (_pointerButtons & kPrimaryMouseButton != 0) {
        _block(true);
      } else if (_pointerButtons & kSecondaryMouseButton != 0) {
        _block(false);
      }
    }
    _pointerStart = null;
  }

  void _newWorld() {
    _ticker.stop();
    _keys.clear();
    final material = _sandbox.material;
    setState(() {
      _sandbox =
          widget.createSandbox?.call() ??
          VoxelSandbox(world: VoxelWorld(seed: ++_seed));
      _sandbox.material = material;
      _message = null;
    });
  }

  Widget _moveButton(String label, LogicalKeyboardKey key) => Listener(
    onPointerDown: (_) {
      _focus.requestFocus();
      _keys.add(key);
      _startTicking();
    },
    onPointerUp: (_) => _keys.remove(key),
    onPointerCancel: (_) => _keys.remove(key),
    child: PortButton.outline(
      onPressed: () {
        _focus.requestFocus();
        setState(
          () => _sandbox.player.step(
            _sandbox.world,
            .05,
            forwardInput: key == LogicalKeyboardKey.keyW
                ? 1
                : key == LogicalKeyboardKey.keyS
                ? -1
                : 0,
            strafeInput: key == LogicalKeyboardKey.keyD
                ? 1
                : key == LogicalKeyboardKey.keyA
                ? -1
                : 0,
          ),
        );
      },
      child: Text(label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final target = _sandbox.target;
    final position = _sandbox.player.position;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Свой лёгкий 3D-блоковый мир · ${_sandbox.world.width}×${_sandbox.world.height}×${_sandbox.world.depth}',
          style: PortText.small,
        ),
        const SizedBox(height: 8),
        Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _key,
          onFocusChange: (focused) {
            if (!focused) {
              _keys.clear();
              _ticker.stop();
            } else if (!_sandbox.player.grounded(_sandbox.world)) {
              _startTicking();
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Listener(
              key: const ValueKey('minecraft-viewport'),
              onPointerDown: _pointerDown,
              onPointerMove: _pointerMove,
              onPointerUp: _pointerUp,
              onPointerCancel: (_) => _pointerStart = null,
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  setState(
                    () => _sandbox.material =
                        VoxelMaterial.values[(_sandbox.material.index +
                                (event.scrollDelta.dy > 0 ? 1 : -1)) %
                            VoxelMaterial.values.length],
                  );
                }
              },
              child: RepaintBoundary(
                child: SizedBox(
                  width: double.infinity,
                  height: math.min(
                    340,
                    math.max(160, MediaQuery.sizeOf(context).height * .42),
                  ),
                  child: CustomPaint(
                    key: const ValueKey('minecraft-3d-render'),
                    painter: VoxelWorldPainter(_sandbox),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'В мире: ${_sandbox.world.blockCount} блоков · ${materialNames[_sandbox.material.index]} '
          '· X ${position.x.toStringAsFixed(1)} Y ${position.y.toStringAsFixed(1)} Z ${position.z.toStringAsFixed(1)}',
          key: const ValueKey('minecraft-hud'),
          style: PortText.small,
        ),
        Text(
          target == null
              ? 'Прицел: нет блока в пределах 6 м'
              : 'Прицел: ${materialNames[target.material.index]} · ${target.distance.toStringAsFixed(1)} м',
          key: const ValueKey('minecraft-target'),
          style: PortText.muted,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PortButton(
              key: const ValueKey('minecraft-place'),
              leading: const Icon(Icons.add_box, size: 16),
              onPressed: () => _block(false),
              child: const Text('Поставить блок · Q'),
            ),
            PortButton.outline(
              key: const ValueKey('minecraft-break'),
              onPressed: () => _block(true),
              child: const Text('Убрать блок · E'),
            ),
            PortButton.outline(
              key: const ValueKey('minecraft-material'),
              onPressed: () => setState(
                () => _sandbox.material =
                    VoxelMaterial.values[(_sandbox.material.index + 1) %
                        VoxelMaterial.values.length],
              ),
              child: const Text('Материал · 1–6'),
            ),
            PortButton.outline(
              key: const ValueKey('minecraft-jump'),
              onPressed: () {
                _focus.requestFocus();
                if (_sandbox.player.jump(_sandbox.world)) _startTicking();
              },
              child: const Text('Прыжок · Space'),
            ),
            PortButton.outline(
              key: const ValueKey('minecraft-day-night'),
              onPressed: () => setState(() => _sandbox.night = !_sandbox.night),
              child: Text(_sandbox.night ? 'Сделать день' : 'Сделать ночь'),
            ),
            PortButton.outline(
              key: const ValueKey('minecraft-clear'),
              onPressed: _newWorld,
              child: const Text('Новый мир'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _moveButton('← A', LogicalKeyboardKey.keyA),
            _moveButton('↑ W', LogicalKeyboardKey.keyW),
            _moveButton('↓ S', LogicalKeyboardKey.keyS),
            _moveButton('D →', LogicalKeyboardKey.keyD),
            PortButton.outline(
              onPressed: () => setState(() => _sandbox.player.look(-.3, 0)),
              child: const Text('Поворот ←'),
            ),
            PortButton.outline(
              onPressed: () => setState(() => _sandbox.player.look(.3, 0)),
              child: const Text('Поворот →'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _message ??
              'Кликните по миру: WASD — ходьба, стрелки или перетаскивание мыши — обзор. '
                  'ЛКМ — убрать, ПКМ — поставить. Есть гравитация, столкновения и прыжок. Мир локальный и хранится только до закрытия игры. '
                  'Это собственная мини-игра, не официальный Minecraft.',
          style: PortText.muted,
        ),
      ],
    );
  }
}
