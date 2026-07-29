import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:vk_video/vk_video.dart';

class VkVideoKeepAlive extends StatefulWidget {
  final String ownerId;
  final String videoId;
  final bool isActive;
  const VkVideoKeepAlive(
      {super.key,
      required this.ownerId,
      required this.videoId,
      required this.isActive});

  @override
  State<VkVideoKeepAlive> createState() => _VkVideoKeepAliveState();
}

class _VkVideoKeepAliveState extends State<VkVideoKeepAlive> {
  bool _ready = false;
  Timer? _initTimer;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _scheduleInit();
  }

  @override
  void didUpdateWidget(covariant VkVideoKeepAlive oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_ready) {
      _scheduleInit();
    } else if (!widget.isActive && _ready) {
      _cancelInit();
      setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    _cancelInit();
    super.dispose();
  }

  void _scheduleInit() {
    _cancelInit();
    _initTimer = Timer(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      setState(() => _ready = true);
    });
  }

  void _cancelInit() {
    _initTimer?.cancel();
    _initTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive || !_ready) {
      return const SizedBox.expand();
    }
    return VKVideo(
      key: ValueKey('vk_${widget.ownerId}_${widget.videoId}'),
      videoOId: widget.ownerId,
      videoId: widget.videoId,
      isIframeAllowFullscreen: true,
      isAllowsInlineMediaPlayback: true,
    );
  }
}
