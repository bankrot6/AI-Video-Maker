import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Панель управления воспроизведением: пауза, перемотка ползунком, время,
/// звук и переход в полный экран.
///
/// Виджет только отображает состояние переданного контроллера и не создаёт его,
/// поэтому одинаково работает и в карточке результата, и в полноэкранном
/// просмотрщике.
class VideoPlayerControls extends StatefulWidget {
  const VideoPlayerControls({
    super.key,
    required this.controller,
    this.onFullscreen,
    this.onInteraction,
  });

  final VideoPlayerController controller;

  /// Кнопка полного экрана показывается только когда обработчик передан.
  final VoidCallback? onFullscreen;

  /// Сообщает родителю о действии пользователя, чтобы тот отложил автоскрытие.
  final VoidCallback? onInteraction;

  @override
  State<VideoPlayerControls> createState() => _VideoPlayerControlsState();
}

class _VideoPlayerControlsState extends State<VideoPlayerControls> {
  /// Пока пользователь тянет ползунок, позиция берётся из этого поля: значение
  /// контроллера отстаёт от жеста и ползунок дёргался бы назад.
  Duration? _dragPosition;
  bool _resumeAfterDrag = false;

  VideoPlayerController get _controller => widget.controller;

  static String _formatDuration(Duration value) {
    final totalSeconds = value.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _notifyInteraction() => widget.onInteraction?.call();

  Future<void> _togglePlayback() async {
    _notifyInteraction();
    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      if (_controller.value.position >= _controller.value.duration) {
        await _controller.seekTo(Duration.zero);
      }
      await _controller.play();
    }
  }

  Future<void> _toggleMute() async {
    _notifyInteraction();
    await _controller.setVolume(_controller.value.volume > 0 ? 0 : 1);
  }

  void _onDragStart(double value) {
    _notifyInteraction();
    _resumeAfterDrag = _controller.value.isPlaying;
    if (_resumeAfterDrag) _controller.pause();
    setState(() => _dragPosition = Duration(milliseconds: value.round()));
  }

  void _onDragUpdate(double value) {
    setState(() => _dragPosition = Duration(milliseconds: value.round()));
  }

  Future<void> _onDragEnd(double value) async {
    _notifyInteraction();
    await _controller.seekTo(Duration(milliseconds: value.round()));
    if (_resumeAfterDrag) await _controller.play();
    if (mounted) setState(() => _dragPosition = null);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        final duration = value.duration;
        final maxMilliseconds = duration.inMilliseconds.toDouble();
        if (maxMilliseconds <= 0) return const SizedBox.shrink();

        final position = _dragPosition ?? value.position;
        final clamped = position.inMilliseconds
            .clamp(0, duration.inMilliseconds)
            .toDouble();

        return Container(
          padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xB3000000)],
            ),
          ),
          child: Row(
            children: [
              _ControlButton(
                icon: value.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                tooltip: value.isPlaying ? 'Пауза' : 'Воспроизвести',
                onPressed: _togglePlayback,
              ),
              Text(
                _formatDuration(position),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white24,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: clamped,
                    max: maxMilliseconds,
                    onChangeStart: _onDragStart,
                    onChanged: _onDragUpdate,
                    onChangeEnd: _onDragEnd,
                  ),
                ),
              ),
              Text(
                _formatDuration(duration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              _ControlButton(
                icon: value.volume > 0
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                tooltip: value.volume > 0 ? 'Выключить звук' : 'Включить звук',
                onPressed: _toggleMute,
              ),
              if (widget.onFullscreen != null)
                _ControlButton(
                  icon: Icons.fullscreen_rounded,
                  tooltip: 'На весь экран',
                  onPressed: () {
                    _notifyInteraction();
                    widget.onFullscreen!.call();
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 22),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}
