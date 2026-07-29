import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui' as ui;
import '../chat_storage_service.dart';

// Импорты для файлов локализации
import 'ru_strings.dart';
import 'locale/ru.dart' as ru_locale;
import 'en_strings.dart';
import 'es_strings.dart';
import 'ar_strings.dart';
import 'fr_strings.dart';
import 'frCA_strings.dart';
import 'fil_strings.dart';
import 'ja_strings.dart';
import 'it_strings.dart';
import 'ko_strings.dart';
import 'ptBR_strings.dart';
import 'pt_strings.dart';
import 'zh_strings.dart';
import 'uk_strings.dart';
import 'th_strings.dart';
import 'el_strings.dart';
import 'tr_strings.dart';
import 'vi_strings.dart';
import 'hi_strings.dart';
import 'de_strings.dart';
import 'hu_strings.dart';
import 'da_strings.dart';
import 'he_strings.dart';
import 'id_strings.dart';
import 'esMX_strings.dart';
import 'ca_strings.dart';
import 'zhTW_strings.dart';
import 'ms_strings.dart';
import 'nl_strings.dart';
import 'no_strings.dart';
import 'pl_strings.dart';
import 'ro_strings.dart';
import 'sk_strings.dart';
import 'fi_strings.dart';
import 'hr_strings.dart';
import 'cs_strings.dart';
import 'sv_strings.dart';

/// Список поддерживаемых языков в приложении
enum AppLanguage {
  /// Русский язык
  ru,

  /// Английский язык
  en,

  /// Испанский язык
  es,

  /// Арабский язык
  ar,

  /// Французский язык
  fr,

  /// Французский язык (Канада)
  frCA,

  /// Филипинский язык
  fil,

  /// Японский язык
  ja,

  /// Итальянский язык
  it,

  /// Корейский язык
  ko,

  /// Португальский язык (Бразилия)
  ptBR,

  /// Португальский язык
  pt,

  /// Китайский язык
  zh,

  /// Украинский язык
  uk,

  /// Тайский язык
  th,

  /// Греческий язык
  el,

  /// Турецкий язык
  tr,

  /// Вьетнамский язык
  vi,

  /// Хинди
  hi,

  /// Немецкий язык
  de,

  /// Венгерский язык
  hu,

  /// Датский язык
  da,

  /// Иврит
  he,

  /// Индонезийский язык
  id,

  /// Испанский язык (Мексика)
  esMX,

  /// Каталанский язык
  ca,

  /// Китайский язык (традиционный)
  zhTW,

  /// Малайский язык
  ms,

  /// Голландский язык
  nl,

  /// Норвежский язык
  no,

  /// Польский язык
  pl,

  /// Румынский язык
  ro,

  /// Словацкий язык
  sk,

  /// Финский язык
  fi,

  /// Хорватский язык
  hr,

  /// Чешский язык
  cs,

  /// Шведский язык
  sv,
}

/// Интерфейс для сервиса локализации
/// Следует принципу разделения интерфейсов (Interface Segregation) из SOLID
abstract class IAppLocalizationService {
  /// Получить текущий язык приложения
  AppLanguage getCurrentLanguage();

  /// Изменить язык приложения
  Future<void> setLanguage(AppLanguage language);

  /// Загрузить сохраненные настройки языка
  Future<void> loadSavedLanguage();

  /// Получить локализованный текст
  String translate(String key);

  /// Получить локализованный текст с параметрами
  String translateWithParams(String key, List<String> params);

  /// Получить строку локали в формате, совместимом с intl библиотекой
  String getIntlLocaleString();

  /// Проверить, является ли текущий язык RTL
  bool isCurrentLanguageRTL();
}

/// Сервис для работы с локализацией приложения
/// Реализует принцип единственной ответственности (Single Responsibility) из SOLID
class AppLocalizationService implements IAppLocalizationService {
  static const String _languagePrefsKey = 'app_language';

  /// Текущий язык приложения
  AppLanguage _currentLanguage = AppLanguage.en;

  /// Объект для работы с хранилищем настроек
  final SharedPreferences _prefs;

  /// Конструктор сервиса локализации
  AppLocalizationService(this._prefs);

  @override
  AppLanguage getCurrentLanguage() {
    return _currentLanguage;
  }

  @override
  Future<void> setLanguage(AppLanguage language) async {
    _currentLanguage = language;
    await _prefs.setString(_languagePrefsKey, language.name);
    // Дополнительно: очищаем историю чата, чтобы приветствие было на новом языке при следующем входе
    try {
      final chatStorageService = await ChatStorageService.create();
      await chatStorageService.clearAllHistory();
    } catch (e) {
      debugPrint('⚠️ Не удалось очистить чат при смене языка: $e');
    }
  }

