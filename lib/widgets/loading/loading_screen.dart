import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Глобальный виджет экрана загрузки.
/// Отображает Lottie анимацию и текст загрузки.
class LoadingScreen extends StatefulWidget {
  /// Текст, отображаемый под анимацией загрузки.
  final String? loadingText;

  /// Путь к Lottie анимации. По умолчанию используется анимация из assets.
  final String animationPath;

  /// Размер анимации.
  final double? animationHeight;

  /// Цвет фона экрана загрузки.
  final Color backgroundColor;

  /// Стиль текста загрузки.
  final TextStyle? textStyle;

  /// Описание этапа обработки (необязательно)
  final String? processingStepText;

  /// Стиль текста для этапа обработки
  final TextStyle? processingStepTextStyle;

  /// Индикатор прогресса (от 0.0 до 1.0, необязательно)
  final double? progressValue;

  /// Текст о количестве оставшихся распознаваний (необязательно)
  final String? remainingRecognitionsText;

  /// Конструктор для создания экрана загрузки.
  const LoadingScreen({
    super.key,
    this.loadingText,
    this.animationPath = 'assets/animations/road.json',
    this.animationHeight = 200.0,
    this.backgroundColor = Colors.white,
    this.textStyle,
    this.processingStepText,
    this.processingStepTextStyle,
    this.progressValue,
    this.remainingRecognitionsText,
  });

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _animationController.repeat();
  }

  @override
  void didUpdateWidget(LoadingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Если изменился путь к анимации, перезапускаем контроллер
    if (oldWidget.animationPath != widget.animationPath) {
      _animationController.reset();
      _animationController.repeat();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final defaultTextStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Colors.black54,
          fontWeight: FontWeight.w500,
        );

    final defaultStepTextStyle =
        Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.black45,
              fontWeight: FontWeight.w400,
              fontSize: 14.0,
            );

    final recognitionsTextStyle =
        Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.deepOrange.shade700,
              fontWeight: FontWeight.w500,
              fontSize: 14.0,
            );

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      color: widget.backgroundColor,
      width: double.infinity,
      height: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Анимация на весь экран по ширине
          SizedBox(
            width: screenWidth,
            height: widget.animationHeight ?? screenHeight * 0.4,
            child: Lottie.asset(
              widget.animationPath,
              width: screenWidth,
              height: widget.animationHeight,
              fit: BoxFit.contain,
              controller: _animationController,
              onLoaded: (composition) {
                // Устанавливаем длительность контроллера на длительность анимации
                _animationController.duration = composition.duration;
                _animationController.repeat();
              },
            ),
          ),

          // Основной текст загрузки
          if (widget.loadingText != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 24.0, horizontal: 32.0),
              child: Text(
                widget.loadingText!,
                style: widget.textStyle ?? defaultTextStyle,
                textAlign: TextAlign.center,
              ),
            ),

          // Индикатор прогресса (если указан)
          if (widget.progressValue != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 40.0, vertical: 8.0),
              child: LinearProgressIndicator(
                value: widget.progressValue,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                minHeight: 6.0,
                borderRadius: BorderRadius.circular(6.0),
              ),
            ),

          // Подробное описание этапа обработки (если указано)
          if (widget.processingStepText != null)
            Padding(
              padding:
                  const EdgeInsets.only(top: 16.0, left: 32.0, right: 32.0),
              child: Text(
                widget.processingStepText!,
                style: widget.processingStepTextStyle ?? defaultStepTextStyle,
                textAlign: TextAlign.center,
              ),
            ),

          // Информация об оставшихся распознаваниях (если указана)
          if (widget.remainingRecognitionsText != null &&
              widget.remainingRecognitionsText!.isNotEmpty)
            Padding(
              padding:
                  const EdgeInsets.only(top: 16.0, left: 32.0, right: 32.0),
              child: Text(
                widget.remainingRecognitionsText!,
                style: recognitionsTextStyle,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
