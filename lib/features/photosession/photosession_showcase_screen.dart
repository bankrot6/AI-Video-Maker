import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/deep_link_handler.dart';
import '../../widgets/banner_limit_provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../models/credit_usage_model.dart';
import '../../models/preset_earnings.dart';
import '../../models/generation_task.dart';
import '../../models/photo_session_preset.dart';
import '../../models/preset_tag.dart';
import '../../models/image_generation_request.dart';
import '../../config/credit_config.dart';
import '../../providers/credit_providers.dart';
import '../../services/credit_service.dart';
import '../../services/device_registry_service.dart';
import '../../services/localization/app_localization_service.dart';
import '../../services/post_photosession_review_service.dart';
import '../../services/proxied_image_service.dart';
import '../../services/preset_reward_service.dart';
import '../../widgets/magic_shimmer.dart';
import '../../widgets/preset_like_chip.dart';
import '../../widgets/proxied_network_image.dart';
import '../../widgets/showcase_credits_earnings_menu.dart';
import '../earnings/preset_earnings_screen.dart';
import '../subscription/purchase_routes.dart';
import '../subscription/subscription_providers.dart';
import 'background_generation_provider.dart';
import 'custom_preset_creation_screen.dart';
import 'photosession_generation_screen.dart';
import 'photosession_providers.dart';
import 'preset_likes_provider.dart';
import 'photosession_preset_screen.dart';
import 'photosession_faceswap_screen.dart';
import 'theme/photosession_palette.dart';
import 'theme/photosession_theme_scope.dart';
import 'tutorial/photosession_tutorial.dart';
import 'widgets/photosession_theme_toggle.dart';

const _kSpacing = 6.0;
const _kPadding = 12.0;
const _kChipHeight = 34.0;
const _kCardRadius = 10.0;
const _kPrefetchThumbAheadCount = 20; // Уменьшено для быстрой загрузки
const _kPrefetchFullPreviewCount = 8; // Уменьшено для быстрой загрузки
const _kDeferFullImagePrefetch =
    Duration(milliseconds: 200); // Быстрее для лучшего UX
const _kScrollThumbPrefetchDebounce = Duration(milliseconds: 120);
const _kScrollThumbViewportWindow = 22;
const _kScrollThumbAvgSlotPx = 128.0;
const _kPrefsLastAckLiveLikes = 'showcase_last_ack_live_likes_v1';
final _searchCleanupPattern = RegExp(r'[^a-zA-Z0-9а-яА-ЯёЁ]+');
final _searchWhitespacePattern = RegExp(r'\s+');

const _aspectRatios = [0.65, 0.72, 0.82, 0.95, 1.05, 1.2];
typedef _ShowcaseTutorialStep = ({
  GlobalKey key,
  String id,
  String title,
  String description,
  IconData icon,
  ContentAlign align,
});

class PhotosessionShowcaseScreen extends ConsumerStatefulWidget {
  const PhotosessionShowcaseScreen({super.key});

  @override
  ConsumerState<PhotosessionShowcaseScreen> createState() =>
      _PhotosessionShowcaseScreenState();
}

