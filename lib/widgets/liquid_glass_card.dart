import 'package:flutter/material.dart';

class LiquidGlassCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final double borderRadius;
  final VoidCallback? onTap;
  final Object? settings;
  final double? blur;
  final bool? useFakeGlass;

  const LiquidGlassCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 20,
    this.onTap,
    this.settings,
    this.blur,
    this.useFakeGlass,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final content = SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );

    Widget result = Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        side: BorderSide(
          color: theme.dividerColor.withOpacity(0.25),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              child: content,
            ),
    );

    if (margin != null) {
      result = Padding(padding: margin!, child: result);
    }

    return result;
  }
}

class LiquidGlassButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;
  final double? width;
  final double? height;
  final double borderRadius;
  final Color? color;
  final Object? settings;

  const LiquidGlassButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.width,
    this.height,
    this.borderRadius = 16,
    this.color,
    this.settings,
  });

  @override
  State<LiquidGlassButton> createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<LiquidGlassButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = widget.color ?? theme.colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTap: () {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: widget.height ?? 56,
            minWidth: widget.width ?? 0,
          ),
          child: FilledButton(
            onPressed: widget.onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.borderRadius),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class SmallGlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Object settings;
  final double size;

  const SmallGlassButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.settings,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primary,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.58, color: Colors.white),
        ),
      ),
    );
  }
}

class LiquidGlassExerciseCard extends StatelessWidget {
  final String title;
  final String sets;
  final String reps;
  final String weight;
  final VoidCallback? onTap;

  const LiquidGlassExerciseCard({
    super.key,
    required this.title,
    required this.sets,
    required this.reps,
    required this.weight,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlassCard(
      onTap: onTap,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade200,
            ),
            child: const Icon(
              Icons.fitness_center_rounded,
              color: Colors.black87,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildBadge(sets),
                    const SizedBox(width: 8),
                    _buildBadge(reps),
                    const SizedBox(width: 8),
                    _buildBadge(weight),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade200,
            ),
            child: const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.black54,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Карточка упражнения с эффектом жидкого стекла (для светлого фона)
/// Использует старый стиль содержимого с новым стеклянным фоном
class LiquidGlassExerciseCardLight extends StatelessWidget {
  final String title;
  final String sets;
  final String reps;
  final String weight;
  final VoidCallback? onTap;

  const LiquidGlassExerciseCardLight({
    super.key,
    required this.title,
    required this.sets,
    required this.reps,
    required this.weight,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).dividerColor.withOpacity(0.25),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  _buildAdaptiveChipsRow(context),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey[400],
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdaptiveChipsRow(BuildContext context) {
    final chips = [sets, reps, if (weight.isNotEmpty) weight];

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        final availableWidth = constraints.maxWidth;

        final isCompact = screenWidth < 360 || availableWidth < 200;
        final isMedium = screenWidth < 400 || availableWidth < 250;

        final fontSize = isCompact ? 10.0 : (isMedium ? 11.0 : 12.0);
        final horizontalPadding = isCompact ? 5.0 : (isMedium ? 6.0 : 8.0);
        final verticalPadding = isCompact ? 2.0 : 3.0;
        final spacing = isCompact ? 4.0 : (isMedium ? 6.0 : 8.0);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < chips.length; i++) ...[
              Flexible(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    vertical: verticalPadding,
                    horizontal: horizontalPadding,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A3A3A),
                    borderRadius: BorderRadius.circular(isCompact ? 6 : 8),
                  ),
                  child: Text(
                    chips[i],
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (i < chips.length - 1) SizedBox(width: spacing),
            ],
          ],
        );
      },
    );
  }
}

/// Максимально оптимизированная карточка упражнения без эффекта жидкого стекла
/// Использует простой BackdropFilter для минимальной нагрузки на GPU
/// Рекомендуется для слабых устройств или когда на экране много карточек
class LiquidGlassExerciseCardUltraLight extends StatelessWidget {
  final String title;
  final String sets;
  final String reps;
  final String weight;
  final VoidCallback? onTap;
  final Widget? actions; // нижняя панель действий внутри карточки
  final VoidCallback? onInfoTap; // отдельная кнопка Инфо справа от текста
  final VoidCallback?
      onReplaceTap; // кнопка замены упражнения (для режима редактирования)
  final bool isEditMode; // режим редактирования
  final Function(int)? onSetsEdit; // колбэк для изменения подходов
  final Function(int)? onRepsEdit; // колбэк для изменения повторений
  final Function(double)? onWeightEdit; // колбэк для изменения веса
  final int? completedSets; // количество выполненных подходов
  final int? totalSets; // общее количество подходов

  const LiquidGlassExerciseCardUltraLight({
    super.key,
    required this.title,
    required this.sets,
    required this.reps,
    required this.weight,
    this.onTap,
    this.actions,
    this.onInfoTap,
    this.onReplaceTap,
    this.isEditMode = false,
    this.onSetsEdit,
    this.onRepsEdit,
    this.onWeightEdit,
    this.completedSets,
    this.totalSets,
  });

