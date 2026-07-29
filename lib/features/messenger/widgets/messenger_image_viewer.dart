import 'dart:io';

import 'package:flutter/material.dart';

import '../models/messenger_message.dart';

String messengerImageHeroTag(MessengerMessage message) =>
    'messenger-image-${message.id}';

class MessengerImageViewer extends StatefulWidget {
  final List<MessengerMessage> images;
  final int initialIndex;
  final Future<void> Function(MessengerMessage message)? onSetAvatar;

  const MessengerImageViewer({
    super.key,
    required this.images,
    required this.initialIndex,
    this.onSetAvatar,
  });

  @override
  State<MessengerImageViewer> createState() => _MessengerImageViewerState();
}

class _MessengerImageViewerState extends State<MessengerImageViewer> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _showChrome = true;

  @override
  void initState() {
    super.initState();
    final safeIndex = widget.images.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.images.length - 1);
    _currentIndex = safeIndex;
    _pageController = PageController(initialPage: safeIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleChrome() {
    setState(() {
      _showChrome = !_showChrome;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white54),
        ),
      );
    }

    final total = widget.images.length;
    final title = total > 1 ? '${_currentIndex + 1} / $total' : 'Фото';
    final currentMessage = widget.images[_currentIndex];
    final canSetAvatar = widget.onSetAvatar != null &&
        (currentMessage.imagePath != null || currentMessage.imageUrl != null);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _showChrome
          ? AppBar(
              backgroundColor: Colors.black.withOpacity(0.35),
              elevation: 0,
              title: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              leading: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
              actions: [
                if (canSetAvatar)
                  IconButton(
                    onPressed: () async {
                      final handler = widget.onSetAvatar;
                      if (handler == null) return;
                      await handler(currentMessage);
                    },
                    icon: const Icon(Icons.person, color: Colors.white),
                    tooltip: 'Сделать аватаром',
                  ),
              ],
            )
          : null,
      body: SafeArea(
        child: PageView.builder(
          controller: _pageController,
          itemCount: total,
          onPageChanged: (index) {
            if (index == _currentIndex) return;
            setState(() {
              _currentIndex = index;
            });
          },
          itemBuilder: (context, index) {
            final message = widget.images[index];
            return _ImagePage(
              message: message,
              onTap: _toggleChrome,
            );
          },
        ),
      ),
    );
  }
}

class _ImagePage extends StatelessWidget {
  final MessengerMessage message;
  final VoidCallback onTap;

  const _ImagePage({
    required this.message,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Hero(
          tag: messengerImageHeroTag(message),
          child: _InteractiveImage(message: message),
        ),
      ),
    );
  }
}

class _InteractiveImage extends StatelessWidget {
  final MessengerMessage message;

  const _InteractiveImage({
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 1,
      maxScale: 4,
      clipBehavior: Clip.none,
      child: _buildImage(),
    );
  }

  Widget _buildImage() {
    final imagePath = message.imagePath;
    final imageUrl = message.imageUrl;

    if (imagePath != null) {
      return Image.file(
        File(imagePath),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => _imageErrorPlaceholder(),
      );
    }

    if (imageUrl != null) {
      return Image.network(
        imageUrl,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          final expected = loadingProgress.expectedTotalBytes;
          final value = expected != null
              ? loadingProgress.cumulativeBytesLoaded / expected
              : null;
          return Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                value: value,
                color: Colors.white,
                strokeWidth: 2.4,
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => _imageErrorPlaceholder(),
      );
    }

    return _imageErrorPlaceholder();
  }

  Widget _imageErrorPlaceholder() {
    return const ColoredBox(
      color: Color(0xFF1E1E1E),
      child: SizedBox(
        width: 120,
        height: 120,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Colors.white38,
            size: 40,
          ),
        ),
      ),
    );
  }
}
