import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;
import '../services/providers.dart';
import '../services/localization/app_localization_service.dart';

/// Диалог для голосового ввода с круглой кнопкой
class VoiceInputDialog extends ConsumerStatefulWidget {
  /// Обработчик распознанного текста
  final Function(String) onRecognized;

  /// Создает диалог для голосового ввода
  const VoiceInputDialog({
    super.key,
    required this.onRecognized,
  });

  @override
  ConsumerState<VoiceInputDialog> createState() => _VoiceInputDialogState();
}

class _VoiceInputDialogState extends ConsumerState<VoiceInputDialog>
    with SingleTickerProviderStateMixin {
  bool _isListening = false;
  bool _isProcessing = false;
  late AnimationController _animationController;
  String _hintText = 'press_hold_to_start';
  Timer? _recordingTimer;
  static const _maxRecordingDuration = Duration(seconds: 15);
  double _progress = 0.0;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // Инициализируем сервис распознавания речи и регистрируем обработчик
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final speechService = ref.read(speechRecognitionServiceProvider);

      speechService.setRecognitionCompleteHandler((text) {
        if (!mounted) return;

        debugPrint('🎤 Распознавание завершено с текстом: "$text"');

        _animationController.stop();

        setState(() {
          _isListening = false;
          _isProcessing = false;
        });

        if (text.isNotEmpty) {
          setState(() {
            _hintText = 'speech_recognized';
          });

          // Вызываем обработчик с небольшой задержкой для лучшего UX
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              widget.onRecognized(text);
            }
          });
        } else {
          setState(() {
            _hintText = 'speech_not_recognized';
          });

          // Показываем подсказку, что речь не была распознана
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.tr('speak_louder')),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _recordingTimer?.cancel();
    _progressTimer?.cancel();
    _cancelListening();
    super.dispose();
  }

  void _startTimers() {
    _recordingTimer = Timer(_maxRecordingDuration, () {
      if (_isListening) {
        _stopListening();
      }
    });

    // Создаем таймер для обновления индикатора прогресса
    _progress = 0.0;
    const updateInterval = Duration(milliseconds: 100);
    final totalSteps =
        _maxRecordingDuration.inMilliseconds ~/ updateInterval.inMilliseconds;

    _progressTimer = Timer.periodic(updateInterval, (timer) {
      if (!_isListening) {
        timer.cancel();
        return;
      }

      setState(() {
        _progress += 1.0 / totalSteps;
        if (_progress >= 1.0) {
          _progress = 1.0;
          timer.cancel();
        }
      });
    });
  }

  /// Начинает запись аудио
  Future<void> _startListening() async {
    if (_isListening) return;

    setState(() {
      _isListening = true;
      _progress = 0.0;
      _hintText = 'speak_now';
    });

    _animationController.repeat(reverse: true);

    // Запускаем таймеры
    _startTimers();

    // Получаем выбранный язык интерфейса приложения, а не язык устройства
    final currentContext = context;
    Locale currentLocale;

    try {
      // Получаем язык интерфейса приложения через AppLocalizationService
      final container = ProviderScope.containerOf(currentContext);
      final localizationService =
          container.read(appLocalizationServiceProvider);
      final appLanguage = localizationService.getCurrentLanguage();

      // Используем универсальную логику для получения языкового кода
      String languageCode = _getLanguageCodeFromAppLanguage(appLanguage);

      currentLocale = Locale(languageCode);
    } catch (e) {
      // Если не удалось получить язык приложения, используем язык устройства как fallback
      currentLocale = Localizations.localeOf(currentContext);
      if (kDebugMode) {
        print(
            '🎤 Не удалось получить язык приложения, используем язык устройства: $e');
      }
    }

    // Используем стандартное поведение
    final speechService = ref.read(speechRecognitionServiceProvider);

    try {
      // Начинаем запись с обработкой ошибок
      await speechService.startListening(locale: currentLocale);

      // Если успешно начали запись, запускаем анимацию и таймеры
      if (kDebugMode) {
        print(
            '🎤 Запись голоса начата (локаль: ${currentLocale.languageCode})');
      }
    } catch (e) {
      if (kDebugMode) {
        print('🎤 Ошибка при запуске записи: $e');
      }
      _handleRecordingError(e);
    }
  }

  Future<void> _stopListening() async {
    if (!_isListening) return;

    _recordingTimer?.cancel();
    _progressTimer?.cancel();
    setState(() {
      _isListening = false;
      _isProcessing = true;
      _hintText = 'recognition_in_progress';
    });

    // Используем стандартное поведение
    final speechService = ref.read(speechRecognitionServiceProvider);
    try {
      await speechService.stopListening();

      if (kDebugMode) {
        print('🎤 Запись голоса остановлена и отправлена на распознавание');
      }
    } catch (e) {
      if (kDebugMode) {
        print('🎤 Ошибка при остановке записи: $e');
      }
      _handleStopRecordingError(e);
    }
  }

  /// Обрабатывает ошибку запуска записи
  void _handleRecordingError(dynamic error) {
    // Восстанавливаем состояние в случае ошибки
    _animationController.stop();
    _recordingTimer?.cancel();
    _progressTimer?.cancel();

    setState(() {
      _isListening = false;
      _hintText = 'error_occurred';
    });

    // Показываем сообщение об ошибке
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.trParams('voice_recording_error', ['$error'])),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Обрабатывает ошибку остановки записи
  void _handleStopRecordingError(dynamic error) {
    // Обработка ошибки остановки записи
    setState(() {
      _isProcessing = false;
      _hintText = 'error_occurred';
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(context.trParams('speech_recognition_error', ['$error'])),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _cancelListening() async {
    if (!_isListening) return;

    _recordingTimer?.cancel();
    _progressTimer?.cancel();

    final speechService = ref.read(speechRecognitionServiceProvider);
    try {
      await speechService.stopListening();
    } catch (e) {
      // Игнорируем ошибки при очистке
    }

    setState(() {
      _isListening = false;
      _isProcessing = false;
      _hintText = 'press_hold_to_start';
    });
    _animationController.stop();
  }

  /// Универсальный метод для получения языкового кода из AppLanguage
  /// Автоматически поддерживает все языки приложения
  String _getLanguageCodeFromAppLanguage(AppLanguage appLanguage) {
    // Используем название enum как базу для языкового кода
    String enumName = appLanguage.name;

    // Обрабатываем специальные случаи
    switch (appLanguage) {
      case AppLanguage.ptBR:
        return 'pt'; // Португальский (Бразилия) -> pt
      case AppLanguage.frCA:
        return 'fr'; // Французский (Канада) -> fr
      case AppLanguage.esMX:
        return 'es'; // Испанский (Мексика) -> es
      case AppLanguage.zhTW:
        return 'zh'; // Китайский (традиционный) -> zh
      case AppLanguage.fil:
        return 'tl'; // Филиппинский -> tl (Tagalog)
      default:
        // Для всех остальных языков используем название enum как есть
        // ru -> ru, en -> en, ar -> ar, he -> he, de -> de, etc.
        return enumName;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(
            context.tr('voice_input'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 20),

        if (!_isListening && !_isProcessing)
          Center(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                context.tr('press_mic_button'),
                style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.5)),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        if (_isListening)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                context.tr(_hintText),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        if (_isProcessing)
          Center(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                context.tr('processing_speech'),
                style: const TextStyle(fontSize: 12, color: Color(0xFF9D7FE1)),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        const SizedBox(height: 24),

        // Индикатор прогресса записи
        if (_isListening)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF9D7FE1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.trParams('recording_time', [
                      (_progress * _maxRecordingDuration.inSeconds)
                          .toStringAsFixed(1)
                    ]),
                    style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
          ),

        // Индикатор обработки
        if (_isProcessing)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF9D7FE1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('speech_recognition'),
                    style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 20),

        // Большая круглая кнопка микрофона со стеклянным эффектом
        Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: _isProcessing ? null : (_) => _startListening(),
            onLongPressEnd: _isProcessing ? null : (_) => _stopListening(),
            onLongPressCancel: _isProcessing ? null : _cancelListening,
            onTap: _isProcessing
                ? null
                : () {
                    if (_isListening) {
                      _stopListening();
                    } else {
                      _startListening();
                    }
                  },
            child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              final color = _isProcessing
                  ? const Color(0xFF7FE1D4)
                  : const Color(0xFF9D7FE1);
              
              return ClipRRect(
                borderRadius: BorderRadius.circular(60),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _isListening
                            ? [
                                color.withValues(alpha: 0.4 + _animationController.value * 0.2),
                                color.withValues(alpha: 0.3 + _animationController.value * 0.15),
                              ]
                            : [
                                color.withValues(alpha: 0.25),
                                color.withValues(alpha: 0.15),
                              ],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 2,
                      ),
                      boxShadow: _isListening || _isProcessing
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.5),
                                blurRadius: 20,
                                spreadRadius: 5,
                              )
                            ]
                          : null,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          _isProcessing
                              ? Icons.hourglass_top
                              : _isListening
                                  ? Icons.mic
                                  : Icons.mic_none,
                          color: Colors.black87,
                          size: 50,
                        ),
                        if (_isProcessing)
                          SizedBox(
                            width: 90,
                            height: 90,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.black.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
            ),
          ),
        ),

        const SizedBox(height: 30),

        // Отступ для клавиатуры
        SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
      ],
    );
  }
}