  @override
  Widget build(BuildContext context) {
    // В режиме редактирования используем упрощенный вариант без тяжелых эффектов
    if (isEditMode) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.black.withOpacity(0.08),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    _buildAdaptiveChipsRow(context),
                  ],
                ),
              ),
              // Кнопка замены в режиме редактирования
              if (onReplaceTap != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onReplaceTap,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3498DB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.swap_horiz,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.black.withOpacity(0.08),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      _buildAdaptiveChipsRow(context),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isEditMode && onReplaceTap != null)
                  IconButton(
                    onPressed: onReplaceTap,
                    icon: const Icon(Icons.swap_horiz),
                    color: const Color(0xFF007AFF),
                  )
                else if (!isEditMode && onInfoTap != null)
                  IconButton(
                    onPressed: onInfoTap,
                    icon: const Icon(Icons.info_outline),
                    color: const Color(0xFF007AFF),
                  ),
              ],
            ),
            if (completedSets != null &&
                totalSets != null &&
                totalSets! > 0 &&
                !isEditMode) ...[
              const SizedBox(height: 8),
              _buildProgressBar(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final progress = completedSets! / totalSets!;
    final isCompleted = progress >= 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 6,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Container(color: Colors.black.withOpacity(0.06)),
              ),
              if (progress > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        color: isCompleted
                            ? const Color(0xFF34C759)
                            : const Color(0xFF007AFF),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$completedSets из $totalSets',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            if (isCompleted)
              const Icon(
                Icons.check_circle,
                size: 14,
                color: Colors.green,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAdaptiveChipsRow(BuildContext context) {
    final chips = <Widget>[
      _AdaptiveChip(
        text: sets,
        type: 'sets',
        isEditMode: isEditMode,
        onEdit: onSetsEdit != null
            ? () => _showEditDialog(context, 'Подходы', sets, (value) {
                  final intValue = int.tryParse(value);
                  if (intValue != null && intValue > 0) {
                    onSetsEdit!(intValue);
                  }
                })
            : null,
      ),
      _AdaptiveChip(
        text: reps,
        type: 'reps',
        isEditMode: isEditMode,
        onEdit: onRepsEdit != null
            ? () => _showEditDialog(context, 'Повторения', reps, (value) {
                  final intValue = int.tryParse(value);
                  if (intValue != null && intValue > 0) {
                    onRepsEdit!(intValue);
                  }
                })
            : null,
      ),
      if (weight.isNotEmpty)
        _AdaptiveChip(
          text: weight,
          type: 'weight',
          isEditMode: isEditMode,
          onEdit: onWeightEdit != null
              ? () => _showEditDialog(context, 'Вес (кг)', weight, (value) {
                    final doubleValue =
                        double.tryParse(value.replaceAll(',', '.'));
                    if (doubleValue != null && doubleValue >= 0) {
                      onWeightEdit!(doubleValue);
                    }
                  })
              : null,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        final availableWidth = constraints.maxWidth;

        final isCompact = screenWidth < 360 || availableWidth < 200;
        final isMedium = screenWidth < 400 || availableWidth < 250;

        final spacing = isCompact ? 4.0 : (isMedium ? 6.0 : 8.0);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < chips.length; i++) ...[
              Flexible(
                child: _AdaptiveChipContainer(
                  isCompact: isCompact,
                  isMedium: isMedium,
                  child: chips[i],
                ),
              ),
              if (i < chips.length - 1) SizedBox(width: spacing),
            ],
          ],
        );
      },
    );
  }

  void _showEditDialog(
    BuildContext context,
    String title,
    String currentValue,
    Function(String) onSave,
  ) {
    // Извлекаем числовое значение из текста (например, "3 подхода" -> "3")
    final numericValue = currentValue.split(' ')[0];
    final controller = TextEditingController(text: numericValue);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onSubmitted: (value) {
                      if (value.isNotEmpty) {
                        onSave(value);
                        Navigator.of(sheetContext).pop();
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('Отмена'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            final value = controller.text;
                            if (value.isNotEmpty) {
                              onSave(value);
                              Navigator.of(sheetContext).pop();
                            }
                          },
                          child: const Text('Сохранить'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AdaptiveChip extends StatelessWidget {
  final String text;
  final String type;
  final bool isEditMode;
  final VoidCallback? onEdit;

  const _AdaptiveChip({
    required this.text,
    required this.type,
    required this.isEditMode,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _AdaptiveChipContainer extends StatelessWidget {
  final bool isCompact;
  final bool isMedium;
  final Widget child;

  const _AdaptiveChipContainer({
    required this.isCompact,
    required this.isMedium,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = isCompact ? 10.0 : (isMedium ? 11.0 : 12.0);
    final horizontalPadding = isCompact ? 5.0 : (isMedium ? 6.0 : 8.0);
    final verticalPadding = isCompact ? 2.0 : 3.0;

    if (child is _AdaptiveChip) {
      final chip = child as _AdaptiveChip;

      final chipWidget = Container(
        padding: EdgeInsets.symmetric(
          vertical: verticalPadding,
          horizontal: horizontalPadding,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF3A3A3A),
          borderRadius: BorderRadius.circular(isCompact ? 6 : 8),
        ),
        child: Text(
          chip.text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );

      if (!chip.isEditMode || chip.onEdit == null) {
        return chipWidget;
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: chip.onEdit,
        child: chipWidget,
      );
    }

    return child;
  }
}
