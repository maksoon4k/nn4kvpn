import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' show Icons, Slider;
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../../../widgets/port_ui/port_ui.dart';
import 'cassette_audio.dart';

typedef AudioControllerFactory = VideoPlayerController Function(String path);
typedef AudioFilePicker = Future<String?> Function();

Future<String?> pickLocalAudioFile() async {
  final result = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['wav', 'mp3', 'm4a', 'aac', 'wma'],
  );
  return result?.path;
}

class RecorderTool extends StatefulWidget {
  final CassetteAudioSource Function()? sourceFactory;
  final AudioControllerFactory? controllerFactory;
  final AudioFilePicker pickFile;

  const RecorderTool({
    super.key,
    this.sourceFactory,
    this.controllerFactory,
    this.pickFile = pickLocalAudioFile,
  });

  @override
  State<RecorderTool> createState() => _RecorderToolState();
}

class _RecorderToolState extends State<RecorderTool> {
  late final _source =
      widget.sourceFactory?.call() ?? TemporaryCassetteAudioSource();
  VideoPlayerController? _controller;
  final _initializing = <VideoPlayerController>{};
  final _releases = <VideoPlayerController, Future<void>>{};
  int _generation = 0;
  int _tape = 0;
  String? _localPath;
  String? _error;
  double _volume = .6;
  bool _loop = true;
  bool _loading = false;
  bool _commandPending = false;
  bool _picking = false;
  Duration? _seekPreview;

  String get _title => _localPath == null
      ? cassetteNames[_tape]
      : File(_localPath!).uri.pathSegments.last;
  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _release(VideoPlayerController controller) {
    _initializing.remove(controller);
    controller.removeListener(_changed);
    return _releases.putIfAbsent(controller, () async {
      try {
        if (controller.value.isInitialized) await controller.pause();
      } catch (_) {
        /* Disposal below remains mandatory. */
      }
      try {
        await controller.dispose();
      } catch (_) {
        /* Closing never breaks NN4K. */
      }
    });
  }

  Future<void> _load({required bool play}) {
    final generation = ++_generation;
    final tape = _tape;
    final path = _localPath;
    final old = _controller;
    _controller = null;
    for (final pending in _initializing.toList()) {
      unawaited(_release(pending));
    }
    setState(() {
      _loading = true;
      _error = null;
      _seekPreview = null;
    });
    return _initialize(generation, tape, path, old, play);
  }

  Future<void> _initialize(
    int generation,
    int tape,
    String? path,
    VideoPlayerController? old,
    bool play,
  ) async {
    VideoPlayerController? controller;
    var accepted = false;
    bool current() => mounted && generation == _generation;
    try {
      if (old != null) await _release(old);
      if (!current()) return;
      final prepared = path ?? await _source.prepare(tape);
      if (!current()) return;
      controller =
          widget.controllerFactory?.call(prepared) ??
          VideoPlayerController.file(File(prepared));
      _initializing.add(controller);
      await controller.initialize();
      if (!current()) return;
      if (!controller.value.isInitialized || controller.value.hasError) {
        throw StateError('Не удалось декодировать аудио.');
      }
      await controller.setLooping(_loop);
      if (!current()) return;
      await controller.setVolume(_volume);
      if (!current()) return;
      if (play) await controller.play();
      if (!current()) return;
      controller.addListener(_changed);
      setState(() => _controller = controller);
      _initializing.remove(controller);
      accepted = true;
    } catch (error) {
      if (current()) {
        setState(
          () => _error =
              'Не удалось воспроизвести: $error. '
              'Проверьте устройство вывода и громкость Windows; попробуйте WAV/MP3. '
              'В Windows N/KN нужен Media Feature Pack.',
        );
      }
    } finally {
      if (!accepted && controller != null) await _release(controller);
      if (current()) setState(() => _loading = false);
    }
  }

