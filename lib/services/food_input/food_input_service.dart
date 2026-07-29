// import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:path/path.dart' as path;
// import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/nutrition_info.dart';
import '../../features/analysis/analysis_providers.dart' as analysis;
import '../../features/camera/camera_screen.dart';
import '../../features/analysis/food_analysis_screen.dart';
// import '../../widgets/loading/loading_manager.dart';
import '../../widgets/voice_input_dialog.dart';
// import '../providers.dart' as services; // больше не используется здесь
import '../../utils/usage_limit_util.dart';
import '../localization/app_localization_service.dart';
// import '../../utils/file_utils.dart';
import '../../widgets/rtl_wrapper.dart';
import '../../models/weight_entry_model.dart';
// import '../../models/meal_model.dart';
import '../../utils/measurement_system.dart';
import '../../widgets/date_selector_header.dart' as date_selector;
import 'package:flutter/services.dart';
// import '../../features/favorites/favorites_screen.dart';
import '../../features/measurements/measurements_input_screen.dart';
import '../../features/water/water_input_screen.dart';
// import '../../features/search/product_search_screen.dart';
import '../openfoodfacts/openfoodfacts_service.dart';
import '../../features/home/home_providers.dart' as home;
// import 'package:http/http.dart' as http;
// import '../../widgets/portion_input_sheet.dart';

/// Ограничивает ввод до трёх целых цифр и одной цифры после запятой/точки
class OneDecimalInputFormatter extends TextInputFormatter {
  static final _pattern = RegExp(r'^\d{0,3}(?:[.,]\d?)?');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;

    // Допускаем пустое значение
    if (text.isEmpty) return newValue;

    // Удаляем все пробелы
    final cleaned = text.replaceAll(' ', '');

    // Проверяем соответствие паттерну
    if (_pattern.hasMatch(cleaned)) {
      return newValue.copyWith(text: cleaned, selection: newValue.selection);
    }

    // Если введён лишний символ, откатываем к предыдущему значению
    return oldValue;
  }
}

/// Сервис для работы с добавлением приемов пищи
class FoodInputService {
  final WidgetRef _ref;
  final BuildContext _context;
  Function? _onFoodAddedCallback;

  /// Создает экземпляр сервиса для работы с добавлением приемов пищи
  ///
  /// Параметр ref может быть как WidgetRef, так и ProviderRef
  FoodInputService(this._ref, this._context);

  /// Открыть ввод веса (публичный метод для упрощённого FAB-меню)
  void openWeightInput() {
    _navigateToWeightInput(_context);
  }

  /// Открыть экран замеров (публичный метод для упрощённого FAB-меню)
  void openMeasurementsScreen() {
    _navigateToMeasurements(_context);
  }

  /// Переключает календарь на сегодняшний день после добавления блюда
  void _switchToTodayAfterSaving() {
    final today = DateTime.now();
    print(
        '🔄 FoodInputService: Переключение на сегодня: ${today.day}.${today.month}.${today.year}');

    // Принудительно инвалидируем провайдер, чтобы вызвать перестройку всех виджетов
    _ref.invalidate(date_selector.selectedDateProvider);

    // Теперь устанавливаем новое значение
    _ref.read(date_selector.selectedDateProvider.notifier).state = today;
    print(
        '✅ FoodInputService: Провайдер selectedDateProvider обновлен и инвалидирован');
  }

  /// Переход к экрану замеров тела
  void _navigateToMeasurements(BuildContext context) async {
    Navigator.of(context).pop();
    if (!_context.mounted) return;
    await Navigator.of(_context).push(
      MaterialPageRoute(
        builder: (context) => const MeasurementsInputScreen(),
      ),
    );
  }

  // Ввод воды больше не используется

  /// Показывает диалог выбора способа добавления приема пищи
  void showAddFoodOptions({Function? onFoodAdded}) async {
    // Сохраняем колбэк, если он предоставлен
    _onFoodAddedCallback = onFoodAdded;

    // Ранний показ сообщения об оставшихся попытках перенесен в логику сохранения еды

    // Очищаем предыдущие данные анализа
    _clearAnalysisData();

    // Показываем нижнее меню с вариантами ввода
    if (_context.mounted) {
      showModalBottomSheet(
        context: _context,
        builder: (context) => _buildAddFoodBottomSheet(context),
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      );
    }
  }

