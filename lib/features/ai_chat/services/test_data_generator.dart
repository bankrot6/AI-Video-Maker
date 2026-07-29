import 'package:uuid/uuid.dart';

import '../../../models/meal_model.dart';

/// Генератор тестовых данных питания для демонстрации недельного анализа
class TestDataGenerator {
  static const _uuid = Uuid();

  /// Создает тестовые данные питания за неделю (7 дней по 3 приема пищи)
  static List<MealModel> generateWeeklyMeals() {
    final meals = <MealModel>[];
    final now = DateTime.now();

    // Генерируем приемы пищи за последние 7 дней
    for (int day = 6; day >= 0; day--) {
      final date = now.subtract(Duration(days: day));

      // Завтрак
      final breakfastData = _getBreakfastData(day);
      meals.add(_createMeal(
        name: breakfastData['name'],
        dateTime: DateTime(date.year, date.month, date.day, 8, 30),
        ingredients: breakfastData['ingredients'],
        nutrients: breakfastData['nutrients'],
      ));

      // Обед
      final lunchData = _getLunchData(day);
      meals.add(_createMeal(
        name: lunchData['name'],
        dateTime: DateTime(date.year, date.month, date.day, 13, 0),
        ingredients: lunchData['ingredients'],
        nutrients: lunchData['nutrients'],
      ));

      // Ужин
      final dinnerData = _getDinnerData(day);
      meals.add(_createMeal(
        name: dinnerData['name'],
        dateTime: DateTime(date.year, date.month, date.day, 19, 30),
        ingredients: dinnerData['ingredients'],
        nutrients: dinnerData['nutrients'],
      ));
    }

    return meals;
  }

  static MealModel _createMeal({
    required String name,
    required DateTime dateTime,
    required List<IngredientModel> ingredients,
    required MealNutrientsModel nutrients,
  }) {
    return MealModel(
      id: _uuid.v4(),
      name: name,
      dateTime: dateTime,
      ingredients: ingredients,
      nutrients: nutrients,
    );
  }

  // === ЗАВТРАКИ ===

  static Map<String, dynamic> _getBreakfastData(int day) {
    switch (day % 7) {
      case 0: // Овсяная каша с ягодами
        return {
          'name': 'Овсяная каша с ягодами',
          'ingredients': [
            _createIngredient('Овсяные хлопья', 50),
            _createIngredient('Молоко 2.5%', 200),
            _createIngredient('Черника', 80),
            _createIngredient('Мед', 20),
          ],
          'nutrients': _createNutrients(402, 13, 8, 70),
        };
      case 1: // Яичница с тостами
        return {
          'name': 'Яичница с тостами',
          'ingredients': [
            _createIngredient('Яйца куриные', 120),
            _createIngredient('Хлеб цельнозерновой', 60),
            _createIngredient('Масло сливочное', 10),
            _createIngredient('Помидор', 100),
          ],
          'nutrients': _createNutrients(446, 22, 24, 33),
        };
      case 2: // Творог с фруктами
        return {
          'name': 'Творог с фруктами',
          'ingredients': [
            _createIngredient('Творог 9%', 150),
            _createIngredient('Банан', 120),
            _createIngredient('Яблоко', 150),
            _createIngredient('Грецкие орехи', 20),
          ],
          'nutrients': _createNutrients(485, 22, 22, 53),
        };
      case 3: // Мюсли с молоком
        return {
          'name': 'Мюсли с молоком',
          'ingredients': [
            _createIngredient('Мюсли', 60),
            _createIngredient('Молоко 2.5%', 250),
            _createIngredient('Изюм', 30),
          ],
          'nutrients': _createNutrients(443, 16, 13, 70),
        };
      case 4: // Сырники со сметаной
        return {
          'name': 'Сырники со сметаной',
          'ingredients': [
            _createIngredient('Творог 5%', 120),
            _createIngredient('Яйцо', 50),
            _createIngredient('Мука пшеничная', 30),
            _createIngredient('Сметана 20%', 50),
          ],
          'nutrients': _createNutrients(428, 30, 20, 27),
        };
      case 5: // Омлет с овощами
        return {
          'name': 'Омлет с овощами',
          'ingredients': [
            _createIngredient('Яйца куриные', 120),
            _createIngredient('Молоко', 50),
            _createIngredient('Болгарский перец', 80),
            _createIngredient('Лук репчатый', 40),
            _createIngredient('Масло подсолнечное', 10),
          ],
          'nutrients': _createNutrients(341, 17, 24, 12),
        };
      case 6: // Блинчики с медом
        return {
          'name': 'Блинчики с медом',
          'ingredients': [
            _createIngredient('Мука пшеничная', 80),
            _createIngredient('Молоко', 150),
            _createIngredient('Яйцо', 50),
            _createIngredient('Мед', 25),
          ],
          'nutrients': _createNutrients(512, 18, 10, 87),
        };
      default:
        return {
          'name': 'Завтрак',
          'ingredients': [_createIngredient('Хлеб', 50)],
          'nutrients': _createNutrients(150, 5, 2, 28),
        };
    }
  }

