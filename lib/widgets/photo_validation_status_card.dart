import 'package:flutter/material.dart';

import '../services/photo_input_validation_service.dart';
import '../theme/semantic_colors.dart';

class PhotoValidationStatusCard extends StatelessWidget {
  const PhotoValidationStatusCard({
    super.key,
    required this.isChecking,
    required this.result,
  });

  final bool isChecking;
  final PhotoInputValidationResult? result;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;

    if (!isChecking && result == null) {
      return const SizedBox.shrink();
    }

    final Color foregroundColor;
    final Color borderColor;
    final String text;

    if (isChecking) {
      foregroundColor = colors.primary;
      borderColor = colors.primary.withOpacity(0.28);
      text = 'Проверяем, подходит ли фото';
    } else {
      switch (result!.severity) {
        case PhotoValidationSeverity.valid:
          foregroundColor = semantic.success;
          borderColor = semantic.success.withValues(alpha: 0.32);
          break;
        case PhotoValidationSeverity.warning:
          foregroundColor = semantic.warning;
          borderColor = semantic.warning.withValues(alpha: 0.32);
          break;
        case PhotoValidationSeverity.error:
          foregroundColor = colors.error;
          borderColor = colors.error.withValues(alpha: 0.32);
          break;
      }
      text = _compactText(result!);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: Padding(
        key: ValueKey(
          '$isChecking-${result?.severity}-${result?.title}-${result?.message}',
        ),
        padding: const EdgeInsets.only(top: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.25,
              fontWeight: FontWeight.w500,
              color: foregroundColor.withOpacity(0.92),
            ),
          ),
        ),
      ),
    );
  }

  String _compactText(PhotoInputValidationResult result) {
    switch (result.severity) {
      case PhotoValidationSeverity.valid:
        return 'Фото подходит для генерации';
      case PhotoValidationSeverity.warning:
        if (result.title == 'Лицо можно взять крупнее') {
          return 'Фото подходит, но лучше крупнее';
        }
        if (result.title == 'Лицо близко к краю') {
          return 'Фото подходит, но лицо близко к краю';
        }
        if (result.title == 'Голова заметно повернута') {
          return 'Фото подходит, но лучше прямой ракурс';
        }
        return 'Фото подходит, но есть нюанс';
      case PhotoValidationSeverity.error:
        if (result.title == 'Лицо не найдено') {
          return 'Фото не подходит: лицо не найдено';
        }
        if (result.title == 'На фото несколько лиц') {
          return 'Фото не подходит: нужно одно лицо';
        }
        if (result.title == 'Не удалось проверить фото') {
          return 'Фото не удалось проверить';
        }
        if (result.title == 'Лицо слишком далеко') {
          return 'Фото не подходит: лицо слишком далеко';
        }
        if (result.title == 'Лицо обрезано') {
          return 'Фото не подходит: лицо обрезано';
        }
        if (result.title == 'Фото недоступно') {
          return 'Фото недоступно';
        }
        if (result.title == 'Проверка не удалась') {
          return 'Ошибка при проверке фото';
        }
        return 'Фото не подходит';
    }
  }
}
