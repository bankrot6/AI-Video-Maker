import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/proxied_image_service.dart';
import 'magic_shimmer.dart';

class ProxiedNetworkImage extends StatefulWidget {
  const ProxiedNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.loadingBuilder,
    this.errorBuilder,
    this.onLoaded,
    this.placeholder,
    this.errorWidget,
  });

  final String url;
  final BoxFit fit;
  final int? cacheWidth;
  final Widget Function(BuildContext context)? loadingBuilder;
  final Widget Function(BuildContext context)? errorBuilder;
  final VoidCallback? onLoaded;
  @Deprecated('Use loadingBuilder instead')
  final Widget? placeholder;
  @Deprecated('Use errorBuilder instead')
  final Widget? errorWidget;

  String get imageUrl => url;

  @override
  State<ProxiedNetworkImage> createState() => _ProxiedNetworkImageState();
}

class _ProxiedNetworkImageState extends State<ProxiedNetworkImage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  Uint8List? _imageBytes;
  bool _error = false;
  String? _activeUrl;
  bool _appearedFromNetwork = false;

  late final AnimationController _fadeController;

  @override
  bool get wantKeepAlive => _imageBytes != null;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _resolveImage();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ProxiedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _appearedFromNetwork = false;
      _resolveImage();
    }
  }

  void _resolveImage() {
    final cached = ProxiedImageService().getFromMemory(widget.url);

    if (cached != null) {
      _imageBytes = cached;
      _error = false;
      _activeUrl = widget.url;
      _fadeController.value = 1.0;
      updateKeepAlive();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLoaded?.call();
      });
      return;
    }

    _error = false;
    _activeUrl = widget.url;
    if (_imageBytes != null) {
      _imageBytes = null;
      updateKeepAlive();
    }
    _fadeController.reset();
    _loadAsync();
  }

  Future<void> _loadAsync() async {
    final url = widget.url;
    _activeUrl = url;

    try {
      final bytes = await ProxiedImageService().downloadImage(url);
      if (!mounted || _activeUrl != url) return;

      if (bytes != null) {
        setState(() {
          _imageBytes = bytes;
          _error = false;
          _appearedFromNetwork = true;
        });
        updateKeepAlive();
        await _fadeController.forward(from: 0);
        if (mounted) widget.onLoaded?.call();
      } else {
        setState(() => _error = _imageBytes == null);
      }
    } catch (_) {
      if (!mounted || _activeUrl != url) return;
      setState(() => _error = _imageBytes == null);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_imageBytes != null) {
      final image = Image.memory(
        _imageBytes!,
        fit: widget.fit,
        cacheWidth: widget.cacheWidth,
        gaplessPlayback: true,
      );

      if (!_appearedFromNetwork) return image;

      return FadeTransition(
        opacity: CurvedAnimation(
          parent: _fadeController,
          curve: Curves.easeOut,
        ),
        child: image,
      );
    }

    if (_error) {
      if (widget.errorBuilder != null) return widget.errorBuilder!(context);
      if (widget.errorWidget != null) return widget.errorWidget!;
      return _DefaultErrorPlaceholder();
    }

    if (widget.loadingBuilder != null) return widget.loadingBuilder!(context);
    if (widget.placeholder != null) return widget.placeholder!;
    return const MagicShimmer();
  }
}

class _DefaultErrorPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.broken_image_rounded,
          color: colors.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}