  /// Получить язык устройства
  AppLanguage _getDeviceLanguage() {
    // Получаем языковые настройки устройства
    final deviceLocale = ui.PlatformDispatcher.instance.locale;
    final String langCode = deviceLocale.languageCode.toLowerCase();
    final String countryCode = deviceLocale.countryCode?.toLowerCase() ?? '';

    // Проверяем языковой код
    if (langCode == 'ru') {
      return AppLanguage.ru;
    } else if (langCode == 'es') {
      // Проверяем испанский язык для Мексики
      if (countryCode == 'mx') {
        return AppLanguage.esMX;
      }
      return AppLanguage.es;
    } else if (langCode == 'ar') {
      return AppLanguage.ar;
    } else if (langCode == 'fr') {
      // Проверяем французский язык для Канады
      if (countryCode == 'ca') {
        return AppLanguage.frCA;
      }
      return AppLanguage.fr;
    } else if (langCode == 'fil' || langCode == 'tl') {
      return AppLanguage.fil;
    } else if (langCode == 'ja') {
      return AppLanguage.ja;
    } else if (langCode == 'it') {
      return AppLanguage.it;
    } else if (langCode == 'ko') {
      return AppLanguage.ko;
    } else if (langCode == 'pt') {
      // Проверяем португальский язык для Бразилии
      if (countryCode == 'br') {
        return AppLanguage.ptBR;
      }
      return AppLanguage.pt;
    } else if (langCode == 'zh') {
      // Проверяем китайский язык для Тайваня
      if (countryCode == 'tw' || countryCode == 'hk') {
        return AppLanguage.zhTW;
      }
      return AppLanguage.zh;
    } else if (langCode == 'uk') {
      return AppLanguage.uk;
    } else if (langCode == 'th') {
      return AppLanguage.th;
    } else if (langCode == 'el') {
      return AppLanguage.el;
    } else if (langCode == 'tr') {
      return AppLanguage.tr;
    } else if (langCode == 'vi') {
      return AppLanguage.vi;
    } else if (langCode == 'hi') {
      return AppLanguage.hi;
    } else if (langCode == 'de') {
      return AppLanguage.de;
    } else if (langCode == 'hu') {
      return AppLanguage.hu;
    } else if (langCode == 'da') {
      return AppLanguage.da;
    } else if (langCode == 'he') {
      return AppLanguage.he;
    } else if (langCode == 'id') {
      return AppLanguage.id;
    } else if (langCode == 'ca') {
      return AppLanguage.ca;
    } else if (langCode == 'ms') {
      return AppLanguage.ms;
    } else if (langCode == 'nl') {
      return AppLanguage.nl;
    } else if (langCode == 'no' || langCode == 'nb') {
      return AppLanguage.no;
    } else if (langCode == 'pl') {
      return AppLanguage.pl;
    } else if (langCode == 'ro') {
      return AppLanguage.ro;
    } else if (langCode == 'sk') {
      return AppLanguage.sk;
    } else if (langCode == 'fi') {
      return AppLanguage.fi;
    } else if (langCode == 'hr') {
      return AppLanguage.hr;
    } else if (langCode == 'cs') {
      return AppLanguage.cs;
    } else if (langCode == 'sv') {
      return AppLanguage.sv;
    }

    return AppLanguage.en;
  }

  @override
  Future<void> loadSavedLanguage() async {
    final savedLanguage = _prefs.getString(_languagePrefsKey);
    if (savedLanguage != null) {
      // Пытаемся найти сохраненный язык
      for (final language in AppLanguage.values) {
        if (language.name == savedLanguage) {
          _currentLanguage = language;
          return;
        }
      }
    }

    // Если сохраненного языка нет или он не найден, используем язык устройства
    _currentLanguage = _getDeviceLanguage();
  }

