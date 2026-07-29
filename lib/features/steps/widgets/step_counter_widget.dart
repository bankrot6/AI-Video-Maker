import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../step_providers.dart';
import '../../../widgets/liquid_glass_card.dart';
import '../../../services/localization/app_localization_service.dart';
import '../step_details_screen.dart';

class StepCounterWidget extends ConsumerStatefulWidget {
  final bool isEditMode;

  const StepCounterWidget({
    super.key,
    this.isEditMode = false,
  });

  @override
  ConsumerState<StepCounterWidget> createState() => _StepCounterWidgetState();
}

class _StepCounterWidgetState extends ConsumerState<StepCounterWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;
  double _lastProgress = 0;
  bool _isRequestingPermission = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _progressAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeOutCubic),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initializeTracker();
    });
  }

  void _initializeTracker() {
    ref.read(stepTrackerInitProvider);
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _animateProgress(double targetProgress) {
    if (targetProgress == _lastProgress) return;

    _progressAnimation = Tween<double>(
      begin: _lastProgress,
      end: targetProgress,
    ).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeOutCubic),
    );
    _progressController.forward(from: 0);
    _lastProgress = targetProgress;
  }

  @override
  Widget build(BuildContext context) {
    final stepEntry = ref.watch(stepNotifierProvider);
    final goal = ref.watch(stepGoalProvider);
    final hasPermissionAsync = ref.watch(hasStepPermissionProvider);
    final service = ref.watch(stepTrackerServiceProvider);

    final steps = stepEntry.steps;
    final progress = goal > 0 ? (steps / goal).clamp(0.0, 1.0) : 0.0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _animateProgress(progress);
    });

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.isEditMode
          ? null
          : () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const StepDetailsScreen(),
                ),
              );
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LiquidGlassCard(
          borderRadius: 12,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          child: hasPermissionAsync.when(
            data: (hasPermission) {
              final actualHasPermission =
                  service.hasPermission || hasPermission;

              if (!actualHasPermission) {
                return _buildPermissionRequest(context);
              }
              return _buildCompactStepContent(
                context: context,
                steps: steps,
                goal: goal,
                progress: progress,
              );
            },
            loading: () => _buildLoadingState(),
            error: (_, __) {
              if (service.hasPermission) {
                return _buildCompactStepContent(
                  context: context,
                  steps: steps,
                  goal: goal,
                  progress: progress,
                );
              }
              return _buildPermissionRequest(context);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const SizedBox(
      height: 50,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildPermissionRequest(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.tr('step_tracker'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Flexible(
                    child: _buildInfoChip(context.tr('permission_required')),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            if (_isRequestingPermission) return;

            setState(() {
              _isRequestingPermission = true;
            });

            HapticFeedback.lightImpact();

            try {
              final service = ref.read(stepTrackerServiceProvider);
              final granted = await service.requestPermission();
              if (granted && mounted) {
                await service.initialize();
                ref.invalidate(hasStepPermissionProvider);
                ref.invalidate(stepNotifierProvider);
              }
            } finally {
              if (mounted) {
                setState(() {
                  _isRequestingPermission = false;
                });
              }
            }
          },
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.check_circle_outline,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactStepContent({
    required BuildContext context,
    required int steps,
    required int goal,
    required double progress,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.tr('steps_today'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  _buildChipsRow(context, goal),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (widget.isEditMode) ...[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showEditGoalDialog(context, goal),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.edit,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ] else ...[
              Text(
                '$steps',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _getProgressColor(progress),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: _progressAnimation,
          builder: (context, child) {
            return _buildProgressBar(_progressAnimation.value, steps, goal);
          },
        ),
      ],
    );
  }

  void _showEditGoalDialog(BuildContext context, int currentGoal) {
    final controller = TextEditingController(text: currentGoal.toString());

    HapticFeedback.mediumImpact();

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
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    context.tr('set_daily_goal'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.7),
                      hintText: '10000',
                      suffixText: context.tr('steps_unit'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF2196F3),
                          width: 2,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: const Color(0xFF2196F3).withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF2196F3),
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onSubmitted: (value) {
                      final newGoal = int.tryParse(value);
                      if (newGoal != null && newGoal > 0) {
                        ref
                            .read(stepNotifierProvider.notifier)
                            .setGoal(newGoal);
                        Navigator.of(sheetContext).pop();
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [5000, 7500, 10000, 12000, 15000].map((preset) {
                      return GestureDetector(
                        onTap: () {
                          controller.text = preset.toString();
                          HapticFeedback.selectionClick();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _formatWithSpaces(preset),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: LiquidGlassButton(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                          },
                          borderRadius: 12,
                          height: 48,
                          child: Text(context.tr('cancel')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: LiquidGlassButton(
                          onPressed: () {
                            final value = controller.text;
                            final newGoal = int.tryParse(value);
                            if (newGoal != null && newGoal > 0) {
                              ref
                                  .read(stepNotifierProvider.notifier)
                                  .setGoal(newGoal);
                              Navigator.of(sheetContext).pop();
                              HapticFeedback.mediumImpact();
                            }
                          },
                          borderRadius: 12,
                          height: 48,
                          child: Text(context.tr('save')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChipsRow(BuildContext context, int goal) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        final availableWidth = constraints.maxWidth;

        final isCompact = screenWidth < 360 || availableWidth < 200;
        final isMedium = screenWidth < 400 || availableWidth < 250;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: GestureDetector(
                onTap: widget.isEditMode
                    ? () => _showEditGoalDialog(context, goal)
                    : null,
                child: _buildChip(
                  '${_formatWithSpaces(goal)} ${context.tr('steps_unit')}',
                  isCompact,
                  isMedium,
                  isEditable: widget.isEditMode,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatWithSpaces(int number) {
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

  Widget _buildChip(String text, bool isCompact, bool isMedium,
      {bool isSecondary = false, bool isEditable = false}) {
    final fontSize = isCompact ? 10.0 : (isMedium ? 11.0 : 12.0);
    final horizontalPadding = isCompact ? 5.0 : (isMedium ? 6.0 : 8.0);
    final verticalPadding = isCompact ? 2.0 : 3.0;

    return Container(
      padding: EdgeInsets.symmetric(
        vertical: verticalPadding,
        horizontal: horizontalPadding,
      ),
      decoration: BoxDecoration(
        color: isEditable
            ? const Color(0xFF2196F3).withValues(alpha: 0.8)
            : (isSecondary ? Colors.grey[600] : const Color(0xFF3A3A3A)),
        borderRadius: BorderRadius.circular(isCompact ? 6 : 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isEditable) ...[
            Icon(
              Icons.edit,
              size: fontSize,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.orange[800],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildProgressBar(double progress, int steps, int goal) {
    final isCompleted = progress >= 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 6,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Container(color: Colors.black.withOpacity(0.06)),
              ),
              if (progress > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        color: isCompleted
                            ? const Color(0xFF34C759)
                            : const Color(0xFF007AFF),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$steps из $goal',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            if (isCompleted)
              const Icon(
                Icons.check_circle,
                size: 14,
                color: Colors.green,
              ),
          ],
        ),
      ],
    );
  }

  Color _getProgressColor(double progress) {
    if (progress >= 1.0) return const Color(0xFF4CAF50);
    if (progress >= 0.75) return const Color(0xFF8BC34A);
    if (progress >= 0.5) return const Color(0xFFFFC107);
    if (progress >= 0.25) return const Color(0xFFFF9800);
    return const Color(0xFF2196F3);
  }
}
