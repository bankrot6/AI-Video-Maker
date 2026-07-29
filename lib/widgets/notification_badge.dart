import 'package:flutter/material.dart';

/// Виджет красного круга с цифрой уведомлений как в мессенджерах (WhatsApp/Telegram)
/// Показывает анимированное появление для привлечения внимания пользователя
class NotificationBadge extends StatefulWidget {
  /// Количество уведомлений для отображения
  final int count;

  /// Показывать ли badge (если false, badge скрыт)
  final bool isVisible;

  /// Размер badge (по умолчанию 20)
  final double size;

  /// Цвет фона badge (по умолчанию красный)
  final Color backgroundColor;

  /// Цвет текста (по умолчанию белый)
  final Color textColor;

  /// Позиция по горизонтали относительно родительского виджета
  final double? right;
  final double? left;

  /// Позиция по вертикали относительно родительского виджета
  final double? top;
  final double? bottom;

  const NotificationBadge({
    super.key,
    required this.count,
    this.isVisible = true,
    this.size = 20,
    this.backgroundColor = Colors.red,
    this.textColor = Colors.white,
    this.right,
    this.left,
    this.top,
    this.bottom,
  });

  @override
  State<NotificationBadge> createState() => _NotificationBadgeState();
}

class _NotificationBadgeState extends State<NotificationBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();

    // Создаем контроллер анимации
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // Анимация масштабирования с эффектом "появления"
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
    ));

    // Анимация подпрыгивания для привлечения внимания (как в мессенджерах)
    _bounceAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.5, 1.0, curve: Curves.elasticInOut),
    ));

    // Запускаем анимацию если badge должен быть видимым
    if (widget.isVisible && widget.count > 0) {
      _animationController.forward();
    }
  }

  @override
  void didUpdateWidget(NotificationBadge oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Если visibility изменилась, запускаем или останавливаем анимацию
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible && widget.count > 0) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }

    // Если количество изменилось (увеличилось), запускаем анимацию снова
    if (widget.count != oldWidget.count && widget.count > oldWidget.count) {
      _animationController.reset();
      _animationController.forward();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Если badge не должен быть видимым или количество 0, возвращаем пустой виджет
    if (!widget.isVisible || widget.count <= 0) {
      return const SizedBox.shrink();
    }

    return Positioned(
      right: widget.right,
      left: widget.left,
      top: widget.top,
      bottom: widget.bottom,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value * _bounceAnimation.value,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: widget.backgroundColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.backgroundColor.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  widget.count > 99 ? '99+' : widget.count.toString(),
                  style: TextStyle(
                    color: widget.textColor,
                    fontSize: widget.size *
                        0.6, // Размер шрифта пропорционален размеру badge
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Обертка для добавления badge к любому виджету
class BadgeWrapper extends StatelessWidget {
  /// Дочерний виджет, к которому добавляется badge
  final Widget child;

  /// Количество уведомлений
  final int badgeCount;

  /// Показывать ли badge
  final bool showBadge;

  /// Размер badge
  final double badgeSize;

  /// Смещение badge от правого верхнего угла
  final Offset badgeOffset;

  const BadgeWrapper({
    super.key,
    required this.child,
    this.badgeCount = 1,
    this.showBadge = true,
    this.badgeSize = 20,
    this.badgeOffset = const Offset(-5, 5),
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        NotificationBadge(
          count: badgeCount,
          isVisible: showBadge,
          size: badgeSize,
          right: badgeOffset.dx,
          top: badgeOffset.dy,
        ),
      ],
    );
  }
}
