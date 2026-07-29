import 'dart:async';
import 'package:flutter/material.dart';
import 'loading_screen.dart';

/// Менеджер для управления глобальным экраном загрузки.
/// Используется как Singleton для отображения/скрытия экрана загрузки из любого места приложения.
class LoadingManager {
  /// Константные строки для загрузки (английские по умолчанию)
  static const String _processingText = 'Processing...';
  static const String _transitionText = 'Transitioning to another screen...';
  static const String _preparingTransitionText = 'Preparing transition';

  /// Singleton инстанс
  static final LoadingManager _instance = LoadingManager._internal();

  /// Фабрика для получения singleton инстанса
  factory LoadingManager() => _instance;

  /// Приватный конструктор
  LoadingManager._internal();

  /// Оверлей для отображения экрана загрузки поверх текущего интерфейса
  OverlayEntry? _overlayEntry;

  /// Флаг, указывающий, активен ли экран загрузки
  bool _isActive = false;

  /// Блокировка для операций с оверлеем
  bool _isLocked = false;

  /// Таймер для автоматической разблокировки
  Timer? _lockTimer;

  /// Очередь операций с экраном загрузки
  final List<_PendingOperation> _pendingOperations = [];

  /// Контекст, сохраненный для будущих операций
  BuildContext? _savedContext;

  /// Текущие параметры экрана загрузки
  String? _currentText;
  String _currentAnimationPath = 'assets/animations/road.json';
  double? _currentAnimationHeight;
  Color _currentBackgroundColor = Colors.white;
  TextStyle? _currentTextStyle;
  String? _currentProcessingStepText;
  TextStyle? _currentProcessingStepTextStyle;
  double? _currentProgressValue;
  String? _currentRemainingRecognitionsText;

