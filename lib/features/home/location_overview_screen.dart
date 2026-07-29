import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shimmer/shimmer.dart';
import 'models/location_overview_info.dart';
import 'services/location_overview_service.dart';
import 'services/background_attraction_loading_service.dart';
import 'services/location_overview_cache_service.dart';
import 'widgets/image_carousel.dart';
import '../../services/text_to_speech/base_tts_service.dart';
import '../../services/text_to_speech/tts_providers.dart';
import '../../services/text_to_speech/streaming_tts_orchestrator.dart';
import '../../services/providers.dart' as services;
import '../../services/image_search/google_image_search_service.dart';
import '../../utils/text_cleaner.dart';

final locationOverviewServiceProvider =
    Provider<LocationOverviewService>((ref) {
  return LocationOverviewService();
});

final locationOverviewCacheServiceProvider =
    Provider<LocationOverviewCacheService>((ref) {
  return LocationOverviewCacheService();
});

final locationOverviewStateProvider =
    StateProvider<AsyncValue<LocationOverviewInfo>>(
        (ref) => const AsyncValue.loading());

final locationImagesProvider = StateProvider<List<File>>((ref) => []);

class LocationOverviewScreen extends ConsumerStatefulWidget {
  final String locationName;
  final double latitude;
  final double longitude;

  const LocationOverviewScreen({
    super.key,
    required this.locationName,
    required this.latitude,
    required this.longitude,
  });

  @override
  ConsumerState<LocationOverviewScreen> createState() =>
      _LocationOverviewScreenState();
}

