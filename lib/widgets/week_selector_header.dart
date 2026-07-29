import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/localization/app_localization_service.dart';
import '../features/ai_chat/ai_chat_screen.dart';
import 'notification_badge.dart';

/// Виджет для отображения шапки с логотипом и селектором недели
/// Используется на экране аналитики
class WeekSelectorHeader extends ConsumerStatefulWidget {
  /// Показывать ли логотип слева
  final bool showLogo;

  /// Начальная выбранная дата (будет адаптирована к началу недели)
  final DateTime initialDate;

  /// Функция обработки выбора недели
  final Function(DateTime startDate, DateTime endDate)? onWeekSelected;

  /// Показывать ли badge уведомлений на логотипе
  final bool showNotificationBadge;

  /// Количество уведомлений для отображения в badge
  final int notificationCount;

  /// Функция обработки нажатия на логотип (для навигации к чату)
  final VoidCallback? onLogoTap;

  /// Конструктор
  const WeekSelectorHeader({
    super.key,
    this.showLogo = true,
    required this.initialDate,
    this.onWeekSelected,
    this.showNotificationBadge = false,
    this.notificationCount = 1,
    this.onLogoTap,
  });

  @override
  ConsumerState<WeekSelectorHeader> createState() => _WeekSelectorHeaderState();
}

class _WeekSelectorHeaderState extends ConsumerState<WeekSelectorHeader> {
  late DateTime _selectedWeekStart;
  final List<_WeekRange> _weeks = [];
  final int _weeksToShow = 12; // Показываем 12 недель

  @override
  void initState() {
    super.initState();
    _initializeWeeks();
  }

