import 'package:flutter/material.dart';
import '../../../widgets/liquid_glass_stub.dart';
import 'dart:ui' as ui;
import '../../../widgets/glass_settings_constants.dart';
import '../../../widgets/liquid_glass_card.dart';
import '../../../repositories/workout_execution_repository.dart';
import '../../../services/localization/app_localization_service.dart';

class ExerciseExecutionSheet extends StatefulWidget {
  final String exerciseName;
  final int totalSets;
  final int defaultReps;
  final double defaultWeight;
  final double? initialRpe;
  final List<Map<String, dynamic>> initialSetsData;
  final Future<void> Function(int index, ExerciseSetExecution set) onSaveSet;

  const ExerciseExecutionSheet({
    super.key,
    required this.exerciseName,
    required this.totalSets,
    required this.defaultReps,
    required this.defaultWeight,
    required this.initialSetsData,
    required this.onSaveSet,
    this.initialRpe,
  });

  @override
  State<ExerciseExecutionSheet> createState() => _ExerciseExecutionSheetState();
}

class _ExerciseExecutionSheetState extends State<ExerciseExecutionSheet> {
  late List<Map<String, dynamic>> setsData;
  late int currentIndex;
  late int curReps;
  late double curWeight;
  late double curRpe;
  late final TextEditingController weightController;
  late final TextEditingController repsController;

  @override
  void initState() {
    super.initState();
    setsData = List<Map<String, dynamic>>.from(widget.initialSetsData);
    currentIndex = setsData.indexWhere((e) => e['done'] != true);
    if (currentIndex == -1) currentIndex = 0;
    curReps = (setsData[currentIndex]['reps'] as int?) ?? widget.defaultReps;
    curWeight =
        (setsData[currentIndex]['weight'] as double?) ?? widget.defaultWeight;
    // По умолчанию выбираем "Средне" (7.0) и никогда не оставляем пустым
    curRpe = (setsData[currentIndex]['rpe'] as double?) ??
        (widget.initialRpe ?? 7.0);

    weightController = TextEditingController(
      text: curWeight > 0 ? curWeight.toStringAsFixed(1) : '',
    );
    repsController = TextEditingController(text: curReps.toString());
  }