class _PhotosessionShowcaseScreenState
    extends ConsumerState<PhotosessionShowcaseScreen>
    with WidgetsBindingObserver, RouteAware {
  List<PhotoSessionPreset> _presets = [];
  bool _loading = true;
  String? _error;
  final _chipScrollController = ScrollController();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _categoryChipsKey = GlobalKey();
  final _creditChipKey = GlobalKey();
  final _searchActionKey = GlobalKey();
  final _createFabKey = GlobalKey();
  final _firstPresetCardKey = GlobalKey();
  final _firstPresetLikeKey = GlobalKey();

  StreamSubscription<List<PhotoSessionPreset>>? _streamSub;
  bool _isShowcaseTutorialVisible = false;
  bool _didTryAutoShowcaseTutorial = false;
  bool _showcaseAutoTutorialChain = false;
  bool _isSearchMode = false;
  bool _isCreditsMenuExpanded = false;
  String _searchQuery = '';
  Map<String, int>? _earningsStats;
  bool _earningsStatsLoading = true;
  bool _likesIntroWide = true;
  int _likesNewSinceLastAck = 0;
  Timer? _likesIntroTimer;
  Timer? _deferFullPreviewPrefetchTimer;
  Timer? _scrollThumbPrefetchDebounceTimer;
  bool _likesIntroEndScheduled = false;
  bool _postSessionReviewBannerVisible = false;
  bool _isPostSessionReviewSubmitting = false;
  bool _scheduledPostSessionReviewConsume = false;
  bool _didPresentPaywallAfterShowcaseTutorial = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _syncRewardsInBackground();
    _loadEarningsStats();
    // На серверо-авторитетных сборках (RuStore) подтягиваем актуальный серверный
    // баланс при входе на главный экран, как и на экране пресета. Иначе главная
    // показывает устаревший локальный остаток, а пресет — серверный, и
    // пользователь видит расхождение (215 vs 180). Для YooKassa/IAP оставляем
    // прежнее поведение, чтобы не затронуть их локальный учёт.
    if (CreditUsageModel.isServerAuthoritativeBalance) {
      Future.microtask(
        () =>
            ref.read(creditUsageNotifierProvider.notifier).refreshFromServer(),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      appRouteObserver.subscribe(this, route);
    }
    if (_scheduledPostSessionReviewConsume) return;
    _scheduledPostSessionReviewConsume = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumePostPhotosessionReviewTriggerIfNeeded();
    });
  }

  @override
  void didPopNext() {
    ref.read(homeScreenResumeCountProvider.notifier).state++;
  }

  void _consumePostPhotosessionReviewTriggerIfNeeded() {
    if (!mounted) return;
    final t = ref.read(postPhotosessionReviewHomeTriggerProvider);
    if (!t) return;
    ref.read(postPhotosessionReviewHomeTriggerProvider.notifier).state = false;
    unawaited(_tryShowPostSessionReviewBanner());
  }

  Future<void> _loadEarningsStats() async {
    if (!mounted) return;
    if (_earningsStats == null) {
      setState(() => _earningsStatsLoading = true);
    }
    try {
      final reward = PresetRewardService();
      final stats = await reward.getEarningsStats();
      final liveTotal = await reward.sumLiveLikesOnOwnerPublicPresets();
      final prefs = ref.read(sharedPreferencesProvider);
      final lastAck = prefs.containsKey(_kPrefsLastAckLiveLikes)
          ? prefs.getInt(_kPrefsLastAckLiveLikes)!
          : -1;
      final newLikes =
          lastAck < 0 ? 0 : (liveTotal - lastAck).clamp(0, 1 << 30);

      if (mounted) {
        setState(() {
          _earningsStats = {
            ...stats,
            'totalLikes': liveTotal,
          };
          _earningsStatsLoading = false;
          _likesNewSinceLastAck = newLikes;
        });
      }

      if (mounted && !_likesIntroEndScheduled) {
        _likesIntroEndScheduled = true;
        _likesIntroTimer?.cancel();
        _likesIntroTimer = Timer(const Duration(seconds: 5), () async {
          if (!mounted) return;
          final latest = await reward.sumLiveLikesOnOwnerPublicPresets();
          await prefs.setInt(_kPrefsLastAckLiveLikes, latest);
          if (mounted) {
            setState(() {
              _likesIntroWide = false;
              _likesNewSinceLastAck = 0;
            });
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _earningsStats = const {
            'totalCreditsEarned': 0,
            'totalLikes': 0,
          };
          _earningsStatsLoading = false;
          _likesIntroWide = false;
        });
      }
    }
  }

  void _openCreditsMenu() {
    if (_isCreditsMenuExpanded) return;
    HapticFeedback.selectionClick();
    setState(() {
      _isCreditsMenuExpanded = true;
      if (_isSearchMode) {
        _isSearchMode = false;
        _searchFocusNode.unfocus();
      }
    });
    _loadEarningsStats();
  }

  void _closeCreditsMenu() {
    if (!_isCreditsMenuExpanded) return;
    setState(() => _isCreditsMenuExpanded = false);
  }

  void _openCreditsPurchase(CreditUsageModel? usage) {
    if (usage == null) return;
    Navigator.of(context).push(tokenPurchaseRoute());
  }

  void _showCreditsEarningsHelpTutorial() {
    if (_isShowcaseTutorialVisible) return;

    Future<void> showCoach() async {
      if (!context.mounted) return;
      if (_creditChipKey.currentContext == null) return;
      final creditHelpTargets = [
        buildPhotosessionTutorialTarget(
          context: context,
          key: _creditChipKey,
          id: 'credits_earnings_help',
          title: 'Лайки, кредиты и бесплатный режим',
          description:
              'Публичные пресеты собирают лайки. Кредиты за лайки: 1 лайк = 1 кредит, '
              'начисление с ${PresetEarnings.minLikesForReward} лайков на пресет, '
              'не больше ${PresetEarnings.maxCreditsPerPreset} кредитов с одного пресета. '
              'В бесплатном режиме доступен общий пул ${CreditUsageModel.freeCreditsPool} кредитов; '
              'подписка или покупка пакета расширяют возможности.',
          step: 1,
          total: 1,
          icon: Icons.savings_rounded,
          align: ContentAlign.bottom,
        ),
      ];
      await preparePhotosessionCoachMarkShow(context);
      if (!mounted) return;
      _isShowcaseTutorialVisible = true;
      TutorialCoachMark(
        targets: creditHelpTargets,
        colorShadow: PhotosessionPalette.of(context).depth,
        opacityShadow: 0.78,
        hideSkip: true,
        paddingFocus: 10,
        pulseEnable: false,
        beforeFocus:
            photosessionTutorialBeforeFocus(creditHelpTargets, hasImages: true),
        onFinish: () {
          _isShowcaseTutorialVisible = false;
        },
        onSkip: () {
          _isShowcaseTutorialVisible = false;
          return true;
        },
      ).showForPhotosession(context);
    }

    if (!_isCreditsMenuExpanded) {
      setState(() => _isCreditsMenuExpanded = true);
      _loadEarningsStats();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => unawaited(showCoach()));
      });
    } else {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => unawaited(showCoach()));
    }
  }

  Future<void> _syncRewardsInBackground() async {
    try {
      final newCredits = await PresetRewardService().syncEarnedCredits();
      if (newCredits > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Вы получили $newCredits кредитов за лайки!'),
            backgroundColor: PhotosessionPalette.of(context).success,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
        ref.invalidate(creditUsageNotifierProvider);
        _loadEarningsStats();
      }
    } catch (e) {
      debugPrint('🔴 Ошибка синхронизации вознаграждений: $e');
    }
  }

  Future<void> _loadData() async {
    await _bootstrapPresetsIntoState();
    if (!mounted) return;
    _startStream();
  }

  Future<void> _bootstrapPresetsIntoState() async {
    final cacheService = ref.read(presetCacheServiceProvider);

    // ── STAGE 0: мгновенный рендер из кэша (свежего или устаревшего) ─────────
    final cached = await cacheService.getPresets();
    if (cached != null && cached.isNotEmpty) {
      if (!mounted) return;
      final stale = await cacheService.isStale();
      debugPrint(
          'ShowcaseScreen: ⚡ Рендер из кэша (${cached.length} пресетов, устарел=$stale)');
      setState(() {
        _presets = cached;
        _loading = false;
        _error = null;
      });
      ref.read(presetLikesProvider.notifier).syncFromPresets(cached);
      _syncFeedChipSelection();
      _prefetchImagesSequentially(cached.take(8).toList());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleShowcaseTutorialIfNeeded();
      });
      // Всегда обновляем из сети в фоне — тихо, без шимеров
      unawaited(_refreshAllPresetsInBackground());
      return;
    }

    // ── STAGE 1: кэш пуст (новый пользователь) — грузим с шимерами ──────────
    try {
      await _refreshAllPresetsInBackground();
    } catch (e) {
      debugPrint('ShowcaseScreen: ❌ Ошибка загрузки пресетов: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Загружает изображения первых [presets] последовательно (thumbnail → full).
  void _prefetchImagesSequentially(List<PhotoSessionPreset> presets) {
    if (presets.isEmpty) return;
    final svc = ProxiedImageService();
    for (int i = 0; i < presets.length; i++) {
      final preset = presets[i];
      Future.delayed(Duration(milliseconds: i * 50), () {
        if (!mounted) return;
        final thumbUrl = preset.displayImageUrl.trim();
        if (thumbUrl.isNotEmpty) svc.prefetch([thumbUrl]);
        Future.delayed(const Duration(milliseconds: 100), () {
          if (!mounted) return;
          final fullUrl = preset.previewImageUrl.trim();
          if (fullUrl.isNotEmpty && fullUrl != thumbUrl) {
            svc.prefetch([fullUrl]);
          }
        });
      });
    }
  }

  /// Постраничная загрузка: каждая страница (≈100 пресетов) немедленно
  /// добавляется в UI — без искусственных задержек.
  Future<void> _refreshAllPresetsInBackground() async {
    if (!mounted) return;
    final repo = ref.read(showcaseRepositoryProvider);
    final cacheService = ref.read(presetCacheServiceProvider);

    final wasEmpty = _presets.isEmpty;
    var isFirstPage = true;

    try {
      await for (final pagePresets in repo.streamPresetsBootstrap()) {
        if (!mounted) return;

        if (isFirstPage) {
          // Первая страница: рендерим, запускаем туториал и prefetch первых 8
          debugPrint(
              'ShowcaseScreen: 📦 Первая страница: ${pagePresets.length}');
          setState(() {
            _presets = pagePresets;
            _loading = false;
            _error = null;
          });
          ref.read(presetLikesProvider.notifier).syncFromPresets(pagePresets);
          _syncFeedChipSelection();
          _prefetchImagesSequentially(pagePresets.take(8).toList());
          if (wasEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _scheduleShowcaseTutorialIfNeeded();
            });
          }
          isFirstPage = false;
        } else {
          // Каждая следующая страница добавляется сразу
          debugPrint(
              'ShowcaseScreen: 🔄 +${pagePresets.length - _presets.length} пресетов');
          setState(() {
            _presets = pagePresets;
          });
          ref.read(presetLikesProvider.notifier).syncFromPresets(pagePresets);
          _prefetchImages(pagePresets.skip(_presets.length).toList());
        }
      }

      // Сохраняем финальный список в кэш
      if (mounted && _presets.isNotEmpty) {
        unawaited(cacheService.savePresets(_presets));
      }
    } catch (e) {
      debugPrint('ShowcaseScreen: ❌ Загрузка пресетов: $e');
      if (!mounted) return;
      if (_presets.isEmpty) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _likesIntroTimer?.cancel();
    _deferFullPreviewPrefetchTimer?.cancel();
    _scrollThumbPrefetchDebounceTimer?.cancel();
    _streamSub?.cancel();
    _chipScrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Обновляем при возврате приложения на передний план.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _invalidateCache();
      _loadEarningsStats();
    }
  }

  /// Подписка на real-time изменения коллекции.
  /// skip(1) — пропускаем первый emit (initial HTTP load), т.к. данные
  /// уже получены в [_bootstrapPresetsIntoState] / [_refreshAllPresetsInBackground].
  void _startStream() {
    _streamSub?.cancel();
    final repo = ref.read(showcaseRepositoryProvider);
    _streamSub = repo.watchPresets().skip(1).listen(
      (presets) {
        if (!mounted) return;
        if (presets.isEmpty && _presets.isNotEmpty) return;
        setState(() {
          _presets = presets;
          _loading = false;
          _error = null;
        });
        ref.read(presetLikesProvider.notifier).syncFromPresets(presets);
        _syncFeedChipSelection();
        _prefetchImages(presets);
        ref.read(presetCacheServiceProvider).savePresets(presets);
      },
      onError: (Object e) {
        if (!mounted) return;
        if (_presets.isEmpty) {
          setState(() {
            _error = e.toString();
            _loading = false;
          });
        }
      },
    );
  }

  /// Сбрасывает кэш и подгружает свежие данные в фоне (pull-to-refresh / foreground).
  Future<void> _invalidateCache() async {
    await ref.read(presetCacheServiceProvider).clear();
    if (mounted) unawaited(_refreshAllPresetsInBackground());
  }

  void _prefetchImages(List<PhotoSessionPreset> presets) {
    _deferFullPreviewPrefetchTimer?.cancel();

    final svc = ProxiedImageService();
    final thumbUrls = <String>[];
    final thumbSeen = <String>{};
    for (final p in presets.take(_kPrefetchThumbAheadCount)) {
      final u = p.displayImageUrl.trim();
      if (u.isNotEmpty && thumbSeen.add(u)) thumbUrls.add(u);
    }
    svc.prefetch(thumbUrls);

    _deferFullPreviewPrefetchTimer = Timer(_kDeferFullImagePrefetch, () {
      if (!mounted) return;
      final fullUrls = <String>[];
      final seen = Set<String>.from(thumbSeen);
      for (final p in presets.take(_kPrefetchFullPreviewCount)) {
        final u = p.previewImageUrl.trim();
        if (u.isEmpty || seen.contains(u)) continue;
        seen.add(u);
        fullUrls.add(u);
      }
      svc.prefetch(fullUrls);
    });
  }

  void _debouncedPrefetchThumbsForScroll(
    double pixels,
    List<PhotoSessionPreset> presets,
  ) {
    if (presets.isEmpty) return;
    _scrollThumbPrefetchDebounceTimer?.cancel();
    _scrollThumbPrefetchDebounceTimer =
        Timer(_kScrollThumbPrefetchDebounce, () {
      if (!mounted) return;
      final estFirst = ((pixels / _kScrollThumbAvgSlotPx) * 2).floor().clamp(
            0,
            presets.length - 1,
          );
      final start = (estFirst - 6).clamp(0, presets.length - 1);
      final end =
          (start + _kScrollThumbViewportWindow).clamp(0, presets.length);
      if (start >= end) return;
      final slice = presets.sublist(start, end);
      final urls = <String>[];
      final seen = <String>{};
      for (final p in slice) {
        final u = p.displayImageUrl.trim();
        if (u.isNotEmpty && seen.add(u)) urls.add(u);
      }
      ProxiedImageService().prefetch(urls);
    });
  }

  void _prefetchPresetPreviewForOpen(PhotoSessionPreset preset) {
    final u = preset.previewImageUrl.trim();
    if (u.isEmpty) return;
    ProxiedImageService().prefetch([u]);
  }

  void _syncFeedChipSelection() {
    _syncLikedTagVisibility();
    _syncMyTagVisibility();
  }

  void _syncLikedTagVisibility() {
    final selected = ref.read(selectedPresetTagIdProvider);
    if (selected != PresetTag.idLiked) return;
    final deviceId = ref.read(deviceIdProvider).value;
    final likes = ref.read(presetLikesProvider.notifier);
    final mergedPresets = likes.mergePresets(_presets);
    if (deviceId == null ||
        !mergedPresets.any((p) => likes.isLikedBy(p, deviceId))) {
      ref.read(selectedPresetTagIdProvider.notifier).state = PresetTag.idAll;
    }
  }

  void _syncMyTagVisibility() {
    final selected = ref.read(selectedPresetTagIdProvider);
    if (selected != PresetTag.idCustom) return;
    final deviceId = ref.read(deviceIdProvider).value;
    final usedIds = ref.read(usedPresetIdsProvider).valueOrNull ?? <String>{};
    if (!PresetTag.userHasMyFeedPresets(
      presets: _presets,
      deviceId: deviceId,
      usedPresetIds: usedIds,
    )) {
      ref.read(selectedPresetTagIdProvider.notifier).state = PresetTag.idAll;
    }
  }

  Future<void> _loadPresets({bool forceRefresh = false}) async {
    if (forceRefresh) {
      setState(() => _loading = true);
      await ref.read(presetCacheServiceProvider).clear();
      await _bootstrapPresetsIntoState();
      if (mounted) _startStream();
    }
  }

  void _enterSearchMode() {
    if (_isSearchMode) {
      _searchFocusNode.requestFocus();
      return;
    }

    HapticFeedback.selectionClick();
    setState(() {
      _isSearchMode = true;
      _isCreditsMenuExpanded = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
    });
  }

  void _closeSearchMode() {
    _searchFocusNode.unfocus();
    if (_searchQuery.isNotEmpty || _searchController.text.isNotEmpty) {
      _searchController.clear();
    }
    if (!_isSearchMode && _searchQuery.isEmpty) return;
    setState(() {
      _isSearchMode = false;
      _searchQuery = '';
    });
  }

  void _clearSearchQuery() {
    if (_searchQuery.isEmpty) {
      _closeSearchMode();
      return;
    }
    _searchController.clear();
    setState(() => _searchQuery = '');
    _searchFocusNode.requestFocus();
  }

  String _normalizeSearchQuery(String value) {
    return value
        .toLowerCase()
        .replaceAll(_searchCleanupPattern, ' ')
        .replaceAll(_searchWhitespacePattern, ' ')
        .trim();
  }

  String _buildPresetSearchText(PhotoSessionPreset preset) {
    final style = ImageStyleX.fromId(preset.imageStyle);
    final styleNames = <String>[style.id, style.label];

    return _normalizeSearchQuery([
      preset.title ?? '',
      preset.prompt,
      preset.id,
      ...styleNames,
    ].join(' '));
  }

  List<String> _tokenizeSearchText(String value) {
    return _normalizeSearchQuery(value)
        .split(' ')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }

  bool _matchesSearch(PhotoSessionPreset preset) {
    final query = _normalizeSearchQuery(_searchQuery);
    if (query.isEmpty) return true;
    final searchText = _buildPresetSearchText(preset);
    final searchTokens = _tokenizeSearchText(searchText);
    final terms = query.split(' ');

    return terms.every((term) {
      if (term.isEmpty) return true;
      return searchTokens.any((token) => token.startsWith(term));
    });
  }

  void _sortPresetsByDate(List<PhotoSessionPreset> presets) {
    presets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<PhotoSessionPreset> get _filteredPresets {
    ref.watch(presetLikesProvider);
    final likes = ref.read(presetLikesProvider.notifier);
    final presets = likes.mergePresets(_presets);
    final selectedId = ref.read(selectedPresetTagIdProvider);
    final deviceId = ref.read(deviceIdProvider).value;
    final usedIds = ref.read(usedPresetIdsProvider).valueOrNull ?? <String>{};

    if (selectedId == PresetTag.idLiked) {
      if (deviceId == null) return [];
      final liked = presets
          .where((p) => likes.isLikedBy(p, deviceId))
          .where((p) {
            if (!p.hasTag('custom')) return true;
            return p.ownerId == null || p.ownerId == deviceId || p.isPublic;
          })
          .where(_matchesSearch)
          .toList();
      _sortPresetsByDate(liked);
      return liked;
    }

    // "Мои": собственные созданные пресеты + каталожные с историей генераций
    if (selectedId == PresetTag.idCustom) {
      final mine = presets
          .where((p) {
            // 1. Пользовательский пресет этого устройства
            if (p.hasTag('custom')) {
              if (deviceId == null) return false;
              return p.ownerId == null || p.ownerId == deviceId;
            }
            // 2. Каталожный пресет, с которым пользователь уже генерировал
            return deviceId != null && usedIds.contains(p.id);
          })
          .where(_matchesSearch)
          .toList();
      _sortPresetsByDate(mine);
      return mine;
    }

    List<PhotoSessionPreset> byTag;
    if (selectedId == null ||
        selectedId.isEmpty ||
        selectedId == PresetTag.idAll ||
        selectedId == PresetTag.idTrending) {
      byTag = presets;
    } else if (PresetTag.isStyleId(selectedId)) {
      byTag = presets
          .where(
            (p) => ImageStyleX.fromId(p.imageStyle).id == selectedId,
          )
          .toList();
    } else {
      byTag = presets.where((p) => p.hasTag(selectedId)).toList();
    }

    // В остальных фильтрах скрываем чужие приватные пользовательские пресеты
    final filtered = byTag.where((p) {
      if (!p.hasTag('custom')) return true;
      if (deviceId == null) return false;
      return p.ownerId == null || p.ownerId == deviceId || p.isPublic;
    }).toList();

    if (selectedId == PresetTag.idTrending) {
      filtered.sort((a, b) {
        final likesCompare = b.likesCount.compareTo(a.likesCount);
        if (likesCompare != 0) return likesCompare;
        return b.createdAt.compareTo(a.createdAt);
      });
    } else {
      _sortPresetsByDate(filtered);
    }

    return filtered.where(_matchesSearch).toList();
  }

  bool _isTagSelected(String tagId, String? selectedId) {
    if (selectedId == null || selectedId.isEmpty) {
      return tagId == PresetTag.idAll;
    }
    return selectedId == tagId;
  }

  Future<void> _openCreateScreen() async {
    final canOpenTextGeneration = await _ensureTextGenerationCredits();
    if (!canOpenTextGeneration || !mounted) return;

    final customResult = await Navigator.of(context).push<bool>(
      photosessionRoute<bool>(const CustomPresetCreationScreen()),
    );
    if (!mounted) return;

    await ref.read(presetCacheServiceProvider).clear();
    if (customResult == true) {
      ref.read(selectedPresetTagIdProvider.notifier).state = PresetTag.idAll;
    }
  }

  Future<bool> _ensureTextGenerationCredits() async {
    final usage = await ref.read(creditUsageNotifierProvider.future);
    if (usage.remainingCredits >= CreditCost.economyGeneration) {
      return true;
    }
    if (!mounted) return false;
    await Navigator.of(context).push<void>(paywallRoute<void>());
    return false;
  }

  void _openGenerationTask(String taskId) {
    Navigator.of(context).push(
      photosessionRoute(PhotosessionGenerationScreen(taskId: taskId)),
    );
  }

  Future<void> _presentPaywallAfterShowcaseTutorialIfNeeded() async {
    if (!mounted || _didPresentPaywallAfterShowcaseTutorial) return;
    final paid =
        await ref.read(subscriptionServiceProvider).hasPaidSubscription();
    if (!mounted || paid) return;
    if (!context.mounted) return;
    _didPresentPaywallAfterShowcaseTutorial = true;
    await Navigator.of(context).push<void>(paywallRoute<void>());
  }

  void _scheduleShowcaseTutorialIfNeeded({bool force = false}) {
    if (!mounted || _isShowcaseTutorialVisible) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isShowcaseTutorialVisible) return;
      _doScheduleShowcaseTutorial(force: force);
    });
  }

  void _doScheduleShowcaseTutorial({bool force = false}) {
    if (force) {
      unawaited(() async {
        await preparePhotosessionCoachMarkShow(context);
        if (!mounted) return;
        final store = ref.read(photosessionTutorialStoreProvider);
        final targets = _buildShowcaseAutoTutorialTargets();
        if (targets.isEmpty) return;
        _isShowcaseTutorialVisible = true;
        photosessionShowcaseCoachMarkVisible = true;
        TutorialCoachMark(
          targets: targets,
          colorShadow: PhotosessionPalette.of(context).depth,
          opacityShadow: 0.78,
          hideSkip: true,
          paddingFocus: 10,
          pulseEnable: false,
          beforeFocus:
              photosessionTutorialBeforeFocus(targets, hasImages: true),
          onFinish: () async {
            photosessionShowcaseCoachMarkVisible = false;
            _isShowcaseTutorialVisible = false;
            await store.markSeen(PhotosessionTutorialScenario.showcase);
            await store.markSeen(PhotosessionTutorialScenario.showcaseFeed);
            await _presentPaywallAfterShowcaseTutorialIfNeeded();
          },
          onSkip: () {
            photosessionShowcaseCoachMarkVisible = false;
            _isShowcaseTutorialVisible = false;
            unawaited(() async {
              await store.markSeen(PhotosessionTutorialScenario.showcase);
              await store.markSeen(PhotosessionTutorialScenario.showcaseFeed);
              await _presentPaywallAfterShowcaseTutorialIfNeeded();
            }());
            return true;
          },
        ).showForPhotosession(context);
      }());
      return;
    }

    runPhotosessionAutoTutorialChain(
      context: context,
      ref: ref,
      force: false,
      scenario: PhotosessionTutorialScenario.showcase,
      schedulingGateOk: () => mounted && !_isShowcaseTutorialVisible,
      buildTargets: _buildShowcaseAutoTutorialTargets,
      getDidTryAuto: () => _didTryAutoShowcaseTutorial,
      setDidTryAuto: (v) => _didTryAutoShowcaseTutorial = v,
      getChainActive: () => _showcaseAutoTutorialChain,
      setChainActive: (v) => _showcaseAutoTutorialChain = v,
      onShow: (targets) {
        final store = ref.read(photosessionTutorialStoreProvider);
        _isShowcaseTutorialVisible = true;
        photosessionShowcaseCoachMarkVisible = true;
        TutorialCoachMark(
          targets: targets,
          colorShadow: PhotosessionPalette.of(context).depth,
          opacityShadow: 0.78,
          hideSkip: true,
          paddingFocus: 10,
          pulseEnable: false,
          beforeFocus:
              photosessionTutorialBeforeFocus(targets, hasImages: true),
          onFinish: () async {
            photosessionShowcaseCoachMarkVisible = false;
            _isShowcaseTutorialVisible = false;
            await store.markSeen(PhotosessionTutorialScenario.showcase);
            await store.markSeen(PhotosessionTutorialScenario.showcaseFeed);
            await _presentPaywallAfterShowcaseTutorialIfNeeded();
          },
          onSkip: () {
            photosessionShowcaseCoachMarkVisible = false;
            _isShowcaseTutorialVisible = false;
            unawaited(() async {
              await store.markSeen(PhotosessionTutorialScenario.showcase);
              await store.markSeen(PhotosessionTutorialScenario.showcaseFeed);
              await _presentPaywallAfterShowcaseTutorialIfNeeded();
            }());
            return true;
          },
        ).showForPhotosession(context);
      },
    );
  }

  List<TargetFocus> _buildShowcaseAutoTutorialTargets() {
    final basics = _buildShowcaseBasicsTutorialSteps();
    final feed = _buildShowcaseFeedTutorialSteps();
    final allSteps = [...basics, ...feed];
    if (allSteps.isEmpty) return const <TargetFocus>[];

    // Проверяем, что первый пресет загружен
    if (_presets.isEmpty) {
      debugPrint('ShowcaseScreen: не загружены пресеты для обучения');
      return const <TargetFocus>[];
    }

    final readySteps = <_ShowcaseTutorialStep>[];
    for (final step in allSteps) {
      if (step.key.currentContext != null) {
        readySteps.add(step);
      }
    }

    // Показываем базовые шаги + первый пресет (минимум 4 шага)
    if (readySteps.length >= 4) {
      return _buildTutorialTargets(readySteps);
    }

    debugPrint(
        'ShowcaseScreen: готово ${readySteps.length}/4+ шагов обучения, ждем');
    return const <TargetFocus>[];
  }

  List<_ShowcaseTutorialStep> _buildShowcaseBasicsTutorialSteps() {
    final steps = <_ShowcaseTutorialStep>[];

    if (_categoryChipsKey.currentContext != null) {
      steps.add((
        key: _categoryChipsKey,
        id: 'showcase_filters',
        title: 'Что такое пресеты',
        description:
            'Пресеты - это готовые идеи фотосессий с уже продуманными сценами, стилем и настроением. Теги помогают быстро сузить подборку: "Все", "В тренде", "Лайки" или "Мои".',
        icon: Icons.grid_view_rounded,
        align: ContentAlign.bottom,
      ));
    }

    if (_searchActionKey.currentContext != null) {
      steps.add((
        key: _searchActionKey,
        id: 'showcase_search',
        title: 'Быстрый поиск по пресетам',
        description:
            'Нажмите на поиск или зажмите строку тегов, чтобы раскрыть полноширинный поиск. Он ищет по названию, описанию сцены и тегам, а вернуться обратно к тегам можно одной кнопкой.',
        icon: Icons.search_rounded,
        align: ContentAlign.bottom,
      ));
    }

    if (_createFabKey.currentContext != null) {
      steps.add((
        key: _createFabKey,
        id: 'showcase_create',
        title: 'Создайте свою идею',
        description:
            'Нажмите "+", если хотите не брать готовую идею, а собрать фотосессию под себя: по текстовому описанию или по референсу.',
        icon: Icons.auto_awesome_rounded,
        align: ContentAlign.top,
      ));
    }

    return steps;
  }

  List<_ShowcaseTutorialStep> _buildShowcaseFeedTutorialSteps() {
    return [
      (
        key: _firstPresetCardKey,
        id: 'showcase_preset',
        title: 'Готовые пресеты',
        description:
            'Здесь уже есть готовые идеи фотосессий. Откройте любую карточку, чтобы посмотреть пример, добавить своё фото, выбрать модель и при желании поправить описание сцены.',
        icon: Icons.style_rounded,
        align: ContentAlign.bottom,
      ),
      (
        key: _firstPresetLikeKey,
        id: 'showcase_likes',
        title: 'Лайки на пресетах',
        description:
            'Так пользователи отмечают понравившиеся идеи. Если вы создадите свой удачный публичный пресет, он тоже сможет собирать лайки и приносить вам кредиты.',
        icon: Icons.favorite_rounded,
        align: ContentAlign.bottom,
      ),
    ];
  }

  List<TargetFocus> _buildTutorialTargets(List<_ShowcaseTutorialStep> steps) {
    return [
      for (var i = 0; i < steps.length; i++)
        buildPhotosessionTutorialTarget(
          context: context,
          key: steps[i].key,
          id: steps[i].id,
          title: steps[i].title,
          description: steps[i].description,
          step: i + 1,
          total: steps.length,
          icon: steps[i].icon,
          align: steps[i].align,
        ),
    ];
  }

  Future<void> _tryShowPostSessionReviewBanner() async {
    if (!mounted) return;
    final prefs = ref.read(sharedPreferencesProvider);
    final show = await PostPhotosessionReviewService.shouldShowBanner(prefs);
    if (!show || !mounted) return;
    await PostPhotosessionReviewService.consumeBannerOpportunity(prefs);
    if (!mounted) return;
    setState(() => _postSessionReviewBannerVisible = true);
  }

  Future<void> _dismissPostSessionReviewBanner() async {
    if (_isPostSessionReviewSubmitting) return;
    final prefs = ref.read(sharedPreferencesProvider);
    await PostPhotosessionReviewService.onUserDismissedBanner(prefs);
    if (mounted) setState(() => _postSessionReviewBannerVisible = false);
  }

  Future<void> _onPostSessionReviewRatePressed() async {
    if (_isPostSessionReviewSubmitting) return;
    final prefs = ref.read(sharedPreferencesProvider);
    setState(() => _isPostSessionReviewSubmitting = true);
    final reviewResult = await PostPhotosessionReviewService.requestStoreReview(
      prefs,
    );
    if (!mounted) return;

    var snackbarText = _reviewOutcomeMessage(reviewResult.outcome);
    const bool isRuStoreBuild = bool.fromEnvironment('RUSTORE');
    if (isRuStoreBuild && reviewResult.shouldAttemptReward) {
      final claim = await DeviceRegistryService().claimReviewBonus(
        store: 'rustore',
        appVersion: reviewResult.appVersion,
        reviewOutcome: reviewResult.outcome.name,
      );
      if (claim.awardedCredits > 0) {
        await CreditService().addEarnedCredits(claim.awardedCredits);
        await PostPhotosessionReviewService.markReviewRewardGranted(prefs);
        snackbarText = 'За отзыв начислено ${claim.awardedCredits} кредитов';
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(snackbarText)),
    );
    setState(() {
      _postSessionReviewBannerVisible = false;
      _isPostSessionReviewSubmitting = false;
    });
  }

  String _reviewOutcomeMessage(StoreReviewOutcome outcome) {
    switch (outcome) {
      case StoreReviewOutcome.completed:
        return 'Спасибо за обратную связь!';
      case StoreReviewOutcome.alreadyReviewed:
        return 'Спасибо! Оценка уже была оставлена ранее.';
      case StoreReviewOutcome.throttled:
        return 'Слишком рано для повторного запроса оценки. Попробуйте позже.';
      case StoreReviewOutcome.unavailable:
        return 'Не удалось открыть окно оценки в магазине.';
      case StoreReviewOutcome.failed:
        return 'Не получилось отправить запрос на оценку.';
    }
  }

  Widget _buildPostSessionReviewDialog(ColorScheme colors, ThemeData theme) {
    final onRatePressed =
        _isPostSessionReviewSubmitting ? null : _onPostSessionReviewRatePressed;
    final onLaterPressed =
        _isPostSessionReviewSubmitting ? null : _dismissPostSessionReviewBanner;
    return Positioned.fill(
      child: ColoredBox(
        color: PhotosessionPalette.of(context).depth.withValues(alpha: 0.62),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                color: colors.surface,
                elevation: 10,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.rate_review_rounded,
                            color: colors.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Поддержите приложение',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Дарим 10 кредитов за отзыв в RuStore. Это займет меньше минуты.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurface.withOpacity(0.86),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(
                            Icons.workspace_premium_rounded,
                            size: 18,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Нажмите "Оценить" и получите бонус прямо сейчас.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: onRatePressed,
                              child: _isPostSessionReviewSubmitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Оценить'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: onLaterPressed,
                              child: const Text('Не сейчас'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(selectedPresetTagIdProvider);
    ref.listen(deviceIdProvider, (previous, next) {
      if (!mounted || !next.hasValue) return;
      _syncFeedChipSelection();
    });
    ref.listen(usedPresetIdsProvider, (previous, next) {
      if (!mounted || !next.hasValue) return;
      _syncMyTagVisibility();
    });
    ref.watch(deviceIdProvider);
    ref.watch(usedPresetIdsProvider);
    final tasks = ref.watch(backgroundGenerationProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final palette = PhotosessionPalette.of(context);

    final creditAsync = ref.watch(creditUsageNotifierProvider);

    return PhotosessionThemeScope(
      child: WillPopScope(
        onWillPop: () async {
          if (_postSessionReviewBannerVisible) {
            await _dismissPostSessionReviewBanner();
            return false;
          }
          if (_isCreditsMenuExpanded) {
            _closeCreditsMenu();
            return false;
          }
          if (_isSearchMode || _searchQuery.isNotEmpty) {
            _closeSearchMode();
            return false;
          }
          return true;
        },
        child: Scaffold(
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: 8),
                    creditAsync.when(
                      data: (usage) => _SubscriptionBanner(usage: usage),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                    _buildCategoryChips(colors),
                    if (tasks.isNotEmpty) _buildGenerationTasks(tasks, colors),
                    Expanded(child: _buildBody(context)),
                  ],
                ),
                if (_postSessionReviewBannerVisible)
                  _buildPostSessionReviewDialog(colors, theme),
              ],
            ),
          ),
          floatingActionButton: KeyedSubtree(
            key: _createFabKey,
            child: FloatingActionButton(
              onPressed: _openCreateScreen,
              backgroundColor: palette.accent,
              foregroundColor: palette.background,
              elevation: 4,
              tooltip: 'Создать изображение',
              child: const Icon(Icons.add_rounded, size: 28),
            ),
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
        ),
      ),
    );
  }

  Widget _buildGenerationTasks(List<GenerationTask> tasks, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kPadding, 8, _kPadding, 0),
      child: Column(
        children: [
          for (final task in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _GenerationTaskCard(
                task: task,
                onTap: () => _openGenerationTask(task.id),
                onRetry: () => ref
                    .read(backgroundGenerationProvider.notifier)
                    .retryTask(task.id),
                onDismiss: () => ref
                    .read(backgroundGenerationProvider.notifier)
                    .removeTask(task.id),
              ),
            ),
        ],
      ),
    );
  }

  double _measureChipWidth(PresetTag tag) {
    final tp = TextPainter(
      text: TextSpan(
        text: tag.name,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return 14 + 16 + 6 + tp.width + 14;
  }

  void _scrollToChip(int index, List<PresetTag> tags) {
    if (!_chipScrollController.hasClients) return;

    double offset = 0;
    for (int i = 0; i < index; i++) {
      offset += _measureChipWidth(tags[i]) + 8;
    }

    final max = _chipScrollController.position.maxScrollExtent;
    _chipScrollController.animateTo(
      offset.clamp(0.0, max),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Widget _buildCategoryChips(ColorScheme colors) {
    final palette = PhotosessionPalette.of(context);
    final selectedTagId = ref.watch(selectedPresetTagIdProvider);
    final creditAsync = ref.watch(creditUsageNotifierProvider);
    final deviceId = ref.watch(deviceIdProvider).value;
    final usedIds = ref.watch(usedPresetIdsProvider).valueOrNull ?? <String>{};
    ref.watch(presetLikesProvider);
    final likes = ref.read(presetLikesProvider.notifier);
    final chipTags = PresetTag.chipsForFeed(
      presets: likes.mergePresets(_presets),
      deviceId: deviceId,
      usedPresetIds: usedIds,
    );
    final activeTag =
        selectedTagId == null ? null : PresetTag.byId(selectedTagId);
    final isAllSelected =
        selectedTagId == null || selectedTagId == PresetTag.idAll;
    final searchChipIndex = isAllSelected ? 1 : -1;

    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: KeyedSubtree(
        key: _categoryChipsKey,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final isWide = child.key == const ValueKey('search_mode') ||
                child.key == const ValueKey('credits_menu_mode');
            final offsetTween = Tween<Offset>(
              begin: isWide ? const Offset(0.06, 0) : const Offset(-0.06, 0),
              end: Offset.zero,
            );
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: offsetTween.animate(animation),
                child: child,
              ),
            );
          },
          child: _isSearchMode
              ? Padding(
                  key: const ValueKey('search_mode'),
                  padding: const EdgeInsets.symmetric(horizontal: _kPadding),
                  child: _buildSearchField(colors, activeTag),
                )
              : _isCreditsMenuExpanded
                  ? Padding(
                      key: const ValueKey('credits_menu_mode'),
                      padding:
                          const EdgeInsets.symmetric(horizontal: _kPadding),
                      child: ShowcaseCreditsEarningsMenu(
                        expanded: true,
                        creditAsync: creditAsync,
                        earningsStats: _earningsStats,
                        earningsStatsLoading: _earningsStatsLoading,
                        likesPeekVisible: _likesIntroWide,
                        newLikesSinceLastAck: _likesNewSinceLastAck,
                        onExpand: () {},
                        onCollapse: _closeCreditsMenu,
                        onPurchase: () => _openCreditsPurchase(
                          creditAsync.asData?.value,
                        ),
                        onEarningsDetails: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PresetEarningsScreen(),
                            ),
                          );
                        },
                        onHelp: _showCreditsEarningsHelpTutorial,
                        activeColor: palette.accent,
                      ),
                    )
                  : SizedBox(
                      key: const ValueKey('chips_mode'),
                      height: 50,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                              left: _kPadding,
                              right: 8,
                            ),
                            child: const PhotosessionThemeToggle(),
                          ),
                          Expanded(
                            child: Center(
                              child: SizedBox(
                                height: _kChipHeight,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    _kChipHeight / 2,
                                  ),
                                  child: ListView.separated(
                                    controller: _chipScrollController,
                                    scrollDirection: Axis.horizontal,
                                    padding:
                                        const EdgeInsets.only(right: _kPadding),
                                    itemCount: chipTags.length +
                                        (isAllSelected ? 1 : 0),
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 8),
                                    itemBuilder: (context, index) {
                                      if (index == searchChipIndex) {
                                        return KeyedSubtree(
                                          key: _searchActionKey,
                                          child: _buildSearchAction(colors),
                                        );
                                      }

                                      final tagIndex =
                                          index > searchChipIndex &&
                                                  isAllSelected
                                              ? index - 1
                                              : index;
                                      final tag = chipTags[tagIndex];
                                      final isSelected =
                                          _isTagSelected(tag.id, selectedTagId);

                                      return GestureDetector(
                                        onLongPress: isAllSelected
                                            ? _enterSearchMode
                                            : null,
                                        onTap: () {
                                          ref
                                              .read(selectedPresetTagIdProvider
                                                  .notifier)
                                              .state = tag.id ==
                                                  PresetTag.idAll
                                              ? null
                                              : tag.id;
                                          _scrollToChip(tagIndex, chipTags);
                                        },
                                        child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          curve: Curves.easeInOut,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                          ),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? palette.accent
                                                : colors
                                                    .surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(
                                              _kChipHeight / 2,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                tag.icon,
                                                size: 16,
                                                color: isSelected
                                                    ? palette.background
                                                    : colors.onSurface
                                                        .withOpacity(0.55),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                tag.name,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: isSelected
                                                      ? FontWeight.w600
                                                      : FontWeight.w500,
                                                  color: isSelected
                                                      ? palette.background
                                                      : colors.onSurface
                                                          .withOpacity(0.75),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            key: _creditChipKey,
                            padding: const EdgeInsets.only(
                                right: _kPadding, left: 8),
                            child: Center(
                              child: ShowcaseCreditsEarningsMenu(
                                expanded: false,
                                creditAsync: creditAsync,
                                earningsStats: _earningsStats,
                                earningsStatsLoading: _earningsStatsLoading,
                                likesPeekVisible: _likesIntroWide,
                                newLikesSinceLastAck: _likesNewSinceLastAck,
                                onExpand: _openCreditsMenu,
                                onCollapse: _closeCreditsMenu,
                                onPurchase: () => _openCreditsPurchase(
                                  creditAsync.asData?.value,
                                ),
                                onEarningsDetails: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const PresetEarningsScreen(),
                                    ),
                                  );
                                },
                                onHelp: _showCreditsEarningsHelpTutorial,
                                activeColor: palette.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildSearchAction(ColorScheme colors) {
    return Tooltip(
      message: 'Поиск по пресетам',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _enterSearchMode,
          borderRadius: BorderRadius.circular(_kChipHeight / 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(_kChipHeight / 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: colors.onSurface.withOpacity(0.72),
                ),
                const SizedBox(width: 6),
                Text(
                  'Поиск',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface.withOpacity(0.78),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(ColorScheme colors, PresetTag? activeTag) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.primary.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _closeSearchMode,
            splashRadius: 20,
            icon: Icon(
              Icons.arrow_back_rounded,
              color: colors.onSurface.withOpacity(0.72),
            ),
          ),
          Icon(
            Icons.search_rounded,
            size: 18,
            color: colors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: (value) => setState(() => _searchQuery = value),
              textInputAction: TextInputAction.search,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.onSurface,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: activeTag == null
                    ? 'Название, описание или тег'
                    : 'Искать в "${activeTag.name}"',
                hintStyle: TextStyle(
                  color: colors.onSurface.withOpacity(0.45),
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: IconButton(
              key: ValueKey(_searchQuery.isEmpty ? 'close' : 'clear'),
              onPressed: _clearSearchQuery,
              splashRadius: 20,
              icon: Icon(
                _searchQuery.isEmpty
                    ? Icons.close_rounded
                    : Icons.cancel_rounded,
                color: colors.onSurface.withOpacity(0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerSkeleton(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columnWidth = (width - _kPadding * 2 - _kSpacing) / 2;
        return MasonryGridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: _kSpacing,
          crossAxisSpacing: _kSpacing,
          padding: const EdgeInsets.all(_kPadding),
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 6,
          itemBuilder: (context, index) {
            final ratio = _aspectRatios[index % _aspectRatios.length];
            final extent = columnWidth / ratio;
            return SizedBox(
              height: extent,
              child: MagicShimmer(borderRadius: _kCardRadius),
            );
          },
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (_loading) {
      return _buildShimmerSkeleton(context);
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurface.withOpacity(0.8)),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadPresets,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }
    final filtered = _filteredPresets;
    final faceSwapPresets =
        ref.watch(faceSwapPresetsProvider).valueOrNull ?? const [];
    final selectedId = ref.read(selectedPresetTagIdProvider);
    final displayPresets = [...filtered];
    final showFaceSwapPresets = selectedId == PresetTag.idCustom ||
        selectedId == null ||
        selectedId == PresetTag.idAll;
    for (final faceSwapPreset in faceSwapPresets) {
      if (!showFaceSwapPresets || !_matchesSearch(faceSwapPreset)) continue;
      if (displayPresets.any((p) => p.id == faceSwapPreset.id)) continue;
      final insertIdx = displayPresets.indexWhere(
        (p) => p.createdAt.isBefore(faceSwapPreset.createdAt),
      );
      if (insertIdx == -1) {
        displayPresets.add(faceSwapPreset);
      } else {
        displayPresets.insert(insertIdx, faceSwapPreset);
      }
    }

    if (displayPresets.isEmpty) {
      final hasSearch = _normalizeSearchQuery(_searchQuery).isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _presets.isEmpty
                    ? 'Пресетов не загружено.\nПотяните список вниз для обновления.'
                    : hasSearch
                        ? 'По запросу "${_searchQuery.trim()}" ничего не найдено.\nПопробуйте другое слово или закройте поиск.'
                        : 'В этой категории пока нет фотосессий.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurface.withOpacity(0.8)),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: hasSearch
                    ? _closeSearchMode
                    : _loading
                        ? null
                        : _loadPresets,
                icon:
                    Icon(hasSearch ? Icons.search_off_rounded : Icons.refresh),
                label: Text(hasSearch ? 'Вернуться к тегам' : 'Обновить'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadPresets(forceRefresh: true),
      color: colors.onPrimary,
      backgroundColor: colors.surfaceContainerHighest,
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification n) {
          if (n.metrics.axis != Axis.vertical) return false;
          if (n is! ScrollUpdateNotification && n is! ScrollEndNotification) {
            return false;
          }
          _debouncedPrefetchThumbsForScroll(
            n.metrics.pixels,
            displayPresets,
          );
          return false;
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columnWidth = (width - _kPadding * 2 - _kSpacing) / 2;
            return MasonryGridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: _kSpacing,
              crossAxisSpacing: _kSpacing,
              cacheExtent: 900,
              padding: const EdgeInsets.fromLTRB(
                _kPadding,
                _kPadding,
                _kPadding,
                _kPadding + 80,
              ),
              itemCount: displayPresets.length,
              itemBuilder: (context, index) {
                final preset = displayPresets[index];
                final ratio = _aspectRatios[index % _aspectRatios.length];
                final extent = columnWidth / ratio;
                return RepaintBoundary(
                  key: ValueKey(preset.id),
                  child: SizedBox(
                    height: extent,
                    child: _PresetCard(
                      cardKey: index == 0 ? _firstPresetCardKey : null,
                      likeKey: index == 0 ? _firstPresetLikeKey : null,
                      preset: preset,
                      onTap: () {
                        _prefetchPresetPreviewForOpen(preset);
                        if (isFaceSwapPresetId(preset.id)) {
                          Navigator.of(context).push(
                            photosessionRoute<void>(
                              PhotosessionFaceSwapScreen(
                                initialReferenceUrl: preset.previewImageUrl,
                                initialPresetId: preset.id,
                              ),
                            ),
                          );
                        } else {
                          Navigator.of(context).push(
                            photosessionRoute<void>(
                              PhotosessionPresetScreen(preset: preset),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _PresetCard extends ConsumerStatefulWidget {
  const _PresetCard({
    this.cardKey,
    this.likeKey,
    required this.preset,
    required this.onTap,
  });

  final GlobalKey? cardKey;
  final GlobalKey? likeKey;
  final PhotoSessionPreset preset;
  final VoidCallback onTap;

  @override
  ConsumerState<_PresetCard> createState() => _PresetCardState();
}

class _PresetCardState extends ConsumerState<_PresetCard> {
  String? _localThumbnailUrl;

  @override
  void initState() {
    super.initState();
    if (widget.preset.thumbnailUrl == null &&
        !isFaceSwapPresetId(widget.preset.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestThumbnail());
    }
  }

  Future<void> _requestThumbnail() async {
    if (!mounted) return;
    final service = ref.read(presetThumbnailServiceProvider);
    final url = await service.generateForPreset(widget.preset);
    if (mounted && url != null) {
      setState(() => _localThumbnailUrl = url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = PhotosessionPalette.of(context);
    final preset = widget.preset;
    final deviceId = ref.watch(deviceIdProvider).value;
    ref.watch(presetLikesProvider);
    final likes = ref.read(presetLikesProvider.notifier);
    final snapshot = likes.resolve(preset);
    final isLiked = deviceId != null && snapshot.likedBy.contains(deviceId);
    final imageUrl = _localThumbnailUrl ?? preset.displayImageUrl;

    return SizedBox.expand(
      key: widget.cardKey,
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(_kCardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ProxiedNetworkImage(
                url: imageUrl,
                fit: BoxFit.cover,
                cacheWidth: 400,
              ),
              Positioned(
                top: 6,
                right: 6,
                child: SizedBox(
                  key: widget.likeKey,
                  child: PresetLikeChip(
                    count: snapshot.likesCount,
                    isLiked: isLiked,
                    busy: false,
                    style: PresetLikeChipStyle.onImage,
                    onPressed: deviceId == null || likes.isPending(preset.id)
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              await likes.toggle(preset, deviceId);
                            } catch (e) {
                              debugPrint('Ошибка лайка: $e');
                              if (!mounted) return;
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Не удалось обновить лайк: $e'),
                                  backgroundColor: palette.danger,
                                ),
                              );
                            }
                          },
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        palette.backgroundScrim,
                      ],
                    ),
                  ),
                  child: Text(
                    preset.title ?? 'Фотосессия',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenerationTaskCard extends StatelessWidget {
  const _GenerationTaskCard({
    required this.task,
    required this.onTap,
    required this.onRetry,
    required this.onDismiss,
  });

  final GenerationTask task;
  final VoidCallback onTap;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = PhotosessionPalette.of(context);

    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 52,
                  height: 68,
                  child: _buildThumbnail(colors, palette),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      task.presetTitle ?? 'Фотосессия',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildStatusLine(colors, palette),
                  ],
                ),
              ),
              ..._buildActions(colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(ColorScheme colors, PhotosessionPalette palette) {
    if (task.isCompleted && task.resultImageUrl != null) {
      return ProxiedNetworkImage(
        url: task.resultImageUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (_) => Container(color: colors.surfaceContainerHighest),
        errorBuilder: (_) => Container(
          color: colors.surfaceContainerHighest,
          child: const Icon(Icons.broken_image, size: 20),
        ),
      );
    }

    String? thumbnailUrl = task.presetPreviewUrl;
    Widget? thumbnailWidget;

    if (task.taskType == GenerationTaskType.faceSwap &&
        task.referenceImageUrl != null) {
      final refUrl = task.referenceImageUrl!;
      final isLocal =
          !refUrl.startsWith('http://') && !refUrl.startsWith('https://');

      if (isLocal) {
        thumbnailWidget = Image.file(
          File(refUrl),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Container(color: colors.surfaceContainerHighest),
        );
      } else {
        thumbnailUrl = refUrl;
      }
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (thumbnailWidget != null)
          thumbnailWidget
        else if (thumbnailUrl != null)
          ProxiedNetworkImage(
            url: thumbnailUrl,
            fit: BoxFit.cover,
            loadingBuilder: (_) =>
                Container(color: colors.surfaceContainerHighest),
            errorBuilder: (_) =>
                Container(color: colors.surfaceContainerHighest),
          ),
        Container(
          color: palette.depth.withValues(alpha: task.isError ? 0.62 : 0.42),
          child: Center(
            child: task.isError
                ? Icon(
                    Icons.error_outline_rounded,
                    color: colors.error,
                    size: 22,
                  )
                : SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.accent,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusLine(ColorScheme colors, PhotosessionPalette palette) {
    if (task.isActive) {
      return Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              task.statusMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurface.withOpacity(0.6),
              ),
            ),
          ),
        ],
      );
    }

    if (task.isCompleted) {
      return Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 14,
            color: palette.success,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Готово! Нажмите, чтобы посмотреть',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: palette.success,
              ),
            ),
          ),
        ],
      );
    }

    return Text(
      task.displayError,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12, color: colors.error),
    );
  }

  List<Widget> _buildActions(ColorScheme colors) {
    if (task.isError) {
      return [
        IconButton(
          onPressed: onRetry,
          icon: Icon(Icons.refresh_rounded, color: colors.primary),
          iconSize: 20,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          padding: EdgeInsets.zero,
        ),
        IconButton(
          onPressed: onDismiss,
          icon: Icon(
            Icons.close_rounded,
            color: colors.onSurface.withOpacity(0.4),
          ),
          iconSize: 18,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          padding: EdgeInsets.zero,
        ),
      ];
    }

    if (task.isCompleted) {
      return [
        Icon(
          Icons.chevron_right_rounded,
          color: colors.onSurface.withOpacity(0.3),
        ),
      ];
    }

    return [];
  }
}

class _SubscriptionBanner extends ConsumerStatefulWidget {
  const _SubscriptionBanner({required this.usage});
  final CreditUsageModel usage;

  @override
  ConsumerState<_SubscriptionBanner> createState() =>
      _SubscriptionBannerState();
}

class _SubscriptionBannerState extends ConsumerState<_SubscriptionBanner> {
  static const _promoText = 'Попробуйте PRO бесплатно!';

  String _displayedText = '';
  bool _isTyping = false;
  Timer? _typingTimer;
  int _currentCharIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.usage.isFreeUser) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startTyping());
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    super.dispose();
  }

  void _startTyping() {
    if (!mounted || _isTyping) return;
    _typingTimer?.cancel();
    setState(() {
      _isTyping = true;
      _currentCharIndex = 0;
      _displayedText = '';
    });

    _typingTimer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_currentCharIndex < _promoText.length) {
        setState(() {
          _currentCharIndex++;
          _displayedText = _promoText.substring(0, _currentCharIndex);
        });
      } else {
        timer.cancel();
        setState(() => _isTyping = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.usage.remainingCredits;
    final isFree = widget.usage.isFreeUser;
    final isTrial = widget.usage.isTrialUser;

    if (isTrial) {
      return const SizedBox.shrink();
    }

    if (!isFree && !isTrial && remaining > 50) {
      return const SizedBox.shrink();
    }

    if (!isFree && !isTrial && remaining > 50) return const SizedBox.shrink();

    ref.listen<int>(homeScreenResumeCountProvider, (_, __) {
      if (isFree) _startTyping();
    });

    final palette = PhotosessionPalette.of(context);

    final Color startColor;
    final Color endColor;
    final Color foreground;
    final String title;
    final String subtitle;
    final String buttonText;
    final VoidCallback onTap;

    if (isFree) {
      startColor = palette.accent;
      endColor = palette.accentMuted;
      foreground = palette.background;
      title = 'Бесплатная версия';
      subtitle = _displayedText.isEmpty ? _promoText : _displayedText;
      buttonText = 'PRO';
      onTap = () => Navigator.of(context).push(paywallRoute());
    } else if (isTrial) {
      startColor = palette.surfaceHigh;
      endColor = palette.surface;
      foreground = palette.textPrimary;
      title = 'Пробный период';
      final daysRemaining = widget.usage.trialDaysRemaining;
      final dayLabel = daysRemaining == 1 ? 'день' : 'дней';
      subtitle = '$daysRemaining $dayLabel · $remaining кредитов';
      buttonText = 'Купить кредиты';
      onTap = () => Navigator.of(context).push(tokenPurchaseRoute());
    } else {
      startColor = palette.warning;
      endColor = palette.danger;
      foreground = palette.background;
      title = 'Кредиты заканчиваются';
      subtitle = 'Осталось $remaining кредитов';
      buttonText = 'Купить';
      onTap = () => Navigator.of(context).push(tokenPurchaseRoute());
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(_kPadding, 0, _kPadding, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [startColor, endColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: foreground.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: foreground,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: foreground.withValues(alpha: 0.85),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: foreground,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      buttonText,
                      style: TextStyle(
                        color: startColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
