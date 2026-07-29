import 'package:flutter/material.dart';
import '../../../models/weight_entry_model.dart';
import 'dart:ui' as ui;

/// Линейный график веса за неделю в минималистичном «apple-style»
class WeightLineChart extends StatelessWidget {
  const WeightLineChart(
      {super.key, required this.weeklyWeights, this.height = 140});

  /// Список весов за неделю (7 элементов, порядок с понедельника по воскресенье)
  final List<WeightEntryModel> weeklyWeights;

  /// Фиксированная высота графика
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _WeightLineChartPainter(
          weeklyWeights: weeklyWeights,
          primaryColor: Theme.of(context).primaryColor,
        ),
      ),
    );
  }
}

class _WeightLineChartPainter extends CustomPainter {
  _WeightLineChartPainter(
      {required this.weeklyWeights, required this.primaryColor});

  final List<WeightEntryModel> weeklyWeights;
  final Color primaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();

    // Отступы
    const double topPad = 12.0;
    const double bottomPad = 0.0;

    // Минимальные отступы для графика - основная область должна использовать всю ширину
    const double graphLeftPad = 16.0; // Небольшой отступ слева (не трогаем)
    const double graphRightPad =
        24.0; // Увеличиваем правый отступ для создания зазора до текста

    // Стиль текстовых подписей (например «100.0»)

    final chartHeight = size.height - topPad - bottomPad;

    // Ширина графика использует почти всю доступную ширину (значение не требуется явно)

    // Фильтруем данные: только до текущего дня (включительно) И только с валидным значением (> 0)
    final visible = weeklyWeights
        .where((entry) => !entry.dateTime.isAfter(now) && entry.weight > 0)
        .toList();

    // Рассчитываем позиции точек: первая точка на graphLeftPad, последняя на size.width - graphRightPad
    // Точки равномерно распределены между этими границами
    List<double> getPointPositions() {
      if (visible.isEmpty) return [];
      if (visible.length == 1) {
        return [size.width / 2]; // Центрируем единственную точку
      }

      final positions = <double>[];
      final startX = graphLeftPad;
      final endX = size.width - graphRightPad;
      final totalWidth = endX - startX;

      for (int i = 0; i < visible.length; i++) {
        // Равномерно распределяем точки от startX до endX
        final x = startX + (totalWidth * i / (visible.length - 1));
        positions.add(x);
      }
      return positions;
    }

    // Подготовим значения сетки. Если нет валидных данных — используем 0/5/10
    double minGrid;
    double maxGrid;
    if (visible.isEmpty) {
      minGrid = 0;
      maxGrid = 10;
    } else {
      // Находим минимум и максимум среди всех значений
      final weights = visible.map((e) => e.weight).toList();
      final minWeight = weights.reduce((a, b) => a < b ? a : b);
      final maxWeight = weights.reduce((a, b) => a > b ? a : b);
      
      // Добавляем отступы для красивого отображения
      final range = maxWeight - minWeight;
      final padding = range > 0 ? range * 0.2 : 5.0;
      
      minGrid = minWeight - padding;
      maxGrid = maxWeight + padding;
    }

    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..strokeWidth = 1.0;

    // Вычисляем оптимальный интервал для меток
    final range = maxGrid - minGrid;
    double interval = 1.0;
    if (range > 50) {
      interval = 10.0;
    } else if (range > 20) {
      interval = 5.0;
    } else if (range > 10) {
      interval = 2.0;
    } else if (range > 5) {
      interval = 1.0;
    } else {
      interval = 0.5;
    }

    // Находим начальное и конечное значение для меток (кратные интервалу)
    final startLabel = (minGrid / interval).ceil() * interval;
    final endLabel = (maxGrid / interval).floor() * interval;

    // Рисуем метки и линии сетки
    for (double value = startLabel; value <= endLabel; value += interval) {
      final normalized = (value - minGrid) / (maxGrid - minGrid);
      final y = topPad + (1 - normalized) * chartHeight;

      // Рисуем линию сетки
      canvas.drawLine(
        Offset(graphLeftPad, y),
        Offset(size.width - graphRightPad, y),
        gridPaint,
      );

      // Форматируем значение
      String formatLabel(double v) {
        if (v % 1 == 0) {
          return v.toStringAsFixed(0);
        } else if ((v * 10) % 1 == 0) {
          return v.toStringAsFixed(1);
        } else {
          return v.toStringAsFixed(2);
        }
      }

      final labelStr = formatLabel(value);

      final textSpan = TextSpan(
        text: labelStr,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: ui.TextDirection.ltr,
      )..layout();

      // Размещаем метки справа
      final labelX = size.width - tp.width - 4;
      final labelY = y - tp.height / 2;

      // Рисуем метку без фона
      tp.paint(canvas, Offset(labelX, labelY));
    }

    // Если данных нет — рисуем только сетку и выходим
    if (visible.isEmpty) {
      return;
    }

    // Функция нормализации веса к координате
    double mapWeight(double w) => (w - minGrid) / (maxGrid - minGrid);

    // Получаем позиции точек
    final pointPositions = getPointPositions();

    // Строим путь кривой по видимым данным
    final path = Path();
    bool firstPoint = true;
    double firstX = 0;
    double lastXPoint = 0;

    for (var i = 0; i < visible.length; i++) {
      final model = visible[i];
      final x = pointPositions[i];

      final normalized = mapWeight(model.weight).clamp(0.0, 1.0);
      final y = topPad + (1 - normalized) * chartHeight;

      if (firstPoint) {
        // Сохраняем координату первой точки ДО того как сбросим флаг
        firstX = x;
        path.moveTo(x, y);
        firstPoint = false;
      } else {
        path.lineTo(x, y);
      }
      lastXPoint = x;
    }

    // Заливка под кривой – спускаемся вертикально вниз от последней и первой точек
    final fillPath = Path.from(path)
      ..lineTo(lastXPoint, size.height)
      ..lineTo(firstX, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [primaryColor.withOpacity(0.25), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Линия
    final linePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    // Маркеры
    final dotPaint = Paint()..color = primaryColor;
    for (var i = 0; i < visible.length; i++) {
      final model = visible[i];
      final x = pointPositions[i];

      final y =
          topPad + (1 - mapWeight(model.weight).clamp(0.0, 1.0)) * chartHeight;
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WeightLineChartPainter oldDelegate) {
    return oldDelegate.weeklyWeights != weeklyWeights ||
        oldDelegate.primaryColor != primaryColor;
  }
}
