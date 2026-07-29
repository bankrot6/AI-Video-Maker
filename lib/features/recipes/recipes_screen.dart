/*
 * ЗАКОММЕНТИРОВАНО: Файл с экраном рецептов не используется в текущей версии приложения
 * Вместо него используется экран истории (HistoryScreen)
 */

/*
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/home_screen.dart';
import '../analytics/analytics_screen.dart';
import '../camera/camera_screen.dart';
import '../settings/settings_screen.dart';
import '../../utils/usage_limit_util.dart';

class RecipesScreen extends ConsumerWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('recipes_title')),
        automaticallyImplyLeading: false, // Отключаем кнопку назад
      ),
      body: ListView(
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildCategoryList(),
          const SizedBox(height: 24),
          _buildPopularRecipes(context),
          // Добавляем отступ внизу для нижней панели
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(context),
      floatingActionButton: _buildAddButton(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    // Определяем цвет активной иконки и неактивных иконок
    final Color activeColor = Colors.blue;
    final Color inactiveColor = Colors.grey;
    
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: Icon(Icons.home, color: inactiveColor),
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const HomeScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.bar_chart, color: inactiveColor),
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => const AnalyticsScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 40), // Место для FAB
          IconButton(
            icon: Icon(Icons.restaurant_menu, color: activeColor),
            onPressed: () {
              // Уже на экране рецептов
            },
          ),
          IconButton(
            icon: Icon(Icons.settings, color: inactiveColor),
            onPressed: () {
              // Показываем меню выбора настроек
              _showSettingsMenu(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton(BuildContext context) {
    return FloatingActionButton(
      onPressed: () async {
        // Проверяем лимиты использования перед открытием камеры
        bool canContinue = await UsageLimitUtil.checkUsageLimitBeforeAction(context, ref);
        
        // Только если лимит не превышен, открываем камеру
        if (canContinue && mounted) {
          // Переходим к экрану камеры
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const CameraScreen()),
          );
        }
      },
      child: const Icon(Icons.camera_alt),
    );
  }

  // Метод для отображения меню настроек
  void _showSettingsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.settings),
                title: Text(context.tr('app_settings_title')),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Рецепты, подобранные для вас',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'На основе ваших целей и предпочтений',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryList() {
    final categories = [
      {'name': 'Белковые', 'icon': Icons.fitness_center},
      {'name': 'Быстрые', 'icon': Icons.speed},
      {'name': 'ПП', 'icon': Icons.health_and_safety},
      {'name': 'Веганские', 'icon': Icons.eco},
      {'name': 'Низкоуглеводные', 'icon': Icons.grain},
    ];

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          return Padding(
            padding: EdgeInsets.only(
              left: index == 0 ? 16 : 8,
              right: index == categories.length - 1 ? 16 : 8,
            ),
            child: _buildCategoryCard(
              category['name'] as String,
              category['icon'] as IconData,
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryCard(String name, IconData icon) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            icon,
            size: 40,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildPopularRecipes(BuildContext context) {
    final recipes = [
      {
        'name': 'Куриная грудка с овощами',
        'calories': 320,
        'time': '30 мин',
        'image': 'https://via.placeholder.com/150/0000FF/FFFFFF/?text=Курица'
      },
      {
        'name': 'Греческий салат',
        'calories': 220,
        'time': '15 мин',
        'image': 'https://via.placeholder.com/150/00FF00/FFFFFF/?text=Салат'
      },
      {
        'name': 'Омлет с овощами',
        'calories': 280,
        'time': '10 мин',
        'image': 'https://via.placeholder.com/150/FF0000/FFFFFF/?text=Омлет'
      },
      {
        'name': 'Тушеные овощи',
        'calories': 180,
        'time': '25 мин',
        'image': 'https://via.placeholder.com/150/FFFF00/000000/?text=Овощи'
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            'Популярные рецепты',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: recipes.length,
          itemBuilder: (context, index) {
            final recipe = recipes[index];
            return _buildRecipeCard(
              recipe['name'] as String,
              recipe['calories'] as int,
              recipe['time'] as String,
              recipe['image'] as String,
              context,
            );
          },
        ),
      ],
    );
  }

  Widget _buildRecipeCard(
    String name,
    int calories,
    String time,
    String imageUrl,
    BuildContext context,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                // В реальном приложении здесь должен быть механизм загрузки изображений
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 80,
                    height: 80,
                    color: Colors.grey[300],
                    child: const Icon(Icons.restaurant, color: Colors.white),
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.local_fire_department, size: 16),
                      Text(' $calories ккал'),
                      const SizedBox(width: 16),
                      const Icon(Icons.access_time, size: 16),
                      Text(' $time'),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 16),
              onPressed: () {
                // Переход к детальной информации о рецепте
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Рецепт: $name'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
*/