  @override
  String translate(String key) {
    switch (_currentLanguage) {
      case AppLanguage.ru:
        return _getRussianTranslation(key) ?? key;
      case AppLanguage.es:
        return _getSpanishTranslation(key) ?? key;
      case AppLanguage.ar:
        return _getArabicTranslation(key) ?? key;
      case AppLanguage.fr:
        return _getFrenchTranslation(key) ?? key;
      case AppLanguage.frCA:
        return _getCanadianFrenchTranslation(key) ?? key;
      case AppLanguage.fil:
        return _getFilipinoTranslation(key) ?? key;
      case AppLanguage.ja:
        return _getJapaneseTranslation(key) ?? key;
      case AppLanguage.it:
        return _getItalianTranslation(key) ?? key;
      case AppLanguage.ko:
        return _getKoreanTranslation(key) ?? key;
      case AppLanguage.ptBR:
        return _getBrazilianPortugueseTranslation(key) ?? key;
      case AppLanguage.pt:
        return _getPortugueseTranslation(key) ?? key;
      case AppLanguage.zh:
        return _getChineseTranslation(key) ?? key;
      case AppLanguage.uk:
        return _getUkrainianTranslation(key) ?? key;
      case AppLanguage.th:
        return _getThaiTranslation(key) ?? key;
      case AppLanguage.el:
        return _getGreekTranslation(key) ?? key;
      case AppLanguage.tr:
        return _getTurkishTranslation(key) ?? key;
      case AppLanguage.vi:
        return _getVietnameseTranslation(key) ?? key;
      case AppLanguage.hi:
        return _getHindiTranslation(key) ?? key;
      case AppLanguage.de:
        return _getGermanTranslation(key) ?? key;
      case AppLanguage.hu:
        return _getHungarianTranslation(key) ?? key;
      case AppLanguage.da:
        return _getDanishTranslation(key) ?? key;
      case AppLanguage.he:
        return _getHebrewTranslation(key) ?? key;
      case AppLanguage.id:
        return _getIndonesianTranslation(key) ?? key;
      case AppLanguage.esMX:
        return _getMexicanSpanishTranslation(key) ?? key;
      case AppLanguage.ca:
        return _getCatalanTranslation(key) ?? key;
      case AppLanguage.zhTW:
        return _getTraditionalChineseTranslation(key) ?? key;
      case AppLanguage.ms:
        return _getMalayTranslation(key) ?? key;
      case AppLanguage.nl:
        return _getDutchTranslation(key) ?? key;
      case AppLanguage.no:
        return _getNorwegianTranslation(key) ?? key;
      case AppLanguage.pl:
        return _getPolishTranslation(key) ?? key;
      case AppLanguage.ro:
        return _getRomanianTranslation(key) ?? key;
      case AppLanguage.sk:
        return _getSlovakTranslation(key) ?? key;
      case AppLanguage.fi:
        return _getFinnishTranslation(key) ?? key;
      case AppLanguage.hr:
        return _getCroatianTranslation(key) ?? key;
      case AppLanguage.cs:
        return _getCzechTranslation(key) ?? key;
      case AppLanguage.sv:
        return _getSwedishTranslation(key) ?? key;
      case AppLanguage.en:
        return _getEnglishTranslation(key) ?? key;
    }
  }

  @override
  String translateWithParams(String key, List<String> params) {
    String translatedText = translate(key);

    // Заменяем плейсхолдеры {0}, {1}, ... на соответствующие параметры
    for (int i = 0; i < params.length; i++) {
      translatedText = translatedText.replaceAll('{$i}', params[i]);
    }

    return translatedText;
  }

  /// Получить перевод на русский язык
  String? _getRussianTranslation(String key) {
    // Основной словарь (генерируемый): ruStrings
    // Резервный компактный словарь: ru_locale.ru
    return ruStrings[key] ?? ru_locale.ru[key];
  }

  /// Получить перевод на английский язык
  String? _getEnglishTranslation(String key) {
    return enStrings[key];
  }

  /// Получить перевод на испанский язык
  String? _getSpanishTranslation(String key) {
    return esStrings[key];
  }

  /// Получить перевод на арабский язык
  String? _getArabicTranslation(String key) {
    return arStrings[key];
  }

  /// Получить перевод на французский язык
  String? _getFrenchTranslation(String key) {
    return frStrings[key];
  }

  /// Получить перевод на французский язык для Канады
  String? _getCanadianFrenchTranslation(String key) {
    return frCAStrings[key];
  }

  /// Получить перевод на филипинский язык
  String? _getFilipinoTranslation(String key) {
    return filStrings[key];
  }

  /// Получить перевод на японский язык
  String? _getJapaneseTranslation(String key) {
    return jaStrings[key];
  }

  /// Получить перевод на итальянский язык
  String? _getItalianTranslation(String key) {
    return itStrings[key];
  }

  /// Получить перевод на корейский язык
  String? _getKoreanTranslation(String key) {
    return koStrings[key];
  }

  /// Получить перевод на португальский язык (Бразилия)
  String? _getBrazilianPortugueseTranslation(String key) {
    return ptBRStrings[key];
  }

  /// Получить перевод на португальский язык
  String? _getPortugueseTranslation(String key) {
    return ptStrings[key];
  }

  /// Получить перевод на китайский язык
  String? _getChineseTranslation(String key) {
    return zhStrings[key];
  }

