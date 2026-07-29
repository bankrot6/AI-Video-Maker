import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'video_player_controls.dart';

/// Набор элементов управления поверх видео.
enum VideoControlsMode {
  /// Без управления — для превью в сетках и списках.
  none,

  /// Только play/pause по тапу.
  tapToPlay,

  /// Панель с паузой, ползунком перемотки, временем и звуком.
  full,
}

/// Проигрывает сгенерированный клип с автостартом и зацикливанием.
///
/// Источник может быть и локальным файлом (клиентская генерация сохраняет MP4
/// в документы приложения), и HTTP-ссылкой (результат, поднятый в сторадж).
class GeneratedVideoView extends StatefulWidget {
  const GeneratedVideoView({
    super.key,
    required this.url,
    this.fit = BoxFit.contain,
    this.autoPlay = true,
    this.loop = true,
    this.controls = VideoControlsMode.full,
    this.onFullscreen,
    this.loadingBuilder,
    this.errorBuilder,
    this.onLoaded,
  });

  final String url;
  final BoxFit fit;
  final bool autoPlay;
  final bool loop;
  final VideoControlsMode controls;

  /// Кнопка полного экрана в панели управления; без обработчика не показывается.
  final VoidCallback? onFullscreen;
  final WidgetBuilder? loadingBuilder;
  final WidgetBuilder? errorBuilder;
  final VoidCallback? onLoaded;

  @override
  State<GeneratedVideoView> createState() => _GeneratedVideoViewState();
}

class _GeneratedVideoViewState extends State<GeneratedVideoView> {
  static const Duration _autoHideDelay = Duration(seconds: 3);

  VideoPlayerController? _controller;
  bool _failed = false;
  bool _controlsVisible = true;
  Timer? _autoHideTimer;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(GeneratedVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _disposeController();
      _failed = false;
      _controlsVisible = true;
      _initialize();
    }
  }

  Future<void> _initialize() async {
    final url = widget.url.trim();
    final isRemote = url.startsWith('http://') || url.startsWith('https://');
    final controller = isRemote
        ? VideoPlayerController.networkUrl(Uri.parse(url))
        : VideoPlayerController.file(File(url));
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(widget.loop);
      if (widget.autoPlay) {
        await controller.play();
        _scheduleAutoHide();
      }
      setState(() {});
      widget.onLoaded?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  /// Панель мешает смотреть клип, поэтому во время воспроизведения она уходит
  /// сама; на паузе остаётся видимой, чтобы можно было перемотать.
  void _scheduleAutoHide() {
    _autoHideTimer?.cancel();
    if (widget.controls != VideoControlsMode.full) return;
    _autoHideTimer = Timer(_autoHideDelay, () {
      if (!mounted) return;
      if (_controller?.value.isPlaying != true) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleAutoHide();
  }

  void _disposeController() {
    _autoHideTimer?.cancel();
    final controller = _controller;
    _controller = null;
    controller?.dispose();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _onSurfaceTap() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    switch (widget.controls) {
      case VideoControlsMode.none:
        return;
      case VideoControlsMode.tapToPlay:
        setState(() {
          if (controller.value.isPlaying) {
            controller.pause();
          } else {
            controller.play();
          }
        });
      case VideoControlsMode.full:
        if (_controlsVisible) {
          setState(() => _controlsVisible = false);
          _autoHideTimer?.cancel();
        } else {
          _showControls();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return widget.errorBuilder?.call(context) ??
          const Center(child: Icon(Icons.broken_image));
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return widget.loadingBuilder?.call(context) ??
          const Center(child: CircularProgressIndicator());
    }

    final video = FittedBox(
      fit: widget.fit,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );

    if (widget.controls == VideoControlsMode.none) return video;

    return GestureDetector(
      onTap: _onSurfaceTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          video,
          if (widget.controls == VideoControlsMode.tapToPlay)
            _CenterPlayBadge(visible: !controller.value.isPlaying)
          else
            // Панель занимает высоту по содержимому и прижата к нижнему краю
            // кадра: растянутая на всю высоту, она уводила бы кнопки в центр.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildFullControls(controller),
            ),
        ],
      ),
    );
  }

  Widget _buildFullControls(VideoPlayerController controller) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final visible = _controlsVisible || !value.isPlaying;
        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: VideoPlayerControls(
              controller: controller,
              onFullscreen: widget.onFullscreen,
              onInteraction: _showControls,
            ),
          ),
        );
      },
    );
  }
}

class _CenterPlayBadge extends StatelessWidget {
  const _CenterPlayBadge({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Center(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.play_arrow_rounded,
          color: Colors.white,
          size: 36,
        ),
      ),
    );
  }
}
