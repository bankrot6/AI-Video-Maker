import 'package:flutter/material.dart';
import '../../services/localization/app_localization_service.dart';
import 'loading_manager.dart';

/// Пример использования LoadingManager
class LoadingExample extends StatelessWidget {
  const LoadingExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('loading_example')),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                // Показать экран загрузки с текстом и анимацией дороги
                LoadingManager().showLoadingScreen(
                  context,
                  text: context.tr('loading_data'),
                  animationPath: 'assets/animations/road.json',
                  animationHeight: 180.0, // Удобная высота для анимации дороги
                );

                // Имитация асинхронной операции
                Future.delayed(const Duration(seconds: 3), () {
                  // Обновить текст
                  LoadingManager().updateLoadingText(
                    context,
                    newText: context.tr('almost_done'),
                    animationPath: 'assets/animations/road.json',
                    animationHeight: 180.0,
                  );

                  // Скрыть экран загрузки через 2 секунды
                  Future.delayed(const Duration(seconds: 2), () {
                    LoadingManager().hideLoadingScreen();
                  });
                });
              },
              child: Text(context.tr('show_road_animation')),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // Показать экран загрузки с точками
                LoadingManager().showLoadingScreen(
                  context,
                  text: context.tr('loading_data'),
                  animationPath: 'assets/animations/road.json',
                  animationHeight: 150.0,
                );

                // Имитация асинхронной операции
                Future.delayed(const Duration(seconds: 3), () {
                  LoadingManager().hideLoadingScreen();
                });
              },
              child: Text(context.tr('show_small_animation')),
            ),
          ],
        ),
      ),
    );
  }
}
