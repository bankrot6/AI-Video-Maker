import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../models/gamification_model.dart';
import '../features/home/gamification_providers.dart';
import '../features/ai_chat/ai_chat_screen.dart';
import '../services/localization/app_localization_service.dart';

/// Виджет для отображения прогресса приемов пищи за неделю
class WeeklyProgressCard extends ConsumerWidget {
  const WeeklyProgressCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gamificationData = ref.watch(gamificationProvider);

    if (gamificationData == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          // Заголовок
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Text(
              context.tr('your_weekly_progress'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),

          // Приемы пищи за неделю
          _buildDailyMealsIndicator(
            context,
            context.tr('meal_intake'),
            gamificationData.currentWeeklyMeals,
            21,
            Colors.blue,
          ),
          const SizedBox(height: 16),

          // Недельный прогресс
          _buildWeeklyProgressIndicator(
            context,
            context.tr('target_days_per_week'),
            gamificationData.currentWeeklyProgress,
            gamificationData.weeklyDaysTarget,
            Colors.green,
          ),
          const SizedBox(height: 16),

          // Визуализация недели
          _buildWeekVisualization(context, gamificationData),
          const SizedBox(height: 20),

          // Кнопка консультации с ИИ
          _buildAiConsultationButton(context, gamificationData),
        ],
      ),
    );
  }

  Widget _buildDailyMealsIndicator(
    BuildContext context,
    String label,
    int current,
    int target,
    Color color,
  ) {
    final percentage = (current / target).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '$current / $target',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final double maxBarWidth = constraints.maxWidth;
            const double minFilledWidthPx = 8.0;
            final double filledWidth = percentage <= 0
                ? 0
                : math.min(
                    maxBarWidth,
                    math.max(minFilledWidthPx, percentage * maxBarWidth),
                  );

            return Container(
              height: 20,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: filledWidth,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      '${(percentage * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildWeeklyProgressIndicator(
    BuildContext context,
    String label,
    int current,
    int target,
    Color color,
  ) {
    final percentage = (current / target).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '$current / $target',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 20,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            children: [
              // Прогресс-бар
              FractionallySizedBox(
                widthFactor: percentage,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              // Текстовый процент внутри
              Center(
                child: Text(
                  '${(percentage * 100).toInt()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWeekVisualization(BuildContext context, GamificationModel data) {
    final now = DateTime.now();
    final weekDays = [
      context.tr('monday_short'),
      context.tr('tuesday_short'),
      context.tr('wednesday_short'),
      context.tr('thursday_short'),
      context.tr('friday_short'),
      context.tr('saturday_short'),
      context.tr('sunday_short'),
    ];

    // Получаем начало недели (понедельник)
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('daily_progress'),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(7, (index) {
            final dayDate = startOfWeek.add(Duration(days: index));
            final isToday = _isSameDay(dayDate, now);
            final isPast =
                dayDate.isBefore(DateTime(now.year, now.month, now.day));
            final isCurrentWeek =
                dayDate.isBefore(now.add(const Duration(days: 1)));

            // Реальные данные: считаем выполненным день, если приемов >= dailyMealsTarget
            final mealsForDay = (data.weekDailyMeals.length == 7)
                ? data.weekDailyMeals[index]
                : 0;
            final isDayCompleted = mealsForDay >= data.dailyMealsTarget &&
                (isToday || isPast) &&
                isCurrentWeek;

            return Column(
              children: [
                Text(
                  weekDays[index],
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        isToday ? Theme.of(context).primaryColor : Colors.grey,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isDayCompleted
                        ? (isToday
                            ? Theme.of(context).primaryColor
                            : Colors.green)
                        : (isPast ? Colors.red.shade300 : Colors.grey.shade300),
                    shape: BoxShape.circle,
                    border: isToday
                        ? Border.all(
                            color: Theme.of(context).primaryColor, width: 2)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      mealsForDay > 0 ? '$mealsForDay' : '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('d').format(dayDate),
                  style: TextStyle(
                    fontSize: 10,
                    color:
                        isToday ? Theme.of(context).primaryColor : Colors.grey,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  Widget _buildAiConsultationButton(
      BuildContext context, GamificationModel data) {
    final isUnlocked = data.shouldUnlockAiChat;
    final progress = data.currentWeeklyProgress;
    final target = data.weeklyDaysTarget;
    final remaining = target - progress;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onAiConsultationTap(context, isUnlocked, remaining),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isUnlocked
                ? [Colors.green.shade400, Colors.green.shade600]
                : [Colors.grey.shade300, Colors.grey.shade400],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: (isUnlocked ? Colors.green : Colors.grey).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Иконка и заголовок
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isUnlocked ? Icons.psychology : Icons.lock,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('ai_consultation_title'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isUnlocked
                            ? context.tr('chat_unlocked_description')
                            : remaining == 1
                                ? context.tr('days_remaining_one')
                                : context.trParams('days_remaining_many',
                                    [remaining.toString()]),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isUnlocked)
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white,
                    size: 16,
                  ),
              ],
            ),

            if (!isUnlocked) ...[
              const SizedBox(height: 12),
              // Прогресс до разблокировки
              Container(
                height: 6,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (progress / target).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _onAiConsultationTap(
      BuildContext context, bool isUnlocked, int remaining) {
    if (isUnlocked) {
      // Открываем чат с ИИ диетологом
      _showAiChatDialog(context);
    } else {
      // Показываем информацию о том, что нужно сделать для разблокировки
      _showUnlockInfoDialog(context, remaining);
    }
  }

  void _showAiChatDialog(BuildContext context) {
    // Открываем полноценный экран чата с ИИ диетологом
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AiChatScreen(isActive: true),
      ),
    );
  }

  void _showUnlockInfoDialog(BuildContext context, int remaining) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.lock, color: Colors.grey),
            const SizedBox(width: 8),
            Text(context.tr('chat_locked_title')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('chat_unlock_description'),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      remaining == 1
                          ? context.tr('days_remaining_info_one')
                          : context.trParams('days_remaining_info_many',
                              [remaining.toString()]),
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('understood')),
          ),
        ],
      ),
    );
  }
}
