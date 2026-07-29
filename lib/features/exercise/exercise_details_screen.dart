import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import '../../widgets/liquid_glass_stub.dart';
import 'dart:ui';
import '../../models/exercise_info.dart';
import '../../models/workout_plan_model.dart';
import '../../services/localization/app_localization_service.dart';
import '../../services/providers.dart' as services;
import '../../models/exercise_video_candidate.dart';
import 'vk_video_keep_alive.dart';
import 'rutube_video_keep_alive.dart';
import 'exercise_providers.dart';
import '../../widgets/liquid_glass_card.dart';
import '../../widgets/glass_settings_constants.dart';
import 'widgets/exercise_execution_sheet.dart';

/// Экран просмотра подробностей упражнения
class ExerciseDetailsScreen extends ConsumerStatefulWidget {
  final ExerciseItem exercise;

  const ExerciseDetailsScreen({
    super.key,
    required this.exercise,
  });

  @override
  ConsumerState<ExerciseDetailsScreen> createState() =>
      _ExerciseDetailsScreenState();
}

class _ExerciseDetailsScreenState extends ConsumerState<ExerciseDetailsScreen> {
  bool _isAnalysisInProgress = false;
  File? _imageFile;
  bool _imageGenerated = false;
  List<ExerciseVideoCandidate> _videoCandidates = const [];
  // ignore: unused_field
  int _selectedVideoIndex = 0;
  bool _videoLoading = false;
  late PageController _pageController;
  int _currentPage = 0;
  int _activeVideoIndex = 0; // индекс текущего видео-слайда (pageIndex - 1)
  int? _currentSets;
  int? _currentReps;
  double? _currentWeight;
  double? _lastRpe;
  List<Map<String, dynamic>> _completedSets = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    // Запускаем анализ упражнения после создания виджета
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _analyzeExercise();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Запускает анализ упражнения
  Future<void> _analyzeExercise() async {
    if (_isAnalysisInProgress) return;

    setState(() {
      _isAnalysisInProgress = true;
    });

    try {
      debugPrint(
          '🏋️ EXERCISE_DETAILS: Начало анализа упражнения: ${widget.exercise.name}');

      // Проверяем кэш перед анализом
      final cacheService = ref.read(exerciseCacheServiceProvider);
      final cachedInfo =
          await cacheService.getCachedExerciseInfo(widget.exercise.name);

      if (cachedInfo != null && mounted) {
        debugPrint('✅ EXERCISE_DETAILS: Использованы данные из кэша');

        // Устанавливаем данные из кэша
        ref.read(exerciseAnalysisStateProvider.notifier).state =
            AsyncValue.data(cachedInfo);

        // Запускаем поиск изображения и видео
        _searchExerciseImage(cachedInfo.name);
        _searchVideo(cachedInfo.name);

        setState(() {
          _isAnalysisInProgress = false;
        });
        return;
      }

      // Устанавливаем состояние загрузки
      ref.read(exerciseAnalysisStateProvider.notifier).state =
          const AsyncValue.loading();

      // Получаем сервис анализа
      final analysisService = ref.read(exerciseAnalysisServiceProvider);

      // Запускаем потоковый анализ
      ExerciseInfo? lastInfo;
      await for (final exerciseInfo in analysisService.analyzeExerciseStream(
        widget.exercise.name,
        context: context,
      )) {
        if (!mounted) return;

        lastInfo = exerciseInfo;

        // Обновляем состояние с частичными результатами
        ref.read(exerciseAnalysisStateProvider.notifier).state =
            AsyncValue.data(exerciseInfo);

        // Если еще не начали поиск изображения и уже получили название
        if (!_imageGenerated && exerciseInfo.name.isNotEmpty) {
          _imageGenerated = true;
          _searchExerciseImage(exerciseInfo.name);
          _searchVideo(exerciseInfo.name);
        }
      }

      // Сохраняем финальный результат в кэш
      if (lastInfo != null && lastInfo.description.isNotEmpty) {
        await cacheService.cacheExerciseInfo(widget.exercise.name, lastInfo);
      }

      debugPrint('✅ EXERCISE_DETAILS: Анализ завершен');
    } catch (e) {
      debugPrint('❌ EXERCISE_DETAILS: Ошибка анализа: $e');
      ref.read(exerciseAnalysisStateProvider.notifier).state =
          AsyncValue.error(e, StackTrace.current);
    } finally {
      if (mounted) {
        setState(() {
          _isAnalysisInProgress = false;
        });
      }
    }
  }