class _LocationOverviewScreenState
    extends ConsumerState<LocationOverviewScreen> {
  bool _isAnalysisInProgress = false;
  bool _imagesLoading = false;
  List<File> _imageFiles = [];

  String? _currentPlayingSection;
  bool _isDisposed = false;
  bool _isAutoPlayMode = true;
  bool _autoPlayStarted = false;

  StreamSubscription<LocationOverviewInfo>? _analysisSubscription;
  Timer? _playbackMonitorTimer;

  StreamingTtsOrchestrator? _autoTts;
  String _latestAutoText = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _analyzeLocation();
    });
  }

  void _resetPlaybackState() {
    _autoPlayStarted = false;
    _isAutoPlayMode = true;
    _currentPlayingSection = null;
    _latestAutoText = '';
    _autoTts?.dispose();
    _autoTts = null;
    _playbackMonitorTimer?.cancel();
    _playbackMonitorTimer = null;
  }

  Future<void> _stopPlayback() async {
    debugPrint('🔇 TTS: Остановка воспроизведения');
    _playbackMonitorTimer?.cancel();
    _playbackMonitorTimer = null;
    _currentPlayingSection = null;
    _latestAutoText = '';
    _autoTts?.dispose();
    _autoTts = null;

    try {
      final ttsService = ref.read(attractionTTSServiceProvider);
      await ttsService.stop();
      await ttsService.clearQueue();
    } catch (e) {
      debugPrint('⚠️ TTS: Ошибка остановки: $e');
    }
  }

  @override
  void dispose() {
    debugPrint('🧹 LOCATION_OVERVIEW: Dispose');
    _isDisposed = true;
    _isAutoPlayMode = false;
    _playbackMonitorTimer?.cancel();

    _analysisSubscription?.cancel();
    _analysisSubscription = null;

    try {
      final ttsService = ref.read(attractionTTSServiceProvider);
      ttsService.stop();
      ttsService.clearQueue();
    } catch (e) {
      debugPrint('⚠️ LOCATION_OVERVIEW: Ошибка в dispose: $e');
    }

    super.dispose();
  }

  Future<void> _analyzeLocation({bool forceRefresh = false}) async {
    if (_isAnalysisInProgress) return;

    if (forceRefresh) {
      await _stopPlayback();
      _resetPlaybackState();
    }

    _isDisposed = false;
    _imagesLoading = false;

    if (!mounted) return;
    setState(() {
      _isAnalysisInProgress = true;
    });

    debugPrint(
        '🌍 LOCATION_OVERVIEW: Начало анализа локации: ${widget.locationName}');

    final overviewService = ref.read(locationOverviewServiceProvider);
    final overviewCache = ref.read(locationOverviewCacheServiceProvider);
    final cacheService = ref.read(attractionCacheServiceProvider);

    final cacheKey = widget.locationName;

    if (!forceRefresh) {
      final cachedOverview =
          await overviewCache.getCachedLocationOverview(cacheKey);
      final isComplete = await overviewCache.isCacheComplete(cacheKey);
      if (cachedOverview != null && isComplete) {
        debugPrint(
            '💾 LOCATION_OVERVIEW: Текст загружен из кэша (complete: $isComplete)');
        ref.read(locationOverviewStateProvider.notifier).state =
            AsyncValue.data(cachedOverview);
        if (mounted) {
          setState(() {
            _isAnalysisInProgress = false;
          });
        }
        return;
      }
    }

    if (!forceRefresh) {
      final cachedImages =
          await cacheService.getCachedImages('location_${widget.locationName}');
      if (cachedImages.isNotEmpty && mounted) {
        setState(() {
          _imageFiles = cachedImages;
        });
        ref.read(locationImagesProvider.notifier).state = cachedImages;
        debugPrint(
            '🖼️ LOCATION_OVERVIEW: ${cachedImages.length} изображений загружено из кэша');
      }
    }

    if (!mounted) return;
    ref.read(locationOverviewStateProvider.notifier).state =
        const AsyncValue.loading();

    _analysisSubscription?.cancel();
    _analysisSubscription = overviewService
        .analyzeLocationStream(
      widget.locationName,
      context: context,
    )
        .listen(
      (locationInfo) async {
        if (!mounted || _isDisposed) return;

        ref.read(locationOverviewStateProvider.notifier).state =
            AsyncValue.data(locationInfo);

        final isCompleteNow = _isLocationInfoComplete(locationInfo);
        if (locationInfo.name.isNotEmpty &&
            (locationInfo.generalInfo.length > 200 ||
                locationInfo.history.length > 200 ||
                locationInfo.culture.length > 200 ||
                locationInfo.interestingFacts.length > 200 ||
                locationInfo.practicalInfo.length > 200)) {
          await overviewCache.cacheLocationOverview(
            cacheKey,
            locationInfo,
            isComplete: isCompleteNow,
          );
        }

        if (!_imagesLoading &&
            _imageFiles.isEmpty &&
            locationInfo.name.isNotEmpty) {
          _imagesLoading = true;
          _searchLocationImages(locationInfo.name);
        }

        await _enqueueAvailableText(locationInfo);
      },
      onError: (error, stackTrace) {
        if (!mounted || _isDisposed) return;
        debugPrint('❌ LOCATION_OVERVIEW: Ошибка анализа: $error');
        ref.read(locationOverviewStateProvider.notifier).state =
            AsyncValue.error(error, stackTrace);
        if (mounted) {
          setState(() {
            _isAnalysisInProgress = false;
          });
        }
      },
      onDone: () async {
        if (!mounted || _isDisposed) return;
        debugPrint('✅ LOCATION_OVERVIEW: Анализ завершен');

        final last = ref.read(locationOverviewStateProvider).valueOrNull;
        if (last != null && last.name.isNotEmpty) {
          await overviewCache.cacheLocationOverview(
            cacheKey,
            last,
            isComplete: _isLocationInfoComplete(last),
          );
        }

        await _autoTts?.updateFullText(_latestAutoText, isFinal: true);

        if (mounted) {
          setState(() {
            _isAnalysisInProgress = false;
          });
        }
      },
    );
  }

  bool _isLocationInfoComplete(LocationOverviewInfo info) {
    return info.generalInfo.length > 300 &&
        info.history.length > 300 &&
        info.culture.length > 300 &&
        info.interestingFacts.length > 300 &&
        info.practicalInfo.length > 300 &&
        (info.error == null || info.error!.isEmpty);
  }

  String _getAllAvailableText(LocationOverviewInfo info) {
    final parts = <String>[];

    if (info.generalInfo.isNotEmpty) {
      parts.add('Общая информация. ${info.generalInfo}');
    }
    if (info.history.isNotEmpty) {
      parts.add('История. ${info.history}');
    }
    if (info.culture.isNotEmpty) {
      parts.add('Культура. ${info.culture}');
    }
    if (info.interestingFacts.isNotEmpty) {
      parts.add('Интересные факты. ${info.interestingFacts}');
    }
    if (info.practicalInfo.isNotEmpty) {
      parts.add('Практические советы. ${info.practicalInfo}');
    }

    return parts.join(' ');
  }

  Future<void> _enqueueAvailableText(LocationOverviewInfo info) async {
    if (!_isAutoPlayMode || _isDisposed || !mounted) return;

    final ttsService = ref.read(attractionTTSServiceProvider);

    final allText = _getAllAvailableText(info);
    final cleaned = TextCleaner.cleanForSpeechPreserveContent(allText);
    _latestAutoText = cleaned;

    if (!_autoPlayStarted) {
      if (cleaned.length < 120) return;

      debugPrint(
          '🎤 TTS: Запуск автоозвучки. Доступно ${cleaned.length} символов');
      _autoPlayStarted = true;

      final locationIntro = 'Сейчас мы расскажем о ${widget.locationName}.';
      await ttsService.addToQueue(locationIntro, languageCode: 'ru-RU');

      _autoTts = StreamingTtsOrchestrator(
        tts: ttsService,
        languageCode: 'ru-RU',
        minStartBufferChars: 180,
        targetQueueChunks: 3,
        maxQueueChunks: 8,
        minChunkChars: 80,
        maxChunkChars: 320,
        softLookAheadChars: 140,
      );

      _startPlaybackMonitor();
    }

    await _autoTts?.updateFullText(cleaned, isFinal: false);
  }

  void _startPlaybackMonitor() {
    _playbackMonitorTimer?.cancel();

    _playbackMonitorTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (timer) async {
        if (_isDisposed || !mounted) {
          timer.cancel();
          return;
        }

        final ttsService = ref.read(attractionTTSServiceProvider);
        final isPlaying = ttsService.isPlaying || ttsService.hasQueuedItems;

        if (isPlaying && _currentPlayingSection == null) {
          if (mounted) {
            setState(() {
              _currentPlayingSection = 'auto';
            });
          }
        }

        if (isPlaying && ttsService.queueSize <= 2) {
          await _autoTts?.pump();
        }

        if (!isPlaying && _currentPlayingSection != null) {
          debugPrint('✅ TTS: Воспроизведение завершено');
          if (mounted) {
            setState(() {
              _currentPlayingSection = null;
            });
          }
          timer.cancel();
        }
      },
    );
  }

  Future<void> _searchLocationImages(String locationName) async {
    try {
      final cacheService = ref.read(attractionCacheServiceProvider);

      final cachedImages =
          await cacheService.getCachedImages('location_$locationName');
      if (cachedImages.isNotEmpty && mounted) {
        debugPrint(
            '🖼️ LOCATION_OVERVIEW: ${cachedImages.length} изображений из кэша');
        setState(() {
          _imageFiles = cachedImages;
          _imagesLoading = false;
        });
        ref.read(locationImagesProvider.notifier).state = cachedImages;
        return;
      }

      debugPrint(
          '🖼️ LOCATION_OVERVIEW: Стриминг изображений для: $locationName');

      final imageSearchService = ref.read(services.imageSearchServiceProvider);

      if (imageSearchService is! GoogleImageSearchService) {
        debugPrint('⚠️ LOCATION_OVERVIEW: Сервис не поддерживает стриминг');
        setState(() => _imagesLoading = false);
        return;
      }

      String? cityName;
      String? countryName;
      try {
        final placemarks = await placemarkFromCoordinates(
          widget.latitude,
          widget.longitude,
        );
        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          cityName = placemark.locality ?? placemark.administrativeArea;
          countryName = placemark.country;
        }
      } catch (_) {}

      final searchSuffixes = [
        '',
        'город city',
        'достопримечательности landmarks',
        'панорама skyline',
        'архитектура architecture',
        'туризм tourism',
      ];

      debugPrint(
          '🖼️ LOCATION_OVERVIEW: Город: $cityName, Страна: $countryName');

      final List<File> collectedFiles = [];

      await for (final file in imageSearchService.streamImages(
        baseName: locationName,
        cityName: cityName,
        countryName: countryName,
        searchSuffixes: searchSuffixes,
        maxImages: 6,
      )) {
        if (!mounted || _isDisposed) break;

        collectedFiles.add(file);

        setState(() {
          _imageFiles = List.from(collectedFiles);
        });
        ref.read(locationImagesProvider.notifier).state =
            List.from(collectedFiles);

        debugPrint(
            '🖼️ LOCATION_OVERVIEW: Отображено ${collectedFiles.length} фото');
      }

      if (collectedFiles.isNotEmpty && mounted) {
        await cacheService.cacheAttractionImages(
            'location_$locationName', collectedFiles);
        debugPrint(
            '✅ LOCATION_OVERVIEW: Закэшировано ${collectedFiles.length} фото');
      }

      if (mounted) {
        setState(() => _imagesLoading = false);
      }
    } catch (e) {
      debugPrint('❌ LOCATION_OVERVIEW: Ошибка стриминга: $e');
      if (mounted) {
        setState(() => _imagesLoading = false);
      }
    }
  }

  Future<void> _playSection(
      String sectionKey, String title, String content) async {
    if (_isDisposed || !mounted) return;

    final ttsService = ref.read(attractionTTSServiceProvider);
    final isCurrentlyPlaying =
        ttsService.isPlaying || ttsService.hasQueuedItems;

    if (_currentPlayingSection == sectionKey && isCurrentlyPlaying) {
      debugPrint('🎙️ MANUAL: Остановка озвучки');
      await _stopPlayback();
      _isAutoPlayMode = false;
      return;
    }

    debugPrint('🎙️ MANUAL: Ручной запуск секции $sectionKey');
    _isAutoPlayMode = false;

    await _stopPlayback();

    final cleaned = TextCleaner.cleanForSpeechPreserveContent(content);
    if (cleaned.length < 30) return;

    if (mounted) {
      setState(() {
        _currentPlayingSection = sectionKey;
      });
    }

    final locationIntro = 'Сейчас мы расскажем о ${widget.locationName}.';
    await ttsService.addToQueue(locationIntro, languageCode: 'ru-RU');
    await ttsService.addToQueue('$title.', languageCode: 'ru-RU');
    await ttsService.addToQueue(cleaned, languageCode: 'ru-RU');

    _startPlaybackMonitor();
  }

  void _showVoiceSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _VoiceSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final analysisState = ref.watch(locationOverviewStateProvider);

    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          debugPrint(
              '🔙 LOCATION_OVERVIEW: Пользователь покидает экран - остановка озвучки');
          await _stopPlayback();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildImageSection(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 12.0),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 16),
                      child: Text(
                        widget.locationName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
                analysisState.when(
                  data: (info) => _buildLocationDetails(info),
                  loading: () => _buildLoadingPlaceholder(),
                  error: (error, stack) => _buildErrorWidget(error),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    final serviceType = ref.watch(ttsServiceTypeProvider);
    final isLocalTTS = serviceType == TTSServiceType.local;
    final height = MediaQuery.of(context).size.height * 0.35;
    final borderRadius = const BorderRadius.only(
      bottomLeft: Radius.circular(20),
      bottomRight: Radius.circular(20),
    );

    if (_imagesLoading && _imageFiles.isEmpty) {
      return ImageCarouselLoading(
        height: height,
        borderRadius: borderRadius,
      );
    }

    return ImageCarousel(
      images: _imageFiles,
      height: height,
      borderRadius: borderRadius,
      placeholder: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.grey[300],
        child: Icon(
          Icons.location_city,
          size: 80,
          color: Colors.grey[600],
        ),
      ),
      onBackPressed: () async {
        debugPrint('🔙 LOCATION_OVERVIEW: Нажата кнопка "Назад"');
        await _stopPlayback();
        if (mounted) {
          Navigator.of(context).pop();
        }
      },
      topRightWidget: _buildTopRightButtons(isLocalTTS),
    );
  }

  Widget? _buildTopRightButtons(bool isLocalTTS) {
    if (!isLocalTTS) return null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(30),
      ),
      child: IconButton(
        icon: const Icon(Icons.settings_voice, color: Colors.white),
        onPressed: _showVoiceSettings,
        tooltip: 'Настройки голоса',
      ),
    );
  }

  Widget _buildLocationDetails(LocationOverviewInfo info) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _maybeShimmer(
            visible: info.generalInfo.isNotEmpty,
            child: _buildInfoCard(
              sectionKey: 'generalInfo',
              title: 'Общая информация',
              displayTitle: '🌍 Общая информация',
              content: info.generalInfo,
              icon: Icons.info_outline,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 16),
          _maybeShimmer(
            visible: info.history.isNotEmpty,
            child: _buildInfoCard(
              sectionKey: 'history',
              title: 'История',
              displayTitle: '📖 История',
              content: info.history,
              icon: Icons.history_edu,
              color: Colors.purple,
            ),
          ),
          const SizedBox(height: 16),
          _maybeShimmer(
            visible: info.culture.isNotEmpty,
            child: _buildInfoCard(
              sectionKey: 'culture',
              title: 'Культура',
              displayTitle: '🎭 Культура',
              content: info.culture,
              icon: Icons.theater_comedy,
              color: Colors.teal,
            ),
          ),
          const SizedBox(height: 16),
          _maybeShimmer(
            visible: info.interestingFacts.isNotEmpty,
            child: _buildInfoCard(
              sectionKey: 'interestingFacts',
              title: 'Интересные факты',
              displayTitle: '✨ Интересные факты',
              content: info.interestingFacts,
              icon: Icons.lightbulb_outline,
              color: Colors.orange,
            ),
          ),
          const SizedBox(height: 16),
          _maybeShimmer(
            visible: info.practicalInfo.isNotEmpty,
            child: _buildInfoCard(
              sectionKey: 'practicalInfo',
              title: 'Практические советы',
              displayTitle: '🎯 Практические советы',
              content: info.practicalInfo,
              icon: Icons.tips_and_updates,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required String sectionKey,
    required String title,
    required String displayTitle,
    required String content,
    required IconData icon,
    required Color color,
  }) {
    final isPlaying = _currentPlayingSection == sectionKey;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    displayTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _playSection(sectionKey, title, content),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isPlaying
                          ? Colors.red.withValues(alpha: 0.1)
                          : color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      isPlaying ? Icons.stop : Icons.play_arrow,
                      color: isPlaying ? Colors.red : color,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              TextCleaner.cleanForDisplayPreserveStructure(content),
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _maybeShimmer({
    required bool visible,
    required Widget child,
  }) {
    if (visible) {
      return child;
    }

    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: const SizedBox(
          width: double.infinity,
          height: 150,
        ),
      ),
    );
  }

  Widget _buildLoadingPlaceholder() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildShimmerCard(),
          const SizedBox(height: 16),
          _buildShimmerCard(),
          const SizedBox(height: 16),
          _buildShimmerCard(),
          const SizedBox(height: 16),
          _buildShimmerCard(),
          const SizedBox(height: 16),
          _buildShimmerCard(),
        ],
      ),
    );
  }

  Widget _buildShimmerCard() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: const SizedBox(
          width: double.infinity,
          height: 150,
        ),
      ),
    );
  }

  Widget _buildErrorWidget(Object error) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              const Text(
                'Ошибка загрузки информации',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _analyzeLocation(forceRefresh: true),
                child: const Text('Повторить попытку'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceSettingsSheet extends ConsumerWidget {
  const _VoiceSettingsSheet();

  static const List<_SpeedOption> _speedOptions = [
    _SpeedOption(label: '0.5×', value: 0.25, multiplier: 0.5),
    _SpeedOption(label: '0.75×', value: 0.375, multiplier: 0.75),
    _SpeedOption(label: '1×', value: 0.5, multiplier: 1.0),
    _SpeedOption(label: '1.25×', value: 0.625, multiplier: 1.25),
    _SpeedOption(label: '1.5×', value: 0.75, multiplier: 1.5),
    _SpeedOption(label: '2×', value: 1.0, multiplier: 2.0),
  ];

  static const List<_PitchOption> _pitchOptions = [
    _PitchOption(label: 'Низкий', value: 0.75),
    _PitchOption(label: 'Обычный', value: 1.0),
    _PitchOption(label: 'Высокий', value: 1.25),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speechRate = ref.watch(speechRateProvider);
    final pitch = ref.watch(pitchProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              '🎤 Настройки голоса',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Скорость воспроизведения',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          _buildSpeedSelector(context, ref, speechRate),
          const SizedBox(height: 24),
          const Text(
            'Высота голоса',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          _buildPitchSelector(context, ref, pitch),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSpeedSelector(
      BuildContext context, WidgetRef ref, double currentRate) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: _speedOptions.map((option) {
          final isSelected = (currentRate - option.value).abs() < 0.05;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                ref.read(speechRateProvider.notifier).setRate(option.value);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? Colors.blue.shade700 : Colors.black54,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPitchSelector(
      BuildContext context, WidgetRef ref, double currentPitch) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: _pitchOptions.map((option) {
          final isSelected = (currentPitch - option.value).abs() < 0.05;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                ref.read(pitchProvider.notifier).setPitch(option.value);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? Colors.blue.shade700 : Colors.black54,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SpeedOption {
  final String label;
  final double value;
  final double multiplier;

  const _SpeedOption({
    required this.label,
    required this.value,
    required this.multiplier,
  });
}

class _PitchOption {
  final String label;
  final double value;

  const _PitchOption({
    required this.label,
    required this.value,
  });
}
