import 'package:flutter/material.dart';

import '../services/generated_media.dart';
import '../services/proxied_image_service.dart';
import 'generated_video_view.dart';
import 'magic_shimmer.dart';
import 'proxied_network_image.dart';

/// Показывает результат генерации, сам выбирая плеер или картинку.
///
/// Повторяет API [ProxiedNetworkImage], поэтому места вывода результата
/// переключаются на видео без изменения остального кода. Изображения остаются
/// поддержанными: в галерее ещё живут превью пресетов и старые генерации.
class GeneratedMediaView extends StatelessWidget {
  const GeneratedMediaView({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.loadingBuilder,
    this.errorBuilder,
    this.onLoaded,
    this.autoPlay = true,
    this.videoControls = VideoControlsMode.full,
    this.onFullscreen,
  });

  final String url;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget Function(BuildContext context)? loadingBuilder;
  final Widget Function(BuildContext context)? errorBuilder;
  final VoidCallback? onLoaded;
  final bool autoPlay;
  final VideoControlsMode videoControls;

  /// Кнопка полного экрана в панели управления видео.
  final VoidCallback? onFullscreen;

  @override
  Widget build(BuildContext context) {
    return _MediaSwitcher(
      url: url,
      fit: fit,
      cacheWidth: cacheWidth,
      autoPlay: autoPlay,
      loop: true,
      videoControls: videoControls,
      onFullscreen: onFullscreen,
      loadingBuilder: loadingBuilder,
      errorBuilder: errorBuilder,
      onLoaded: onLoaded,
    );
  }
}

/// Превью для сеток и списков: видео не проигрывается, чтобы не держать
/// несколько декодеров одновременно, — вместо этого рисуется бейдж с иконкой.
class GeneratedMediaThumbnail extends StatelessWidget {
  const GeneratedMediaThumbnail({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.loadingBuilder,
    this.errorBuilder,
  });

  final String url;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget Function(BuildContext context)? loadingBuilder;
  final Widget Function(BuildContext context)? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return _MediaSwitcher(
      url: url,
      fit: fit,
      cacheWidth: cacheWidth,
      autoPlay: false,
      loop: false,
      videoControls: VideoControlsMode.none,
      videoBadge: true,
      loadingBuilder: loadingBuilder,
      errorBuilder: errorBuilder,
    );
  }
}

enum _MediaKind { unknown, image, video }

/// Выбирает между картинкой и плеером.
///
/// Расширение в ссылке — не всегда доступный признак: у записей, созданных до
/// того, как расширение стало попадать в имя файла, результат лежит по URL
/// Appwrite или Firebase без него. Поэтому неопознанная ссылка проверяется по
/// сигнатуре скачанных байтов. Загрузка идёт через [ProxiedImageService], у
/// которого есть кэш, так что картинка ниже не качается второй раз.
class _MediaSwitcher extends StatefulWidget {
  const _MediaSwitcher({
    required this.url,
    required this.fit,
    required this.autoPlay,
    required this.loop,
    required this.videoControls,
    this.onFullscreen,
    this.cacheWidth,
    this.videoBadge = false,
    this.loadingBuilder,
    this.errorBuilder,
    this.onLoaded,
  });

  final String url;
  final BoxFit fit;
  final bool autoPlay;
  final bool loop;
  final VideoControlsMode videoControls;
  final VoidCallback? onFullscreen;
  final int? cacheWidth;
  final bool videoBadge;
  final Widget Function(BuildContext context)? loadingBuilder;
  final Widget Function(BuildContext context)? errorBuilder;
  final VoidCallback? onLoaded;

  @override
  State<_MediaSwitcher> createState() => _MediaSwitcherState();
}

class _MediaSwitcherState extends State<_MediaSwitcher> {
  late _MediaKind _kind;

  @override
  void initState() {
    super.initState();
    _resolveKind();
  }

  @override
  void didUpdateWidget(_MediaSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _resolveKind();
  }

  void _resolveKind() {
    if (GeneratedMedia.isVideo(widget.url)) {
      _kind = _MediaKind.video;
      return;
    }

    final cached = ProxiedImageService().getFromMemory(widget.url);
    if (cached != null) {
      _kind = GeneratedMedia.looksLikeVideoBytes(cached)
          ? _MediaKind.video
          : _MediaKind.image;
      return;
    }

    _kind = _MediaKind.unknown;
    _sniffKind(widget.url);
  }

  Future<void> _sniffKind(String url) async {
    final bytes = await ProxiedImageService().downloadImage(url);
    if (!mounted || widget.url != url) return;
    setState(() {
      _kind = bytes != null && GeneratedMedia.looksLikeVideoBytes(bytes)
          ? _MediaKind.video
          : _MediaKind.image;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_kind) {
      case _MediaKind.video:
        return _buildVideo(context);
      case _MediaKind.unknown:
        return widget.loadingBuilder?.call(context) ?? const MagicShimmer();
      case _MediaKind.image:
        return ProxiedNetworkImage(
          url: widget.url,
          fit: widget.fit,
          cacheWidth: widget.cacheWidth,
          loadingBuilder: widget.loadingBuilder,
          errorBuilder: widget.errorBuilder,
          onLoaded: widget.onLoaded,
        );
    }
  }

  Widget _buildVideo(BuildContext context) {
    final video = GeneratedVideoView(
      url: widget.url,
      fit: widget.fit,
      autoPlay: widget.autoPlay,
      loop: widget.loop,
      controls: widget.videoControls,
      onFullscreen: widget.onFullscreen,
      loadingBuilder: widget.loadingBuilder,
      errorBuilder: widget.errorBuilder,
      onLoaded: widget.onLoaded,
    );

    if (!widget.videoBadge) return video;

    return Stack(
      fit: StackFit.expand,
      children: [
        video,
        Positioned(
          right: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
        ),
      ],
    );
  }
}