  // === ОБЕДЫ ===

  static Map<String, dynamic> _getLunchData(int day) {
    switch (day % 7) {
      case 0: // Куриная грудка с рисом
        return {
          'name': 'Куриная грудка с рисом',
          'ingredients': [
            _createIngredient('Куриная грудка', 150),
            _createIngredient('Рис белый', 80),
            _createIngredient('Брокколи', 120),
            _createIngredient('Масло оливковое', 10),
          ],
          'nutrients': _createNutrients(665, 57, 13, 71),
        };
      case 1: // Борщ с говядиной
        return {
          'name': 'Борщ с говядиной',
          'ingredients': [
            _createIngredient('Говядина', 100),
            _createIngredient('Свекла', 80),
            _createIngredient('Капуста', 100),
            _createIngredient('Морковь', 60),
            _createIngredient('Картофель', 120),
            _createIngredient('Сметана 15%', 30),
          ],
          'nutrients': _createNutrients(479, 31, 21, 42),
        };
      case 2: // Рыба с овощами
        return {
          'name': 'Рыба с овощами',
          'ingredients': [
            _createIngredient('Лосось', 140),
            _createIngredient('Цукини', 150),
            _createIngredient('Спаржа', 100),
            _createIngredient('Лимон', 20),
          ],
          'nutrients': _createNutrients(282, 35, 11, 11),
        };
      case 3: // Паста с томатным соусом
        return {
          'name': 'Паста с томатным соусом',
          'ingredients': [
            _createIngredient('Макароны', 100),
            _createIngredient('Помидоры', 200),
            _createIngredient('Лук', 50),
            _createIngredient('Чеснок', 10),
            _createIngredient('Пармезан', 20),
          ],
          'nutrients': _createNutrients(509, 23, 6, 90),
        };
      case 4: // Плов с курицей
        return {
          'name': 'Плов с курицей',
          'ingredients': [
            _createIngredient('Рис длиннозерный', 80),
            _createIngredient('Курица', 120),
            _createIngredient('Морковь', 80),
            _createIngredient('Лук', 60),
            _createIngredient('Масло подсолнечное', 15),
          ],
          'nutrients': _createNutrients(668, 36, 24, 77),
        };
      case 5: // Суп с фрикадельками
        return {
          'name': 'Суп с фрикадельками',
          'ingredients': [
            _createIngredient('Говяжий фарш', 80),
            _createIngredient('Картофель', 100),
            _createIngredient('Морковь', 50),
            _createIngredient('Лук', 40),
            _createIngredient('Вермишель', 30),
          ],
          'nutrients': _createNutrients(479, 25, 20, 49),
        };
      case 6: // Гречка с котлетой
        return {
          'name': 'Гречка с котлетой',
          'ingredients': [
            _createIngredient('Гречневая крупа', 80),
            _createIngredient('Свиной фарш', 100),
            _createIngredient('Лук', 30),
            _createIngredient('Яйцо', 25),
          ],
          'nutrients': _createNutrients(592, 31, 27, 59),
        };
      default:
        return {
          'name': 'Обед',
          'ingredients': [_createIngredient('Рис', 100)],
          'nutrients': _createNutrients(350, 7, 1, 78),
        };
    }
  }

