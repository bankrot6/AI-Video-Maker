import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/localization/app_localization_service.dart';
import '../features/ai_chat/ai_chat_screen.dart';
import 'notification_badge.dart';
import 'rtl_wrapper.dart';

/// Провайдер для хранения выбранной даты
final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// Виджет для отображения шапки с логотипом и селектором даты
/// Используется на главном экране и экране аналитики
class DateSelectorHeader extends ConsumerStatefulWidget {
  /// Показывать ли логотип слева
  final bool showLogo;

  /// Функция обработки выбора даты
  final Function(DateTime)? onDateSelected;

  /// Показывать ли badge уведомлений на логотипе
  final bool showNotificationBadge;

  /// Количество уведомлений для отображения в badge
  final int notificationCount;

  /// Функция обработки нажатия на логотип (для навигации к чату)
  final VoidCallback? onLogoTap;

  /// Необязательный список дат, которые нужно отобразить в календаре.
  /// Если передан, календарь показывает только эти даты и игнорирует прошлые/будущие по умолчанию.
  final List<DateTime>? allowedDates;

  /// Конструктор
  const DateSelectorHeader({
    super.key,
    this.showLogo = true,
    this.onDateSelected,
    this.showNotificationBadge = false,
    this.notificationCount = 1,
    this.onLogoTap,
    this.allowedDates,
  });

  @override
  ConsumerState<DateSelectorHeader> createState() => _DateSelectorHeaderState();
}

class _DateSelectorHeaderState extends ConsumerState<DateSelectorHeader> {
  late DateTime _selectedDate;
  ScrollController? _scrollController;
  bool _showLeftFade = false;
  bool _showRightFade = true;

  @override
  void initState() {
    super.initState();
    _selectedDate = ref.read(selectedDateProvider);
  }

  @override
  void dispose() {
    _scrollController?.removeListener(_onCalendarScroll);
    _scrollController?.dispose();
    super.dispose();
  }

  void _onCalendarScroll() {
    if (_scrollController == null || !_scrollController!.hasClients) return;

    final shouldShowLeftFade = _scrollController!.offset > 10;

    // Проверяем, достигли ли конца списка (с небольшим запасом в 10px)
    final maxScroll = _scrollController!.position.maxScrollExtent;
    final currentScroll = _scrollController!.offset;
    final shouldShowRightFade = currentScroll < maxScroll - 10;

    if (shouldShowLeftFade != _showLeftFade ||
        shouldShowRightFade != _showRightFade) {
      setState(() {
        _showLeftFade = shouldShowLeftFade;
        _showRightFade = shouldShowRightFade;
      });
    }
  }

  /// Создает список дат для календаря.
  /// Если переданы [widget.allowedDates], возвращает их (отсортированные).
  /// Иначе: 30 дней назад и 365 дней вперед (полная навигация).
  List<DateTime> _createDatesList() {
    if (widget.allowedDates != null && widget.allowedDates!.isNotEmpty) {
      final copy = widget.allowedDates!
          .map((d) => DateTime(d.year, d.month, d.day))
          .toList();
      copy.sort((a, b) => a.compareTo(b));
      return copy;
    }
    final now = DateTime.now();
    const int pastDaysToShow = 30;
    const int futureDaysToShow = 365;
    final List<DateTime> dates = [];

    // Создаем даты: 30 дней назад + сегодня + 365 дней вперед
    for (int i = -pastDaysToShow; i <= futureDaysToShow; i++) {
      dates.add(DateTime(now.year, now.month, now.day).add(Duration(days: i)));
    }

    return dates;
  }

