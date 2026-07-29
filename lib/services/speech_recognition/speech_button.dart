import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../localization/app_localization_service.dart';

/// Кнопка для голосового ввода
class SpeechButton extends ConsumerStatefulWidget {
  /// Обработчик распознанного текста
  final Function(String) onRecognized;

  /// Размер кнопки
  final double size;

  /// Создает кнопку для голосового ввода
  const SpeechButton({
    super.key,
    required this.onRecognized,
    this.size = 48.0,
  });

  @override
  ConsumerState<SpeechButton> createState() => _SpeechButtonState();
}

class _SpeechButtonState extends ConsumerState<SpeechButton>
    with SingleTickerProviderStateMixin {
  bool _isListening = false;
  late AnimationController _animationController;
  String _hintText = 'speech_hold_to_record';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _cancelListening();
    super.dispose();
  }

  Future<void> _startListening() async {
    final speechService = ref.read(speechRecognitionServiceProvider);

    // Проверяем доступность сервиса
    final isAvailable = await speechService.isAvailable();

    if (!isAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('speech_recognition_unavailable')),
          ),
        );
      }
      return;
    }

    // Устанавливаем обработчик завершения
    speechService.setRecognitionCompleteHandler((text) {
      widget.onRecognized(text);
      if (mounted) {
        setState(() {
          _isListening = false;
          _hintText = 'speech_hold_to_record';
        });
      }
      _animationController.stop();
    });

    // Начинаем прослушивание
    try {
      await speechService.startListening();
      _animationController.repeat(reverse: true);
      setState(() {
        _isListening = true;
        _hintText = 'speech_speaking';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.trParams('speech_start_error', ['$e'])),
          ),
        );
      }
    }
  }

  Future<void> _stopListening() async {
    if (!_isListening) return;

    final speechService = ref.read(speechRecognitionServiceProvider);
    setState(() {
      _hintText = 'speech_recognizing';
    });

    try {
      await speechService.stopListening();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.trParams('speech_stop_error', ['$e'])),
          ),
        );
      }
    }
  }

  Future<void> _cancelListening() async {
    if (!_isListening) return;

    final speechService = ref.read(speechRecognitionServiceProvider);

    try {
      await speechService.stopListening();
      setState(() {
        _isListening = false;
        _hintText = 'speech_hold_to_record';
      });
      _animationController.stop();
    } catch (e) {
      // Игнорируем ошибки при очистке
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onLongPressStart: (_) => _startListening(),
          onLongPressEnd: (_) => _stopListening(),
          onLongPressCancel: _cancelListening,
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: _isListening
                      ? Theme.of(context)
                          .primaryColor
                          .withOpacity(0.4 + _animationController.value * 0.3)
                      : Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(widget.size / 2),
                ),
                child: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  color: Theme.of(context).primaryColor,
                  size: widget.size / 2,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr(_hintText),
          style: const TextStyle(fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
