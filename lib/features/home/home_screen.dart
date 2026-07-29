import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/travel_plan.dart';
import 'travel_plan_details_screen.dart';
import 'travel_plans_provider.dart';
import 'services/city_image_service.dart';
import '../../widgets/liquid_glass_card.dart';
import '../../widgets/rtl_wrapper.dart';
import '../../widgets/premium_trial_banner.dart';
import '../../services/localization/app_localization_service.dart';
import '../subscription/subscription_providers.dart';
import '../../models/subscription_model.dart';
import '../../services/city_limit_service.dart';


class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _hasInitialized = false;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final travelPlans = ref.watch(travelPlansProvider);
    final subscriptionAsync = ref.watch(subscriptionProvider);
    final showFreeBanner = subscriptionAsync.maybeWhen(
      data: (subscription) => subscription.type == SubscriptionType.free,
      orElse: () => false,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_hasInitialized) return;
      _hasInitialized = true;
      final notifier = ref.read(travelPlansProvider.notifier);
      notifier.restoreFromCache().then((_) {
        if (!mounted) return;
        final current = ref.read(travelPlansProvider);
        if (current.isEmpty) {
          _createInitialPlanFromOnboarding();
        }
      });
    });

    return RTLWrapper(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: const Color(0xFFF2F2F7),
          body: SafeArea(
            child: Column(
              children: [
                if (showFreeBanner) const PremiumTrialBanner(),
                Expanded(
                  child: _buildTravelPlansList(
                    travelPlans,
                    hasBanner: showFreeBanner,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTravelPlansList(
    List<TravelPlan> plans, {
    required bool hasBanner,
  }) {
    return RefreshIndicator(
      onRefresh: () => Future.value(null),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, hasBanner ? 8 : 16, 16, 96),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          if (plans.isEmpty)
            const _LoadingFirstPlan()
          else
            ...plans.map(
              (plan) => _TravelPlanCard(
                plan: plan,
                onOpen: () => _openPlanDetails(plan),
                onDelete: () =>
                    ref.read(travelPlansProvider.notifier).removePlan(plan.id),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _createInitialPlanFromOnboarding() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final city = (prefs.getString('last_trip_city') ?? '').trim();
      final days = prefs.getInt('last_trip_days') ?? 3;
      if (city.isEmpty) return;
      final notifier = ref.read(travelPlansProvider.notifier);
      await notifier.createPlan(
        placeQuery: city,
        stayDays: days.clamp(1, 30),
        interests: const [],
        previewAttractionsLimit: 7,
        prioritizePreviewAttractions: true,
        keepOriginalPlaceLabel: true,
      );
    } catch (e) {
      if (mounted) {
        final message = e is CityLimitException
            ? _formatCityLimitError(context, e.result)
            : 'Не удалось создать экскурсию. Попробуйте снова.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: _createInitialPlanFromOnboarding,
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  String _formatCityLimitError(
      BuildContext context, CityLimitCheckResult result) {
    switch (result.reason) {
      case CityLimitReason.dailyLimit:
        return context.trParams(
          'city_daily_limit_reached',
          [result.dailyLimit?.toString() ?? '0'],
        );
      case CityLimitReason.totalLimit:
        return context.trParams(
          'city_total_limit_reached',
          [result.totalLimit?.toString() ?? '0'],
        );
      case CityLimitReason.trialDailyLimit:
        return context.trParams(
          'city_trial_daily_limit_reached',
          [result.dailyLimit?.toString() ?? '0'],
        );
      case CityLimitReason.trialTotalLimit:
        return context.trParams(
          'city_trial_total_limit_reached',
          [result.totalLimit?.toString() ?? '0'],
        );
      case null:
        return context.tr('city_limit_generic_error');
    }
  }

  void _openPlanDetails(TravelPlan plan) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TravelPlanDetailsScreen(plan: plan),
      ),
    );
  }

}

class _TravelPlanCard extends StatelessWidget {
  final TravelPlan plan;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _TravelPlanCard({
    required this.plan,
    required this.onOpen,
    required this.onDelete,
  });

  int _countUniquePlaces(TravelPlan plan) {
    String key(String v) =>
        v.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
    final seen = <String>{};
    int count = 0;

    for (final route in plan.routes) {
      for (final stop in route.stops) {
        final k = key(stop.name);
        if (k.isEmpty) continue;
        if (seen.add(k)) count++;
      }
    }

    for (final place in plan.attractions) {
      final k = key(place.name);
      if (k.isEmpty) continue;
      if (seen.add(k)) count++;
    }

    return count;
  }

  @override
  Widget build(BuildContext context) {
    return LiquidGlassCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned.fill(
            child: _TravelPlanCardBackground(
              cacheKey: plan.id,
              cityLabel: plan.placeLabel,
              latitude: plan.latitude,
              longitude: plan.longitude,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.35),
                    Colors.white.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.placeLabel,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Пребывание: ${plan.stayDays} дн.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              if (plan.isLoading) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
              PopupMenuButton<String>(
                tooltip: 'Действия',
                onSelected: (value) {
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Удалить'),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.more_horiz_rounded,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
          // Резервируем место под статус, чтобы карточка не "прыгала" по высоте
          // во время загрузки/обновления.
          const SizedBox(height: 12),
          SizedBox(
            height: 32,
            child: Align(
              alignment: Alignment.centerLeft,
              child: (plan.isLoading || plan.isPartial || plan.hasError)
                  ? Row(
                      children: [
                        if (plan.isLoading)
                          _StatusPill(
                            text: 'Создаётся',
                            background: Colors.blue.withValues(alpha: 0.12),
                            foreground: const Color(0xFF007AFF),
                            icon: Icons.hourglass_top_rounded,
                          ),
                        if (plan.isLoading && (plan.isPartial || plan.hasError))
                          const SizedBox(width: 8),
                        if (plan.isPartial)
                          _StatusPill(
                            text: 'Обновляется',
                            background: Colors.orange.withValues(alpha: 0.16),
                            foreground: Colors.orange.shade800,
                            icon: Icons.sync_rounded,
                          ),
                        if (plan.isPartial && plan.hasError)
                          const SizedBox(width: 8),
                        if (plan.hasError)
                          _StatusPill(
                            text: 'Ошибка',
                            background: Colors.red.withValues(alpha: 0.12),
                            foreground: Colors.red.shade700,
                            icon: Icons.error_outline_rounded,
                          ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          if (plan.interests.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: plan.interests
                  .map((tag) => Chip(
                        label: Text(tag),
                        backgroundColor:
                            const Color.fromRGBO(33, 150, 243, 0.1),
                        labelStyle: const TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                        ),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 16),
          _MetaRow(
            leftIcon: Icons.route_rounded,
            leftText: 'Маршрутов: ${plan.routes.length}',
            rightIcon: Icons.place_outlined,
            rightText: 'Мест: ${_countUniquePlaces(plan)}',
          ),
          if (plan.hasError &&
              plan.errorMessage != null &&
              plan.errorMessage!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              plan.errorMessage!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.red.shade700,
                    height: 1.25,
                  ),
            ),
          ],
          const SizedBox(height: 12),
          _OpenPlanRow(
            enabled: !plan.hasError && !plan.isLoading,
            onTap: (plan.hasError || plan.isLoading) ? null : onOpen,
          ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TravelPlanCardBackground extends ConsumerWidget {
  final String cacheKey;
  final String cityLabel;
  final double? latitude;
  final double? longitude;

  const _TravelPlanCardBackground({
    required this.cacheKey,
    required this.cityLabel,
    this.latitude,
    this.longitude,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normalizedCacheKey = cityImageCacheKey(cacheKey);
    final memoryImage = ref.watch(
      cityImageMemoryCacheProvider.select(
        (cache) => cache[normalizedCacheKey],
      ),
    );
    final image = ref.watch(
      cityImageProvider(
        CityImageRequest(
          cacheKey: cacheKey,
          label: cityLabel,
          latitude: latitude,
          longitude: longitude,
        ),
      ),
    );
    final imageProvider = memoryImage ?? image.asData?.value;
    return _buildBackground(imageProvider);
  }

  Widget _buildBackground(ImageProvider? imageProvider) {
    if (imageProvider == null) {
      return const ColoredBox(color: Color(0xFFF5F5FA));
    }

    return ClipRect(
      child: Transform.scale(
        scale: 1.15,
        alignment: Alignment.topCenter,
        child: Image(
          image: imageProvider,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) =>
              const ColoredBox(color: Color(0xFFF5F5FA)),
        ),
      ),
    );
  }
}

class _OpenPlanRow extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;

  const _OpenPlanRow({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          child: Row(
            children: [
              Icon(
                Icons.explore_rounded,
                color: enabled ? const Color(0xFF007AFF) : Colors.black26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Открыть экскурсию',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: enabled ? Colors.black87 : Colors.black38,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: enabled
                    ? Colors.black.withValues(alpha: 0.35)
                    : Colors.black26,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData leftIcon;
  final String leftText;
  final IconData rightIcon;
  final String rightText;

  const _MetaRow({
    required this.leftIcon,
    required this.leftText,
    required this.rightIcon,
    required this.rightText,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(leftIcon, color: const Color(0xFF007AFF)),
          const SizedBox(width: 8),
          Expanded(child: Text(leftText, style: textStyle)),
          Icon(rightIcon, color: const Color(0xFF34C759)),
          const SizedBox(width: 8),
          Text(rightText, style: textStyle),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;
  final IconData icon;

  const _StatusPill({
    required this.text,
    required this.background,
    required this.foreground,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingFirstPlan extends StatelessWidget {
  const _LoadingFirstPlan();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: LiquidGlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Городов пока нет',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Добавьте новый город кнопкой снизу.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                  ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 90,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              ),
              child: const Center(
                child: Icon(
                  Icons.location_on_outlined,
                  size: 28,
                  color: Color(0xFF007AFF),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
