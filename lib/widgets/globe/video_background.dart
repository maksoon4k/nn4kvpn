import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

/// Полноэкранный фон из видеофайла юзера (`HomeBackground.customVideo`,
/// `AppSettings.customVideoPath`) — лупом, без звука. Аналог
/// `ShaderBackground`, но источник не шейдер, а произвольный видеофайл,
/// который юзер сам выбрал и который был скопирован в аппдату
/// (`custom_video_storage.dart`).
class VideoBackground extends StatefulWidget {
  final String filePath;
  final VideoPlayerController Function(String)? controllerFactory;

  const VideoBackground({
    super.key,
    required this.filePath,
    this.controllerFactory,
  });

  @override
  State<VideoBackground> createState() => _VideoBackgroundState();
}

class _VideoBackgroundState extends State<VideoBackground> {
  VideoPlayerController? _controller;
  bool _failed = false;
  int _generation = 0;
  final _pending = <VideoPlayerController>{};
  final _disposals = Expando<Future<void>>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VideoBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _generation++;
      final old = _controller;
      if (old != null) _disposeController(old);
      for (final pending in _pending.toList()) {
        _disposeController(pending);
      }
      _controller = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    VideoPlayerController? controller;
    var accepted = false;
    bool current() => mounted && generation == _generation;
    try {
      controller =
          widget.controllerFactory?.call(widget.filePath) ??
          VideoPlayerController.file(File(widget.filePath));
      _pending.add(controller);
      await controller.initialize();
      if (!current()) return;
      await controller.setLooping(true);
      if (!current()) return;
      await controller.setVolume(0);
      if (!current()) return;
      await controller.play();
      if (!current()) return;
      setState(() => _controller = controller);
      accepted = true;
    } catch (_) {
      // Файл мог быть удалён/повреждён/в неподдерживаемом формате извне
      // приложения — тихо остаёмся без фона, а не роняем экран подключения.
      if (current()) setState(() => _failed = true);
    } finally {
      _pending.remove(controller);
      if (!accepted && controller != null) await _disposeController(controller);
    }
  }

  Future<void> _disposeController(VideoPlayerController controller) {
    _pending.remove(controller);
    return _disposals[controller] ??= _release(controller);
  }

  Future<void> _release(VideoPlayerController controller) async {
    try {
      await controller.dispose();
    } catch (_) {
      // An obsolete or unavailable decoder cannot break the connection screen.
    }
  }

  @override
  void dispose() {
    _generation++;
    final controller = _controller;
    if (controller != null) _disposeController(controller);
    for (final pending in _pending.toList()) {
      _disposeController(pending);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed || controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}
