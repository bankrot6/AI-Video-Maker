import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'attraction_details_screen.dart';
import 'attraction_providers.dart';
import 'location_overview_screen.dart';
import 'travel_plans_provider.dart';
import 'models/attraction_place.dart';
import 'models/attraction_route.dart';
import 'models/travel_plan.dart';
import '../../widgets/liquid_glass_card.dart';
import '../../widgets/liquid_glass_shimmer.dart';

class TravelPlanDetailsScreen extends ConsumerStatefulWidget {
  final TravelPlan plan;

  const TravelPlanDetailsScreen({super.key, required this.plan});

  @override
  ConsumerState<TravelPlanDetailsScreen> createState() =>
      _TravelPlanDetailsScreenState();
}

class _TravelPlanDetailsScreenState
    extends ConsumerState<TravelPlanDetailsScreen> {
  bool _navigatorOpening = false;
  int _selectedTabIndex = 0;

  static const _tabItems = <(String label, IconData icon)>[
    ('Объекты', CupertinoIcons.building_2_fill),
    ('Маршруты', CupertinoIcons.map_fill),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefetchTopPlaceIds();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final plans = ref.watch(travelPlansProvider);
    final plan = plans.firstWhere(
      (p) => p.id == widget.plan.id,
      orElse: () => widget.plan,
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(plan.placeLabel),
      ),
      body: SafeArea(child: _buildTabBody(plan)),
      bottomNavigationBar: SafeArea(
        top: false,
        child: CupertinoTabBar(
          currentIndex: _selectedTabIndex,
          onTap: (index) => setState(() => _selectedTabIndex = index),
          activeColor: colorScheme.primary,
          items: [
            for (final item in _tabItems)
              BottomNavigationBarItem(
                icon: Icon(item.$2),
                label: item.$1,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBody(TravelPlan plan) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PlanHeader(
          plan: plan,
          onOpenOverview: _openLocationOverview,
        ),
        const SizedBox(height: 16),
        if (_selectedTabIndex == 0) ...[
          _AttractionsSection(
            plan: plan,
            onOpenNavigator: _openInNavigator,
            onOpenDetails: _openPlaceDetails,
          ),
        ] else ...[
          if (plan.routes.isNotEmpty)
            _RoutesSection(
              routes: plan.routes,
              onOpenNavigator: _openInNavigator,
              onOpenDetails: _openPlaceDetails,
            )
          else if (plan.isLoading || plan.isPartial)
            const _RoutesShimmerSection()
          else
            const _EmptyRoutesHint(),
        ],
        const SizedBox(height: 80),
      ],
    );
  }

  void _openPlaceDetails(AttractionPlace place) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AttractionDetailsScreen(place: place),
      ),
    );
  }

  void _openLocationOverview() {
    final plans = ref.read(travelPlansProvider);
    final plan = plans.firstWhere(
      (p) => p.id == widget.plan.id,
      orElse: () => widget.plan,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LocationOverviewScreen(
          locationName: plan.placeLabel,
          latitude: plan.latitude,
          longitude: plan.longitude,
        ),
      ),
    );
  }

  Future<void> _openInNavigator(AttractionPlace place) async {
    if (_navigatorOpening) return;

    setState(() => _navigatorOpening = true);

    var resolved = place;
    var hasCoords = _hasValidCoordinates(resolved);
    final hasPlaceId = (resolved.googlePlaceId ?? '').isNotEmpty;

    // Лениво получаем place_id (и координаты) для точного POI.
    // Даже если координаты уже есть, без place_id карты могут открыть просто точку.
    if (!hasPlaceId) {
      try {
        final plans = ref.read(travelPlansProvider);
        final plan = plans.firstWhere(
          (p) => p.id == widget.plan.id,
          orElse: () => widget.plan,
        );
        final placesService = ref.read(googlePlacesServiceProvider);
        final realPlace = await placesService.findPlaceByName(
          name: place.name,
          nearLocation: LatLng(plan.latitude, plan.longitude),
          cityHint: plan.placeLabel,
          radiusMeters: 50000,
        );
        if (realPlace != null) {
          // ВАЖНО: не меняем отображаемое имя/описание/категорию из модели.
          // Сохраняем только данные для навигатора (place_id/координаты).
          resolved = place.copyWith(
            googlePlaceId: realPlace.googlePlaceId ?? realPlace.id,
            latitude: realPlace.latitude,
            longitude: realPlace.longitude,
          );
          hasCoords = _hasValidCoordinates(resolved);
          await ref.read(travelPlansProvider.notifier).replacePlaceInPlan(
                planId: plan.id,
                oldName: place.name,
                updated: resolved,
              );
        }
      } catch (_) {
        // игнорируем — откроем по названию
      }
    }

    final encodedName = Uri.encodeComponent(resolved.name);

    try {
      final uri = _buildNavigationUri(resolved, hasCoords, encodedName);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть навигатор: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _navigatorOpening = false);
      }
    }
  }

  Uri _buildNavigationUri(
    AttractionPlace place,
    bool hasCoords,
    String encodedName,
  ) {
    final googlePlaceId = place.googlePlaceId ??
        ((place.id.trim().startsWith('ChI') && place.id.trim().length > 10)
            ? place.id.trim()
            : null);

    // Если есть Google place_id — открываем именно карточку POI (точное место).
    if (googlePlaceId != null && googlePlaceId.isNotEmpty) {
      return Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$encodedName&query_place_id=$googlePlaceId',
      );
    }

    // Если place_id нет — предпочтительнее поиск по названию (а не pin по координатам),
    // чтобы карты показывали именно объект (например "Кремль"), а не случайную точку.
    if (encodedName.isNotEmpty) {
      if (Platform.isIOS) {
        return Uri.parse('http://maps.apple.com/?q=$encodedName');
      }
      return Uri.parse('geo:0,0?q=$encodedName');
    }

    if (!hasCoords) {
      if (Platform.isIOS) {
        return Uri.parse('http://maps.apple.com/?q=$encodedName');
      }
      return Uri.parse('geo:0,0?q=$encodedName');
    }

    if (Platform.isIOS) {
      return Uri.parse(
        'http://maps.apple.com/?q=$encodedName&ll=${place.latitude},${place.longitude}',
      );
    }

    return Uri(
      scheme: 'geo',
      path: '${place.latitude},${place.longitude}',
      queryParameters: {
        'q': '${place.latitude},${place.longitude}(${place.name})',
      },
    );
  }

  bool _hasValidCoordinates(AttractionPlace place) {
    final latOk = place.latitude.abs() <= 90;
    final lngOk = place.longitude.abs() <= 180;
    final notZero = place.latitude != 0 || place.longitude != 0;
    return latOk && lngOk && notZero;
  }

  void _prefetchTopPlaceIds() {
    // Скрытая загрузка: подготавливаем place_id для самых “важных” мест (из маршрутов),
    // чтобы клики по навигатору открывали точный POI.
    final plans = ref.read(travelPlansProvider);
    final plan = plans.firstWhere(
      (p) => p.id == widget.plan.id,
      orElse: () => widget.plan,
    );

    if (!mounted) return;

    final candidates = <AttractionPlace>[];
    for (final route in plan.routes) {
      for (final stop in route.stops) {
        if ((stop.googlePlaceId ?? '').isNotEmpty) continue;
        candidates.add(stop);
      }
    }

    final unique = <String, AttractionPlace>{};
    String key(String v) =>
        v.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
    for (final c in candidates) {
      unique.putIfAbsent(key(c.name), () => c);
    }

    final list = unique.values.take(12).toList(growable: false);
    if (list.isEmpty) return;

    final placesService = ref.read(googlePlacesServiceProvider);
    final notifier = ref.read(travelPlansProvider.notifier);
    final center = LatLng(plan.latitude, plan.longitude);

    Future<void>(() async {
      for (final place in list) {
        if (!mounted) return;
        try {
          final realPlace = await placesService.findPlaceByName(
            name: place.name,
            nearLocation: center,
            cityHint: plan.placeLabel,
          );
          if (realPlace == null) continue;
          // Не меняем UI-данные — только place_id/координаты.
          final updated = place.copyWith(
            googlePlaceId: realPlace.googlePlaceId ?? realPlace.id,
            latitude: realPlace.latitude,
            longitude: realPlace.longitude,
          );
          await notifier.replacePlaceInPlan(
            planId: plan.id,
            oldName: place.name,
            updated: updated,
          );
        } catch (_) {
          // тихо, без влияния на UX
        }
      }
    });
  }
}

