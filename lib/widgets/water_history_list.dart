import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../features/home/home_providers.dart';
import '../models/water_entry_model.dart';
import '../services/localization/app_localization_service.dart';
import '../services/widgets/home_widgets_service.dart';

/// Компактный список записей воды на день
class WaterHistoryList extends ConsumerWidget {
  final List<WaterEntryModel> entries;
  final DateFormat? timeFormat;

  const WaterHistoryList({
    super.key,
    required this.entries,
    this.timeFormat,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) return const SizedBox.shrink();

    final DateFormat tf = timeFormat ?? DateFormat('HH:mm');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.tr('water'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.lightBlue[700],
                ),
              ),
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final e = entries[index];
              return _WaterEntryTile(entry: e, tf: tf);
            },
          ),
        ],
      ),
    );
  }
}

class _WaterEntryTile extends ConsumerWidget {
  final WaterEntryModel entry;
  final DateFormat tf;

  const _WaterEntryTile({
    required this.entry,
    required this.tf,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.08),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Иконка стакана воды вместо фото блюда
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.lightBlue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.local_drink, color: Colors.lightBlue),
            ),
            const SizedBox(width: 12),
            // Текстовые данные
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${entry.volumeMl} ${context.tr('ml_suffix')}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.access_time,
                              size: 12,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              tf.format(entry.dateTime),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Бейдж «Вода» для визуального отличия
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.lightBlue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      context.tr('water'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.lightBlue,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // Корзина для удаления
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.grey),
              onPressed: () async {
                final repo = ref.read(waterRepositoryProvider);
                await repo.removeEntry(entry.id);
                // Инвалидируем провайдеры воды для текущего дня
                final date = DateTime(entry.dateTime.year, entry.dateTime.month,
                    entry.dateTime.day);
                ref.invalidate(waterEntriesForDateProvider(date));
                ref.invalidate(waterTotalForDateProvider(date));
                // Обновляем виджеты через updateDailyProgressFromRepo для полной инициализации (как при добавлении еды)
                await HomeWidgetsService.updateDailyProgressFromRepo(ref);
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
