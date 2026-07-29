import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/localization/app_localization_service.dart';
import '../../../services/providers.dart';
import '../providers/chat_providers.dart';
import '../../../services/voice_message_storage.dart';

/// Виджет поля ввода сообщений в стиле WhatsApp
class MessageInput extends StatefulWidget {
  final Function(String) onSendMessage;
  final bool isLoading;
  final bool enabled;

  const MessageInput({
    super.key,
    required this.onSendMessage,
    this.isLoading = false,
    this.enabled = true,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;
  // Removed unused animations. Keep state minimal.
  DateTime? _recordingStartTime;
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
  }

  void _sendMessage() {
    final text = _controller.text;
    if (text.isNotEmpty && widget.enabled && !widget.isLoading) {
      widget.onSendMessage(text);
      _controller.clear();
      _focusNode.requestFocus();
    }
  }

  Future<void> _startRecording(WidgetRef ref) async {
    final speech = ref.read(speechRecognitionServiceProvider);
    try {
      setState(() {
        _recordingStartTime = DateTime.now();
        _recordingPath = null;
      });
      speech.setPreserveAudioFile(true);
      await speech.startListening();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.trParams('speech_start_error', ['$e']))),
      );
    }
  }

  Future<void> _stopRecording(WidgetRef ref) async {
    final speech = ref.read(speechRecognitionServiceProvider);
    try {
      await speech.stopListening();
      final tempPath = speech.getLastRecordingPath();
      if (tempPath != null) {
        _recordingPath = await VoiceMessageStorage.saveFromTemp(tempPath);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.trParams('speech_stop_error', ['$e']))),
      );
    } finally {
      setState(() {});
    }
  }

  Future<void> _cancelRecording(WidgetRef ref) async {
    final speech = ref.read(speechRecognitionServiceProvider);
    try {
      await speech.stopListening();
    } catch (_) {}
    setState(() {
      _recordingPath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 40),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(
                minHeight: 48,
                maxHeight: 150,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFFE1E1E6),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: widget.enabled && !widget.isLoading,
                      maxLines: 6,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: widget.isLoading
                            ? context.tr('ai_dietitian_typing')
                            : context.tr('write_message_placeholder'),
                        hintStyle: TextStyle(
                          color: Colors.black.withOpacity(0.35),
                          fontSize: 16,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 0,
                        ),
                        isDense: true,
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  if (widget.isLoading)
                    Container(
                      margin: const EdgeInsets.only(left: 12, bottom: 12),
                      child: const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.black)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _VoiceActionButton(
            hasText: _hasText,
            isEnabled: widget.enabled && !widget.isLoading,
            onSend: _sendMessage,
            onStartRecording: (ref) async => await _startRecording(ref),
            onStopRecording: (ref, {String? placeholderId}) async {
              await _stopRecording(ref);
              final speech = ref.read(speechRecognitionServiceProvider);
              final transcript = speech.getRecognizedText();
              final audioPath = _recordingPath;
              final durationMs = _recordingStartTime == null
                  ? 0
                  : DateTime.now()
                      .difference(_recordingStartTime!)
                      .inMilliseconds;
              if (audioPath != null) {
                await ref.read(chatProvider.notifier).sendVoiceMessage(
                      audioPath: audioPath,
                      durationMs: durationMs,
                      transcription: transcript,
                      placeholderId: placeholderId,
                    );
              }
            },
            onCancel: (ref) async => await _cancelRecording(ref),
          ),
        ],
      ),
    );
  }
}

class _VoiceActionButton extends ConsumerStatefulWidget {
  final bool hasText;
  final bool isEnabled;
  final VoidCallback onSend;
  final Future<void> Function(WidgetRef ref) onStartRecording;
  final Future<void> Function(WidgetRef ref, {String? placeholderId})
      onStopRecording;
  final Future<void> Function(WidgetRef ref) onCancel;

  const _VoiceActionButton({
    required this.hasText,
    required this.isEnabled,
    required this.onSend,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onCancel,
  });

  @override
  ConsumerState<_VoiceActionButton> createState() => _VoiceActionButtonState();
}

