import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:device_region/device_region.dart';
import 'dart:async';

/// Сервис для работы с регионом и валютой пользователя
class RegionService {
  // Singleton
  static final RegionService _instance = RegionService._internal();
  factory RegionService() => _instance;
  RegionService._internal();

  // Константы для хранения настроек
  static const String _currencyCodeKey = 'user_currency_code';
  static const String _regionCodeKey = 'user_region_code';

  // Справочник кодов валют с их символами
  static const Map<String, String> _currencySymbols = {
    'RUB': '₽',
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    // Можно добавить другие валюты при необходимости
  };

  // Страны, относящиеся к России (для упрощения)
  static const List<String> _russianRegions = [
    'ru',
    'RU',
    'rus',
    'RUS',
    'ru_RU',
    'RU_ru',
  ];

  /// Получает код валюты пользователя (например, RUB, USD)
  Future<String> getCurrencyCode() async {
    try {
      // Пробуем получить сохраненное значение
      final prefs = await SharedPreferences.getInstance();
      final savedCurrency = prefs.getString(_currencyCodeKey);

      if (savedCurrency != null && savedCurrency.isNotEmpty) {
        debugPrint('💰 REGION: Загружена сохраненная валюта: $savedCurrency');
        return savedCurrency;
      }

      // Если нет сохраненной валюты, определяем по локали устройства
      final String currencyCode = await _detectCurrencyCode();

      // Сохраняем определенную валюту
      await prefs.setString(_currencyCodeKey, currencyCode);

      debugPrint('💰 REGION: Определена и сохранена валюта: $currencyCode');
      return currencyCode;
    } catch (e) {
      debugPrint('🔴 REGION: Ошибка при получении кода валюты: $e');
      return 'USD'; // Возвращаем USD по умолчанию в случае ошибки
    }
  }

  /// Возвращает символ валюты по коду
  Future<String> getCurrencySymbol() async {
    final String currencyCode = await getCurrencyCode();
    return _currencySymbols[currencyCode] ?? currencyCode;
  }

  /// Проверяет, является ли валюта пользователя рублем
  Future<bool> isRussianRuble() async {
    try {
      final String currencyCode = await getCurrencyCode();
      debugPrint('💰 REGION: Проверка валюты: $currencyCode');

      // Проверяем только рубль
      final bool isRub = currencyCode == 'RUB';

      debugPrint('💰 REGION: Результат проверки рубля: $isRub');
      return isRub;
    } catch (e) {
      debugPrint('🔴 REGION: Ошибка при проверке валюты: $e');
      return false;
    }
  }

  /// Определяет регион пользователя (приоритет SIM через device_region, затем локаль, затем быстрый IP)
  Future<String> getRegionCode() async {
    try {
      // Пробуем получить сохраненное значение
      final prefs = await SharedPreferences.getInstance();
      final savedRegion = prefs.getString(_regionCodeKey);

      if (savedRegion != null && savedRegion.isNotEmpty) {
        debugPrint('🌎 REGION: Загружен сохраненный регион: $savedRegion');
        return savedRegion;
      }

      // 1) Пытаемся получить страну по SIM через device_region
      try {
        final simCode = await DeviceRegion.getSIMCountryCode();
        if (simCode != null && simCode.isNotEmpty) {
          final regionCode = simCode.toUpperCase();
          await prefs.setString(_regionCodeKey, regionCode);
          debugPrint('🌎 REGION: Определен регион по SIM: $regionCode');
          return regionCode;
        }
      } catch (e) {
        debugPrint('🔸 REGION: Не удалось получить регион по SIM: $e');
      }

      // 2) Fallback: локаль устройства
      final locales = PlatformDispatcher.instance.locales;
      final String regionCode = locales.isNotEmpty
          ? locales.first.countryCode?.toUpperCase() ?? 'US'
          : 'US';

      // 3) Параллельно пробуем быстрый IP (не блокируем UI дольше 700мс)
      // Если успеем получить IP-страну, перезапишем и вернём её; иначе вернём локаль
      try {
        final ipFuture = getCountryByIp();
        final ipCode = await ipFuture.timeout(const Duration(milliseconds: 700),
            onTimeout: () => null);
        if (ipCode != null && ipCode.isNotEmpty) {
          final ipRegion = ipCode.toUpperCase();
          await prefs.setString(_regionCodeKey, ipRegion);
          debugPrint('🌎 REGION: Перезаписан регион по IP: $ipRegion');
          return ipRegion;
        }
      } catch (e) {
        debugPrint('🔸 REGION: Быстрый IP не получен: $e');
      }

      // Сохраняем fallback по локали
      await prefs.setString(_regionCodeKey, regionCode);
      debugPrint('🌎 REGION: Использован fallback по локали: $regionCode');
      return regionCode;
    } catch (e) {
      debugPrint('🔴 REGION: Ошибка при получении кода региона: $e');
      return 'US'; // По умолчанию - США
    }
  }