  // === УЖИНЫ ===

  static Map<String, dynamic> _getDinnerData(int day) {
    switch (day % 7) {
      case 0: // Салат с креветками
        return {
          'name': 'Салат с креветками',
          'ingredients': [
            _createIngredient('Креветки', 120),
            _createIngredient('Листья салата', 80),
            _createIngredient('Огурец', 100),
            _createIngredient('Авокадо', 60),
            _createIngredient('Масло оливковое', 10),
          ],
          'nutrients': _createNutrients(333, 25, 22, 8),
        };
      case 1: // Запеченная семга
        return {
          'name': 'Запеченная семга',
          'ingredients': [
            _createIngredient('Семга', 150),
            _createIngredient('Спаржа', 120),
            _createIngredient('Лимон', 30),
            _createIngredient('Укроп', 10),
          ],
          'nutrients': _createNutrients(268, 38, 11, 9),
        };
      case 2: // Овощное рагу
        return {
          'name': 'Овощное рагу',
          'ingredients': [
            _createIngredient('Баклажан', 120),
            _createIngredient('Кабачок', 100),
            _createIngredient('Помидоры', 120),
            _createIngredient('Болгарский перец', 80),
            _createIngredient('Лук', 50),
          ],
          'nutrients': _createNutrients(114, 4, 1, 27),
        };
      case 3: // Курица с овощами
        return {
          'name': 'Курица с овощами',
          'ingredients': [
            _createIngredient('Куриное филе', 130),
            _createIngredient('Цветная капуста', 150),
            _createIngredient('Морковь', 80),
            _createIngredient('Зеленая фасоль', 100),
          ],
          'nutrients': _createNutrients(304, 46, 2, 22),
        };
      case 4: // Творожная запеканка
        return {
          'name': 'Творожная запеканка',
          'ingredients': [
            _createIngredient('Творог 5%', 150),
            _createIngredient('Яйцо', 50),
            _createIngredient('Мука', 20),
            _createIngredient('Изюм', 20),
          ],
          'nutrients': _createNutrients(387, 34, 13, 34),
        };
      case 5: // Тунец с салатом
        return {
          'name': 'Тунец с салатом',
          'ingredients': [
            _createIngredient('Тунец консервированный', 100),
            _createIngredient('Салат айсберг', 100),
            _createIngredient('Помидоры черри', 80),
            _createIngredient('Огурец', 80),
            _createIngredient('Оливковое масло', 5),
          ],
          'nutrients': _createNutrients(182, 24, 6, 9),
        };
      case 6: // Омлет с грибами
        return {
          'name': 'Омлет с грибами',
          'ingredients': [
            _createIngredient('Яйца', 100),
            _createIngredient('Шампиньоны', 100),
            _createIngredient('Сыр', 30),
            _createIngredient('Молоко', 50),
          ],
          'nutrients': _createNutrients(318, 24, 21, 7),
        };
      default:
        return {
          'name': 'Ужин',
          'ingredients': [_createIngredient('Овощи', 200)],
          'nutrients': _createNutrients(150, 5, 1, 30),
        };
    }
  }

  static IngredientModel _createIngredient(String name, double quantity) {
    return IngredientModel(
      name: name,
      quantity: quantity,
      unit: IngredientUnits.GRAMS,
    );
  }

  static MealNutrientsModel _createNutrients(
      int calories, double proteins, double fats, double carbs) {
    return MealNutrientsModel(
      calories: calories,
      proteins: proteins,
      fats: fats,
      carbs: carbs,
    );
  }
}
