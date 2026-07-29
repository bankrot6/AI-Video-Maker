import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shimmer/shimmer.dart';
import 'models/attraction_info.dart';
import 'models/attraction_place.dart';
import 'services/background_attraction_loading_service.dart';
import 'widgets/image_carousel.dart';
import '../../services/text_to_speech/base_tts_service.dart';
import '../../services/text_to_speech/tts_providers.dart';
import '../../services/text_to_speech/streaming_tts_orchestrator.dart';
import '../../services/providers.dart' as services;
import '../../services/image_search/google_image_search_service.dart';
import '../../utils/text_cleaner.dart';

final attractionAnalysisStateProvider =
    StateProvider<AsyncValue<AttractionInfo>>(
        (ref) => const AsyncValue.loading());

final attractionImagesProvider = StateProvider<List<File>>((ref) => []);

final attractionLoadedFromCacheProvider = StateProvider<bool>((ref) => false);

class AttractionDetailsScreen extends ConsumerStatefulWidget {
  final AttractionPlace place;

  const AttractionDetailsScreen({
    super.key,
    required this.place,
  });

  @override
  ConsumerState<AttractionDetailsScreen> createState() =>
      _AttractionDetailsScreenState();
}

class _AttractionDetailsScreenState
    extends ConsumerState<AttractionDetailsScreen> {
  bool _isAnalysisInProgress = false;
  bool _imagesLoading = false;
  List<File> _imageFiles = [];

  String? _currentPlayingSection;
  bool _isDisposed = false;
  bool _isAutoPlayMode = true;
  bool _autoPlayStarted = false;

  StreamSubscription<AttractionInfo>? _analysisSubscription;
  Timer? _playbackMonitorTimer;

  final Set<String> _enqueuedSections = {};

  StreamingTtsOrchestrator? _autoTts;
  final Set<String> _autoAnnouncedSections = {};
  int _autoSectionIndex = 0;
  AttractionInfo? _lastInfo;
  bool _autoCurrentSectionFinal = false;
  bool _analysisDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _analyzeAttraction();
    });
  }

  void _resetPlaybackState() {
    _autoPlayStarted = false;
    _isAutoPlayMode = true;
    _currentPlayingSection = null;
    _enqueuedSections.clear();
    _autoAnnouncedSections.clear();
    _autoSectionIndex = 0;
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
    _enqueuedSections.clear();
    _autoAnnouncedSections.clear();
    _autoSectionIndex = 0;
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
    debugPrint('🧹 ATTRACTION_DETAILS: Dispose');
    _isDisposed = true;
    _isAutoPlayMode = false;
    _playbackMonitorTimer?.cancel();

    _analysisSubscription?.cancel();
    _analysisSubscription = null;

    try {
      final backgroundLoader = ref.read(backgroundAttractionLoaderProvider);
      backgroundLoader.detachFromUI(widget.place.name);

      final ttsService = ref.read(attractionTTSServiceProvider);
      ttsService.stop();
      ttsService.clearQueue();
      _autoTts?.dispose();
      _autoTts = null;
    } catch (e) {
      debugPrint('⚠️ ATTRACTION_DETAILS: Ошибка в dispose: $e');
    }

    super.dispose();
  }

  Future<void> _analyzeAttraction({bool forceRefresh = false}) async {
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
        '🏛️ ATTRACTION_DETAILS: Начало анализа места: ${widget.place.name}');
    _analysisDone = false;

    final backgroundLoader = ref.read(backgroundAttractionLoaderProvider);
    final cacheService = ref.read(attractionCacheServiceProvider);

    if (!forceRefresh) {
      final cachedImages =
          await cacheService.getCachedImages(widget.place.name);
      if (cachedImages.isNotEmpty && mounted) {
        setState(() {
          _imageFiles = cachedImages;
        });
        ref.read(attractionImagesProvider.notifier).state = cachedImages;
        debugPrint(
            '🖼️ ATTRACTION_DETAILS: ${cachedImages.length} изображений загружено из кэша');
      }
    }

    if (!mounted) return;
    ref.read(attractionAnalysisStateProvider.notifier).state =
        const AsyncValue.loading();

    _analysisSubscription?.cancel();
    _analysisSubscription = backgroundLoader
        .streamAttractionInfo(
      placeName: widget.place.name,
      category: widget.place.category,
      context: context,
      forceRefresh: forceRefresh,
    )
        .listen(
      (attractionInfo) async {
        if (!mounted || _isDisposed) return;
        _lastInfo = attractionInfo;

        ref.read(attractionAnalysisStateProvider.notifier).state =
            AsyncValue.data(attractionInfo);

        if (!_imagesLoading &&
            _imageFiles.isEmpty &&
            attractionInfo.name.isNotEmpty) {
          _imagesLoading = true;
          _searchAttractionImages(attractionInfo.name);
        }

        await _enqueueAvailableSections(attractionInfo, isFinal: false);
      },
      onError: (error, stackTrace) {
        if (!mounted || _isDisposed) return;
        debugPrint('❌ ATTRACTION_DETAILS: Ошибка анализа: $error');
        ref.read(attractionAnalysisStateProvider.notifier).state =
            AsyncValue.error(error, stackTrace);
        if (mounted) {
          setState(() {
            _isAnalysisInProgress = false;
          });
        }
      },
      onDone: () async {
        if (!mounted || _isDisposed) return;
        debugPrint('✅ ATTRACTION_DETAILS: Анализ завершен');
        _analysisDone = true;

        final info = _lastInfo;
        if (info != null) {
          await _enqueueAvailableSections(info, isFinal: true);
        }

        if (mounted) {
          setState(() {
            _isAnalysisInProgress = false;
          });
        }
      },
    );
  }

  List<(String, String, String)> _getSectionsData(AttractionInfo info) {
    return [
      ('practicalInfo', 'Советы для посещения', info.practicalInfo),
      ('history', 'История', info.history),
      ('architecturalDetails', 'Архитектура', info.architecturalDetails),
      ('interestingFacts', 'Секреты и интересные факты', info.interestingFacts),
    ];
  }

  static const int _minSectionLength = 150;

  Future<void> _enqueueAvailableSections(AttractionInfo info,
      {required bool isFinal}) async {
    if (!_isAutoPlayMode || _isDisposed || !mounted) return;

    final ttsService = ref.read(attractionTTSServiceProvider);
    final sections = _getSectionsData(info)
        .map((s) =>
            (s.$1, s.$2, TextCleaner.cleanForSpeechPreserveContent(s.$3)))
        .toList();

    final finals = <bool>[
      isFinal || info.history.isNotEmpty,
      isFinal || info.architecturalDetails.isNotEmpty,
      isFinal || info.interestingFacts.isNotEmpty,
      isFinal,
    ];

    if (!_autoPlayStarted) {
      final first = sections.firstWhere((s) => s.$1 == 'practicalInfo');
      if (first.$3.length < 120 && !isFinal) return;

      _autoPlayStarted = true;
      final placeIntro = 'Сейчас мы расскажем о ${widget.place.name}.';
      await ttsService.addToQueue(placeIntro, languageCode: 'ru-RU');

      _autoTts ??= StreamingTtsOrchestrator(
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

    if (_autoTts == null) return;
    if (_autoSectionIndex >= sections.length) return;

    final currentKey = sections[_autoSectionIndex].$1;
    final currentTitle = sections[_autoSectionIndex].$2;
    final currentContent = sections[_autoSectionIndex].$3;
    final currentIsFinal = finals[_autoSectionIndex];

    if (currentContent.length < _minSectionLength && !currentIsFinal) return;

    await _ensureAutoSectionAnnounced(ttsService, currentKey, currentTitle);
    _autoCurrentSectionFinal = currentIsFinal;
    await _autoTts!.updateFullText(currentContent, isFinal: currentIsFinal);

    await _tryAdvanceAutoSection(ttsService, sections, finals);
  }

  Future<void> _tryAdvanceAutoSection(
    BaseTTSService ttsService,
    List<(String, String, String)> sections,
    List<bool> finals,
  ) async {
    if (_autoTts == null) return;

    while (_autoSectionIndex < sections.length) {
      final currentFinal = finals[_autoSectionIndex];
      if (!currentFinal) return;

      if (_autoTts!.hasBufferedText) return;

      _autoSectionIndex++;
      _autoTts!.reset();

      if (_autoSectionIndex >= sections.length) return;

      final nextKey = sections[_autoSectionIndex].$1;
      final nextTitle = sections[_autoSectionIndex].$2;
      final nextContent = sections[_autoSectionIndex].$3;
      final nextFinal = finals[_autoSectionIndex];

      if (nextContent.length < _minSectionLength && !nextFinal) return;

      await _ensureAutoSectionAnnounced(ttsService, nextKey, nextTitle);
      _autoCurrentSectionFinal = nextFinal;
      await _autoTts!.updateFullText(nextContent, isFinal: nextFinal);
    }
  }

  Future<void> _ensureAutoSectionAnnounced(
    BaseTTSService ttsService,
    String sectionKey,
    String title,
  ) async {
    if (_autoAnnouncedSections.contains(sectionKey)) return;
    _autoAnnouncedSections.add(sectionKey);

    _enqueuedSections.add(sectionKey);
    if (mounted) {
      setState(() {
        _currentPlayingSection = sectionKey;
      });
    }

    await ttsService.addToQueue('$title.', languageCode: 'ru-RU');
  }

  void _startPlaybackMonitor() {
    _playbackMonitorTimer?.cancel();

    _playbackMonitorTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (timer) async {
        if (_isDisposed || !mounted) {
          timer.cancel();
          return;
        }

        final ttsService = ref.read(attractionTTSServiceProvider);
        final isPlaying = ttsService.isPlaying || ttsService.hasQueuedItems;

        if (isPlaying && ttsService.queueSize <= 2) {
          if (_autoCurrentSectionFinal) {
            await _autoTts?.flush();
          } else {
            await _autoTts?.pump();
          }

          final info = _lastInfo;
          if (info != null && _autoTts != null) {
            final sections = _getSectionsData(info)
                .map((s) => (
                      s.$1,
                      s.$2,
                      TextCleaner.cleanForSpeechPreserveContent(s.$3)
                    ))
                .toList();
            final finals = <bool>[
              _analysisDone || info.history.isNotEmpty,
              _analysisDone || info.architecturalDetails.isNotEmpty,
              _analysisDone || info.interestingFacts.isNotEmpty,
              _analysisDone,
            ];
            await _tryAdvanceAutoSection(ttsService, sections, finals);
          }
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

  Future<void> _searchAttractionImages(String attractionName) async {
    try {
      final cacheService = ref.read(attractionCacheServiceProvider);

      final cachedImages =
          await cacheService.getCachedImages(widget.place.name);
      if (cachedImages.isNotEmpty && mounted) {
        debugPrint(
            '🖼️ ATTRACTION_DETAILS: ${cachedImages.length} изображений из кэша');
        setState(() {
          _imageFiles = cachedImages;
          _imagesLoading = false;
        });
        ref.read(attractionImagesProvider.notifier).state = cachedImages;
        return;
      }

      debugPrint(
          '🖼️ ATTRACTION_DETAILS: Стриминг изображений для: $attractionName');

      final imageSearchService = ref.read(services.imageSearchServiceProvider);

      if (imageSearchService is! GoogleImageSearchService) {
        debugPrint('⚠️ ATTRACTION_DETAILS: Сервис не поддерживает стриминг');
        setState(() => _imagesLoading = false);
        return;
      }

      String? cityName;
      String? countryName;
      try {
        final placemarks = await placemarkFromCoordinates(
          widget.place.latitude,
          widget.place.longitude,
        );
        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          cityName = placemark.locality ?? placemark.administrativeArea;
          countryName = placemark.country;
        }
      } catch (_) {}

      final searchSuffixes = [
        '',
        'photo',
        'достопримечательность',
        'landmark',
        'architecture',
        'туризм tourism',
      ];

      debugPrint(
          '🖼️ ATTRACTION_DETAILS: Город: $cityName, Страна: $countryName');

      final List<File> collectedFiles = [];

      await for (final file in imageSearchService.streamImages(
        baseName: attractionName,
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
        ref.read(attractionImagesProvider.notifier).state =
            List.from(collectedFiles);

        debugPrint(
            '🖼️ ATTRACTION_DETAILS: Отображено ${collectedFiles.length} фото');
      }

      if (collectedFiles.isNotEmpty && mounted) {
        await cacheService.cacheAttractionImages(
            widget.place.name, collectedFiles);
        debugPrint(
            '✅ ATTRACTION_DETAILS: Закэшировано ${collectedFiles.length} фото');
      }

      if (mounted) {
        setState(() => _imagesLoading = false);
      }
    } catch (e) {
      debugPrint('❌ ATTRACTION_DETAILS: Ошибка стриминга: $e');
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
    _enqueuedSections.clear();

    await _stopPlayback();

    final cleaned = TextCleaner.cleanForSpeechPreserveContent(content);
    if (cleaned.length < 30) return;

    _enqueuedSections.add(sectionKey);

    if (mounted) {
      setState(() {
        _currentPlayingSection = sectionKey;
      });
    }

    final placeIntro = 'Сейчас мы расскажем о ${widget.place.name}.';
    await ttsService.addToQueue(placeIntro, languageCode: 'ru-RU');
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
    final analysisState = ref.watch(attractionAnalysisStateProvider);

    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          debugPrint(
              '🔙 ATTRACTION_DETAILS: Пользователь покидает экран - остановка озвучки');
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
                        widget.place.name,
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
                  data: (info) => _buildAttractionDetails(info),
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
          _getCategoryIcon(),
          size: 80,
          color: Colors.grey[600],
        ),
      ),
      onBackPressed: () async {
        debugPrint('🔙 ATTRACTION_DETAILS: Нажата кнопка "Назад"');
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

  IconData _getCategoryIcon() {
    switch (widget.place.category.toLowerCase()) {
      case 'museum':
        return Icons.museum;
      case 'park':
        return Icons.park;
      case 'restaurant':
        return Icons.restaurant;
      case 'historical':
        return Icons.castle;
      case 'shopping':
        return Icons.shopping_bag;
      case 'entertainment':
        return Icons.celebration;
      default:
        return Icons.place;
    }
  }

  Widget _buildAttractionDetails(AttractionInfo info) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _maybeShimmer(
            visible: info.practicalInfo.isNotEmpty,
            child: _buildInfoCard(
              sectionKey: 'practicalInfo',
              title: 'Советы для посещения',
              displayTitle: '🎯 Советы для посещения',
              content: info.practicalInfo,
              icon: Icons.info_outline,
              color: Colors.green,
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
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 16),
          _maybeShimmer(
            visible: info.architecturalDetails.isNotEmpty,
            child: _buildInfoCard(
              sectionKey: 'architecturalDetails',
              title: 'Архитектура',
              displayTitle: '🏛️ Архитектура',
              content: info.architecturalDetails,
              icon: Icons.architecture,
              color: Colors.teal,
            ),
          ),
          const SizedBox(height: 16),
          _maybeShimmer(
            visible: info.interestingFacts.isNotEmpty,
            child: _buildInfoCard(
              sectionKey: 'interestingFacts',
              title: 'Секреты и интересные факты',
              displayTitle: '✨ Секреты и интересные факты',
              content: info.interestingFacts,
              icon: Icons.lightbulb_outline,
              color: Colors.orange,
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
        child: SizedBox(
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
        child: SizedBox(
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
                onPressed: () => _analyzeAttraction(forceRefresh: true),
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
