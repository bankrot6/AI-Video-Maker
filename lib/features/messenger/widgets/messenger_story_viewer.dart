import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../../utils/navigation.dart';
import '../models/messenger_story.dart';

class MessengerStoryViewer extends StatefulWidget {
  final List<MessengerStory> stories;
  final int initialIndex;
  final ValueChanged<MessengerStory>? onStoryViewed;

  const MessengerStoryViewer({
    super.key,
    required this.stories,
    this.initialIndex = 0,
    this.onStoryViewed,
  });

  @override
  State<MessengerStoryViewer> createState() => _MessengerStoryViewerState();
}

enum _StoryMediaType { video, image }

class _StoryMedia {
  final _StoryMediaType type;
  final File? file;
  final String? url;

  const _StoryMedia({
    required this.type,
    this.file,
    this.url,
  });
}

class _MessengerStoryViewerState extends State<MessengerStoryViewer>
    with TickerProviderStateMixin {
  late final PageController _pageController;
  VideoPlayerController? _controller;
  AnimationController? _imageController;
  int _index = 0;
  bool _isLoading = true;
  String? _error;
  bool _isTransitioning = false;
  _StoryMedia? _media;
  static const Duration _imageDuration = Duration(seconds: 5);
  final Set<String> _viewedStoryIds = {};

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.stories.length - 1);
    _pageController = PageController(initialPage: _index);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadStory(_index);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );
    _disposeController();
    _disposeImageController();
    _pageController.dispose();
    super.dispose();
  }

  void _disposeController() {
    final controller = _controller;
    if (controller == null) return;
    controller.removeListener(_handlePlayback);
    controller.dispose();
    _controller = null;
  }

  void _disposeImageController() {
    final controller = _imageController;
    if (controller == null) return;
    controller.dispose();
    _imageController = null;
  }

  Future<void> _loadStory(int index) async {
    _disposeController();
    _disposeImageController();
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final story = widget.stories[index];
    
    if (story.isLocked) {
      if (mounted) {
        Navigator.of(context).pop();
        AppNavigation.showPaywall(context);
      }
      return;
    }
    
    final media = _resolveMedia(story);
    _media = media;
    if (media == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Медиа недоступно для этой сторис.';
      });
      return;
    }
    _markViewedIfNeeded(story);

    if (media.type == _StoryMediaType.image) {
      final controller = AnimationController(
        vsync: this,
        duration: _imageDuration,
      );
      _imageController = controller;
      controller.addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _goNext();
        }
      });
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      controller.forward();
      return;
    }

    final controller = media.file != null
        ? VideoPlayerController.file(media.file!)
        : VideoPlayerController.networkUrl(Uri.parse(media.url!));
    _controller = controller;
    controller.addListener(_handlePlayback);

    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.play();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      controller.removeListener(_handlePlayback);
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _controller = null;
        _isLoading = false;
        _error = 'Не удалось загрузить видео.';
      });
    }
  }

  void _markViewedIfNeeded(MessengerStory story) {
    if (story.isViewed) return;
    if (_viewedStoryIds.contains(story.id)) return;
    _viewedStoryIds.add(story.id);
    widget.onStoryViewed?.call(story);
  }

  File? _resolveStoryFile(MessengerStory story) {
    final path = story.videoPath;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return file;
  }

  String? _resolveStoryUrl(MessengerStory story) {
    final url = story.videoUrl?.trim();
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('gs://')) {
      final match = RegExp(r'^gs://([^/]+)/(.+)$').firstMatch(url);
      if (match == null) return null;
      final bucket = match.group(1);
      final object = match.group(2);
      if (bucket == null || object == null) return null;
      return 'https://storage.googleapis.com/$bucket/$object';
    }
    if (url.startsWith('http')) return url;
    return null;
  }

  File? _resolveImageFile(MessengerStory story) {
    final path = story.imagePath;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return file;
  }

  String? _resolveImageUrl(MessengerStory story) {
    final url = story.imageUrl?.trim();
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('gs://')) {
      final match = RegExp(r'^gs://([^/]+)/(.+)$').firstMatch(url);
      if (match == null) return null;
      final bucket = match.group(1);
      final object = match.group(2);
      if (bucket == null || object == null) return null;
      return 'https://storage.googleapis.com/$bucket/$object';
    }
    if (url.startsWith('http')) return url;
    return null;
  }

  _StoryMedia? _resolveMedia(MessengerStory story) {
    final imageFile = _resolveImageFile(story);
    final imageUrl = _resolveImageUrl(story);
    if (imageFile != null || imageUrl != null) {
      return _StoryMedia(
        type: _StoryMediaType.image,
        file: imageFile,
        url: imageUrl,
      );
    }
    final videoFile = _resolveStoryFile(story);
    final videoUrl = _resolveStoryUrl(story);
    if (videoFile != null || videoUrl != null) {
      return _StoryMedia(
        type: _StoryMediaType.video,
        file: videoFile,
        url: videoUrl,
      );
    }
    return null;
  }

  void _handlePlayback() {
    if (_media?.type != _StoryMediaType.video) return;
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    if (!value.isInitialized) return;
    final duration = value.duration;
    if (duration == Duration.zero) return;
    final position = value.position;
    if (_isTransitioning) return;
    final completed = position >= duration - const Duration(milliseconds: 200);
    if (completed && !value.isPlaying) {
      _goNext();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    final width = MediaQuery.of(context).size.width;
    if (details.localPosition.dx < width * 0.35) {
      _goPrevious();
    } else {
      _goNext();
    }
  }

  void _goNext() {
    if (_isTransitioning) return;
    if (_index >= widget.stories.length - 1) {
      Navigator.of(context).maybePop();
      return;
    }
    _isTransitioning = true;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  void _goPrevious() {
    if (_isTransitioning) return;
    if (_index <= 0) {
      Navigator.of(context).maybePop();
      return;
    }
    _isTransitioning = true;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stories.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Сторис не найдены.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _handleTapUp,
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.stories.length,
                onPageChanged: (index) {
                  _isTransitioning = false;
                  _index = index;
                  _loadStory(index);
                },
                itemBuilder: (context, index) {
                  if (index != _index) {
                    return const SizedBox.expand(
                      child: ColoredBox(color: Colors.black),
                    );
                  }
                  return _buildPlayer();
                },
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProgressBar(),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.stories[_index].contactName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildCaption(),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayer() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ),
      );
    }
    final media = _media;
    if (media == null) {
      return const SizedBox.shrink();
    }
    if (media.type == _StoryMediaType.image) {
      return _buildImage(media);
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }
    final size = controller.value.size;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  Widget _buildImage(_StoryMedia media) {
    if (media.file != null) {
      return Image.file(
        media.file!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
    if (media.url != null) {
      return Image.network(
        media.url!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildProgressBar() {
    if (_media?.type == _StoryMediaType.image) {
      final controller = _imageController;
      if (controller == null) {
        return _buildProgressRow(0);
      }
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return _buildProgressRow(controller.value.clamp(0, 1));
        },
      );
    }
    final controller = _controller;
    if (controller == null) {
      return _buildProgressRow(0);
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final value = controller.value;
        double progress = 0;
        if (value.isInitialized) {
          final duration = value.duration.inMilliseconds;
          final position = value.position.inMilliseconds;
          if (duration > 0) {
            progress = position / duration;
          }
        }
        return _buildProgressRow(progress.clamp(0, 1));
      },
    );
  }

  Widget _buildProgressRow(double progress) {
    return Row(
      children: List.generate(
        widget.stories.length,
        (index) {
          final value = index < _index
              ? 1.0
              : index == _index
                  ? progress
                  : 0.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 3,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCaption() {
    final caption = widget.stories[_index].caption.trim();
    if (caption.isEmpty) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black54,
              Colors.black87,
            ],
          ),
        ),
        child: Text(
          caption,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
