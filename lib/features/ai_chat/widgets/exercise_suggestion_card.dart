import 'package:flutter/material.dart';
import '../models/ai_agent_action.dart';
import '../../../services/localization/app_localization_service.dart';
import '../../../models/workout_plan_model.dart';

/// Карточка с предложением упражнения от AI
class ExerciseSuggestionCard extends StatelessWidget {
  final ExerciseSuggestion suggestion;
  final Function(int dayIndex, String dayTitle) onAddToDay;
  final VoidCallback? onDismiss;
  final List<WorkoutPlanModel> availableDays;

  const ExerciseSuggestionCard({
    super.key,
    required this.suggestion,
    required this.onAddToDay,
    this.onDismiss,
    this.availableDays = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFE1E1E6),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок с иконкой
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.fitness_center,
                    color: Color(0xFF1565C0),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    suggestion.exercise.name,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black54),
                    onPressed: onDismiss,
                    iconSize: 20,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Параметры упражнения
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildParameter(
                  icon: Icons.repeat,
                  label: context.tr('sets'),
                  value: '${suggestion.exercise.sets}',
                ),
                _buildParameter(
                  icon: Icons.numbers,
                  label: context.tr('reps'),
                  value: '${suggestion.exercise.reps}',
                ),
                if (suggestion.exercise.weightKg > 0)
                  _buildParameter(
                    icon: Icons.monitor_weight,
                    label: context.tr('weight'),
                    value: '${suggestion.exercise.weightKg.toStringAsFixed(1)} кг',
                  ),
              ],
            ),

            if (suggestion.reasoning.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                suggestion.reasoning,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ],

            if (suggestion.targetDayTitle != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      size: 12,
                      color: Color(0xFF1565C0),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      suggestion.targetDayTitle!,
                      style: const TextStyle(
                        color: Color(0xFF1565C0),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Кнопка добавления
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showDaySelectionSheet(context),
                icon: const Icon(Icons.add),
                label: Text(context.tr('add_to_workout')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDaySelectionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 24,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 16),
              child: Text(
                context.tr('select_workout_day'),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            
            // Список дней или создание нового
            if (availableDays.isEmpty)
              _buildNewDayOption(context)
            else
              ...availableDays.asMap().entries.map((entry) {
                final index = entry.key;
                final day = entry.value;
                return _buildDayOption(
                  context,
                  dayIndex: index,
                  dayTitle: day.dayTitle,
                  exerciseCount: day.exercises.length,
                );
              }),
            
            // Опция создания нового дня
            if (availableDays.isNotEmpty)
              _buildNewDayOption(context),
          ],
        ),
      ),
    );
  }

  Widget _buildDayOption(
    BuildContext context, {
    required int dayIndex,
    required String dayTitle,
    required int exerciseCount,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            onAddToDay(dayIndex, dayTitle);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7FB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFE1E1E6),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.fitness_center,
                    color: Color(0xFF1565C0),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dayTitle,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$exerciseCount ${context.tr('exercises_count')}',
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.6),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.black.withOpacity(0.4),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNewDayOption(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            onAddToDay(
              availableDays.length,
              'День ${availableDays.length + 1}',
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.green.shade200,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.add,
                    color: Color(0xFF2E7D32),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.tr('create_new_day'),
                    style: const TextStyle(
                      color: Color(0xFF2E7D32),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.green.withOpacity(0.6),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildParameter({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.black87),
          const SizedBox(width: 4),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Список предложений упражнений
class ExerciseSuggestionsWidget extends StatefulWidget {
  final List<ExerciseSuggestion> suggestions;
  final Function(ExerciseSuggestion, int dayIndex, String dayTitle) onAddExercise;
  final List<WorkoutPlanModel> availableDays;

  const ExerciseSuggestionsWidget({
    super.key,
    required this.suggestions,
    required this.onAddExercise,
    this.availableDays = const [],
  });

  @override
  State<ExerciseSuggestionsWidget> createState() =>
      _ExerciseSuggestionsWidgetState();
}

class _ExerciseSuggestionsWidgetState extends State<ExerciseSuggestionsWidget> {
  final Set<String> _dismissedIds = {};

  @override
  Widget build(BuildContext context) {
    final visibleSuggestions = widget.suggestions
        .where((s) => !_dismissedIds.contains(s.id))
        .toList();

    if (visibleSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(
                Icons.lightbulb_outline,
                color: Colors.amber,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                context.tr('ai_suggestions'),
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        ...visibleSuggestions.map(
          (suggestion) => ExerciseSuggestionCard(
            suggestion: suggestion,
            availableDays: widget.availableDays,
            onAddToDay: (dayIndex, dayTitle) {
              widget.onAddExercise(suggestion, dayIndex, dayTitle);
            },
            onDismiss: () {
              setState(() {
                _dismissedIds.add(suggestion.id);
              });
            },
          ),
        ),
      ],
    );
  }
}
