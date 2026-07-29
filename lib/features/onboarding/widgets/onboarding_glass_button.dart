import 'package:flutter/material.dart';
import '../../../widgets/liquid_glass_stub.dart';
import '../../../widgets/glass_settings_constants.dart';

/// Стеклянная кнопка для онбоардинга с эффектом жидкого стекла
class OnboardingGlassButton extends StatefulWidget {
  /// Рекомендуемая высота кнопки (используется для вертикальных отступов)
  static const double recommendedHeight = 56.0;

  final String text;
  final bool isSelected;
  final VoidCallback onPressed;

  /// Дополнительные отступы вокруг кнопки (не внутри).
  final EdgeInsetsGeometry margin;

  /// Внутренние отступы
  final EdgeInsetsGeometry padding;

  /// Необязательные виджеты слева/справа (например, иконка стрелки)
  final Widget? leading;
  final Widget? trailing;

  /// Сильно выделять выбранное состояние (добавляет галочку)
  final bool emphasizeSelection;

  const OnboardingGlassButton({
    super.key,
    required this.text,
    required this.isSelected,
    required this.onPressed,
    this.margin = const EdgeInsets.only(top: 12),
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    this.leading,
    this.trailing,
    this.emphasizeSelection = false,
  });

  @override
  State<OnboardingGlassButton> createState() => _OnboardingGlassButtonState();
}

class _OnboardingGlassButtonState extends State<OnboardingGlassButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    const double checkIconSize = 20;
    const double iconGap = 8;
    const double sideIconCellWidth = checkIconSize + iconGap;

    // iOS‑style пресеты
    final glassSettings = widget.isSelected
        ? GlassSettingsConstants.ios26ButtonSelected
        : GlassSettingsConstants.ios26Button;

    return Container(
      margin: widget.margin,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: FakeGlass(
            shape: const LiquidRoundedSuperellipse(
              borderRadius: Radius.circular(999), // Капсульная форма
            ),
            settings: glassSettings,
            child: Container(
              padding: widget.padding,
              decoration: widget.emphasizeSelection && widget.isSelected
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.6),
                        width: 2,
                      ),
                    )
                  : null,
              child: widget.emphasizeSelection
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: sideIconCellWidth,
                          child: widget.isSelected
                              ? const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Icon(
                                    Icons.check_rounded,
                                    size: checkIconSize,
                                    color: Colors.black,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        Flexible(
                          child: Text(
                            widget.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              shadows: widget.isSelected
                                  ? [
                                      Shadow(
                                        color: Colors.black.withOpacity(0.3),
                                        offset: const Offset(0, 1),
                                        blurRadius: 2,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: sideIconCellWidth),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.leading != null) ...[
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: widget.leading!,
                          ),
                        ],
                        Flexible(
                          child: Text(
                            widget.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              shadows: widget.isSelected
                                  ? [
                                      Shadow(
                                        color: Colors.black.withOpacity(0.3),
                                        offset: const Offset(0, 1),
                                        blurRadius: 2,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                        if (widget.trailing != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: widget.trailing!,
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