  /// Получить перевод на украинский язык
  String? _getUkrainianTranslation(String key) {
    return ukStrings[key];
  }

  /// Получить перевод на тайский язык
  String? _getThaiTranslation(String key) {
    return thStrings[key];
  }

  /// Получить перевод на греческий язык
  String? _getGreekTranslation(String key) {
    return elStrings[key];
  }

  /// Получить перевод на турецкий язык
  String? _getTurkishTranslation(String key) {
    return trStrings[key];
  }

  /// Получить перевод на вьетнамский язык
  String? _getVietnameseTranslation(String key) {
    return viStrings[key];
  }

  /// Получить перевод на хинди
  String? _getHindiTranslation(String key) {
    return hiStrings[key];
  }

  /// Получить перевод на немецкий язык
  String? _getGermanTranslation(String key) {
    return deStrings[key];
  }

  /// Получить перевод на венгерский язык
  String? _getHungarianTranslation(String key) {
    return huStrings[key];
  }

  /// Получить перевод на датский язык
  String? _getDanishTranslation(String key) {
    return daStrings[key];
  }

  /// Получить перевод на иврит
  String? _getHebrewTranslation(String key) {
    return heStrings[key];
  }

  /// Получить перевод на индонезийский язык
  String? _getIndonesianTranslation(String key) {
    return idStrings[key];
  }

  /// Получить перевод на испанский язык (Мексика)
  String? _getMexicanSpanishTranslation(String key) {
    return esMXStrings[key];
  }

  /// Получить перевод на каталанский язык
  String? _getCatalanTranslation(String key) {
    return caStrings[key];
  }

  /// Получить перевод на китайский язык (традиционный)
  String? _getTraditionalChineseTranslation(String key) {
    return zhTWStrings[key];
  }

  /// Получить перевод на малайский язык
  String? _getMalayTranslation(String key) {
    return msStrings[key];
  }

  /// Получить перевод на голландский язык
  String? _getDutchTranslation(String key) {
    return nlStrings[key];
  }

  /// Получить перевод на норвежский язык
  String? _getNorwegianTranslation(String key) {
    return noStrings[key];
  }

  /// Получить перевод на польский язык
  String? _getPolishTranslation(String key) {
    return plStrings[key];
  }

  /// Получить перевод на румынский язык
  String? _getRomanianTranslation(String key) {
    return roStrings[key];
  }

  /// Получить перевод на словацкий язык
  String? _getSlovakTranslation(String key) {
    return skStrings[key];
  }

  /// Получить перевод на финский язык
  String? _getFinnishTranslation(String key) {
    return fiStrings[key];
  }

  /// Получить перевод на хорватский язык
  String? _getCroatianTranslation(String key) {
    return hrStrings[key];
  }

  /// Получить перевод на чешский язык
  String? _getCzechTranslation(String key) {
    return csStrings[key];
  }

  /// Получить перевод на шведский язык
  String? _getSwedishTranslation(String key) {
    return svStrings[key];
  }

  /// Получить строку локали в формате, совместимом с intl библиотекой
  @override
  String getIntlLocaleString() {
    switch (_currentLanguage) {
      case AppLanguage.ru:
        return 'ru';
      case AppLanguage.en:
        return 'en';
      case AppLanguage.es:
        return 'es';
      case AppLanguage.ar:
        return 'ar';
      case AppLanguage.fr:
        return 'fr';
      case AppLanguage.frCA:
        return 'fr_CA';
      case AppLanguage.fil:
        return 'fil';
      case AppLanguage.ja:
        return 'ja';
      case AppLanguage.it:
        return 'it';
      case AppLanguage.ko:
        return 'ko';
      case AppLanguage.ptBR:
        return 'pt_BR';
      case AppLanguage.pt:
        return 'pt';
      case AppLanguage.zh:
        return 'zh';
      case AppLanguage.uk:
        return 'uk';
      case AppLanguage.th:
        return 'th';
      case AppLanguage.el:
        return 'el';
      case AppLanguage.tr:
        return 'tr';
      case AppLanguage.vi:
        return 'vi';
      case AppLanguage.hi:
        return 'hi';
      case AppLanguage.de:
        return 'de';
      case AppLanguage.hu:
        return 'hu';
      case AppLanguage.da:
        return 'da';
      case AppLanguage.he:
        return 'he';
      case AppLanguage.id:
        return 'id';
      case AppLanguage.esMX:
        return 'es_MX';
      case AppLanguage.ca:
        return 'ca';
      case AppLanguage.zhTW:
        return 'zh_TW';
      case AppLanguage.ms:
        return 'ms';
      case AppLanguage.nl:
        return 'nl';
      case AppLanguage.no:
        return 'no';
      case AppLanguage.pl:
        return 'pl';
      case AppLanguage.ro:
        return 'ro';
      case AppLanguage.sk:
        return 'sk';
      case AppLanguage.fi:
        return 'fi';
      case AppLanguage.hr:
        return 'hr';
      case AppLanguage.cs:
        return 'cs';
      case AppLanguage.sv:
        return 'sv';
    }
  }