  Future<void> _command(
    Future<void> Function(VideoPlayerController) command,
  ) async {
    final controller = _controller;
    if (controller == null || _commandPending || _loading) return;
    final generation = _generation;
    setState(() {
      _commandPending = true;
      _error = null;
    });
    try {
      await command(controller);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Ошибка воспроизведения: $error');
      }
    } finally {
      if (mounted) setState(() => _commandPending = false);
    }
  }

  Future<void> _toggle() async {
    if (_loading || _commandPending) return;
    if (_controller == null) {
      await _load(play: true);
      return;
    }
    await _command((controller) async {
      if (controller.value.isPlaying && !controller.value.isCompleted) {
        await controller.pause();
      } else {
        if (controller.value.isCompleted) {
          await controller.seekTo(Duration.zero);
        }
        if (mounted && identical(_controller, controller)) {
          await controller.play();
        }
      }
    });
  }

  Future<void> _nextTape() async {
    final playing = _controller?.value.isPlaying ?? false;
    setState(() {
      _tape = (_tape + 1) % cassetteNames.length;
      _localPath = null;
    });
    await _load(play: playing);
  }

  Future<void> _pick() async {
    if (_picking) return;
    final generation = _generation;
    setState(() => _picking = true);
    try {
      final path = await widget.pickFile();
      if (!mounted || generation != _generation || path == null) return;
      setState(() => _localPath = path);
      await _load(play: true);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Не удалось открыть аудиофайл: $error');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    final controller = _controller;
    if (controller != null) unawaited(_release(controller));
    for (final pending in _initializing.toList()) {
      unawaited(_release(pending));
    }
    unawaited(_cleanup());
    super.dispose();
  }

  Future<void> _cleanup() async {
    await Future.wait(_releases.values.toList());
    try {
      await _source.dispose();
    } catch (_) {
      /* Private source cleanup only. */
    }
  }

  String _time(Duration value) =>
      '${value.inMinutes.toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final value = _controller?.value;
    final playing = value?.isPlaying == true && value?.isCompleted != true;
    final duration =
        value?.duration ?? const Duration(seconds: cassetteSeconds);
    final position = _seekPreview ?? value?.position ?? Duration.zero;
    final busy = _loading || _commandPending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 82,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: PortColors.secondary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${_time(position)} / ${_time(duration)}',
            key: const ValueKey('recorder-time'),
            style: const TextStyle(fontSize: 27),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Кассета: $_title',
          key: const ValueKey('recorder-title'),
          style: PortText.small,
        ),
        Slider(
          key: const ValueKey('recorder-seek'),
          value: position.inMilliseconds.toDouble().clamp(
            0.0,
            duration.inMilliseconds.toDouble(),
          ),
          max: duration.inMilliseconds > 0
              ? duration.inMilliseconds.toDouble()
              : 1,
          onChanged: _controller == null || busy
              ? null
              : (milliseconds) => setState(
                  () => _seekPreview = Duration(
                    milliseconds: milliseconds.round(),
                  ),
                ),
          onChangeEnd: _controller == null || busy
              ? null
              : (milliseconds) async {
                  await _command(
                    (controller) => controller.seekTo(
                      Duration(milliseconds: milliseconds.round()),
                    ),
                  );
                  if (mounted) setState(() => _seekPreview = null);
                },
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PortButton(
              key: const ValueKey('recorder-play'),
              leading: Icon(playing ? Icons.pause : Icons.play_arrow, size: 17),
              onPressed: busy ? null : _toggle,
              child: Text(
                _loading
                    ? 'Подготовка…'
                    : playing
                    ? 'Пауза'
                    : 'Воспроизвести',
              ),
            ),
            PortButton.outline(
              key: const ValueKey('recorder-rewind'),
              leading: const Icon(Icons.fast_rewind, size: 17),
              onPressed: _controller == null || busy
                  ? null
                  : () => _command((controller) async {
                      await controller.pause();
                      if (mounted && identical(_controller, controller)) {
                        await controller.seekTo(Duration.zero);
                      }
                    }),
              child: const Text('Стоп / Перемотать'),
            ),
            PortButton.outline(
              key: const ValueKey('recorder-tape'),
              onPressed: busy ? null : _nextTape,
              child: const Text('Сменить кассету'),
            ),
            PortButton.outline(
              key: const ValueKey('recorder-file'),
              onPressed: busy || _picking ? null : _pick,
              child: Text(_picking ? 'Выбор…' : 'Свой аудиофайл'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Громкость магнитофона: ${(_volume * 100).round()}%',
          style: PortText.small,
        ),
        Slider(
          key: const ValueKey('recorder-volume'),
          value: _volume,
          onChanged: busy ? null : (volume) => setState(() => _volume = volume),
          onChangeEnd: busy
              ? null
              : (volume) =>
                    _command((controller) => controller.setVolume(volume)),
        ),
        PortSwitch(
          key: const ValueKey('recorder-loop'),
          value: _loop,
          label: const Text('Повторять кассету'),
          onChanged: busy
              ? null
              : (loop) {
                  setState(() => _loop = loop);
                  unawaited(
                    _command((controller) => controller.setLooping(loop)),
                  );
                },
        ),
        const SizedBox(height: 10),
        Text(
          _error ??
              value?.errorDescription ??
              (_loading
                  ? 'Готовим локальную кассету…'
                  : 'Настоящее воспроизведение через системный аудиодекодер. '
                        'Три собственные звуковые петли или ваш WAV/MP3/M4A/AAC/WMA. '
                        'Микрофон не используется; звук останавливается при закрытии инструмента.'),
          key: const ValueKey('recorder-status'),
          style: PortText.muted,
        ),
      ],
    );
  }
}
