import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aivideomaker/services/localization/app_localization_service.dart';

void main() {
  group('Локализация — в приложении AI Video Maker', () {
    late SharedPreferences prefs;
    late AppLocalizationService localizationService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      localizationService = AppLocalizationService(prefs);
    });

    test(
        'Переводы для русского языка работают корректно — в приложении AI Video Maker',
        () async {
      await localizationService.setLanguage(AppLanguage.ru);

      // Проверяем основные ключи локализации
      expect(localizationService.translate('app_name'), 'AI Video Maker');
      expect(localizationService.translate('yes'), 'Да');
      expect(localizationService.translate('no'), 'Нет');
      expect(localizationService.translate('cancel'), 'Отмена');
      expect(localizationService.translate('save'), 'Сохранить');

      // Проверяем ключи онбординга
      expect(localizationService.translate('onboarding_gender_title'),
          'Какой ваш пол?');
      expect(localizationService.translate('gender_male'), 'Мужчина');
      expect(localizationService.translate('gender_female'), 'Женщина');

      // Проверяем ключи инициализации из main.dart
      expect(localizationService.translate('env_file_loaded'),
          'Env файл загружен');
      expect(localizationService.translate('shared_prefs_initialized'),
          'SharedPreferences инициализированы');

      // Проверяем ключи планов питания
      expect(localizationService.translate('total_calories'), 'Всего калорий');
      expect(localizationService.translate('calories_suffix'), 'ккал');
      expect(localizationService.translate('meal_plan_breakfast_3'),
          'Смузи из ягод с протеином');
      expect(localizationService.translate('meal_plan_lunch_3'),
          'Рис с курицей и овощами');
      expect(localizationService.translate('nutritional_value'),
          'Пищевая ценность');

      // Тестируем параметры
      final paramTranslation =
          localizationService.translateWithParams('user_created', ['2000']);
      expect(paramTranslation, 'Пользователь создан с целью калорий: 2000');

      // Тестируем несколько параметров
      final multiParamTranslation = localizationService
          .translateWithParams('available_keys', ['key1, key2, key3']);
      expect(multiParamTranslation, 'Доступные ключи в .env: key1, key2, key3');
    });

    test(
        'Переводы для английского языка работают корректно — в приложении AI Video Maker',
        () async {
      await localizationService.setLanguage(AppLanguage.en);

      // Проверяем основные ключи локализации
      expect(localizationService.translate('app_name'), 'AI Video Maker');
      expect(localizationService.translate('yes'), 'Yes');
      expect(localizationService.translate('no'), 'No');
      expect(localizationService.translate('cancel'), 'Cancel');
      expect(localizationService.translate('save'), 'Save');

      // Проверяем ключи онбординга
      expect(localizationService.translate('onboarding_gender_title'),
          'Select Gender');
      expect(localizationService.translate('gender_male'), 'Male');
      expect(localizationService.translate('gender_female'), 'Female');

      // Проверяем ключи инициализации из main.dart
      expect(
          localizationService.translate('env_file_loaded'), '.env file loaded');
      expect(localizationService.translate('shared_prefs_initialized'),
          'SharedPreferences initialized');

      // Проверяем ключи планов питания
      expect(localizationService.translate('total_calories'), 'Total calories');
      expect(localizationService.translate('calories_suffix'), 'kcal');
      expect(localizationService.translate('meal_plan_breakfast_3'),
          'Berry protein smoothie');
      expect(localizationService.translate('meal_plan_lunch_3'),
          'Chicken and vegetable rice bowl');
      expect(localizationService.translate('nutritional_value'),
          'Nutritional value');
    });

    test('Переводы с параметрами работают корректно — в приложении AI Video Maker',
        () async {
      await localizationService.setLanguage(AppLanguage.ru);

      // Тестируем ключи с параметрами
      final translatedWithParams = localizationService
          .translateWithParams('error_occurred', ['Тестовая ошибка']);
      expect(translatedWithParams, 'Произошла ошибка: Тестовая ошибка');

      // Тестируем несколько параметров
      final multiParamTranslation = localizationService
          .translateWithParams('available_keys', ['key1, key2, key3']);
      expect(multiParamTranslation, 'Доступные ключи в .env: key1, key2, key3');
    });

    test('Неизвестные ключи возвращают сам ключ — в приложении AI Video Maker',
        () async {
      await localizationService.setLanguage(AppLanguage.ru);

      final unknownKey = 'unknown_translation_key';
      expect(localizationService.translate(unknownKey), unknownKey);
    });

    testWidgets(
        'BuildContext.tr() возвращает корректный перевод — в приложении AI Video Maker',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final mockPrefs = await SharedPreferences.getInstance();
      final mockLocalizationService = AppLocalizationService(mockPrefs);
      await mockLocalizationService.setLanguage(AppLanguage.ru);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(mockPrefs),
            appLocalizationServiceProvider
                .overrideWithValue(mockLocalizationService),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: Text(context.tr('yes')),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Да'), findsOneWidget);
    });
  });
}