  @override
  bool isCurrentLanguageRTL() {
    return _currentLanguage == AppLanguage.ar ||
        _currentLanguage == AppLanguage.he;
  }

  /// Статический delegate для Flutter локализации
  static const LocalizationsDelegate<AppLocalizationService> delegate =
      _AppLocalizationDelegate();

  /// Поддерживаемые локали
  static const List<Locale> supportedLocales = [
    Locale('en', 'US'),
    Locale('ru', 'RU'),
    Locale('es', 'ES'),
    Locale('ar', 'SA'),
    Locale('he', 'IL'),
    Locale('fr', 'FR'),
    Locale('fr', 'CA'),
    Locale('fil', 'PH'),
    Locale('ja', 'JP'),
    Locale('it', 'IT'),
    Locale('ko', 'KR'),
    Locale('pt', 'BR'),
    Locale('pt', 'PT'),
    Locale('zh', 'CN'),
    Locale('uk', 'UA'),
    Locale('th', 'TH'),
    Locale('el', 'GR'),
    Locale('tr', 'TR'),
    Locale('vi', 'VN'),
    Locale('hi', 'IN'),
    Locale('de', 'DE'),
    Locale('hu', 'HU'),
    Locale('da', 'DK'),
    Locale('id', 'ID'),
    Locale('es', 'MX'),
    Locale('ca', 'ES'),
    Locale('zh', 'TW'),
    Locale('ms', 'MY'),
    Locale('nl', 'NL'),
    Locale('no', 'NO'),
    Locale('pl', 'PL'),
    Locale('ro', 'RO'),
    Locale('sk', 'SK'),
    Locale('fi', 'FI'),
    Locale('hr', 'HR'),
    Locale('cs', 'CZ'),
    Locale('sv', 'SE'),
  ];
}

/// Delegate для локализации
class _AppLocalizationDelegate
    extends LocalizationsDelegate<AppLocalizationService> {
  const _AppLocalizationDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizationService.supportedLocales.any((supportedLocale) =>
        supportedLocale.languageCode == locale.languageCode);
  }

  @override
  Future<AppLocalizationService> load(Locale locale) async {
    // Получаем SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final service = AppLocalizationService(prefs);
    await service.loadSavedLanguage();
    return service;
  }

  @override
  bool shouldReload(LocalizationsDelegate<AppLocalizationService> old) => false;
}

/// Провайдер для SharedPreferences
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
      'SharedPreferences должен быть инициализирован в main()');
});

/// Riverpod провайдер для сервиса локализации
final appLocalizationServiceProvider = Provider<IAppLocalizationService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return AppLocalizationService(prefs);
});

/// Провайдер для отслеживания текущего языка приложения
final currentLanguageProvider =
    StateNotifierProvider<LanguageNotifier, AppLanguage>((ref) {
  final localizationService = ref.watch(appLocalizationServiceProvider);
  return LanguageNotifier(localizationService);
});

/// Notifier для управления текущим языком
class LanguageNotifier extends StateNotifier<AppLanguage> {
  final IAppLocalizationService _localizationService;

  LanguageNotifier(this._localizationService)
      : super(_localizationService.getCurrentLanguage());

  /// Изменить язык приложения
  Future<void> setLanguage(AppLanguage language) async {
    await _localizationService.setLanguage(language);
    state = language;
  }

  /// Загрузить сохраненный язык
  Future<void> loadSavedLanguage() async {
    await _localizationService.loadSavedLanguage();
    state = _localizationService.getCurrentLanguage();
  }
}

/// Расширение для удобного доступа к локализованному тексту
extension LocalizationExtension on BuildContext {
  /// Получить локализованный текст по ключу
  String tr(String key) {
    final container = ProviderScope.containerOf(this);
    final localizationService = container.read(appLocalizationServiceProvider);
    return localizationService.translate(key);
  }

  /// Получить локализованный текст по ключу с параметрами
  String trParams(String key, List<String> params) {
    final container = ProviderScope.containerOf(this);
    final localizationService = container.read(appLocalizationServiceProvider);
    return localizationService.translateWithParams(key, params);
  }
}
