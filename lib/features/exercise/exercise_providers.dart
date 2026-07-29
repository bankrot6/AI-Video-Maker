import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/exercise_info.dart';
import '../../services/exercise_analysis_service.dart';
import '../../services/exercise_cache_service.dart';
import '../../services/google_video_search_service.dart';
import '../../services/rutube_video_search_service.dart';
import '../../repositories/workout_execution_repository.dart';
import '../../services/localization/app_localization_service.dart';

/// Провайдер сервиса анализа упражнений
final exerciseAnalysisServiceProvider =
    Provider<ExerciseAnalysisService>((ref) {
  return ExerciseAnalysisService();
});

/// Провайдер сервиса кэширования упражнений
final exerciseCacheServiceProvider = Provider<ExerciseCacheService>((ref) {
  return ExerciseCacheService();
});

// Удалён провайдер веб-скрейпинга VK — используем только Google CSE

/// Провайдер Google Video Search (Google CSE для VK видео)
final googleVideoSearchServiceProvider =
    Provider<GoogleVideoSearchService>((ref) {
  return GoogleVideoSearchService();
});

/// Провайдер RuTube Video Search (через Google CSE site:rutube.ru)
final rutubeVideoSearchServiceProvider =
    Provider<RutubeVideoSearchService>((ref) {
  return RutubeVideoSearchService();
});

/// Провайдер состояния анализа упражнения
final exerciseAnalysisStateProvider =
    StateProvider<AsyncValue<ExerciseInfo>>((ref) {
  return const AsyncValue.data(ExerciseInfo(
    name: '',
    description: '',
    keyPoints: '',
    commonMistakes: '',
    targetMuscles: '',
  ));
});

/// Провайдер выбранного изображения упражнения
final selectedExerciseImageProvider = StateProvider<File?>((ref) => null);

/// Провайдер для хранения последних результатов анализа
final lastExerciseAnalysisResultsProvider =
    StateProvider<ExerciseAnalysisResults?>((ref) => null);

/// Класс для хранения результатов анализа упражнения
class ExerciseAnalysisResults {
  final ExerciseInfo info;
  final DateTime timestamp;

  ExerciseAnalysisResults({
    required this.info,
    required this.timestamp,
  });
}

/// Провайдер репозитория выполнения подходов
final workoutExecutionRepositoryProvider =
    Provider<WorkoutExecutionRepository>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  return SharedPrefsWorkoutExecutionRepository(prefs);
});

/// Провайдер для получения прогресса выполнения упражнения
/// Возвращает количество завершенных подходов для указанного упражнения и даты
/// AutoDispose версия для автоматического обновления
final exerciseProgressProvider = FutureProvider.autoDispose.family<int, ({String exerciseName, DateTime date, int totalSets})>((ref, params) async {
  final repo = ref.watch(workoutExecutionRepositoryProvider);
  final sets = await repo.getSets(params.exerciseName, params.date, params.totalSets);
  
  return sets.where((set) => set.done).length;
});
