import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// import '../home/home_providers.dart' as home; // питание удалено
import '../../widgets/date_selector_header.dart' as date_selector;
// Вода отображается в общем списке MealHistoryList
import '../../widgets/screenshot_container.dart';
import '../../services/localization/app_localization_service.dart';
import '../../widgets/bottom_content_blur.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late DateTime _selectedDate;
  // Локальный ключ для избегания конфликтов GlobalKey
  final GlobalKey _historyBoundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Инициализация начального состояния
    _selectedDate = DateTime
        .now(); // Временное значение, будет обновлено в didChangeDependencies

    // НЕ вызываем _loadMealsForDate здесь, чтобы избежать ошибки с InheritedWidget
    // Вместо этого загружаем данные в didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Читаем выбранную дату из провайдера (синхронизация с домашним экраном)
    final providerSelectedDate = ref.read(date_selector.selectedDateProvider);

    // Обновляем локальную дату, если она отличается от провайдера
    if (_selectedDate.year != providerSelectedDate.year ||
        _selectedDate.month != providerSelectedDate.month ||
        _selectedDate.day != providerSelectedDate.day) {
      _selectedDate = providerSelectedDate;
    }

    // Загружаем приемы пищи для выбранной даты после создания виджета
    // Это безопасно, так как InheritedWidget уже доступен
    _loadMealsForDate(_selectedDate);
  }

  Future<void> _loadMealsForDate(DateTime date) async {}

  // Исторические обработчики удалены

  // Добавляем обработчик обновления экрана после анализа

  @override
  Widget build(BuildContext context) {
    // Отслеживаем изменения провайдера выбранной даты (синхронизация с другими экранами)
    final providerSelectedDate = ref.watch(date_selector.selectedDateProvider);

    // Если дата в провайдере отличается от локальной - обновляем локальную (костыль для принудительного обновления)
    if (_selectedDate.year != providerSelectedDate.year ||
        _selectedDate.month != providerSelectedDate.month ||
        _selectedDate.day != providerSelectedDate.day) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedDate = providerSelectedDate;
          });
          _loadMealsForDate(providerSelectedDate);
        }
      });
    }

    // История питания удалена

    // Получаем менеджер скриншотов
    // Менеджер шаринга не требуется здесь напрямую

    return Scaffold(
      backgroundColor: Colors.black,
      extendBody: true,
      body: Stack(
        children: [
          // Фоновое изображение
          Positioned.fill(
            child: Image.asset(
              'assets/images/a-futuristic-digital-background-0.png',
              fit: BoxFit.cover,
              opacity: const AlwaysStoppedAnimation(0.8),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Stack(
              children: [
                // Контент с fade-out эффектом
                BottomFadeMask(
                  fadeHeight: 100.0,
                  fadeStart: 0.70,
                  child: RefreshIndicator(
                    onRefresh: () async {
                      await _loadMealsForDate(_selectedDate);
                    },
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: ScreenshotContainer(
                            boundaryKey: _historyBoundaryKey,
                            child: Column(
                              children: [
                                // Добавляем отступ сверху
                                const SizedBox(height: 16),
                                // Виджет с заголовком и селектором даты
                                date_selector.DateSelectorHeader(
                                  showLogo: true,
                                  showNotificationBadge: true,
                                  notificationCount: 1,
                                  onDateSelected: (date) {
                                    setState(() {
                                      _selectedDate = date;
                                    });
                                    // Провайдер уже обновляется в самом DateSelectorHeader при нажатии
                                    _loadMealsForDate(date);
                                  },
                                ),

                                // Отступ после календаря
                                const SizedBox(height: 12),

                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 24),
                                  child: Text(
                                    context.tr('history_cleared_placeholder'),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Отступ внизу для правильного отображения с навигацией
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 100), // Padding для размытия
                        ),
                      ],
                    ),
                  ),
                ),
                // Размытие снизу (iOS 26 стиль)
                BottomContentBlur(
                  blurHeight: 100.0,
                  maxBlurIntensity: 6.0,
                  overlayColor: Colors.black,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Метод шаринга временно не используется (кнопка заменена на профиль)
}