class _PlanHeader extends StatelessWidget {
  final TravelPlan plan;
  final VoidCallback onOpenOverview;

  const _PlanHeader({
    required this.plan,
    required this.onOpenOverview,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LiquidGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.placeLabel,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: Colors.black.withOpacity(0.06),
          ),
          const SizedBox(height: 10),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpenOverview,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.location_city,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'О месте',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'История, культура и интересные факты',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.black54,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.black.withOpacity(0.35),
                      size: 26,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutesSection extends StatelessWidget {
  final List<AttractionRoute> routes;
  final Future<void> Function(AttractionPlace) onOpenNavigator;
  final void Function(AttractionPlace) onOpenDetails;

  const _RoutesSection({
    required this.routes,
    required this.onOpenNavigator,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Маршруты',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        ...routes.asMap().entries.map((entry) {
          return _RouteExpandableCard(
            route: entry.value,
            position: entry.key + 1,
            onOpenNavigator: onOpenNavigator,
            onOpenDetails: onOpenDetails,
          );
        }),
      ],
    );
  }
}

class _RouteExpandableCard extends StatefulWidget {
  final AttractionRoute route;
  final int position;
  final Future<void> Function(AttractionPlace) onOpenNavigator;
  final void Function(AttractionPlace) onOpenDetails;