  /// Поиск изображения упражнения через Google Image Search
  Future<void> _searchExerciseImage(String exerciseName) async {
    try {
      debugPrint(
          '🖼️ EXERCISE_DETAILS: ========================================');
      debugPrint(
          '🖼️ EXERCISE_DETAILS: Начало поиска изображения для: $exerciseName');

      final imageSearchService = ref.read(services.imageSearchServiceProvider);
      final cacheService = ref.read(exerciseCacheServiceProvider);

      // 1) Пробуем взять из кэша путь к изображению
      debugPrint('🖼️ EXERCISE_DETAILS: Проверка кэша...');
      final cachedPath = await cacheService.getCachedImagePath(exerciseName);
      if (cachedPath != null && File(cachedPath).existsSync()) {
        debugPrint(
            '💾 EXERCISE_CACHE: ✅ Изображение найдено в кэше: $cachedPath');
        setState(() {
          _imageFile = File(cachedPath);
        });
        ref.read(selectedExerciseImageProvider.notifier).state = _imageFile;
        debugPrint(
            '🖼️ EXERCISE_DETAILS: ========================================');
        return;
      }
      debugPrint(
          '🖼️ EXERCISE_DETAILS: ❌ Кэш пуст, запускаем поиск в Google...');

      // Формируем запрос для поиска: название упражнения + ключевые слова
      // Используем "technique demonstration" для более точного поиска демонстрации упражнения
      final query =
          '$exerciseName exercise technique demonstration workout fitness training';

      debugPrint('🖼️ EXERCISE_DETAILS: Поисковый запрос: "$query"');

      // Ищем изображение
      debugPrint(
          '🖼️ EXERCISE_DETAILS: Вызываем imageSearchService.findImage()...');
      File? file = await imageSearchService.findImage(query);

      if (file != null && mounted) {
        debugPrint('✅ EXERCISE_DETAILS: Изображение получено: ${file.path}');

        // Проверяем размер файла для диагностики
        final fileSize = await file.length();
        debugPrint('📊 EXERCISE_DETAILS: Размер файла: $fileSize байт');

        setState(() {
          _imageFile = file;
        });
        ref.read(selectedExerciseImageProvider.notifier).state = file;

        debugPrint('💾 EXERCISE_DETAILS: Сохраняем в кэш...');
        await cacheService.cacheExerciseImage(exerciseName, file.path);
        debugPrint('✅ EXERCISE_DETAILS: Сохранено в кэш успешно');
      } else {
        debugPrint('⚠️ EXERCISE_DETAILS: ❌ findImage вернул null!');
        debugPrint(
            '⚠️ EXERCISE_DETAILS: Проверьте настройки GOOGLE_CSE_API_KEY и GOOGLE_CSE_ID в .env файле');
      }
      debugPrint(
          '🖼️ EXERCISE_DETAILS: ========================================');
    } catch (e, stackTrace) {
      debugPrint(
          '❌ EXERCISE_DETAILS: ========================================');
      debugPrint('❌ EXERCISE_DETAILS: ОШИБКА при поиске изображения: $e');
      debugPrint('❌ EXERCISE_DETAILS: StackTrace: $stackTrace');
      debugPrint(
          '❌ EXERCISE_DETAILS: ========================================');
    }
  }

