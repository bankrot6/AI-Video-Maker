import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/video_poster_service.dart';
import 'magic_shimmer.dart';

/// Кадр из видео как обычная картинка.
///
/// Кадр уже посчитан и лежит в кэше — тогда он рисуется в том же кадре
/// отрисовки, без мигания заглушкой. Если платформа кадр не отдала (битый
/// файл, неизвестный контейнер), показывается [fallbackBuilder].
class VideoPosterImage extends StatefulWidget {
  const VideoPosterImage({
    super.key,
    required this.source,
    required this.fallbackBuilder,
    this.fit = BoxFit.cover,
    this.loadingBuilder,
    this.onLoaded,
  });

  /// Локальный путь или ссылка на видео.
  final String source;
  final WidgetBuilder fallbackBuilder;
  final BoxFit fit;
  final Widget Function(BuildContext context)? loadingBuilder;
  final VoidCallback? onLoaded;

  @override
  State<VideoPosterImage> createState() => _VideoPosterImageState();
}

class _VideoPosterImageState extends State<VideoPosterImage> {
  Uint8List? _poster;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(VideoPosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _poster = null;
      _failed = false;
      _load();
    }
  }

  void _load() {
    final source = widget.source;
    final cached = VideoPosterService().fromMemory(source);
    if (cached != null) {
      _poster = cached;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onLoaded?.call());
      return;
    }

    VideoPosterService().poster(source).then((bytes) {
      if (!mounted || widget.source != source) return;
      setState(() {
        _poster = bytes;
        _failed = bytes == null;
      });
      if (bytes != null) widget.onLoaded?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final poster = _poster;
    if (poster != null) {
      return Image.memory(
        poster,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (context, _, __) => widget.fallbackBuilder(context),
      );
    }
    if (_failed) return widget.fallbackBuilder(context);
    return widget.loadingBuilder?.call(context) ?? const MagicShimmer();
  }
}
