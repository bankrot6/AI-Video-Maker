import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import '../../models/step_model.dart';
import '../../widgets/glass_settings_constants.dart';
import '../../widgets/liquid_glass_card.dart';
import '../../widgets/liquid_glass_stub.dart';
import '../../services/localization/app_localization_service.dart';
import 'step_providers.dart';

class StepDetailsScreen extends ConsumerStatefulWidget {
  const StepDetailsScreen({super.key});

  @override
  ConsumerState<StepDetailsScreen> createState() => _StepDetailsScreenState();
}

class _StepDetailsScreenState extends ConsumerState<StepDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StepPeriod _selectedPeriod = StepPeriod.week;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {
        _selectedPeriod = StepPeriod.values[_tabController.index];
      });
      ref.read(selectedPeriodProvider.notifier).state = _selectedPeriod;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stepEntry = ref.watch(stepNotifierProvider);
    final goal = ref.watch(stepGoalProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/a-futuristic-digital-background-0.png',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildAppBar(context),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        _buildTodayCard(stepEntry, goal),
                        const SizedBox(height: 16),
                        _buildPeriodSelector(),
                        const SizedBox(height: 16),
                        _buildChartCard(),
                        const SizedBox(height: 16),
                        _buildStatsCards(),
                        const SizedBox(height: 16),
                        _buildHistoryList(),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
            child: FakeGlass(
              shape: const LiquidRoundedSuperellipse(
                borderRadius: Radius.circular(12),
              ),
              settings: GlassSettingsConstants.matteList,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 20,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            context.tr('step_tracker'),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _showGoalBottomSheet(context),
            child: FakeGlass(
              shape: const LiquidRoundedSuperellipse(
                borderRadius: Radius.circular(12),
              ),
              settings: GlassSettingsConstants.matteList,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(
                  Icons.settings_rounded,
                  size: 20,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayCard(StepEntry stepEntry, int goal) {
    final steps = stepEntry.steps;
    final distanceKm = stepEntry.distanceKm;
    final caloriesBurned = stepEntry.caloriesBurned;
    final progress = goal > 0 ? (steps / goal).clamp(0.0, 1.0) : 0.0;
    final isGoalReached = progress >= 1.0;

    return FakeGlass(
      shape: const LiquidRoundedSuperellipse(
        borderRadius: Radius.circular(24),
      ),
      settings: GlassSettingsConstants.matteList,
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 160,
                  height: 160,
                  child: CustomPaint(
                    painter: _CircularProgressPainter(
                      progress: progress,
                      color: _getProgressColor(progress),
                      backgroundColor: Colors.grey.withOpacity(0.2),
                      strokeWidth: 12,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isGoalReached)
                      const Icon(
                        Icons.celebration_rounded,
                        size: 32,
                        color: Color(0xFF4CAF50),
                      ),
                    Text(
                      _formatNumber(steps),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      context.tr('steps'),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatColumn(
                  icon: Icons.flag_rounded,
                  value: _formatNumber(goal),
                  label: context.tr('goal'),
                  glassSettings: GlassSettingsConstants.blue,
                ),
                _buildStatColumn(
                  icon: Icons.straighten_rounded,
                  value: distanceKm.toStringAsFixed(2),
                  label: context.tr('km'),
                  glassSettings: GlassSettingsConstants.orange,
                ),
                _buildStatColumn(
                  icon: Icons.local_fire_department_rounded,
                  value: '${caloriesBurned.toInt()}',
                  label: context.tr('kcal'),
                  glassSettings: GlassSettingsConstants.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn({
    required IconData icon,
    required String value,
    required String label,
    required LiquidGlassSettings glassSettings,
  }) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            width: 48,
            height: 48,
            child: FakeGlass(
              shape: const LiquidRoundedSuperellipse(
                borderRadius: Radius.circular(24),
              ),
              settings: glassSettings,
              child: Center(
                child: Icon(icon, size: 24, color: Colors.white),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black,
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodSelector() {
    return Row(
      children: [
        Expanded(
          child: _buildPeriodSegment(
            text: context.tr('day'),
            index: 0,
            isSelected: _tabController.index == 0,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildPeriodSegment(
            text: context.tr('week'),
            index: 1,
            isSelected: _tabController.index == 1,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildPeriodSegment(
            text: context.tr('month'),
            index: 2,
            isSelected: _tabController.index == 2,
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodSegment({
    required String text,
    required int index,
    required bool isSelected,
  }) {
    final capitalizedText =
        text.isNotEmpty ? '${text[0].toUpperCase()}${text.substring(1)}' : text;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        _tabController.animateTo(index);
      },
      child: FakeGlass(
        shape: const LiquidRoundedSuperellipse(
          borderRadius: Radius.circular(12),
        ),
        settings: isSelected
            ? GlassSettingsConstants.blue
            : GlassSettingsConstants.matteList,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          child: Text(
            capitalizedText,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChartCard() {
    final stepsData = ref.watch(stepsForPeriodProvider(_selectedPeriod));

    return stepsData.when(
      data: (entries) => _buildChart(entries),
      loading: () => _buildChartSkeleton(),
      error: (_, __) => _buildChartError(),
    );
  }

  Widget _buildChart(List<StepEntry> entries) {
    if (entries.isEmpty) return _buildChartEmpty();

    final goal = ref.watch(stepGoalProvider);
    final maxSteps = entries.map((e) => e.steps).reduce(math.max);
    final maxY = math.max(maxSteps, goal) * 1.2;

    return FakeGlass(
      shape: const LiquidRoundedSuperellipse(
        borderRadius: Radius.circular(20),
      ),
      settings: GlassSettingsConstants.matteList,
      child: Container(
        padding: const EdgeInsets.all(20),
        height: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('step_history'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY,
                  barGroups: _buildBarGroups(entries),
                  titlesData: _buildTitlesData(entries),
                  gridData: FlGridData(
                    show: true,
                    drawHorizontalLine: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.grey.withOpacity(0.2),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => Colors.black87,
                      tooltipRoundedRadius: 8,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '${rod.toY.toInt()} ${context.tr('steps')}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: goal.toDouble(),
                        color: Colors.green.withOpacity(0.5),
                        strokeWidth: 2,
                        dashArray: [5, 5],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          labelResolver: (line) => context.tr('goal'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<BarChartGroupData> _buildBarGroups(List<StepEntry> entries) {
    final goal = ref.watch(stepGoalProvider);

    return entries.asMap().entries.map((entry) {
      final index = entry.key;
      final stepEntry = entry.value;
      final isGoalReached = stepEntry.steps >= goal;

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: stepEntry.steps.toDouble(),
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: isGoalReached
                  ? [
                      const Color(0xFF4CAF50).withOpacity(0.7),
                      const Color(0xFF4CAF50),
                    ]
                  : [
                      const Color(0xFF2196F3).withOpacity(0.7),
                      const Color(0xFF2196F3),
                    ],
            ),
            width: _selectedPeriod == StepPeriod.month ? 8 : 20,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ],
      );
    }).toList();
  }

  FlTitlesData _buildTitlesData(List<StepEntry> entries) {
    return FlTitlesData(
      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (index < 0 || index >= entries.length) {
              return const SizedBox.shrink();
            }
            final entry = entries[index];
            String label;
            switch (_selectedPeriod) {
              case StepPeriod.day:
                label = DateFormat('HH:mm').format(entry.date);
                break;
              case StepPeriod.week:
                label = DateFormat('E').format(entry.date);
                break;
              case StepPeriod.month:
                label = DateFormat('d').format(entry.date);
                break;
            }
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.black,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildChartSkeleton() {
    return FakeGlass(
      shape: const LiquidRoundedSuperellipse(
        borderRadius: Radius.circular(20),
      ),
      settings: GlassSettingsConstants.matteList,
      child: Container(
        padding: const EdgeInsets.all(20),
        height: 280,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }

  Widget _buildChartError() {
    return FakeGlass(
      shape: const LiquidRoundedSuperellipse(
        borderRadius: Radius.circular(20),
      ),
      settings: GlassSettingsConstants.matteList,
      child: Container(
        padding: const EdgeInsets.all(20),
        height: 280,
        child: Center(
          child: Text(
            context.tr('error_loading_data'),
            style: const TextStyle(color: Colors.black54),
          ),
        ),
      ),
    );
  }

  Widget _buildChartEmpty() {
    return FakeGlass(
      shape: const LiquidRoundedSuperellipse(
        borderRadius: Radius.circular(20),
      ),
      settings: GlassSettingsConstants.matteList,
      child: Container(
        padding: const EdgeInsets.all(20),
        height: 280,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.directions_walk_rounded,
                size: 48,
                color: Colors.black38,
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('no_step_data'),
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCards() {
    final stepsData = ref.watch(stepsForPeriodProvider(_selectedPeriod));

    return stepsData.when(
      data: (entries) {
        final stats = StepStats.fromEntries(entries);
        return Row(
          children: [
            Expanded(
              child: _buildStatsCard(
                title: context.tr('average'),
                value: _formatNumber(stats.averageStepsPerDay.toInt()),
                subtitle: context.tr('steps_per_day'),
                icon: Icons.trending_up_rounded,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatsCard(
                title: context.tr('best_day'),
                value: _formatNumber(stats.bestDay),
                subtitle: stats.bestDayDate != null
                    ? DateFormat('dd.MM').format(stats.bestDayDate!)
                    : '-',
                icon: Icons.emoji_events_rounded,
                color: Colors.orange,
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildStatsCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return FakeGlass(
      shape: const LiquidRoundedSuperellipse(
        borderRadius: Radius.circular(16),
      ),
      settings: GlassSettingsConstants.matteList,
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryList() {
    final stepsData = ref.watch(stepsForPeriodProvider(_selectedPeriod));

    return stepsData.when(
      data: (entries) {
        if (entries.isEmpty) return const SizedBox.shrink();

        final sortedEntries = List<StepEntry>.from(entries)
          ..sort((a, b) => b.date.compareTo(a.date));

        return FakeGlass(
          shape: const LiquidRoundedSuperellipse(
            borderRadius: Radius.circular(20),
          ),
          settings: GlassSettingsConstants.matteList,
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('history'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                ...sortedEntries
                    .take(7)
                    .map((entry) => _buildHistoryItem(entry)),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildHistoryItem(StepEntry entry) {
    final goal = ref.watch(stepGoalProvider);
    final progress = goal > 0 ? (entry.steps / goal).clamp(0.0, 1.0) : 0.0;
    final isGoalReached = entry.steps >= goal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getProgressColor(progress).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: isGoalReached
                  ? Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: _getProgressColor(progress),
                    )
                  : Text(
                      '${(progress * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _getProgressColor(progress),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEEE, d MMMM', 'ru').format(entry.date),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  '${entry.distanceKm.toStringAsFixed(2)} ${context.tr('km')} • ${entry.caloriesBurned.toInt()} ${context.tr('kcal')}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _formatNumber(entry.steps),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  void _showGoalBottomSheet(BuildContext context) {
    final goal = ref.read(stepGoalProvider);
    final controller = TextEditingController(text: goal.toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      context.tr('set_daily_goal'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: '10000',
                        suffix: Text(context.tr('steps')),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [5000, 7500, 10000, 12000, 15000].map((preset) {
                        return ActionChip(
                          label: Text(_formatNumber(preset)),
                          onPressed: () => controller.text = preset.toString(),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: LiquidGlassButton(
                        onPressed: () {
                          final newGoal =
                              int.tryParse(controller.text) ?? 10000;
                          ref
                              .read(stepNotifierProvider.notifier)
                              .setGoal(newGoal);
                          Navigator.of(sheetContext).pop();
                        },
                        settings: GlassSettingsConstants.blue,
                        child: Text(context.tr('save')),
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

  Color _getProgressColor(double progress) {
    if (progress >= 1.0) return const Color(0xFF4CAF50);
    if (progress >= 0.75) return const Color(0xFF8BC34A);
    if (progress >= 0.5) return const Color(0xFFFFC107);
    if (progress >= 0.25) return const Color(0xFFFF9800);
    return const Color(0xFF2196F3);
  }

  String _formatNumber(int number) {
    final str = number.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        buffer.write(' ');
      }
      buffer.write(str[i]);
    }
    return buffer.toString();
  }
}

class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;
  final double strokeWidth;

  _CircularProgressPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    final progressPaint = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: [
          color.withOpacity(0.6),
          color,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