class _VoiceActionButtonState extends ConsumerState<_VoiceActionButton>
    with TickerProviderStateMixin {
  bool _recording = false;
  late AnimationController _anim;
  bool _lock = false;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  Timer? _tick;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlay;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    _tick?.cancel();
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hasText) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: widget.isEnabled
              ? Colors.black
              : Colors.black.withOpacity(0.2),
          borderRadius: BorderRadius.circular(24),
          boxShadow: widget.isEnabled
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.isEnabled ? widget.onSend : null,
            borderRadius: BorderRadius.circular(24),
            child: Center(
              child: Icon(
                Icons.send,
                color: widget.isEnabled ? Colors.white : Colors.white70,
                size: 20,
              ),
            ),
          ),
        ),
      );
    }

    // Mic hold-to-record behavior в легком стиле
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) async {
        if (!widget.isEnabled) return;
        setState(() {
          _recording = true;
          _lock = false;
          _startedAt = DateTime.now();
          _elapsed = Duration.zero;
        });
        HapticFeedback.heavyImpact();
        _anim.repeat(reverse: true); // пульсация кнопки
        _tick?.cancel();
        _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
          if (!_recording || _startedAt == null) return;
          _elapsed = DateTime.now().difference(_startedAt!);
          _overlay?.markNeedsBuild();
        });
        _showOverlay();
        await widget.onStartRecording(ref);
      },
      onLongPressEnd: (_) async {
        if (!_recording) return;
        if (_lock) return; // В режиме блокировки останавливаем вручную
        _tick?.cancel();
        // Сначала мгновенно убираем UI, затем останавливаем запись в фоне
        setState(() {
          _recording = false;
        });
        _removeOverlay();
        _anim.stop();
        _anim.value = 1.0;
        HapticFeedback.lightImpact();
        try {
          final placeholderId = ref
              .read(chatProvider.notifier)
              .createVoiceTranscriptionPlaceholder();
          await widget.onStopRecording(ref, placeholderId: placeholderId);
        } catch (_) {}
      },
      onTap: () async {
        // В режиме блокировки тап по кнопке завершает запись и отправляет
        if (_recording && _lock) {
          _tick?.cancel();
          // Мгновенно скрываем UI
          setState(() {
            _recording = false;
            _lock = false;
          });
          _removeOverlay();
          _anim.stop();
          _anim.value = 1.0;
          HapticFeedback.mediumImpact();
          try {
            final placeholderId = ref
                .read(chatProvider.notifier)
                .createVoiceTranscriptionPlaceholder();
            await widget.onStopRecording(ref, placeholderId: placeholderId);
          } catch (_) {}
        }
      },
      onLongPressMoveUpdate: (details) async {
        if (!_recording) return;
        final Offset o = details.offsetFromOrigin;
        final dx = o.dx;
        final dy = o.dy;
        if (dx < -60 && !_lock) {
          _tick?.cancel();
          await widget.onCancel(ref);
          setState(() {
            _recording = false;
            _lock = false;
          });
          _removeOverlay();
          _anim.stop();
          _anim.value = 1.0;
          HapticFeedback.selectionClick();
          return;
        }
        if (dy < -60 && !_lock) {
          setState(() {
            _lock = true;
          });
          _overlay?.markNeedsBuild();
          HapticFeedback.mediumImpact();
        }
      },
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          return CompositedTransformTarget(
            link: _layerLink,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _recording ? Colors.black : Colors.white,
                  border: Border.all(
                    color: _recording
                        ? Colors.black
                        : const Color(0xFFE1E1E6),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    _recording ? Icons.mic : Icons.mic_none,
                    color: _recording ? Colors.white : Colors.black54,
                    size: 22,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  void _showOverlay() {
    _overlay ??= OverlayEntry(builder: (context) {
      return Stack(children: [
        // Большая панель слева от микрофона с размерами как у поля ввода
        CompositedTransformFollower(
          link: _layerLink,
          targetAnchor: Alignment.centerLeft,
          followerAnchor: Alignment.centerRight,
          offset: const Offset(-12, 0),
          showWhenUnlinked: false,
          child: Material(
            color: Colors.transparent,
            child: Builder(builder: (ctx) {
              final screenW = MediaQuery.of(ctx).size.width;
              // ширина: экран - внешние отступы (8+8) - отступ между полем и кнопкой (8) - ширина кнопки (48)
              final double width =
                  (screenW - 8 - 8 - 8 - 48).clamp(160.0, screenW);
              return Container(
                width: width,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.shade600.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  const Icon(Icons.fiber_manual_record,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Text(_formatDuration(_elapsed),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Opacity(
                      opacity: 0.8,
                      child: Text(
                        _lock ? 'Закреплено' : '↑ закрепить    ← отмена',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ),
                ]),
              );
            }),
          ),
        ),
        if (_lock)
          CompositedTransformFollower(
            link: _layerLink,
            targetAnchor: Alignment.centerRight,
            followerAnchor: Alignment.centerLeft,
            offset: const Offset(12, 0),
            showWhenUnlinked: false,
            child: Material(
              color: Colors.transparent,
              child: Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.send, color: Colors.white, size: 16),
                ),
              ]),
            ),
          ),
      ]);
    });

    final overlay = Overlay.of(context);
    if (_overlay != null) {
      overlay.insert(_overlay!);
    }
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }
}
