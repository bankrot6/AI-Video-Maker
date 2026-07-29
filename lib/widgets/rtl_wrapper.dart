import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/localization/app_localization_service.dart';
import '../services/localization/rtl_helper.dart';

/// Виджет-обертка для автоматической поддержки RTL языков
/// Автоматически определяет направление текста на основе текущего языка
class RTLWrapper extends ConsumerWidget {
  final Widget child;

  const RTLWrapper({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLanguage = ref.watch(currentLanguageProvider);
    final textDirection = RTLHelper.getTextDirection(currentLanguage);

    return Directionality(
      textDirection: textDirection,
      child: child,
    );
  }
}

/// Расширение для BuildContext для удобного доступа к RTL функциям
extension RTLExtension on BuildContext {
  /// Проверяет, является ли текущий язык RTL
  bool get isRTL {
    final locale = Localizations.localeOf(this);
    final language = RTLHelper.getLanguageFromLocale(locale);
    return RTLHelper.isRTL(language);
  }

  /// Получает направление текста для текущего языка
  TextDirection get textDirection {
    return isRTL ? TextDirection.rtl : TextDirection.ltr;
  }

  /// Возвращает EdgeInsets с учетом RTL
  /// Для RTL языков start и end меняются местами
  EdgeInsets rtlPadding({
    double start = 0.0,
    double top = 0.0,
    double end = 0.0,
    double bottom = 0.0,
  }) {
    if (isRTL) {
      return EdgeInsets.only(
        left: end,
        top: top,
        right: start,
        bottom: bottom,
      );
    } else {
      return EdgeInsets.only(
        left: start,
        top: top,
        right: end,
        bottom: bottom,
      );
    }
  }

  /// Возвращает Alignment с учетом RTL
  Alignment rtlAlignment(Alignment ltrAlignment) {
    if (!isRTL) return ltrAlignment;

    // Для RTL инвертируем горизонтальное выравнивание
    return Alignment(
      -ltrAlignment.x, // Инвертируем X координату
      ltrAlignment.y,
    );
  }

  /// Возвращает MainAxisAlignment с учетом RTL
  MainAxisAlignment rtlMainAxisAlignment(MainAxisAlignment ltrAlignment) {
    if (!isRTL) return ltrAlignment;

    switch (ltrAlignment) {
      case MainAxisAlignment.start:
        return MainAxisAlignment.end;
      case MainAxisAlignment.end:
        return MainAxisAlignment.start;
      default:
        return ltrAlignment;
    }
  }

  /// Возвращает CrossAxisAlignment с учетом RTL
  CrossAxisAlignment rtlCrossAxisAlignment(CrossAxisAlignment ltrAlignment) {
    if (!isRTL) return ltrAlignment;

    switch (ltrAlignment) {
      case CrossAxisAlignment.start:
        return CrossAxisAlignment.end;
      case CrossAxisAlignment.end:
        return CrossAxisAlignment.start;
      default:
        return ltrAlignment;
    }
  }
}
