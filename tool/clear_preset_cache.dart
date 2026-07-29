import 'dart:io';

void main() async {
  print('Инструкция по очистке кэша пресетов:');
  print('');
  print('1. Закройте приложение полностью');
  print('2. Для Android: Настройки → Приложения → AI Video Maker → Очистить кэш');
  print('3. Для iOS: Удалите и переустановите приложение');
  print('');
  print('Либо кэш автоматически обновится при следующем запуске приложения.');
  print('');
  print('Альтернатива: при разработке удалите папку build/ и переустановите:');
  print('  flutter clean');
  print('  flutter pub get');
  print('  flutter run');
}