  /// Прокрутить к выбранному дню в календаре
  void _scrollToSelectedDate(
      List<DateTime> dates, DateTime selectedDate, double fullItemWidth) {
    // Найти индекс выбранного дня в списке дат
    final selectedIndex = dates.indexWhere((date) =>
        date.year == selectedDate.year &&
        date.month == selectedDate.month &&
        date.day == selectedDate.day);

    if (selectedIndex != -1 &&
        _scrollController != null &&
        _scrollController!.hasClients) {
      final targetOffset = selectedIndex * fullItemWidth;
      _scrollController!.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Отслеживаем изменения провайдера выбранной даты (костыль для синхронизации)
    final providerSelectedDate = ref.watch(selectedDateProvider);

    // Если дата в провайдере отличается от локальной - обновляем локальную
    if (_selectedDate.year != providerSelectedDate.year ||
        _selectedDate.month != providerSelectedDate.month ||
        _selectedDate.day != providerSelectedDate.day) {
      print(
          '📅 DateSelectorHeader: Получено обновление провайдера: ${providerSelectedDate.day}.${providerSelectedDate.month}.${providerSelectedDate.year}');
      print(
          '📅 DateSelectorHeader: Текущая локальная дата: ${_selectedDate.day}.${_selectedDate.month}.${_selectedDate.year}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          print('📅 DateSelectorHeader: Обновляем локальную дату в setState');
          setState(() {
            _selectedDate = providerSelectedDate;
          });
          // Прокручиваем к новой выбранной дате после обновления состояния
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              final dates = _createDatesList();
              const double fullItemWidth = 56.0; // 48 + 8 margin
              _scrollToSelectedDate(dates, providerSelectedDate, fullItemWidth);
              print(
                  '✅ DateSelectorHeader: Локальная дата обновлена и прокручено к дате');
            }
          });
        }
      });
    }

    final dateFormatter = DateFormat('dd');
    final dayFormatter = DateFormat('E');

    // Ширина одной плашки с отступами
    const double itemWidth = 48.0; // Ширина самой кнопки
    const double itemMargin = 8.0; // Сумма отступов слева и справа
    const double fullItemWidth =
        itemWidth + itemMargin; // Полная ширина с отступами

    // Переменные для расчета логотипа удалены, поскольку не используются в текущей реализации

    // Создаем даты для календаря согласно allowedDates (если переданы)
    final List<DateTime> dates = _createDatesList();

    return Container(
      height: 80, // Увеличиваем высоту контейнера
      color: Colors.transparent,
      padding: const EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 6),
      child: Row(
        textDirection: context.textDirection,
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
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: Image.asset(
                    'assets/images/IconRectangle.png',
                    width: 90,
                    height: 90,
                  ),
                ),
              ),
            ),
            //const SizedBox(width: 10),
          ],

          // Селектор дат в Expanded
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              // Фактическая ширина для календаря после построения макета
              final calendarWidth = constraints.maxWidth;

              // Вычисляем количество целых кнопок, которые можно разместить
              // Используем floor для гарантии отсутствия обрезания
              final int visibleButtons =
                  (calendarWidth / fullItemWidth).floor();

              // Убеждаемся, что хотя бы одна кнопка помещается
              final int safeVisibleButtons =
                  visibleButtons > 0 ? visibleButtons : 1;

              // Рассчитываем, сколько кнопок не помещается в видимую область
              final int remainingButtons = dates.length - safeVisibleButtons;

              // Индекс кнопки, с которой начнем отображение (чтобы показать выбранный день)
              // Ищем индекс выбранного дня в списке дат
              final int selectedDateIndex = dates.indexWhere((date) =>
                  date.year == _selectedDate.year &&
                  date.month == _selectedDate.month &&
                  date.day == _selectedDate.day);

              // Рассчитываем стартовый индекс для показа выбранного дня
              int startIndex;
              if (selectedDateIndex != -1) {
                // Если выбранная дата найдена, центрируем её в видимой области
                final int centerOffset = (safeVisibleButtons ~/ 2);
                startIndex = (selectedDateIndex - centerOffset)
                    .clamp(0, remainingButtons > 0 ? remainingButtons : 0);
              } else {
                // Если выбранная дата не найдена, переключаемся на ближайшую доступную
                startIndex = 0;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && dates.isNotEmpty) {
                    setState(() {
                      _selectedDate = dates.first;
                    });
                    ref.read(selectedDateProvider.notifier).state = dates.first;
                    if (widget.onDateSelected != null) {
                      widget.onDateSelected!(dates.first);
                    }
                  }
                });
              }

              return SizedBox(
                width: double.infinity,
                child: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    // Определяем цвета и stops в зависимости от состояния fade
                    List<Color> colors;
                    List<double> stops;

                    if (_showLeftFade && _showRightFade) {
                      // Оба fade активны
                      colors = const [
                        Colors.transparent,
                        Colors.white,
                        Colors.white,
                        Colors.transparent,
                      ];
                      stops = const [0.0, 0.15, 0.85, 1.0];
                    } else if (_showLeftFade && !_showRightFade) {
                      // Только левый fade
                      colors = const [
                        Colors.transparent,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                      ];
                      stops = const [0.0, 0.15, 0.85, 1.0];
                    } else if (!_showLeftFade && _showRightFade) {
                      // Только правый fade
                      colors = const [
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.transparent,
                      ];
                      stops = const [0.0, 0.0, 0.85, 1.0];
                    } else {
                      // Нет fade (на случай если список помещается целиком)
                      colors = const [
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                      ];
                      stops = const [0.0, 0.0, 1.0, 1.0];
                    }

                    return LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: colors,
                      stops: stops,
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: dates.length,
                    controller: _scrollController ??= ScrollController(
                        initialScrollOffset: startIndex * fullItemWidth)
                      ..addListener(_onCalendarScroll),
                    itemBuilder: (context, index) {
                      final date = dates[index];
                      final isSelected = _selectedDate.year == date.year &&
                          _selectedDate.month == date.month &&
                          _selectedDate.day == date.day;

                      // Переменная isToday удалена - больше не нужна с унифицированными параметрами

                      // Получаем локализованное название дня недели через сервис локализации
                      String dayText;
                      switch (date.weekday) {
                        case DateTime.monday:
                          dayText = context.tr('monday_short');
                          break;
                        case DateTime.tuesday:
                          dayText = context.tr('tuesday_short');
                          break;
                        case DateTime.wednesday:
                          dayText = context.tr('wednesday_short');
                          break;
                        case DateTime.thursday:
                          dayText = context.tr('thursday_short');
                          break;
                        case DateTime.friday:
                          dayText = context.tr('friday_short');
                          break;
                        case DateTime.saturday:
                          dayText = context.tr('saturday_short');
                          break;
                        case DateTime.sunday:
                          dayText = context.tr('sunday_short');
                          break;
                        default:
                          dayText = dayFormatter.format(date).toUpperCase();
                      }

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          // Обновляем состояние
                          setState(() {
                            _selectedDate = date;
                          });

                          // Обновляем провайдер выбранной даты
                          ref.read(selectedDateProvider.notifier).state = date;

                          // Вызываем колбэк, если он предоставлен
                          if (widget.onDateSelected != null) {
                            widget.onDateSelected!(date);
                          }
                        },
                        child: Container(
                          width: itemWidth,
                          height: 60, // Задаем явную высоту для кнопки
                          margin: const EdgeInsets.symmetric(
                              horizontal: itemMargin / 2),
                          child: Container(
                            width: itemWidth,
                            height: 60,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF007AFF)
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF007AFF)
                                    : Colors.black.withOpacity(0.06),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  dayText,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  dateFormatter.format(date),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            }),
          ),
          const SizedBox(
            height: 100,
          ),
        ],
      ),
    );
  }
}