  /// Поиск видео упражнения через VK Video (с кэшированием)
  Future<void> _searchVideo(String exerciseName) async {
    if (_videoLoading) return;

    setState(() {
      _videoLoading = true;
    });

    try {
      debugPrint('🎥 EXERCISE_DETAILS: Поиск видео для: $exerciseName');

      // cacheService временно не используется: VK-кэш отключён

      List<ExerciseVideoCandidate> candidates = [];
      final List<ExerciseVideoCandidate> ruCandidates = [];

      // Временное отключение VK: не ищем и не отображаем VK видео

      // Ищем только RuTube и отображаем максимум 3
      try {
        final rutubeService = ref.read(rutubeVideoSearchServiceProvider);
        final found = await rutubeService.searchVideos(exerciseName);
        ruCandidates.addAll(found.take(3));
      } catch (e) {
        debugPrint('❌ EXERCISE_DETAILS: Ошибка поиска RuTube: $e');
      }

      candidates.addAll(ruCandidates);

      if (!mounted) return; // экран мог быть закрыт во время ожидания

      setState(() {
        _videoCandidates = candidates;
        _selectedVideoIndex = 0;
        _activeVideoIndex = 0;
        _videoLoading = false;
      });

      // Кэш VK отключен вместе с поиском VK
    } catch (e) {
      debugPrint('❌ EXERCISE_DETAILS: Ошибка при поиске видео: $e');
      if (mounted) {
        setState(() {
          _videoLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final analysisState = ref.watch(exerciseAnalysisStateProvider);

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 0, 0, 0),
      body: Stack(
        children: [
          // Фоновое изображение на весь экран
          Positioned.fill(
            child: Image.asset(
              'assets/images/a-futuristic-digital-background-0.png',
              fit: BoxFit.cover,
              opacity: const AlwaysStoppedAnimation(0.8),
            ),
          ),
          // Основной контент
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Область изображения с плавающей кнопкой назад
                  _buildImageSection(),

                  // Название упражнения на стеклянной плашке
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 12.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                        child: FakeGlass(
                          shape: const LiquidRoundedSuperellipse(
                            borderRadius: Radius.circular(11),
                          ),
                          settings: GlassSettingsConstants.ios26Overlay,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 13),
                            child: Text(
                              widget.exercise.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Информация об упражнении
                  analysisState.when(
                    data: (exerciseInfo) {
                      return _buildExerciseDetails(exerciseInfo);
                    },
                    loading: () => Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      child: _buildExerciseDetails(ExerciseInfo.empty()),
                    ),
                    error: (e, _) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: LiquidGlassCard(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.black,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                context
                                    .tr('error_occurred')
                                    .replaceAll('{0}', e.toString()),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.black),
                              ),
                              const SizedBox(height: 16),
                              LiquidGlassButton(
                                onPressed: _analyzeExercise,
                                child: Text(context.tr('retry')),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Плавающая кнопка назад в левом верхнем углу
          Positioned(
            left: 16,
            top: MediaQuery.of(context).padding.top + 8,
            child: _buildBackButton(),
          ),
        ],
      ),
    );
  }

  /// Строит стеклянную кнопку назад
  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: FakeGlass(
        shape: const LiquidRoundedSuperellipse(
          borderRadius: Radius.circular(100),
        ),
        settings: const LiquidGlassSettings(
          thickness: 1,
          glassColor: Color(0x18FFFFFF),
          lightIntensity: 0.7,
          ambientStrength: 0.1,
          saturation: 0.9,
        ),
        child: Container(
          width: 50,
          height: 50,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  /// Строит секцию с изображением и видео (карусель)
  Widget _buildImageSection() {
    final videoCount = _videoCandidates.length;
    final pageCount = 1 + videoCount; // 1 — фото
    // Убираем debugPrint из build() чтобы избежать спама в логах

    return Container(
      width: double.infinity,
      height: MediaQuery.of(context).size.height * 0.35,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            child: PageView.builder(
              controller: _pageController,
              allowImplicitScrolling: false,
              onPageChanged: (index) {
                debugPrint('📄 PAGE_VIEW: Переключено на страницу $index');
                setState(() {
                  _currentPage = index;
                  final newActive = index > 0 ? index - 1 : 0;
                  if (newActive != _activeVideoIndex) {
                    _activeVideoIndex = newActive;
                  }
                });
              },
              itemCount: 1 + _videoCandidates.length,
              itemBuilder: (context, index) {
                if (index == 0) return _buildImageWidget();
                final videoIndex = index - 1;
                return _buildVideoSlideAt(videoIndex);
              },
            ),
          ),
          // Индикаторы страниц
          if (pageCount > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  pageCount,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentPage == index
                          ? Colors.white
                          : Colors.white.withOpacity(0.4),
                    ),
                  ),
                ),
              ),
            ),
          // Подсказка для свайпа (показываем только на первой странице)
          if (pageCount > 1 && _currentPage == 0)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.swipe, color: Colors.white, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Свайп для видео',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          // Метка "Видео" на видео-слайдах
          if (_currentPage > 0)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.play_circle,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Видео $_currentPage/${pageCount - 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Строит виджет изображения
  Widget _buildImageWidget() {
    final imageWidget = _imageFile != null
        ? Image.file(
            _imageFile!,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            width: double.infinity,
            height: double.infinity,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) {
                return child;
              }
              return _buildImageShimmer();
            },
            errorBuilder: (context, error, stack) {
              return _buildImageShimmer();
            },
          )
        : _buildImageShimmer();

    return imageWidget;
  }

  Widget _buildVideoSlideAt(int i) {
    if (_videoCandidates.isNotEmpty) {
      if (i < 0 || i >= _videoCandidates.length) return const SizedBox.shrink();
      final c = _videoCandidates[i];
      final isActive = _activeVideoIndex == i;
      if (c.source == ExerciseVideoSource.vk &&
          c.ownerId != null &&
          c.videoId != null) {
        return VkVideoKeepAlive(
            key: PageStorageKey('vk_video_${c.ownerId}_${c.videoId}'),
            ownerId: c.ownerId!,
            videoId: c.videoId!,
            isActive: isActive);
      } else if (c.source == ExerciseVideoSource.rutube && c.videoId != null) {
        return RutubeVideoKeepAlive(
          key: PageStorageKey('rutube_${c.videoId}'),
          videoId: c.videoId!,
          isActive: isActive,
        );
      }
      return const SizedBox.shrink();
    }
    return const SizedBox.shrink();
  }

  /// Строит шиммер для изображения
  Widget _buildImageShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade800,
      highlightColor: Colors.grey.shade700,
      child: Container(
        color: Colors.grey.shade900,
      ),
    );
  }

  /// Строит детальную информацию об упражнении
  Widget _buildExerciseDetails(ExerciseInfo info) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Базовые параметры упражнения
          _buildParametersCard(),

          const SizedBox(height: 16),

          // Описание упражнения
          _maybeShimmer(
            visible: info.description.isNotEmpty,
            child: _buildInfoCard(
              title: context.tr('exercise_description'),
              content: info.description,
              icon: Icons.info_outline,
              color: Colors.blue,
            ),
          ),

          const SizedBox(height: 16),

          // Целевые мышцы
          _maybeShimmer(
            visible: info.targetMuscles.isNotEmpty,
            child: _buildInfoCard(
              title: context.tr('target_muscles'),
              content: info.targetMuscles,
              icon: Icons.fitness_center,
              color: Colors.green,
            ),
          ),

          const SizedBox(height: 16),

          // Ключевые моменты
          _maybeShimmer(
            visible: info.keyPoints.isNotEmpty,
            child: _buildInfoCard(
              title: context.tr('key_points'),
              content: info.keyPoints,
              icon: Icons.lightbulb_outline,
              color: Colors.orange,
            ),
          ),

          const SizedBox(height: 16),

          // Распространенные ошибки
          _maybeShimmer(
            visible: info.commonMistakes.isNotEmpty,
            child: _buildInfoCard(
              title: context.tr('common_mistakes'),
              content: info.commonMistakes,
              icon: Icons.warning_amber_outlined,
              color: Colors.red,
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// Строит карточку с параметрами упражнения (подходы, повторения, вес)
  Widget _buildParametersCard() {
    final int sets = _currentSets ?? widget.exercise.sets;
    final int reps = _currentReps ?? widget.exercise.reps;
    final double weight = _currentWeight ?? widget.exercise.weightKg;
    return LiquidGlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      settings: GlassSettingsConstants.matteList,
      blur: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildParameterItem(
                context.tr('workout_sets'),
                '$sets',
                Icons.repeat,
                const Color(0xFF64B5F6),
              ),
              _buildParameterItem(
                context.tr('workout_reps'),
                '$reps',
                Icons.format_list_numbered,
                const Color(0xFF81C784),
              ),
              if (weight > 0)
                _buildParameterItem(
                  context.tr('workout_weight_kg'),
                  weight.toStringAsFixed(1),
                  Icons.fitness_center,
                  const Color(0xFFFFB74D),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle,
                        size: 16, color: Colors.black54),
                    const SizedBox(width: 6),
                    Text(
                      context
                          .tr('completed_sets')
                          .replaceAll('{0}', '${_completedSets.length}')
                          .replaceAll('{1}', '$sets'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              if (_lastRpe != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speed, size: 16, color: Colors.black54),
                      const SizedBox(width: 6),
                      Text(
                        'RPE: ${_lastRpe!.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: LiquidGlassButton(
              onPressed: _openPerformBottomSheet,
              height: 48,
              borderRadius: 12,
              settings: GlassSettingsConstants.blue,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(context.tr('exercise_perform')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Строит элемент параметра
  Widget _buildParameterItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  /// Открывает bottom sheet для выполнения/редактирования параметров
  Future<void> _openPerformBottomSheet() async {
    final int totalSets = _currentSets ?? widget.exercise.sets;
    // Подготовим локальные данные по подходам (prefill из сохранённых)
    final List<Map<String, dynamic>> setsData = List.generate(totalSets, (i) {
      if (i < _completedSets.length) {
        return {
          'reps': _completedSets[i]['reps'] as int?,
          'weight': _completedSets[i]['weight'] as double?,
          'rpe': _completedSets[i]['rpe'] as double?,
          'done': true,
        };
      }
      return {
        'reps': null,
        'weight': null,
        'rpe': null,
        'done': false,
      };
    });

    int currentIndex = setsData.indexWhere((e) => e['done'] != true);
    if (currentIndex == -1)
      currentIndex = 0; // если всё заполнено, начинаем с 0

    // Начальные значения для текущего подхода
    // Переменные текущего подхода перенесены в ExerciseExecutionSheet

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
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
                    ExerciseExecutionSheet(
                      exerciseName: widget.exercise.name,
                      totalSets: totalSets,
                      defaultReps: (_currentReps ?? widget.exercise.reps),
                      defaultWeight:
                          (_currentWeight ?? widget.exercise.weightKg),
                      initialRpe: _lastRpe,
                      initialSetsData: setsData,
                      onSaveSet: (index, set) async {
                        final execRepo =
                            ref.read(workoutExecutionRepositoryProvider);
                        await execRepo.saveSet(
                          widget.exercise.name,
                          DateTime.now(),
                          index,
                          set,
                          totalSets,
                        );

                        // Инвалидируем провайдер прогресса для обновления UI
                        ref.invalidate(exerciseProgressProvider((
                          exerciseName: widget.exercise.name,
                          date: DateTime.now(),
                          totalSets: totalSets,
                        )));
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ).then((result) {
      if (result is Map) {
        final List<dynamic>? list = result['setsData'] as List<dynamic>?;
        if (list != null) {
          final saved = list
              .whereType<Map>()
              .where((e) => e['done'] == true)
              .map((e) => {
                    'reps': e['reps'] as int?,
                    'weight': e['weight'] as double?,
                    'rpe': e['rpe'] as double?,
                  })
              .toList();
          double? lastRpe;
          final rpes = saved
              .map((e) => e['rpe'] as double?)
              .whereType<double>()
              .toList();
          if (rpes.isNotEmpty) {
            lastRpe = rpes.last;
          }
          setState(() {
            _completedSets = saved;
            if (saved.isNotEmpty) {
              final last = saved.last;
              if (last['reps'] != null) _currentReps = last['reps'] as int;
              if (last['weight'] != null) {
                _currentWeight = last['weight'] as double;
              }
            }
            _lastRpe = lastRpe ?? _lastRpe;
          });
          // Убрали сообщение про числовой RPE, теперь сохраняем категорию без оповещения
        }
      }
    });
  }

  // Удалены устаревшие _quickButton и _quickIcon после перехода на стеклянные кнопки

  /// Строит информационную карточку
  Widget _buildInfoCard({
    required String title,
    required String content,
    required IconData icon,
    required Color color,
  }) {
    return LiquidGlassCard(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      settings: GlassSettingsConstants.matteList,
      blur: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  /// Оборачивает виджет в шиммер, если данные еще не загружены
  Widget _maybeShimmer({
    required bool visible,
    required Widget child,
  }) {
    if (visible || !_isAnalysisInProgress) {
      return child;
    }

    return _buildShimmerBox(height: 120, radius: 16);
  }

  /// Строит шиммер-заглушку
  Widget _buildShimmerBox({
    required double height,
    required double radius,
    double? width,
  }) {
    return Shimmer.fromColors(
      baseColor: Colors.white.withOpacity(0.3),
      highlightColor: Colors.white.withOpacity(0.4),
      period: const Duration(milliseconds: 1200),
      child: Container(
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}