  /// Проверяет, находится ли пользователь в России
  Future<bool> isInRussia() async {
    final String regionCode = await getRegionCode();
    return _russianRegions.contains(regionCode);
  }

  /// Определяет валюту пользователя на основе страны по IP
  Future<String> _detectCurrencyCode() async {
    try {
      debugPrint('💰 REGION: Начинаем определение валюты');

      // Сначала пытаемся определить валюту по стране (IP)
      final String regionCode = await getRegionCode();
      debugPrint('💰 REGION: Регион пользователя: $regionCode');

      // Маппинг основных стран к валютам
      final Map<String, String> countryToCurrency = {
        'RU': 'RUB',
        'US': 'USD',
        'GB': 'GBP',
        'DE': 'EUR',
        'FR': 'EUR',
        'IT': 'EUR',
        'ES': 'EUR',
        'TR': 'TRY',
        'CN': 'CNY',
        'JP': 'JPY',
        'KR': 'KRW',
        'IN': 'INR',
        'BR': 'BRL',
        'CA': 'CAD',
        'AU': 'AUD',
      };

      if (countryToCurrency.containsKey(regionCode)) {
        final currency = countryToCurrency[regionCode]!;
        debugPrint('💰 REGION: Определена валюта по стране: $currency');
        return currency;
      }

      // Fallback на локаль устройства если страна не найдена в маппинге
      final locales = PlatformDispatcher.instance.locales;
      if (locales.isNotEmpty) {
        final locale = locales.first;
        debugPrint(
            '💰 REGION: Fallback на локаль устройства: ${locale.toString()}');

        try {
          final format = NumberFormat.currency(locale: locale.toString());
          final detectedCurrency = format.currencyName ?? 'USD';
          debugPrint(
              '💰 REGION: Определена валюта через locale fallback: $detectedCurrency');
          return detectedCurrency;
        } catch (formatError) {
          debugPrint('💰 REGION: Ошибка форматтера: $formatError');
        }
      }
    } catch (e) {
      debugPrint('🔴 REGION: Ошибка при определении валюты: $e');
    }

    // Если не удалось определить валюту, используем значение по умолчанию
    debugPrint('💰 REGION: Используем валюту по умолчанию: USD');
    return 'USD';
  }

  /// Устанавливает валюту пользователя (например, при ручном выборе)
  Future<void> setCurrencyCode(String currencyCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currencyCodeKey, currencyCode);
      debugPrint('💰 REGION: Установлена валюта: $currencyCode');
    } catch (e) {
      debugPrint('🔴 REGION: Ошибка при сохранении валюты: $e');
    }
  }

  /// Устанавливает регион пользователя (например, при ручном выборе)
  Future<void> setRegionCode(String regionCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_regionCodeKey, regionCode);
      debugPrint('🌎 REGION: Установлен регион: $regionCode');
    } catch (e) {
      debugPrint('🔴 REGION: Ошибка при сохранении региона: $e');
    }
  }

  /// Проверяет, является ли валюта пользователя рублем по символу валюты
  Future<bool> isRussianRubleBySymbol(String priceString) async {
    // Проверяем наличие символа рубля в строке цены
    final bool hasRubleSymbol = priceString.contains('₽') ||
        priceString.contains('руб') ||
        priceString.contains('RUB');

    debugPrint(
        '💰 REGION: Проверка символа рубля в цене "$priceString": $hasRubleSymbol');
    return hasRubleSymbol;
  }

  /// Устанавливает рубль как валюту на основе цены из стора
  Future<void> setRubleBasedOnPrice(String priceString) async {
    if (await isRussianRubleBySymbol(priceString)) {
      await setCurrencyCode('RUB');
      debugPrint('💰 REGION: Установлена валюта RUB на основе цены из стора');
    }
  }

  /// Определяет страну пользователя по IP через бесплатный API (country.is)
  Future<String?> getCountryByIp() async {
    try {
      final response = await http
          .get(Uri.parse('https://country.is/'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['country'] as String?;
      }
    } catch (e) {
      debugPrint('🔴 REGION: Ошибка при определении страны по IP: $e');
    }
    return null;
  }
}
