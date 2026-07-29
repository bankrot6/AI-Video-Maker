import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../widgets/liquid_glass_stub.dart';
import 'dart:ui' as ui;

import '../../models/workout_plan_model.dart';
import '../../models/weekly_workout_plan_model.dart';
import '../../widgets/voice_input_dialog.dart';
import '../localization/app_localization_service.dart';
import '../../features/home/home_providers.dart' as home;
import '../../models/weight_entry_model.dart';
import '../../utils/measurement_system.dart';
import '../../features/measurements/measurements_input_screen.dart';
import '../../features/ai_chat/ai_chat_screen.dart';
import '../nutrition_analysis/deepseek/deepseek_client.dart';
import '../../models/user_model.dart';
import '../../widgets/glass_settings_constants.dart';

class OneDecimalInputFormatter extends TextInputFormatter {
  static final _pattern = RegExp(r'^\d{0,3}(?:[.,]\d?)?');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;

    if (text.isEmpty) return newValue;

    final cleaned = text.replaceAll(' ', '');

    if (_pattern.hasMatch(cleaned)) {
      return newValue.copyWith(text: cleaned, selection: newValue.selection);
    }

    return oldValue;
  }
}

class ExerciseInputService {
  final WidgetRef _ref;
  final BuildContext _context;
  final DateTime _targetDate;
  final Function(ExerciseItem)? onExerciseAdded;
  final VoidCallback? onLoadingStarted;
  final Function(String)? onNameReceived;

  ExerciseInputService(
    this._ref,
    this._context,
    this._targetDate, {
    this.onExerciseAdded,
    this.onLoadingStarted,
    this.onNameReceived,
  });

  Future<void> showAddExerciseOptions() async {
    if (_context.mounted) {
      await showModalBottomSheet(
        context: _context,
        isScrollControlled: true,
        backgroundColor: Colors.black,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => _buildAddExerciseBottomSheet(context),
      );
    }
  }