  const _RouteExpandableCard({
    required this.route,
    required this.position,
    required this.onOpenNavigator,
    required this.onOpenDetails,
  });

  @override
  State<_RouteExpandableCard> createState() => _RouteExpandableCardState();
}

class _RouteExpandableCardState extends State<_RouteExpandableCard>
    with TickerProviderStateMixin {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = widget.route;

    final previewNames = route.stops.take(3).map((s) => s.name).toList();
    final pathPreview = previewNames.isEmpty
        ? ''
        : previewNames.join(' → ') +
            (route.stops.length > previewNames.length ? ' → …' : '');

    return LiquidGlassCard(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        route.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 180),
                      turns: _expanded ? 0.5 : 0,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 28,
                        color: Colors.black.withOpacity(0.45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            route.summary,
            maxLines: _expanded ? null : 2,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.black87,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          _RouteMetaRow(route: route),
          if (pathPreview.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              pathPreview,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.black54,
                height: 1.25,
              ),
            ),
          ],
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      children: [
                        for (final entry in route.stops.asMap().entries)
                          _StopTile(
                            place: entry.value,
                            number: entry.key + 1,
                            onOpenNavigator: () =>
                                widget.onOpenNavigator(entry.value),
                            onOpenDetails: () =>
                                widget.onOpenDetails(entry.value),
                            isLast: entry.key == route.stops.length - 1,
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;

  const _Pill({
    required this.text,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class _RouteMetaRow extends StatelessWidget {
  final AttractionRoute route;

  const _RouteMetaRow({required this.route});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];

    if (route.estimatedDistanceKm != null) {
      items.add(_Meta(
          icon: Icons.route_rounded,
          text: '${route.estimatedDistanceKm!.toStringAsFixed(1)} км'));
    }
    if (route.estimatedDurationMin != null) {
      items.add(_Meta(
          icon: Icons.access_time_rounded,
          text: '${route.estimatedDurationMin} мин'));
    }
    items.add(
        _Meta(icon: Icons.place_outlined, text: '${route.stops.length} точек'));

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: items,
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Meta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.black.withOpacity(0.5)),
        const SizedBox(width: 6),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _StopTile extends StatelessWidget {
  final AttractionPlace place;
  final int number;
  final VoidCallback onOpenNavigator;
  final VoidCallback onOpenDetails;
  final bool isLast;

  const _StopTile({
    required this.place,
    required this.number,
    required this.onOpenNavigator,
    required this.onOpenDetails,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dividerColor = Colors.black.withOpacity(0.06);

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpenDetails,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                place.name,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (place.category.trim().isNotEmpty)
                              _Pill(
                                text: place.categoryRu,
                                background:
                                    colorScheme.primary.withOpacity(0.10),
                                foreground: colorScheme.primary,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          place.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.black54,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onOpenNavigator,
                    tooltip: 'В навигатор',
                    icon: const Icon(Icons.navigation_rounded),
                    color: colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!isLast)
          Container(
            height: 1,
            color: dividerColor,
          ),
      ],
    );
  }
}

class _EmptyRoutesHint extends StatelessWidget {
  const _EmptyRoutesHint();

  @override
  Widget build(BuildContext context) {
    return LiquidGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Маршруты пока не готовы',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Запросите обновление или повторите подборку, чтобы увидеть варианты пути.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttractionsSection extends StatelessWidget {
  final TravelPlan plan;
  final Future<void> Function(AttractionPlace) onOpenNavigator;
  final void Function(AttractionPlace) onOpenDetails;

  const _AttractionsSection({
    required this.plan,
    required this.onOpenNavigator,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryPlaces = _uniqueByName(
      plan.routes.expand((r) => r.stops).toList(growable: false),
    );
    final primaryKeys = primaryPlaces.map((p) => _nameKey(p.name)).toSet();

    final extraPlaces = _uniqueByName(
      plan.attractions
          .where((p) => !primaryKeys.contains(_nameKey(p.name)))
          .toList(growable: false),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Основные (в маршрутах)',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (primaryPlaces.isEmpty)
          if (plan.isLoading || plan.isPartial)
            const _AttractionsShimmerSection(count: 3)
          else
            const LiquidGlassCard(
              padding: EdgeInsets.all(16),
              child: Text(
                'Пока нет списка мест.',
                style: TextStyle(fontSize: 14, color: Colors.black87),
              ),
            )
        else ...[
          ...primaryPlaces.map(
            (place) => _AttractionCard(
              place: place,
              onOpenNavigator: () => onOpenNavigator(place),
              onOpenDetails: () => onOpenDetails(place),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          'Дополнительно',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (extraPlaces.isEmpty)
          if (plan.isLoading || plan.isPartial)
            const _AttractionsShimmerSection(count: 6)
          else
            const LiquidGlassCard(
              padding: EdgeInsets.all(16),
              child: Text(
                'Пока нет дополнительных мест.',
                style: TextStyle(fontSize: 14, color: Colors.black87),
              ),
            )
        else
          ...extraPlaces.map(
            (place) => _AttractionCard(
              place: place,
              onOpenNavigator: () => onOpenNavigator(place),
              onOpenDetails: () => onOpenDetails(place),
            ),
          ),
      ],
    );
  }

  static String _nameKey(String value) =>
      value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  static List<AttractionPlace> _uniqueByName(List<AttractionPlace> input) {
    final seen = <String>{};
    final out = <AttractionPlace>[];
    for (final item in input) {
      final key = _nameKey(item.name);
      if (key.isEmpty) continue;
      if (seen.add(key)) {
        out.add(item);
      }
    }
    return out;
  }
}

class _AttractionsShimmerSection extends StatelessWidget {
  final int count;
  const _AttractionsShimmerSection({required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (index) => const _AttractionCardShimmer(),
        growable: false,
      ),
    );
  }
}

class _AttractionCardShimmer extends StatelessWidget {
  const _AttractionCardShimmer();

  @override
  Widget build(BuildContext context) {
    return const LiquidGlassCard(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: LiquidGlassShimmerLight(height: 16, borderRadius: 8),
              ),
              SizedBox(width: 10),
              LiquidGlassShimmerLight(width: 72, height: 18, borderRadius: 999),
            ],
          ),
          SizedBox(height: 10),
          LiquidGlassShimmerLight(height: 12, borderRadius: 6),
          SizedBox(height: 6),
          LiquidGlassShimmerLight(width: 220, height: 12, borderRadius: 6),
        ],
      ),
    );
  }
}