  /// Публичный метод: открыть диалог голосового ввода напрямую
  void openVoiceInputDialog() {
    final context = _context;
    if (!context.mounted) return;
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          width: double.infinity,
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: VoiceInputDialog(
            onRecognized: (text) {
              Navigator.of(context).pop();
              _navigateToVoiceInput(context, text);
            },
          ),
        );
      },
    );
  }

  /// Публичный метод: запустить поток камеры напрямую
  void startCameraFlow() {
    final context = _context;
    if (!context.mounted) return;
    () async {
      // Проверяем лимиты использования перед переходом к камере
      final canProceed = await UsageLimitUtil.checkUsageLimitBeforeAction(
          context, _ref,
          showRemainingUsagesWarning: true,
          actionName: context.tr('take_photo'),
          suppressFailureSnack: true);

      if (!canProceed) {
        if (context.mounted) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/home', (route) => false, arguments: {
            'show_limit_message': true,
          });
        }
        return;
      }

      // Очищаем предыдущие данные анализа
      _clearAnalysisData();

      final currentContext = context;
      if (!currentContext.mounted) return;

      Navigator.of(currentContext)
          .push(
        MaterialPageRoute(builder: (context) => const CameraScreen()),
      )
          .then((_) async {
        if (currentContext.mounted) {
          if (_onFoodAddedCallback != null) {
            _onFoodAddedCallback!();
          }
          await Future.delayed(const Duration(milliseconds: 100));
          _switchToTodayAfterSaving();
        }
      });
    }();
  }

  /// Публичный метод: открыть экран воды напрямую
  void openWaterScreen() {
    final context = _context;
    if (!context.mounted) return;
    // Открываем без предварительного pop, так как при вызове из виджета
    // на стеке нет нижнего листа и pop может привести к пустому стэку.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const WaterInputScreen(),
      ),
    );
  }

  /// Публичный метод: открыть текстовый ввод напрямую
  void openTextInput() {
    final context = _context;
    if (!context.mounted) return;
    // Создаем контроллер для текстового поля
    final textController = TextEditingController();
    final offService = OpenFoodFactsService();
    List<OpenFoodFactsProduct> suggestions = const [];

    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.tr('enter_dish_name'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: TextField(
                      controller: textController,
                      decoration: InputDecoration(
                        hintText: context.tr('dish_example'),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (v) async {
                        if (v.trim().length < 2) {
                          suggestions = const [];
                          (context as Element).markNeedsBuild();
                          return;
                        }
                        // динамический поиск по названию в OFF
                        final items =
                            await offService.searchByName(v, limit: 10);
                        suggestions = items;
                        (context as Element).markNeedsBuild();
                      },
                      autofocus: true,
                      textDirection: context.textDirection,
                      textAlign:
                          context.isRTL ? TextAlign.right : TextAlign.left,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (suggestions.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: suggestions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final p = suggestions[i];
                          final subtitle =
                              '${p.kcalPer100g.toStringAsFixed(0)} ккал';
                          return ListTile(
                            leading:
                                const Icon(Icons.fastfood, color: Colors.grey),
                            title: Text(p.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(subtitle,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                            onTap: () async {
                              // при выборе из подсказок сразу анализ по названию
                              Navigator.pop(context, p.name);
                            },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          context.tr('cancel'),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          final text = textController.text;
                          if (text.isNotEmpty) {
                            Navigator.pop(context, text);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          context.tr('done'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
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
    ).then((dishName) async {
      if (dishName != null && dishName.isNotEmpty) {
        final currentContext = _context;
        if (!currentContext.mounted) return NutritionInfo.empty();

        _ref.read(analysis.nutritionAnalysisStateProvider.notifier).state =
            const AsyncValue.loading();
        _ref.read(analysis.lastAnalysisResultsProvider.notifier).state = null;
        _ref.read(analysis.manualFoodInputProvider.notifier).state = dishName;

        await Navigator.of(currentContext).push(
          MaterialPageRoute(
            builder: (context) => const FoodAnalysisScreen(isTextInput: true),
          ),
        );

        if (currentContext.mounted) {
          if (_onFoodAddedCallback != null) {
            _onFoodAddedCallback!();
          }
          Future.delayed(const Duration(milliseconds: 100), () {
            _switchToTodayAfterSaving();
          });
        }
        return NutritionInfo.empty();
      }
    });
  }

  /// Создает нижнюю панель для добавления приема пищи
  Widget _buildAddFoodBottomSheet(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr('add_to_journal'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildBottomSheetOption(
                    icon: Icons.monitor_weight,
                    label: context.tr('change_weight'),
                    onTap: () => _navigateToWeightInput(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildBottomSheetOption(
                    icon: Icons.straighten,
                    label: context.tr('body_measurements'),
                    onTap: () => _navigateToMeasurements(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Создает элемент в нижней панели добавления приема пищи
  Widget _buildBottomSheetOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 90, // Фиксированная высота для всех кнопок
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Theme.of(_context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                icon,
                color: Theme.of(_context).primaryColor,
                size: 28,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height:
                  22, // Фиксированная высота для текста (14px * 1.5 line height ≈ 22px)
              child: Text(
                label,
                style: const TextStyle(fontSize: 14),
                textAlign: TextAlign.center,
                maxLines: 1, // Ограничиваем одной строкой
                overflow: TextOverflow.ellipsis, // Обрезаем длинный текст
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Вспомогательные кнопки OFF/штрих-кода удалены

  // Навигация штрих-кода удалена

  // Навигация поиска продуктов удалена

  // Запрос порции удалён

  // Сохранение выбранного продукта (OFF) удалено

  // Кэширование изображений продуктов удалено

  /// Создает кнопку для голосового ввода
  // Кнопка голосового ввода удалена

  // Переход к экрану камеры (удалён)

  // Переход к галерее (удалён)

  // Переход к текстовому вводу (удалён)

  /// Метод для очистки данных анализа
  void _clearAnalysisData() {
    _ref.read(analysis.nutritionAnalysisStateProvider.notifier).state =
        AsyncValue.data(NutritionInfo.empty());
    _ref.read(analysis.selectedImageProvider.notifier).state = null;
    _ref.read(analysis.manualFoodInputProvider.notifier).state = "";
  }

  /// Обработка голосового ввода
  void _navigateToVoiceInput(
      BuildContext context, String recognizedText) async {
    // Открываем экран анализа текста с распознанным текстом
    if (recognizedText.isNotEmpty) {
      // Проверяем лимиты использования перед переходом к анализу
      final canProceed = await UsageLimitUtil.checkUsageLimitBeforeAction(
          _context, _ref,
          showRemainingUsagesWarning: true,
          actionName: context.tr('describe_food'),
          suppressFailureSnack: true);

      if (!canProceed) {
        if (_context.mounted) {
          Navigator.of(_context)
              .pushNamedAndRemoveUntil('/home', (route) => false, arguments: {
            'show_limit_message': true,
          });
        }
        return;
      }

      // Сначала очищаем предыдущие данные анализа
      _clearAnalysisData();

      // Сохраняем текущий контекст для безопасного использования
      final currentContext = _context;
      if (!currentContext.mounted) return;

      // Инициализируем состояние под стрим и сохраняем текст
      _ref.read(analysis.nutritionAnalysisStateProvider.notifier).state =
          const AsyncValue.loading();
      _ref.read(analysis.lastAnalysisResultsProvider.notifier).state = null;
      _ref.read(analysis.manualFoodInputProvider.notifier).state =
          recognizedText;

      if (!currentContext.mounted) return;

      // Мгновенно переходим на экран анализа; стрим запустится в initState
      Navigator.of(currentContext)
          .push(
        MaterialPageRoute(
          builder: (context) => const FoodAnalysisScreen(isVoiceInput: true),
        ),
      )
          .then((_) {
        // После возврата из голосового ввода сначала колбэк, потом переключение даты
        if (currentContext.mounted) {
          if (_onFoodAddedCallback != null) {
            _onFoodAddedCallback!();
          }
          // Небольшая задержка перед переключением даты
          Future.delayed(const Duration(milliseconds: 100), () {
            _switchToTodayAfterSaving(); // Переключаем календарь на сегодняшний день
          });
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('speech_not_recognized')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Переход к вводу веса
  void _navigateToWeightInput(BuildContext context) async {
    Navigator.of(context).pop();

    // Определяем систему измерения
    final measurementSystem = MeasurementUtils.getDefaultMeasurementSystem();

    // Текущий вес пользователя в кг
    final currentUser = _ref.read(home.currentUserProvider);
    final currentWeightKg = currentUser?.weight ?? 70.0;

    // Отображаем в выбранной системе
    final double initialDisplayWeight =
        measurementSystem == MeasurementSystem.imperial
            ? MeasurementUtils.kgToLbs(currentWeightKg)
            : currentWeightKg;

    final controller =
        TextEditingController(text: initialDisplayWeight.toStringAsFixed(1));

    final newDisplayWeight = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(bottomContext).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    bottomContext.tr('change_weight'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [OneDecimalInputFormatter()],
                      decoration: InputDecoration(
                        hintText: bottomContext.tr('weight_example'),
                        suffixText: bottomContext.tr(
                            measurementSystem == MeasurementSystem.imperial
                                ? 'weight_suffix_imperial'
                                : 'weight_suffix'),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      textDirection: bottomContext.textDirection,
                      textAlign: bottomContext.isRTL
                          ? TextAlign.right
                          : TextAlign.left,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(bottomContext),
                        child: Text(
                          bottomContext.tr('cancel'),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          final value = double.tryParse(
                              controller.text.replaceAll(',', '.'));
                          if (value != null && value > 0) {
                            Navigator.pop(bottomContext, value);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          bottomContext.tr('done'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
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

    if (newDisplayWeight != null) {
      // Преобразуем вес обратно в кг при необходимости
      final double weightKg = measurementSystem == MeasurementSystem.imperial
          ? MeasurementUtils.lbsToKg(newDisplayWeight)
          : newDisplayWeight;
      await _saveNewWeight(weightKg);
    }
  }

  /// Переход к экрану избранного
  // Навигация в избранное удалена

  Future<void> _saveNewWeight(double weight) async {
    final user = _ref.read(home.currentUserProvider);
    if (user == null) return;

    // Обновляем пользователя
    final updatedUser = user.copyWith(weight: weight);
    final userRepository = _ref.read(home.userRepositoryProvider);
    await userRepository.updateUser(updatedUser);
    _ref.read(home.currentUserProvider.notifier).setUser(updatedUser);

    // Сохраняем запись веса в историю
    final weightRepository = _ref.read(home.weightRepositoryProvider);
    await weightRepository.addWeightEntry(
      WeightEntryModel(
        id: const Uuid().v4(),
        weight: weight,
        dateTime: DateTime.now(),
      ),
    );
  }

  // Метод склонения использований удален как неиспользуемый (перенос логики показа)
}