  /// Показывает экран загрузки с опциональным текстом
  ///
  /// [context] - контекст для получения доступа к оверлею
  /// [text] - опциональный текст, который будет отображаться под анимацией
  /// [animationPath] - путь к Lottie анимации
  /// [backgroundColor] - цвет фона экрана загрузки
  void showLoadingScreen(
    BuildContext context, {
    String? text,
    String animationPath = 'assets/animations/road.json',
    double? animationHeight,
    Color backgroundColor = Colors.white,
    TextStyle? textStyle,
    String? processingStepText,
    TextStyle? processingStepTextStyle,
    double? progressValue,
    String? remainingRecognitionsText,
  }) {
    // Сохраняем контекст для будущих операций
    _savedContext = context;

    // Сохраняем текущие параметры
    _currentText = text;
    _currentAnimationPath = animationPath;
    _currentAnimationHeight = animationHeight;
    _currentBackgroundColor = backgroundColor;
    _currentTextStyle = textStyle;
    _currentProcessingStepText = processingStepText;
    _currentProcessingStepTextStyle = processingStepTextStyle;
    _currentProgressValue = progressValue;
    _currentRemainingRecognitionsText = remainingRecognitionsText;

    print(
        "🔍 LOADING_MANAGER: Показываем экран загрузки: ${text ?? 'без текста'}, этап: ${processingStepText ?? 'начальный'}");

    // Если есть активный оверлей, обновляем его
    if (_isActive && _overlayEntry != null) {
      _safelyRebuildOverlay();
      return;
    }

    // Блокируем операции на короткое время
    if (_isLocked) {
      _queueOperation(_OperationType.show, context: context);
      return;
    }

    _lock();

    // Используем безопасный способ вставки оверлея
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _createAndInsertOverlay(context);
      _unlock();
    });
  }

  /// Внутренний метод для безопасного обновления оверлея
  void _safelyRebuildOverlay() {
    if (_overlayEntry == null) return;

    try {
      // Используем постфреймовый колбэк для обновления
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_overlayEntry != null && _isActive) {
          _overlayEntry!.markNeedsBuild();
          print("✅ LOADING_MANAGER: Оверлей безопасно обновлен");
        }
      });
    } catch (e) {
      print("❌ LOADING_MANAGER: Ошибка при обновлении оверлея: $e");
    }
  }

  /// Внутренний метод для создания и вставки оверлея
  void _createAndInsertOverlay(BuildContext context) {
    if (!context.mounted) {
      print("⚠️ LOADING_MANAGER: Контекст недействителен при создании оверлея");
      return;
    }

    try {
      // Очищаем предыдущий оверлей, если он есть
      if (_overlayEntry != null) {
        _safelyRemoveOverlay();
      }

      // Создаем новый оверлей
      _overlayEntry = OverlayEntry(
        builder: (context) => LoadingScreen(
          loadingText: _currentText,
          animationPath: _currentAnimationPath,
          animationHeight: _currentAnimationHeight,
          backgroundColor: _currentBackgroundColor,
          textStyle: _currentTextStyle,
          processingStepText: _currentProcessingStepText,
          processingStepTextStyle: _currentProcessingStepTextStyle,
          progressValue: _currentProgressValue,
          remainingRecognitionsText: _currentRemainingRecognitionsText,
        ),
      );

      // Проверяем, что контекст все еще действителен
      if (!context.mounted) {
        print(
            "⚠️ LOADING_MANAGER: Контекст стал недействительным после создания оверлея");
        _overlayEntry = null;
        return;
      }

      // Вставляем оверлей
      try {
        Overlay.of(context).insert(_overlayEntry!);
        _isActive = true;
        print("✅ LOADING_MANAGER: Оверлей успешно вставлен");
      } catch (e) {
        print("❌ LOADING_MANAGER: Ошибка при вставке оверлея: $e");
        _overlayEntry = null;
        _isActive = false;
      }
    } catch (e) {
      print("❌ LOADING_MANAGER: Ошибка при создании оверлея: $e");
      _overlayEntry = null;
      _isActive = false;
    }
  }

  /// Безопасно удаляет оверлей
  void _safelyRemoveOverlay() {
    if (_overlayEntry == null) return;

    try {
      // Сохраняем ссылку на оверлей и сразу очищаем поля
      final overlayEntryToRemove = _overlayEntry;
      _overlayEntry = null;
      _isActive = false;

      // Удаляем оверлей по сохраненной ссылке
      overlayEntryToRemove!.remove();
      print("✅ LOADING_MANAGER: Оверлей успешно удален");
    } catch (e) {
      print("❌ LOADING_MANAGER: Ошибка при удалении оверлея: $e");
      // Обеспечиваем сброс состояния даже при ошибке
      _overlayEntry = null;
      _isActive = false;
    }
  }

  /// Скрывает экран загрузки, если он отображается
  void hideLoadingScreen() {
    print("🔍 LOADING_MANAGER: Скрываем экран загрузки, активен: $_isActive");

    // Если нет активного оверлея, ничего не делаем
    if (!_isActive || _overlayEntry == null) {
      print("⚠️ LOADING_MANAGER: Попытка скрыть неактивный экран загрузки");
      return;
    }

    // Блокируем операции на короткое время
    if (_isLocked) {
      _queueOperation(_OperationType.hide);
      return;
    }

    _lock();

    // Сохраняем ссылку на оверлей и сразу очищаем глобальную ссылку
    // Это предотвращает проблемы с обращением к деактивированному виджету
    final overlayEntryToRemove = _overlayEntry;
    _overlayEntry = null;
    _isActive = false;

    // Используем безопасный способ удаления оверлея
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // Удаляем по сохраненной ссылке, а не по глобальной переменной
        if (overlayEntryToRemove != null) {
          overlayEntryToRemove.remove();
          print("✅ LOADING_MANAGER: Оверлей успешно удален");
        }
      } catch (e) {
        print("❌ LOADING_MANAGER: Ошибка при удалении оверлея: $e");
      } finally {
        _unlock();
      }
    });
  }

  /// Обновляет текст на экране загрузки
  ///
  /// [newText] - новый текст, который будет отображаться
  void updateLoadingText(
    BuildContext context, {
    required String newText,
    String? animationPath,
    double? animationHeight,
    Color? backgroundColor,
    TextStyle? textStyle,
    String? processingStepText,
    TextStyle? processingStepTextStyle,
    double? progressValue,
    String? remainingRecognitionsText,
  }) {
    _updateLoadingScreen(
      context,
      text: newText,
      animationPath: animationPath,
      animationHeight: animationHeight,
      backgroundColor: backgroundColor,
      textStyle: textStyle,
      processingStepText: processingStepText,
      processingStepTextStyle: processingStepTextStyle,
      progressValue: progressValue,
      remainingRecognitionsText: remainingRecognitionsText,
    );
  }

  /// Обновляет информацию о процессе обработки
  ///
  /// [newProcessingStep] - новый текст для этапа обработки
  /// [newProgressValue] - новое значение прогресса (от 0.0 до 1.0)
  void updateProcessingInfo(
    BuildContext context, {
    String? newText,
    required String newProcessingStep,
    double? newProgressValue,
    String? animationPath,
    double? animationHeight,
    Color? backgroundColor,
    TextStyle? textStyle,
    TextStyle? processingStepTextStyle,
    String? remainingRecognitionsText,
  }) {
    print(
        "🔍 LOADING_MANAGER: Обновляем информацию о процессе: $newProcessingStep, прогресс: $newProgressValue");

    _updateLoadingScreen(
      context,
      text: newText ?? _currentText ?? _processingText,
      animationPath: animationPath ?? _currentAnimationPath,
      animationHeight: animationHeight ?? _currentAnimationHeight,
      backgroundColor: backgroundColor ?? _currentBackgroundColor,
      textStyle: textStyle ?? _currentTextStyle,
      processingStepText: newProcessingStep,
      processingStepTextStyle:
          processingStepTextStyle ?? _currentProcessingStepTextStyle,
      progressValue: newProgressValue ?? _currentProgressValue,
      remainingRecognitionsText:
          remainingRecognitionsText ?? _currentRemainingRecognitionsText,
    );
  }

  /// Внутренний метод для обновления экрана загрузки без его удаления
  void _updateLoadingScreen(
    BuildContext context, {
    String? text,
    String? animationPath,
    double? animationHeight,
    Color? backgroundColor,
    TextStyle? textStyle,
    String? processingStepText,
    TextStyle? processingStepTextStyle,
    double? progressValue,
    String? remainingRecognitionsText,
  }) {
    // Блокируем операции на короткое время
    if (_isLocked) {
      _queueOperation(_OperationType.update,
          context: context,
          text: text,
          animationPath: animationPath,
          animationHeight: animationHeight,
          backgroundColor: backgroundColor,
          textStyle: textStyle,
          processingStepText: processingStepText,
          processingStepTextStyle: processingStepTextStyle,
          progressValue: progressValue,
          remainingRecognitionsText: remainingRecognitionsText);
      return;
    }

    _lock();

    // Обновляем сохраненные параметры
    if (text != null) _currentText = text;
    if (animationPath != null) _currentAnimationPath = animationPath;
    if (animationHeight != null) _currentAnimationHeight = animationHeight;
    if (backgroundColor != null) _currentBackgroundColor = backgroundColor;
    if (textStyle != null) _currentTextStyle = textStyle;
    if (processingStepText != null) {
      _currentProcessingStepText = processingStepText;
    }
    if (processingStepTextStyle != null) {
      _currentProcessingStepTextStyle = processingStepTextStyle;
    }
    if (progressValue != null) _currentProgressValue = progressValue;
    if (remainingRecognitionsText != null) {
      _currentRemainingRecognitionsText = remainingRecognitionsText;
    }

    // Сохраняем контекст для будущих операций
    if (context.mounted) {
      _savedContext = context;
    }

    // Используем безопасный способ обновления оверлея
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        // Если экран загрузки активен, обновляем его
        if (_isActive && _overlayEntry != null) {
          _safelyRebuildOverlay();
          print("✅ LOADING_MANAGER: Обновлен контент экрана загрузки");
        } else if (context.mounted) {
          // Если экран не активен, показываем его
          _createAndInsertOverlay(context);
        }
      } catch (e) {
        print("❌ LOADING_MANAGER: Ошибка при обновлении экрана загрузки: $e");
      } finally {
        _unlock();
      }
    });
  }

  /// Принудительно обновляет экран загрузки, используя последние параметры
  void forceRefresh() {
    // Блокируем операции на короткое время
    if (_isLocked) {
      _queueOperation(_OperationType.forceRefresh);
      return;
    }

    _lock();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isActive && _overlayEntry != null) {
        print("🔍 LOADING_MANAGER: Принудительное обновление экрана загрузки");
        _safelyRebuildOverlay();
      } else if (_savedContext != null && _savedContext!.mounted) {
        // Если экран не активен, но есть сохраненный контекст, показываем снова
        _createAndInsertOverlay(_savedContext!);
      }
      _unlock();
    });
  }

  /// Добавляет операцию в очередь для последующего выполнения
  void _queueOperation(
    _OperationType type, {
    BuildContext? context,
    String? text,
    String? animationPath,
    double? animationHeight,
    Color? backgroundColor,
    TextStyle? textStyle,
    String? processingStepText,
    TextStyle? processingStepTextStyle,
    double? progressValue,
    String? remainingRecognitionsText,
  }) {
    _pendingOperations.add(_PendingOperation(
      type: type,
      context: context,
      text: text,
      animationPath: animationPath,
      animationHeight: animationHeight,
      backgroundColor: backgroundColor,
      textStyle: textStyle,
      processingStepText: processingStepText,
      processingStepTextStyle: processingStepTextStyle,
      progressValue: progressValue,
      remainingRecognitionsText: remainingRecognitionsText,
    ));

    print(
        "🔄 LOADING_MANAGER: Операция $type добавлена в очередь (${_pendingOperations.length} ожидающих)");
  }

  /// Обрабатывает ожидающие операции из очереди
  void _processPendingOperations() {
    if (_pendingOperations.isEmpty) return;
    if (_isLocked) return;

    final operation = _pendingOperations.removeAt(0);
    print(
        "🔄 LOADING_MANAGER: Выполнение операции ${operation.type} из очереди");

    switch (operation.type) {
      case _OperationType.show:
        if (operation.context != null) {
          showLoadingScreen(
            operation.context!,
            text: _currentText,
            animationPath: _currentAnimationPath,
            animationHeight: _currentAnimationHeight,
            backgroundColor: _currentBackgroundColor,
            textStyle: _currentTextStyle,
            processingStepText: _currentProcessingStepText,
            processingStepTextStyle: _currentProcessingStepTextStyle,
            progressValue: _currentProgressValue,
            remainingRecognitionsText: _currentRemainingRecognitionsText,
          );
        }
        break;
      case _OperationType.hide:
        hideLoadingScreen();
        break;
      case _OperationType.update:
        if (operation.context != null) {
          _updateLoadingScreen(
            operation.context!,
            text: operation.text,
            animationPath: operation.animationPath,
            animationHeight: operation.animationHeight,
            backgroundColor: operation.backgroundColor,
            textStyle: operation.textStyle,
            processingStepText: operation.processingStepText,
            processingStepTextStyle: operation.processingStepTextStyle,
            progressValue: operation.progressValue,
            remainingRecognitionsText: operation.remainingRecognitionsText,
          );
        }
        break;
      case _OperationType.forceRefresh:
        forceRefresh();
        break;
    }
  }

  /// Блокирует операции с экраном загрузки
  void _lock() {
    _isLocked = true;
    // Отменяем предыдущий таймер, если он существует
    _lockTimer?.cancel();
    // Устанавливаем новый таймер для автоматической разблокировки
    _lockTimer = Timer(Duration(milliseconds: 200), _unlock);
  }

  /// Разблокирует операции с экраном загрузки и обрабатывает очередь
  void _unlock() {
    _isLocked = false;
    _lockTimer?.cancel();
    _lockTimer = null;

    // Обрабатываем очередь операций
    if (_pendingOperations.isNotEmpty) {
      // Небольшая задержка для обработки очереди
      Timer(Duration(milliseconds: 10), _processPendingOperations);
    }
  }

  /// Проверяет, отображается ли экран загрузки
  bool get isActive => _isActive;

  /// Очищает все ресурсы при уничтожении
  void dispose() {
    _lockTimer?.cancel();
    if (_isActive && _overlayEntry != null) {
      _safelyRemoveOverlay();
    }
    _pendingOperations.clear();
    _savedContext = null;
  }

  /// Показывает полноэкранный экран загрузки для переходов между экранами
  /// Этот метод специально оптимизирован для случаев навигации, когда необходимо
  /// исключить мерцание интерфейса и показ промежуточных состояний.
  ///
  /// [context] - контекст для доступа к оверлею
  /// [text] - текст, который будет отображаться
  /// [processingStepText] - описание текущего этапа
  void showTransitionScreen(
    BuildContext context, {
    String? text,
    String animationPath = 'assets/animations/road.json',
    Color backgroundColor = Colors.white,
    String? processingStepText,
  }) {
    // Устанавливаем значения по умолчанию
    final displayText = text ?? _transitionText;
    final displayProcessingStepText =
        processingStepText ?? _preparingTransitionText;

    print("🔍 LOADING_MANAGER: Показываем экран перехода: $displayText");

    // Важно - сразу удаляем любой существующий оверлей для гарантии чистоты
    if (_overlayEntry != null) {
      _safelyRemoveOverlay();
    }

    // Сохраняем параметры
    _currentText = displayText;
    _currentAnimationPath = animationPath;
    _currentAnimationHeight = MediaQuery.of(context).size.height * 0.4;
    _currentBackgroundColor = backgroundColor;
    _currentProcessingStepText = displayProcessingStepText;
    _currentProgressValue = 0.8;

    // Блокируем на время создания оверлея
    _lock();

    // Создаем оверлей в текущем кадре для минимизации задержки
    _createAndInsertOverlay(context);

    // Отложенно делаем обновление оверлея через 100ms для гарантии обновления UI
    Future.delayed(Duration(milliseconds: 100), () {
      if (_isActive && _overlayEntry != null) {
        _overlayEntry!.markNeedsBuild();
      }
    });

    _unlock();
  }

  /// Делает оверлей полностью непрозрачным для плавных переходов
  void makeOverlayOpaque() {
    if (_overlayEntry != null && _isActive) {
      _overlayEntry!.markNeedsBuild();
    }
  }
}

/// Типы операций с экраном загрузки для очереди
enum _OperationType {
  show,
  hide,
  update,
  forceRefresh,
}

/// Класс для хранения отложенной операции с экраном загрузки
class _PendingOperation {
  final _OperationType type;
  final BuildContext? context;
  final String? text;
  final String? animationPath;
  final double? animationHeight;
  final Color? backgroundColor;
  final TextStyle? textStyle;
  final String? processingStepText;
  final TextStyle? processingStepTextStyle;
  final double? progressValue;
  final String? remainingRecognitionsText;

  _PendingOperation({
    required this.type,
    this.context,
    this.text,
    this.animationPath,
    this.animationHeight,
    this.backgroundColor,
    this.textStyle,
    this.processingStepText,
    this.processingStepTextStyle,
    this.progressValue,
    this.remainingRecognitionsText,
  });
}