  void _initializeWeeks() {
    // Получаем текущую дату
    final now = DateTime.now();

    // Инициализируем выбранную неделю на основе начальной даты
    _updateSelectedWeek(widget.initialDate);

    // Создаем список недель
    DateTime currentWeekStart = now;
    // Сначала найдем начало текущей недели (понедельник)
    final int weekday = currentWeekStart.weekday;
    currentWeekStart = currentWeekStart.subtract(Duration(days: weekday - 1));

    // Добавляем текущую неделю и предыдущие недели
    for (int i = 0; i < _weeksToShow; i++) {
      final weekStart = currentWeekStart.subtract(Duration(days: i * 7));
      final weekEnd = weekStart.add(const Duration(days: 6));
      _weeks.add(_WeekRange(weekStart, weekEnd));
    }

    // Сортируем недели в порядке возрастания (сначала самые старые)
    _weeks.sort((a, b) => a.startDate.compareTo(b.startDate));

    // Проверяем есть ли текущая неделя в списке и делаем её выбранной
    final thisWeekStart =
        DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));

    // Если нам нужно выделить текущую неделю при инициализации
    for (final week in _weeks) {
      if (week.startDate.year == thisWeekStart.year &&
          week.startDate.month == thisWeekStart.month &&
          week.startDate.day == thisWeekStart.day) {
        _selectedWeekStart = week.startDate;
        break;
      }
    }
  }

  void _updateSelectedWeek(DateTime date) {
    // Находим начало недели для выбранной даты (понедельник)
    final int weekday = date.weekday;
    _selectedWeekStart = date.subtract(Duration(days: weekday - 1));
  }

  @override
  Widget build(BuildContext context) {
    // Форматтеры для отображения дат
    final localizationService = ref.watch(appLocalizationServiceProvider);
    final locale = localizationService
        .getIntlLocaleString(); // Используем корректный формат локали для intl

    // Используем локаль пользователя вместо жестко заданной 'ru'
    final monthFormat = DateFormat('MMM', locale);

    // Минимальная ширина кнопки и отступы
    const double minItemWidth = 60.0; // Минимальная ширина кнопки
    const double itemMargin = 8.0; // Сумма отступов слева и справа

    return Container(
      height: 70, // Фиксированная высота
      color: Colors.white, // Белый фон под часами
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Логотип приложения слева (если показываем)
          if (widget.showLogo) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onLogoTap ??
                  () {
                    // По умолчанию навигируем к экрану AI чата
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            const AiChatScreen(isActive: true),
                      ),
                    );
                  },
              child: BadgeWrapper(
                showBadge: widget.showNotificationBadge,
                badgeCount: widget.notificationCount,
                badgeSize: 18,
                badgeOffset: const Offset(22, 0),
                child: Image.asset(
                  'assets/images/chatcoach_logo.png',
                  width: 90,
                  height: 90,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],

          // Селектор недель в Expanded
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              // Фактическая ширина для календаря после построения макета
              final calendarWidth = constraints.maxWidth;

              // Определяем оптимальное количество кнопок (от 2 до 5)
              int optimalButtonCount = 3; // Предпочтительное количество

              // Проверяем, сколько кнопок минимальной ширины поместится
              final maxPossibleButtons =
                  (calendarWidth / (minItemWidth + itemMargin)).floor();

              if (maxPossibleButtons >= 4) {
                optimalButtonCount = 4;
              } else if (maxPossibleButtons >= 3) {
                optimalButtonCount = 3;
              } else if (maxPossibleButtons >= 2) {
                optimalButtonCount = 2;
              } else {
                optimalButtonCount = 1;
              }

              // Вычисляем адаптивную ширину кнопки, чтобы заполнить всё пространство
              final double availableWidthForButtons =
                  calendarWidth - (optimalButtonCount * itemMargin);
              final double adaptiveItemWidth =
                  availableWidthForButtons / optimalButtonCount;

              // Убеждаемся, что ширина не меньше минимальной
              final double finalItemWidth =
                  adaptiveItemWidth.clamp(minItemWidth, double.infinity);
              final double fullItemWidth = finalItemWidth + itemMargin;

              return Center(
                child: SizedBox(
                  width: calendarWidth, // Используем всю доступную ширину
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _weeks.length,
                    controller: ScrollController(
                      initialScrollOffset: _getInitialScrollOffset(
                          optimalButtonCount, fullItemWidth),
                    ),
                    itemBuilder: (context, index) {
                      final weekRange = _weeks[index];
                      final isSelected = _selectedWeekStart
                          .isAtSameMomentAs(weekRange.startDate);

                      // Определяем, является ли эта неделя текущей
                      final now = DateTime.now();
                      final isCurrentWeek = now.isAfter(weekRange.startDate) &&
                          now.isBefore(
                              weekRange.endDate.add(const Duration(days: 1)));

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          // Обновляем состояние
                          setState(() {
                            _selectedWeekStart = weekRange.startDate;
                          });

                          // Вызываем колбэк, если он предоставлен
                          if (widget.onWeekSelected != null) {
                            widget.onWeekSelected!(
                                weekRange.startDate, weekRange.endDate);
                          }
                        },
                        child: Container(
                          width: finalItemWidth, // Используем адаптивную ширину
                          margin: const EdgeInsets.symmetric(
                              horizontal: itemMargin / 2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(context).primaryColor
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(context).primaryColor
                                  : isCurrentWeek
                                      ? Theme.of(context)
                                          .primaryColor
                                          .withOpacity(0.5)
                                      : Colors.grey.shade300,
                              width: isCurrentWeek && !isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Показываем месяц
                              Text(
                                monthFormat.format(weekRange.startDate),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? Colors.white
                                      : isCurrentWeek
                                          ? Theme.of(context).primaryColor
                                          : Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 2),
                              // Показываем период в виде 01-07
                              Text(
                                "${weekRange.startDate.day.toString().padLeft(2, '0')}-${weekRange.endDate.day.toString().padLeft(2, '0')}",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      isSelected ? Colors.white : Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  double _getInitialScrollOffset(int visibleButtons, double fullItemWidth) {
    // Находим индекс недели, которая содержит текущую дату
    final now = DateTime.now();
    final thisWeekStart = now.subtract(Duration(days: now.weekday - 1));

    for (int i = 0; i < _weeks.length; i++) {
      if (_isSameDay(_weeks[i].startDate, thisWeekStart)) {
        // Если нашли текущую неделю, возвращаем позицию, чтобы она была видна в центре
        // Но не допускаем отрицательного смещения
        int offset = i - (visibleButtons ~/ 2);
        if (offset < 0) offset = 0;
        return offset * fullItemWidth;
      }
    }

    // Если текущая неделя не найдена, возвращаем самую последнюю доступную неделю
    if (_weeks.isNotEmpty) {
      int offset = _weeks.length - visibleButtons;
      if (offset < 0) offset = 0;
      return offset * fullItemWidth;
    }

    return 0.0;
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}

/// Вспомогательный класс для хранения диапазона недели
class _WeekRange {
  final DateTime startDate;
  final DateTime endDate;

  _WeekRange(this.startDate, this.endDate);
}
