import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:lottie/lottie.dart';
import 'package:bottom_picker/bottom_picker.dart';

import '../../features/home/home_providers.dart';
// Репозиторий подтягивается через провайдер в home_providers
import '../../models/water_entry_model.dart';
import '../../services/localization/app_localization_service.dart';
import '../../services/widgets/home_widgets_service.dart';

class WaterInputScreen extends ConsumerStatefulWidget {
  const WaterInputScreen({super.key});

  @override
  ConsumerState<WaterInputScreen> createState() => _WaterInputScreenState();
}

class _WaterInputScreenState extends ConsumerState<WaterInputScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController(text: '200');
  DateTime _time = DateTime.now();
  late final AnimationController _animController;

  int get _volume =>
      int.tryParse(_controller.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _syncLottieProgress({bool animate = true}) {
    final double progress = _mapVolumeToProgress(_volume);
    if (animate) {
      _animController.animateTo(
        progress,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    } else {
      _animController.stop();
      _animController.value = progress;
    }
  }

  double _mapVolumeToProgress(int ml) {
    if (ml <= 0) return 0.0;
    if (ml <= 50) {
      // 0..50 ml  =>  0..10%
      return (0.19 * (ml / 50.0)).clamp(0.0, 1.0);
    }
    if (ml <= 100) {
      // 50..100 ml  =>  10%..40%
      final t = (ml - 50) / 50.0;
      return (0.10 + 0.30 * t).clamp(0.0, 1.0);
    }
    if (ml <= 150) {
      // 100..150 ml =>  40%..70%
      final t = (ml - 100) / 50.0;
      return (0.30 + 0.30 * t).clamp(0.0, 1.0);
    }
    if (ml <= 200) {
      // 150..200 ml =>  70%..100%
      final t = (ml - 150) / 50.0;
      return (0.70 + 0.30 * t).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    // оставляем вычисления наверху экрана для возможного будущего использования прогресса
    // ignore: unused_local_variable
    final goalWaterMl = user?.nutritionGoals.dailyWaterMl ?? 2000;
    // ignore: unused_local_variable
    final todayTotalAsync =
        ref.watch(waterTotalForDateProvider(DateTime.now()));
    // ignore: unused_local_variable
    final todayTotalMl = todayTotalAsync.value ?? 0;

    final primary = const Color(0xFF655BBB);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('water')),
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Центрируем основной контент по вертикали
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Анимация стакана — увеличена в 1.5 раза (200 -> 300)
                      SizedBox(
                        height: 300,
                        child: Center(
                          child: Lottie.asset(
                            'assets/animations/glass_water_default.json',
                            controller: _animController,
                            onLoaded: (composition) {
                              _animController.duration = composition.duration;
                              _animController.value = 0.0;
                              _animController.forward(from: 0.0);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Блоки управления ниже
                      // Text(
                      //   context.tr('water_goal'),
                      //   style: const TextStyle(fontWeight: FontWeight.bold),
                      // ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: primary.withOpacity(0.3), width: 2),
                                borderRadius: BorderRadius.circular(16),
                                color: Colors.white,
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Row(
                                children: [
                                  _circleIconButton(Icons.remove,
                                      onPressed: () {
                                    final v = (_volume - 50).clamp(0, 8000);
                                    _controller.text = '$v';
                                    setState(() {});
                                    _syncLottieProgress();
                                  }),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _controller,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      decoration: InputDecoration(
                                        border: InputBorder.none,
                                        hintText: '0',
                                        suffixText:
                                            context.tr('ml_suffix').trim(),
                                      ),
                                      onChanged: (_) {
                                        setState(() {});
                                        _syncLottieProgress();
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _circleIconButton(Icons.add, onPressed: () {
                                    final v = (_volume + 50).clamp(0, 8000);
                                    _controller.text = '$v';
                                    setState(() {});
                                    _syncLottieProgress();
                                  }),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (final add in const [50, 100, 200]) ...[
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  final v = (_volume + add).clamp(0, 8000);
                                  _controller.text = '$v';
                                  setState(() {});
                                  _syncLottieProgress();
                                },
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                      color: primary.withOpacity(0.3),
                                      width: 2),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                ),
                                child: Text(
                                    '+$add ${context.tr('ml_suffix').trim()}'),
                              ),
                            ),
                            if (add != 200) const SizedBox(width: 12),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: () async {
                          // Открываем выбор даты/времени как на экране "Анализ еды"
                          await Future<void>.delayed(
                              const Duration(milliseconds: 1));
                          final double submitButtonWidth =
                              MediaQuery.of(context).size.width - 32;
                          BottomPicker.dateTime(
                            initialDateTime: _time,
                            minDateTime: DateTime.now()
                                .subtract(const Duration(days: 365)),
                            maxDateTime: DateTime.now(),
                            // Кастомный контент и размер кнопки подтверждения — как в экране Анализа еды
                            buttonContent: Center(
                              child: Text(
                                context.tr('select'),
                                style: const TextStyle(
                                    fontSize: 16, color: Colors.white),
                              ),
                            ),
                            buttonWidth: submitButtonWidth,
                            buttonPadding: 12,
                            use24hFormat: true,
                            buttonSingleColor: Colors.blue,
                            onSubmit: (date) async {
                              setState(() {
                                _time = date;
                              });
                            },
                          ).show(context);
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(context.tr('time_of_adding')),
                            Text(
                              '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                color: primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Кнопка сохранения — в самом низу и в стиле экрана Замеры
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _volume > 0
                        ? () async {
                            final repo = ref.read(waterRepositoryProvider);
                            await repo.addEntry(WaterEntryModel(
                              id: const Uuid().v4(),
                              volumeMl: _volume,
                              dateTime: _time,
                            ));
                            final day =
                                DateTime(_time.year, _time.month, _time.day);
                            ref.invalidate(waterTotalForDateProvider(day));
                            ref.invalidate(waterEntriesForDateProvider(day));
                            // Глобально инвалидируем семейства, чтобы обновились все слушатели
                            ref.invalidate(waterTotalForDateProvider);
                            ref.invalidate(waterEntriesForDateProvider);
                            // Обновляем виджеты через updateDailyProgressFromRepo для полной инициализации (как при добавлении еды)
                            await HomeWidgetsService
                                .updateDailyProgressFromRepo(ref);
                            if (mounted) Navigator.of(context).pop();
                          }
                        : null,
                    child: Text(
                      context.tr('save'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
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

  Widget _circleIconButton(IconData icon, {required VoidCallback onPressed}) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFEDEBFF),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: const Color(0xFF655BBB)),
      ),
    );
  }
}
