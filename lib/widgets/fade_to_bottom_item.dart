import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Виджет, который делает содержимое прозрачным по мере приближения к нижнему краю экрана
/// 
/// Это легковесная альтернатива ShaderMask и BackdropFilter, которая отлично работает на Android.
/// Вместо применения эффектов ко всему экрану, мы просто меняем opacity отдельных элементов.
/// 
/// Преимущества:
/// - Минимальная нагрузка на GPU
/// - Нет проблем с рендерингом на Android
/// - Плавная анимация через AnimatedOpacity
/// - Работает с любым контентом
class FadeToBottomItem extends StatefulWidget {
  /// Дочерний виджет, который будет исчезать
  final Widget child;
  
  /// Высота зоны затухания от низа экрана (в пикселях)
  final double fadeZoneHeight;
  
  /// Минимальная непрозрачность (0.0 = полностью прозрачно, 1.0 = полностью видно)
  final double minOpacity;
  
  const FadeToBottomItem({
    super.key,
    required this.child,
    this.fadeZoneHeight = 140.0,
    this.minOpacity = 0.0,
  });

  @override
  State<FadeToBottomItem> createState() => _FadeToBottomItemState();
}

class _FadeToBottomItemState extends State<FadeToBottomItem> {
  double _opacity = 1.0;
  final GlobalKey _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Обновляем opacity после первого рендера
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateOpacity();
    });
  }

  void _updateOpacity() {
    if (!mounted) return;
    
    final RenderBox? renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return;

    try {
      // Получаем позицию виджета относительно экрана
      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      
      // Получаем высоту экрана
      final screenHeight = MediaQuery.of(context).size.height;
      
      // Вычисляем расстояние от низа виджета до низа экрана
      final bottomPosition = position.dy + size.height;
      final distanceFromBottom = screenHeight - bottomPosition;
      
      // Вычисляем новую непрозрачность
      double newOpacity;
      if (distanceFromBottom >= widget.fadeZoneHeight) {
        // Виджет далеко от зоны затухания - полностью видим
        newOpacity = 1.0;
      } else if (distanceFromBottom <= 0) {
        // Виджет в/за зоной затухания - минимальная непрозрачность
        newOpacity = widget.minOpacity;
      } else {
        // Виджет в зоне затухания - интерполируем
        final fadeProgress = distanceFromBottom / widget.fadeZoneHeight;
        newOpacity = widget.minOpacity + (1.0 - widget.minOpacity) * fadeProgress;
      }
      
      // Обновляем состояние только если значение изменилось
      if ((newOpacity - _opacity).abs() > 0.01) {
        setState(() {
          _opacity = newOpacity.clamp(widget.minOpacity, 1.0);
        });
      }
    } catch (e) {
      // Игнорируем ошибки при обновлении
      debugPrint('FadeToBottomItem: Error updating opacity: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Обновляем opacity при каждом скролле
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateOpacity();
        });
        return false;
      },
      child: Opacity(
        key: _key,
        opacity: _opacity,
        child: widget.child,
      ),
    );
  }
}