  @override
  void dispose() {
    weightController.dispose();
    repsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalSets = widget.totalSets;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context
                    .tr('set_of')
                    .replaceAll('{0}', '${currentIndex + 1}')
                    .replaceAll('{1}', '$totalSets'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SmallGlassButton(
                icon: Icons.close,
                onTap: () => Navigator.of(context).pop({'setsData': setsData}),
                settings: GlassSettingsConstants.onLightMinimal,
                size: 44,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(totalSets, (i) {
              final done = setsData[i]['done'] == true;
              final isCurrent = i == currentIndex;
              final settings = done
                  ? GlassSettingsConstants.onLightGreen
                  : (isCurrent
                      ? GlassSettingsConstants.onLightBlue
                      : GlassSettingsConstants.onLightMinimal);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    currentIndex = i;
                    curReps = (setsData[currentIndex]['reps'] as int?) ??
                        widget.defaultReps;
                    curWeight = (setsData[currentIndex]['weight'] as double?) ??
                        widget.defaultWeight;
                    curRpe = (setsData[currentIndex]['rpe'] as double?) ??
                        (widget.initialRpe ?? 7.0);
                    repsController.text = curReps.toString();
                    weightController.text =
                        curWeight > 0 ? curWeight.toStringAsFixed(1) : '';
                  });
                },
                child: FakeGlass(
                  shape: const LiquidRoundedSuperellipse(
                    borderRadius: Radius.circular(14),
                  ),
                  settings: settings,
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    child: done
                        ? const Icon(Icons.check, size: 22, color: Colors.white)
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 18,
                              color: isCurrent ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          Text(
            'Вес (кг)',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                    child: FakeGlass(
                      shape: const LiquidRoundedSuperellipse(
                        borderRadius: Radius.circular(12),
                      ),
                      settings: GlassSettingsConstants.onLightMinimal,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: TextField(
                          controller: weightController,
                          onChanged: (val) {
                            setState(() {
                              curWeight =
                                  double.tryParse(val.replaceAll(',', '.')) ??
                                      curWeight;
                            });
                          },
                          onTapOutside: (_) => FocusScope.of(context).unfocus(),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                          textAlignVertical: TextAlignVertical.center,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SmallGlassButton(
                icon: Icons.remove,
                onTap: () {
                  setState(() {
                    curWeight = (curWeight - 2.5).clamp(0, 10000);
                    weightController.text =
                        curWeight > 0 ? curWeight.toStringAsFixed(1) : '';
                  });
                },
                settings: GlassSettingsConstants.onLightOrange,
                size: 44,
              ),
              const SizedBox(width: 6),
              SmallGlassButton(
                icon: Icons.add,
                onTap: () {
                  setState(() {
                    curWeight = (curWeight + 2.5).clamp(0, 10000);
                    weightController.text =
                        curWeight > 0 ? curWeight.toStringAsFixed(1) : '';
                  });
                },
                settings: GlassSettingsConstants.onLightBlue,
                size: 44,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Количество повторов',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                    child: FakeGlass(
                      shape: const LiquidRoundedSuperellipse(
                        borderRadius: Radius.circular(12),
                      ),
                      settings: GlassSettingsConstants.onLightMinimal,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: TextField(
                          controller: repsController,
                          onChanged: (val) {
                            setState(() {
                              curReps = int.tryParse(val) ?? curReps;
                            });
                          },
                          onTapOutside: (_) => FocusScope.of(context).unfocus(),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                          textAlignVertical: TextAlignVertical.center,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SmallGlassButton(
                icon: Icons.remove,
                onTap: () {
                  setState(() {
                    curReps = (curReps - 1).clamp(0, 1000);
                    repsController.text = curReps.toString();
                  });
                },
                settings: GlassSettingsConstants.onLightOrange,
                size: 44,
              ),
              const SizedBox(width: 6),
              SmallGlassButton(
                icon: Icons.add,
                onTap: () {
                  setState(() {
                    curReps = (curReps + 1).clamp(0, 1000);
                    repsController.text = curReps.toString();
                  });
                },
                settings: GlassSettingsConstants.onLightBlue,
                size: 44,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Заголовок без (RPE 1-10)
          Text(
            context.tr('rpe_label'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: LiquidGlassButton(
                  onPressed: () => setState(() => curRpe = 4.0),
                  height: 44,
                  settings: curRpe.round() == 4
                      ? GlassSettingsConstants.onLightGreenSelected
                      : GlassSettingsConstants.onLightMinimal,
                  child: Text(
                    context.tr('rpe_easy'),
                    style: TextStyle(
                      color: curRpe.round() == 4 ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LiquidGlassButton(
                  onPressed: () => setState(() => curRpe = 7.0),
                  height: 44,
                  settings: curRpe.round() == 7
                      ? GlassSettingsConstants.onLightOrangeSelected
                      : GlassSettingsConstants.onLightMinimal,
                  child: Text(
                    context.tr('rpe_medium'),
                    style: TextStyle(
                      color: curRpe.round() == 7 ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LiquidGlassButton(
                  onPressed: () => setState(() => curRpe = 9.0),
                  height: 44,
                  settings: curRpe.round() == 9
                      ? GlassSettingsConstants.onLightRedSelected
                      : GlassSettingsConstants.onLightMinimal,
                  child: Text(
                    context.tr('rpe_hard'),
                    style: TextStyle(
                      color: curRpe.round() == 9 ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: LiquidGlassButton(
              onPressed: () async {
                setsData[currentIndex] = {
                  'reps': curReps,
                  'weight': curWeight,
                  'rpe': curRpe,
                  'done': true,
                };
                await widget.onSaveSet(
                  currentIndex,
                  ExerciseSetExecution(
                    reps: curReps,
                    weight: curWeight,
                    rpe: curRpe,
                    done: true,
                  ),
                );
                if (currentIndex < totalSets - 1) {
                  setState(() {
                    currentIndex += 1;
                    curReps = (setsData[currentIndex]['reps'] as int?) ??
                        widget.defaultReps;
                    curWeight = (setsData[currentIndex]['weight'] as double?) ??
                        widget.defaultWeight;
                    curRpe = (setsData[currentIndex]['rpe'] as double?) ??
                        (widget.initialRpe ?? 7.0);
                    repsController.text = curReps.toString();
                    weightController.text =
                        curWeight > 0 ? curWeight.toStringAsFixed(1) : '';
                  });
                } else {
                  Navigator.of(context).pop({'setsData': setsData});
                }
              },
              height: 48,
              borderRadius: 12,
              settings: GlassSettingsConstants.onLightBlue,
              child: Text(currentIndex < totalSets - 1
                  ? context.tr('save_set')
                  : context.tr('finish_exercise')),
            ),
          ),
        ],
      ),
    );
  }
}
