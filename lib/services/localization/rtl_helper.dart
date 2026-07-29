import 'package:flutter/material.dart';
import 'app_localization_service.dart';

/// Утилита для работы с RTL (Right-to-Left) языками
class RTLHelper {
  /// Список языков, которые пишутся справа налево
  static const Set<AppLanguage> _rtlLanguages = {
    AppLanguage.ar, // Арабский
    AppLanguage.he, // Иврит
  };

  /// Проверяет, является ли язык RTL
  static bool isRTL(AppLanguage language) {
    return _rtlLanguages.contains(language);
  }

  /// Получает направление текста для указанного языка
  static TextDirection getTextDirection(AppLanguage language) {
    return isRTL(language) ? TextDirection.rtl : TextDirection.ltr;
  }

  /// Получает направление текста для текущего языка из контекста
  static TextDirection getTextDirectionFromContext(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final language = getLanguageFromLocale(locale);
    return getTextDirection(language);
  }

  /// Преобразует Locale в AppLanguage
  static AppLanguage getLanguageFromLocale(Locale locale) {
    switch (locale.languageCode) {
      case 'ar':
        return AppLanguage.ar;
      case 'he':
        return AppLanguage.he;
      case 'ru':
        return AppLanguage.ru;
      case 'es':
        return AppLanguage.es;
      case 'fr':
        if (locale.countryCode == 'CA') {
          return AppLanguage.frCA;
        }
        return AppLanguage.fr;
      case 'pt':
        if (locale.countryCode == 'BR') {
          return AppLanguage.ptBR;
        }
        return AppLanguage.pt;
      case 'zh':
        if (locale.countryCode == 'TW') {
          return AppLanguage.zhTW;
        }
        return AppLanguage.zh;
      case 'fil':
        return AppLanguage.fil;
      case 'ja':
        return AppLanguage.ja;
      case 'it':
        return AppLanguage.it;
      case 'ko':
        return AppLanguage.ko;
      case 'uk':
        return AppLanguage.uk;
      case 'th':
        return AppLanguage.th;
      case 'el':
        return AppLanguage.el;
      case 'tr':
        return AppLanguage.tr;
      case 'vi':
        return AppLanguage.vi;
      case 'hi':
        return AppLanguage.hi;
      case 'de':
        return AppLanguage.de;
      case 'hu':
        return AppLanguage.hu;
      case 'da':
        return AppLanguage.da;
      case 'id':
        return AppLanguage.id;
      case 'ca':
        return AppLanguage.ca;
      case 'ms':
        return AppLanguage.ms;
      case 'nl':
        return AppLanguage.nl;
      case 'no':
        return AppLanguage.no;
      case 'pl':
        return AppLanguage.pl;
      case 'ro':
        return AppLanguage.ro;
      case 'sk':
        return AppLanguage.sk;
      case 'fi':
        return AppLanguage.fi;
      case 'hr':
        return AppLanguage.hr;
      case 'cs':
        return AppLanguage.cs;
      case 'sv':
        return AppLanguage.sv;
      default:
        return AppLanguage.en;
    }
  }

  /// Создает Directionality виджет с правильным направлением текста
  static Widget wrapWithDirectionality({
    required BuildContext context,
    required Widget child,
    AppLanguage? language,
  }) {
    final textDirection = language != null
        ? getTextDirection(language)
        : getTextDirectionFromContext(context);

    return Directionality(
      textDirection: textDirection,
      child: child,
    );
  }
}
