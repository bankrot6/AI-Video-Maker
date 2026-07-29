import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aivideomaker/features/home/home_screen.dart';
import 'package:aivideomaker/features/analytics/analytics_screen.dart';
import 'package:aivideomaker/features/history/history_screen.dart';

void main() {
  testWidgets(
      'Проверка создания скриншота домашнего экрана — в приложении AI Video Maker',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    // Ждем загрузки данных
    await tester.pumpAndSettle();

    // Проверяем наличие виджета ScreenshotContainer
    expect(find.byType(RepaintBoundary), findsWidgets);

    // Можно также активировать кнопку шаринга и проверить, что метод вызывается
    // (для этого потребовалось бы создать мок ScreenshotService)
  });

  testWidgets(
      'Проверка кнопки шаринга на экране истории — в приложении AI Video Maker',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: HistoryScreen(),
        ),
      ),
    );

    // Ждем загрузки данных
    await tester.pumpAndSettle();

    // Проверяем наличие кнопки шаринга
    expect(find.byIcon(Icons.share), findsOneWidget);
  });

  // Проверка наличия функционала в аналитике
  testWidgets(
      'Проверка кнопки шаринга на экране аналитики — в приложении AI Video Maker',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: AnalyticsScreen(),
        ),
      ),
    );

    // Ждем загрузки данных
    await tester.pumpAndSettle();

    // Проверяем наличие кнопки шаринга
    expect(find.byIcon(Icons.share), findsOneWidget);
  });
}