  Widget _buildAddExerciseBottomSheet(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/a-futuristic-digital-background-0.png',
                    fit: BoxFit.cover,
                    opacity: const AlwaysStoppedAnimation(1.0),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        context.tr('add_exercise'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      _buildOption(
                        context: context,
                        icon: Icons.edit_rounded,
                        label: context.tr('add_by_text'),
                        color: const Color(0xFF5E7FE1),
                        onTap: () => openTextInput(),
                      ),
                      const SizedBox(height: 12),
                      _buildOption(
                        context: context,
                        icon: Icons.mic_rounded,
                        label: context.tr('add_by_voice'),
                        color: const Color(0xFF9D7FE1),
                        onTap: () => openVoiceInputDialog(),
                      ),
                      const SizedBox(height: 12),
                      _buildOption(
                        context: context,
                        icon: Icons.chat_rounded,
                        label: context.tr('add_through_chat'),
                        color: const Color(0xFF7FE1D4),
                        onTap: () => navigateToChat(),
                      ),
                      const SizedBox(height: 12),
                      _buildOption(
                        context: context,
                        icon: Icons.monitor_weight_rounded,
                        label: context.tr('change_weight'),
                        color: const Color(0xFFE17F8B),
                        onTap: () => openWeightInput(),
                      ),
                      const SizedBox(height: 12),
                      _buildOption(
                        context: context,
                        icon: Icons.straighten_rounded,
                        label: context.tr('body_measurements'),
                        color: const Color(0xFF86A8FF),
                        onTap: () => openMeasurementsScreen(),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: FakeGlass(
          shape: const LiquidRoundedSuperellipse(
            borderRadius: Radius.circular(12),
          ),
          settings: GlassSettingsConstants.onLightMinimal,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: Colors.black87, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.black.withOpacity(0.5),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openTextInput() async {
    final context = _context;
    if (!context.mounted) return;

    Navigator.of(context).pop();

    final textController = TextEditingController();

    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        'assets/images/a-futuristic-digital-background-0.png',
                        fit: BoxFit.cover,
                        opacity: const AlwaysStoppedAnimation(1.0),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            context.tr('add_exercise_by_text'),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: BackdropFilter(
                              filter:
                                  ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    width: 1,
                                  ),
                                ),
                                child: TextField(
                                  controller: textController,
                                  autofocus: true,
                                  maxLines: 3,
                                  style: const TextStyle(
                                      color: Colors.black87, fontSize: 16),
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) async {
                                    final text = textController.text.trim();
                                    if (text.isNotEmpty) {
                                      Navigator.of(context).pop();
                                      await _processExerciseText(text);
                                    }
                                  },
                                  decoration: InputDecoration(
                                    hintText: context.tr('exercise_text_hint'),
                                    hintStyle: TextStyle(
                                      color:
                                          Colors.black.withValues(alpha: 0.4),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.all(16),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                              child: FakeGlass(
                                shape: const LiquidRoundedSuperellipse(
                                  borderRadius: Radius.circular(12),
                                ),
                                settings: GlassSettingsConstants.onLightMinimal,
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () async {
                                      final text = textController.text.trim();
                                      if (text.isNotEmpty) {
                                        Navigator.of(context).pop();
                                        await _processExerciseText(text);
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            const Color(0xFF5E7FE1)
                                                .withValues(alpha: 0.3),
                                            const Color(0xFF5E7FE1)
                                                .withValues(alpha: 0.2),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        context.tr('add'),
                                        style: const TextStyle(
                                          color: Colors.black87,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> openVoiceInputDialog() async {
    final context = _context;
    if (!context.mounted) return;

    Navigator.of(context).pop();

    await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxWidth:
            MediaQuery.of(context).size.width, // Принудительно на всю ширину
        minWidth: MediaQuery.of(context).size.width,
      ),
      builder: (context) {
        return Container(
          width: MediaQuery.of(context).size.width, // Явно указываем ширину
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Stack(
              children: [
                // Футуристический фон
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/a-futuristic-digital-background-0.png',
                    fit: BoxFit.cover,
                    opacity: const AlwaysStoppedAnimation(1.0),
                  ),
                ),
                // Контент
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 16),
                  child: VoiceInputDialog(
                    onRecognized: (text) async {
                      Navigator.of(context).pop();
                      if (text.isNotEmpty) {
                        await _processExerciseText(text);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _processExerciseText(String text) async {
    try {
      final user = _ref.read(home.currentUserProvider);
      if (user == null) {
        throw Exception('Данные пользователя недоступны');
      }

      final localizationService = _ref.read(appLocalizationServiceProvider);
      final AppLanguage currentLang = localizationService.getCurrentLanguage();
      final String interfaceLanguage = _mapLanguageToName(currentLang);

      final prompt = _buildExercisePrompt(
        text: text,
        user: user,
        interfaceLanguage: interfaceLanguage,
      );

      // Вызываем колбэк начала загрузки
      debugPrint('🔄 LOADING_START: Начинаем загрузку упражнения');
      onLoadingStarted?.call();

      final client = DeepSeekClient.fromEnvironment(fastMode: true);
      String fullResponse = '';
      String currentName = '';
      bool startedExtractingName = false;
      int chunkCount = 0;

      await for (final chunk in client.generateTextStream(prompt)) {
        fullResponse += chunk;
        chunkCount++;

        // Начинаем извлекать название ОЧЕНЬ рано - с первого же чанка
        if (chunkCount >= 1) {
          final extractedName = _extractExerciseName(fullResponse);
          if (extractedName != null && extractedName.isNotEmpty) {
            // Отправляем обновление даже если название частично изменилось
            if (extractedName.length > currentName.length ||
                extractedName != currentName) {
              currentName = extractedName;
              if (!startedExtractingName) {
                debugPrint(
                    '📝 NAME_START: Начинаем получать название после чанка #$chunkCount: "$currentName"');
                startedExtractingName = true;
              } else {
                debugPrint(
                    '📝 NAME_UPDATE: Обновление названия (#$chunkCount): "$currentName"');
              }
              // Отправляем каждое обновление названия потоком
              onNameReceived?.call(currentName);
            }
          }
        }
      }

      final exercise = _parseExerciseFromResponse(fullResponse);

      if (exercise != null) {
        debugPrint('✅ PARSE_SUCCESS: Упражнение распознано: ${exercise.name}');
        await _addExerciseToWorkout(exercise);
        debugPrint('✅ ADD_COMPLETE: Упражнение добавлено в план');

        // Вызываем колбэк для обновления UI
        if (onExerciseAdded != null) {
          debugPrint('🔄 CALLBACK: Вызываем колбэк для обновления UI');
          onExerciseAdded!(exercise);
        }
      } else {
        debugPrint(
            '❌ PARSE_FAILED: Не удалось распознать упражнение из ответа AI');
      }
    } catch (e) {
      debugPrint('❌ ERROR: $e');
      if (_context.mounted) {
        ScaffoldMessenger.of(_context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String? _extractExerciseName(String partialResponse) {
    try {
      // 1. Ищем название упражнения в JSON формате (полное)
      final nameMatch =
          RegExp(r'"name":\s*"([^"]+)"').firstMatch(partialResponse);
      if (nameMatch != null) {
        return nameMatch.group(1);
      }

      // 2. Ищем частичное название (даже если кавычка не закрыта)
      final partialNameMatch = RegExp(r'"name":\s*"([^"]*)', dotAll: true)
          .firstMatch(partialResponse);
      if (partialNameMatch != null) {
        final name = partialNameMatch.group(1)?.trim();
        if (name != null && name.isNotEmpty) {
          return name;
        }
      }

      // 3. Альтернативный способ - ищем без кавычек
      final altMatch = RegExp(r'name:\s*([^\n,]+)').firstMatch(partialResponse);
      if (altMatch != null) {
        return altMatch.group(1)?.trim();
      }

      // 4. Пытаемся извлечь любой текст после "name"
      final anyMatch = RegExp(r'name["\s:]+([а-яА-Яa-zA-Z\s]+)', dotAll: true)
          .firstMatch(partialResponse);
      if (anyMatch != null) {
        final name = anyMatch.group(1)?.trim();
        if (name != null && name.length > 2) {
          return name;
        }
      }

      return null;
    } catch (e) {
      debugPrint('⚠️ EXTRACT_NAME_ERROR: $e');
      return null;
    }
  }

  String _buildExercisePrompt({
    required String text,
    required UserModel user,
    required String interfaceLanguage,
  }) {
    return '''You are a professional fitness trainer. Based on the user's description, create an exercise with proper sets, reps, and weight.

User description: "$text"

User info:
- Weight: ${user.weight} kg
- Gender: ${user.gender}
- Age: ${user.age}

Respond in $interfaceLanguage with this JSON format:
{
  "name": "Exercise name",
  "sets": 3,
  "reps": [12, 10, 8],
  "weight": 20.0,
  "notes": "Optional notes"
}

Important:
- Suggest appropriate weight based on user's weight and exercise type
- Use progressive rep scheme (e.g., 12, 10, 8)
- Name should be in $interfaceLanguage
- Keep it simple and safe
''';
  }

  ExerciseItem? _parseExerciseFromResponse(String response) {
    try {
      final jsonStart = response.indexOf('{');
      final jsonEnd = response.lastIndexOf('}') + 1;

      if (jsonStart == -1 || jsonEnd == 0) return null;

      final jsonStr = response.substring(jsonStart, jsonEnd);

      final nameMatch = RegExp(r'"name"\s*:\s*"([^"]+)"').firstMatch(jsonStr);
      final setsMatch = RegExp(r'"sets"\s*:\s*(\d+)').firstMatch(jsonStr);
      final repsMatch =
          RegExp(r'"reps"\s*:\s*\[([^\]]+)\]').firstMatch(jsonStr);
      final weightMatch =
          RegExp(r'"weight"\s*:\s*([\d.]+)').firstMatch(jsonStr);

      if (nameMatch == null || setsMatch == null) return null;

      final name = nameMatch.group(1)!;
      final sets = int.parse(setsMatch.group(1)!);

      int reps;
      if (repsMatch != null) {
        final repsStr = repsMatch.group(1)!;
        final repsList = repsStr
            .split(',')
            .map((e) => int.tryParse(e.trim()) ?? 12)
            .toList();
        reps = repsList.isNotEmpty ? repsList.first : 12;
      } else {
        reps = 12;
      }

      double weight;
      if (weightMatch != null) {
        weight = double.parse(weightMatch.group(1)!);
      } else {
        weight = 0.0;
      }

      return ExerciseItem(
        name: name,
        sets: sets,
        reps: reps,
        weightKg: weight,
      );
    } catch (e) {
      debugPrint('Error parsing exercise: $e');
      return null;
    }
  }

  Future<void> _addExerciseToWorkout(ExerciseItem exercise) async {
    try {
      final weekStart = startOfWeek(_targetDate);
      final workoutPlanRepo = _ref.read(home.workoutPlanRepositoryProvider);

      WeeklyWorkoutPlanModel? weekPlan =
          await workoutPlanRepo.getPlanForWeek(weekStart);

      if (weekPlan == null) {
        debugPrint('❌ ADD_EXERCISE: План недели не найден');
        return;
      }

      final workoutsPerWeek = weekPlan.workoutsPerWeek;

      // Вычисляем индекс дня в неделе для целевой даты
      final scheduledDates = _computeScheduledDates(
        _targetDate,
        workoutsPerWeek,
        weeksForward: 0,
        weeksBackward: 0,
      );

      final dateIndex = scheduledDates.indexWhere(
        (date) => _isSameDate(date, _targetDate),
      );

      if (dateIndex == -1) {
        debugPrint('❌ ADD_EXERCISE: Дата не найдена в расписании');
        return;
      }

      final dayIndexInWeek = dateIndex % workoutsPerWeek;

      debugPrint(
          '💪 ADD_EXERCISE: Добавление упражнения в день $dayIndexInWeek');

      // Получаем текущий день или создаем новый
      String dayTitle = 'Тренировка ${dayIndexInWeek + 1}';
      List<ExerciseItem> currentExercises = [];

      if (dayIndexInWeek < weekPlan.days.length) {
        final existingDay = weekPlan.days[dayIndexInWeek];
        dayTitle = existingDay.dayTitle;
        currentExercises = List<ExerciseItem>.from(existingDay.exercises);
      }

      // Добавляем новое упражнение
      currentExercises.add(exercise);

      // Создаем обновленный план дня
      final updatedDayPlan = WorkoutPlanModel(
        dayTitle: dayTitle,
        exercises: currentExercises,
      );

      // Сохраняем через репозиторий
      await workoutPlanRepo.saveDayAtIndex(
        weekStart,
        updatedDayPlan,
        dayIndexInWeek,
        workoutsPerWeek,
      );

      // Инвалидируем провайдеры для обновления UI
      _ref.invalidate(home.weeklyWorkoutPlanProvider);
      _ref.invalidate(home.weeklyWorkoutPlanForDateProvider(weekStart));

      debugPrint('✅ ADD_EXERCISE: Упражнение успешно добавлено');
    } catch (e) {
      debugPrint('❌ ADD_EXERCISE: Ошибка добавления: $e');
      rethrow;
    }
  }

  List<DateTime> _computeScheduledDates(DateTime base, int workoutsPerWeek,
      {int weeksForward = 1, int weeksBackward = 0}) {
    final DateTime startDate = DateTime(base.year, base.month, base.day);

    List<int> weekdays;
    switch (workoutsPerWeek.clamp(1, 7)) {
      case 3:
        weekdays = [DateTime.monday, DateTime.wednesday, DateTime.friday];
        break;
      case 4:
        weekdays = [
          DateTime.monday,
          DateTime.tuesday,
          DateTime.thursday,
          DateTime.saturday
        ];
        break;
      case 5:
        weekdays = [
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.friday,
          DateTime.saturday
        ];
        break;
      case 1:
        weekdays = [DateTime.monday];
        break;
      case 2:
        weekdays = [DateTime.tuesday, DateTime.friday];
        break;
      default:
        weekdays = [
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.thursday,
          DateTime.friday,
          DateTime.saturday,
          DateTime.sunday,
        ];
    }

    final List<DateTime> dates = [];
    dates.add(startDate);

    final int totalWeeks = weeksBackward + weeksForward;
    final int totalDays = totalWeeks * 7;
    final DateTime firstDate =
        startDate.subtract(Duration(days: weeksBackward * 7));

    for (int i = 0; i < totalDays; i++) {
      final DateTime date = firstDate.add(Duration(days: i));
      if (date.year == startDate.year &&
          date.month == startDate.month &&
          date.day == startDate.day) {
        continue;
      }
      if (weekdays.contains(date.weekday)) {
        dates.add(date);
      }
    }

    return dates;
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _mapLanguageToName(AppLanguage lang) {
    switch (lang) {
      case AppLanguage.ru:
        return 'Russian';
      case AppLanguage.en:
        return 'English';
      case AppLanguage.ar:
        return 'Arabic';
      default:
        return 'English';
    }
  }

  void navigateToChat() {
    if (!_context.mounted) return;
    Navigator.of(_context).pop();

    Navigator.of(_context).push(
      MaterialPageRoute(
        builder: (context) => const AiChatScreen(isActive: true),
      ),
    );
  }

  void openWeightInput() {
    final context = _context;
    if (!context.mounted) return;

    Navigator.of(context).pop();

    final measurementSystem = MeasurementUtils.getDefaultMeasurementSystem();
    final currentUser = _ref.read(home.currentUserProvider);
    final currentWeightKg = currentUser?.weight ?? 70.0;

    final double initialDisplayWeight =
        measurementSystem == MeasurementSystem.imperial
            ? MeasurementUtils.kgToLbs(currentWeightKg)
            : currentWeightKg;

    final controller =
        TextEditingController(text: initialDisplayWeight.toStringAsFixed(1));

    showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (bottomContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(bottomContext).viewInsets.bottom,
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        'assets/images/a-futuristic-digital-background-0.png',
                        fit: BoxFit.cover,
                        opacity: const AlwaysStoppedAnimation(1.0),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            context.tr('change_weight'),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: BackdropFilter(
                              filter:
                                  ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    width: 1,
                                  ),
                                ),
                                child: TextField(
                                  controller: controller,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [OneDecimalInputFormatter()],
                                  autofocus: true,
                                  style: const TextStyle(
                                      color: Colors.black87, fontSize: 16),
                                  decoration: InputDecoration(
                                    labelText: measurementSystem ==
                                            MeasurementSystem.imperial
                                        ? context.tr('weight_lbs')
                                        : context.tr('weight_kg'),
                                    labelStyle: TextStyle(
                                      color:
                                          Colors.black.withValues(alpha: 0.6),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.all(16),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                              child: FakeGlass(
                                shape: const LiquidRoundedSuperellipse(
                                  borderRadius: Radius.circular(12),
                                ),
                                settings: GlassSettingsConstants.onLightMinimal,
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () async {
                                      final value = double.tryParse(
                                        controller.text.replaceAll(',', '.'),
                                      );
                                      if (value != null) {
                                        Navigator.of(bottomContext).pop(value);
                                        final double weightKg =
                                            measurementSystem ==
                                                    MeasurementSystem.imperial
                                                ? MeasurementUtils.lbsToKg(
                                                    value)
                                                : value;
                                        await _saveNewWeight(weightKg);
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            const Color(0xFFE17F8B)
                                                .withValues(alpha: 0.3),
                                            const Color(0xFFE17F8B)
                                                .withValues(alpha: 0.2),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        context.tr('save'),
                                        style: const TextStyle(
                                          color: Colors.black87,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveNewWeight(double weight) async {
    final user = _ref.read(home.currentUserProvider);
    if (user == null) return;

    final updatedUser = user.copyWith(weight: weight);
    final userRepository = _ref.read(home.userRepositoryProvider);
    await userRepository.updateUser(updatedUser);
    _ref.read(home.currentUserProvider.notifier).setUser(updatedUser);

    final weightRepository = _ref.read(home.weightRepositoryProvider);
    await weightRepository.addWeightEntry(
      WeightEntryModel(
        id: const Uuid().v4(),
        weight: weight,
        dateTime: DateTime.now(),
      ),
    );
  }

  void openMeasurementsScreen() async {
    if (!_context.mounted) return;
    Navigator.of(_context).pop();

    await Navigator.of(_context).push(
      MaterialPageRoute(
        builder: (context) => const MeasurementsInputScreen(),
      ),
    );
  }
}

final exerciseInputServiceProvider =
    Provider.family<ExerciseInputService, DateTime>(
  (ref, targetDate) {
    throw UnimplementedError('This provider requires context');
  },
);

Provider<ExerciseInputService Function(WidgetRef, BuildContext, DateTime)>
    exerciseInputServiceFactoryProvider = Provider((ref) {
  return (WidgetRef widgetRef, BuildContext context, DateTime targetDate) {
    return ExerciseInputService(widgetRef, context, targetDate);
  };
});