class _RoutesShimmerSection extends StatelessWidget {
  const _RoutesShimmerSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        LiquidGlassCard(
          padding: EdgeInsets.all(14),
          margin: EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LiquidGlassShimmerLight(height: 16, borderRadius: 8),
              SizedBox(height: 10),
              LiquidGlassShimmerLight(height: 12, borderRadius: 6),
              SizedBox(height: 6),
              LiquidGlassShimmerLight(width: 260, height: 12, borderRadius: 6),
              SizedBox(height: 12),
              LiquidGlassShimmerLight(height: 44, borderRadius: 12),
            ],
          ),
        ),
        LiquidGlassCard(
          padding: EdgeInsets.all(14),
          margin: EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LiquidGlassShimmerLight(height: 16, borderRadius: 8),
              SizedBox(height: 10),
              LiquidGlassShimmerLight(height: 12, borderRadius: 6),
              SizedBox(height: 6),
              LiquidGlassShimmerLight(width: 240, height: 12, borderRadius: 6),
              SizedBox(height: 12),
              LiquidGlassShimmerLight(height: 44, borderRadius: 12),
            ],
          ),
        ),
        LiquidGlassCard(
          padding: EdgeInsets.all(14),
          margin: EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LiquidGlassShimmerLight(height: 16, borderRadius: 8),
              SizedBox(height: 10),
              LiquidGlassShimmerLight(height: 12, borderRadius: 6),
              SizedBox(height: 6),
              LiquidGlassShimmerLight(width: 280, height: 12, borderRadius: 6),
              SizedBox(height: 12),
              LiquidGlassShimmerLight(height: 44, borderRadius: 12),
            ],
          ),
        ),
      ],
    );
  }
}

class _AttractionCard extends StatelessWidget {
  final AttractionPlace place;
  final VoidCallback onOpenNavigator;
  final VoidCallback onOpenDetails;

  const _AttractionCard({
    required this.place,
    required this.onOpenNavigator,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LiquidGlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      onTap: onOpenDetails,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        place.name,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (place.category.trim().isNotEmpty)
                      _Pill(
                        text: place.categoryRu,
                        background: colorScheme.primary.withOpacity(0.10),
                        foreground: colorScheme.primary,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  place.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black54,
                    height: 1.25,
                  ),
                ),
                if (place.highlight != null && place.highlight!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    place.highlight!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.black45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              IconButton(
                onPressed: onOpenNavigator,
                tooltip: 'В навигатор',
                icon: const Icon(Icons.navigation_rounded),
                color: colorScheme.primary,
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.black.withOpacity(0.35),
                size: 26,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
