import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';

import '../../services/generated_media.dart';
import '../../services/proxied_image_service.dart';
import '../../widgets/generated_video_view.dart';
import 'theme/photosession_palette.dart';

class FullscreenImageViewer extends StatefulWidget {
  const FullscreenImageViewer({
    super.key,
    required this.imageUrl,
    this.heroTag,
  });

  final String imageUrl;
  final String? heroTag;

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  /// Просмотрщик всегда тёмный: светлый хром поверх фотографии ухудшает
  /// восприятие снимка независимо от выбранной темы приложения.
  static const PhotosessionPalette _palette = PhotosessionPalette.dark;

  Uint8List? _imageBytes;
  bool _loading = true;

  bool get _isVideo => GeneratedMedia.isVideo(widget.imageUrl);

  @override
  void initState() {
    super.initState();
    // Видео проигрывается плеером по ссылке, поэтому байты не нужны.
    if (_isVideo) {
      _loading = false;
    } else {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final service = ProxiedImageService();
    final bytes = await service.downloadImage(widget.imageUrl);
    if (mounted) {
      setState(() {
        _imageBytes = bytes;
        _loading = false;
      });
    }
  }

  Future<void> _saveToGallery(BuildContext context) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Загружаем видео...')),
      );

      final service = ProxiedImageService();
      final bytes = await service.downloadImage(widget.imageUrl);
      if (bytes == null) {
        throw Exception('Не удалось загрузить изображение');
      }

      final tempDir = await getTemporaryDirectory();
      final extension =
          _isVideo ? GeneratedMedia.videoExtension : '.jpg';
      final fileName =
          'photosession_${DateTime.now().millisecondsSinceEpoch}$extension';
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        await Gal.requestAccess(toAlbum: true);
      }

      if (_isVideo) {
        await Gal.putVideo(filePath, album: 'AI Video Maker');
      } else {
        await Gal.putImage(filePath, album: 'AI Video Maker');
      }

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isVideo
                ? 'Видео сохранено в галерею'
                : 'Фото сохранено в галерею',
          ),
          backgroundColor: _palette.success,
        ),
      );

      await file.delete();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $e'),
          backgroundColor: _palette.danger,
        ),
      );
    }
  }

  Widget _buildPhotoView() {
    if (_isVideo) {
      return GeneratedVideoView(
        url: widget.imageUrl,
        fit: BoxFit.contain,
        loadingBuilder: (_) => Center(
          child: CircularProgressIndicator(color: _palette.accent),
        ),
        errorBuilder: (_) => Center(
          child: Icon(
            Icons.broken_image,
            color: _palette.textSecondary,
            size: 64,
          ),
        ),
      );
    }
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: _palette.accent),
      );
    }
    if (_imageBytes == null) {
      return Center(
        child:
            Icon(Icons.broken_image, color: _palette.textSecondary, size: 64),
      );
    }
    return PhotoView(
      imageProvider: MemoryImage(_imageBytes!),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 4,
      initialScale: PhotoViewComputedScale.covered,
      backgroundDecoration: BoxDecoration(color: _palette.depth),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewer = ColoredBox(
      color: _palette.depth,
      child: SizedBox.expand(
        child: _buildPhotoView(),
      ),
    );

    final wrapped = widget.heroTag != null
        ? Hero(
            tag: widget.heroTag!,
            child: Material(
              color: _palette.depth,
              child: viewer,
            ),
          )
        : viewer;

    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _palette.depth,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _palette.depth,
        body: Stack(
          fit: StackFit.expand,
          children: [
            wrapped,
            Positioned(
              top: topInset + 4,
              left: 4,
              right: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: _palette.backgroundScrim,
                    ),
                    icon: Icon(Icons.close, color: _palette.textPrimary),
                  ),
                  IconButton(
                    onPressed: () => _saveToGallery(context),
                    style: IconButton.styleFrom(
                      backgroundColor: _palette.backgroundScrim,
                    ),
                    icon: Icon(Icons.download, color: _palette.textPrimary),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: bottomInset,
              child: ColoredBox(color: _palette.depth),
            ),
          ],
        ),
      ),
    );
  }
}
