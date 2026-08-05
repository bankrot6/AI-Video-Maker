import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/credit_config.dart';
import '../../models/generation_task.dart';
import '../../models/image_generation_request.dart';
import '../../models/photo_session_preset.dart';
import '../../models/photosession_provider.dart';
import '../../models/preset_tag.dart';
import '../../providers/credit_providers.dart';
import '../../services/apibost_model_catalog.dart';
import '../subscription/purchase_routes.dart';
import '../subscription/subscription_providers.dart';
import 'background_generation_provider.dart';
import 'photosession_generation_screen.dart';
import 'photosession_support_error.dart';
import 'theme/photosession_palette.dart';
import 'theme/photosession_theme_scope.dart';
import 'widgets/model_selection.dart';
import 'widgets/option_chips_row.dart';

/// Генерация видео по готовому промпту пользователя.
///
/// В отличие от создания по описанию промпт не проходит через LLM: текст уходит
/// в модель как есть, поэтому экран содержит только само поле, формат кадра,
/// выбор модели и запуск.
class ManualPromptCreationScreen extends ConsumerStatefulWidget {
  const ManualPromptCreationScreen({super.key});

  @override
  ConsumerState<ManualPromptCreationScreen> createState() =>
      _ManualPromptCreationScreenState();
}

class _ManualPromptCreationScreenState
    extends ConsumerState<ManualPromptCreationScreen> {
  /// Ниже этой длины промпт не описывает сцену, и модель выдаёт случайный кадр.
  static const int _minPromptLength = 12;

  static const String _promptHint =
      'Опишите кадр так, как хотите видеть его в модели: главный объект, '
      'его движение в течение 8 секунд, окружение, работу камеры, свет и звук.\n\n'
      'Текст уйдёт в модель без изменений — ИИ его не дополняет.';

  final _promptController = TextEditingController();
  final _promptFocus = FocusNode();

  ImageFormat _selectedFormat = ImageFormat.story;
  PhotosessionProvider _selectedProvider = PhotosessionProvider.veoFast;
  String? _error;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _promptController.addListener(_onPromptChanged);
  }

  @override
  void dispose() {
    _promptController.removeListener(_onPromptChanged);
    _promptController.dispose();
    _promptFocus.dispose();
    super.dispose();
  }

  void _onPromptChanged() {
    // Кнопка запуска зависит от заполненности поля, поэтому перерисовываем её.
    if (mounted) setState(() {});
  }

  String get _prompt => _promptController.text.trim();

  bool get _isPromptReady => _prompt.length >= _minPromptLength;

  /// Заголовок карточки в галерее: первая строка промпта.
  String get _title {
    final firstLine = _prompt.split('\n').first.trim();
    final source = firstLine.isEmpty ? _prompt : firstLine;
    if (source.length <= 50) return source;
    return '${source.substring(0, 50).trimRight()}…';
  }

  bool get _keyboardVisible => MediaQuery.viewInsetsOf(context).bottom > 0;

  Future<void> _pickModel() async {
    final selected = await showModelSelectionSheet(
      context: context,
      selected: _selectedProvider,
    );
    if (selected != null && mounted) {
      setState(() => _selectedProvider = selected);
    }
  }

  Future<void> _startGeneration() async {
    if (!_isPromptReady) {
      setState(
        () => _error = 'Опишите сцену подробнее — так модель поймёт задачу',
      );
      return;
    }

    setState(() {
      _error = null;
      _starting = true;
    });

    final prompt = _prompt;
    final title = _title;
    final tempPreset = PhotoSessionPreset(
      id: 'image_${DateTime.now().millisecondsSinceEpoch}',
      prompt: prompt,
      previewImageUrl: '',
      title: title,
      tags: [PresetTag.idCustom],
      imageStyle: ImageStyle.auto.id,
      createdAt: DateTime.now(),
    );

    try {
      final result =
          await ref.read(backgroundGenerationProvider.notifier).startGeneration(
                preset: tempPreset,
                prompt: prompt,
                provider: _selectedProvider,
                taskType: GenerationTaskType.userImage,
                aspectRatio: _selectedFormat.aspectRatio,
                generatedImageData: GeneratedImageData(
                  prompt: prompt,
                  title: title,
                  imageStyle: ImageStyle.auto.id,
                ),
              );

      if (!mounted) return;
      setState(() => _starting = false);

      if (!result.isSuccess) {
        switch (result.reason) {
          case 'tier_locked':
            await Navigator.of(context).push(paywallRoute());
          case 'insufficient_credits':
            await Navigator.of(context).push(tokenPurchaseRoute());
          default:
            _showError(creditReservationFailureMessage(result.reason));
        }
        return;
      }

      await Navigator.of(context).push(
        photosessionRoute(
          PhotosessionGenerationScreen(taskId: result.taskId!),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      _showError(normalizePhotosessionErrorMessage(e.toString()));
    }
  }

  void _showError(String message) {
    final palette = PhotosessionPalette.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: palette.danger),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return PhotosessionThemeScope(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: colors.surfaceContainerLowest,
          foregroundColor: colors.onSurface,
          surfaceTintColor: Colors.transparent,
          title: const Text(
            'Свой промпт',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
          ),
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Клавиатура забирает почти всю высоту: с чипами формата
                      // полю остаётся меньше строки, и текст вылезает за рамку.
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: _keyboardVisible
                            ? const SizedBox.shrink()
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  OptionChipsRow<ImageFormat>(
                                    title: 'Формат',
                                    values: ImageFormatX.videoFormats,
                                    selected: _selectedFormat,
                                    labelOf: (value) =>
                                        '${value.label} · ${value.aspectRatio}',
                                    onSelected: (value) =>
                                        setState(() => _selectedFormat = value),
                                  ),
                                  const SizedBox(height: 14),
                                ],
                              ),
                      ),
                      Expanded(child: _buildPromptField(theme, colors)),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        _buildErrorBox(colors),
                      ],
                    ],
                  ),
                ),
              ),
              _buildBottomBar(colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromptField(ThemeData theme, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Промпт',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${_promptController.text.characters.length} / '
              '${ApiBostModelCatalog.maxVideoPromptTextLength}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TextField(
            controller: _promptController,
            focusNode: _promptFocus,
            expands: true,
            maxLines: null,
            minLines: null,
            maxLength: ApiBostModelCatalog.maxVideoPromptTextLength,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            textAlignVertical: TextAlignVertical.top,
            textCapitalization: TextCapitalization.sentences,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            scrollPadding: const EdgeInsets.only(top: 24, bottom: 320),
            decoration: InputDecoration(
              // Счётчик выведен над полем: встроенный не помещается в поле,
              // растянутое на всю доступную высоту.
              counterText: '',
              hintText: _promptHint,
              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                height: 1.45,
                color: colors.onSurface.withValues(alpha: 0.45),
              ),
              alignLabelWithHint: true,
              contentPadding: const EdgeInsets.all(14),
              filled: true,
              fillColor: colors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: colors.outline.withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.primary, width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBox(ColorScheme colors) {
    final palette = PhotosessionPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: palette.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(color: colors.onSurface, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme colors) {
    final palette = PhotosessionPalette.of(context);
    final usage = ref.watch(creditUsageNotifierProvider).valueOrNull;
    final hasPaidSubscription =
        ref.watch(subscriptionProvider).valueOrNull?.isPaidUser ?? false;
    final isTierLocked = !CreditCost.isTierAccessible(
      _selectedProvider.creditTier,
      hasPaidSubscription: hasPaidSubscription,
    );
    final hasEnoughCredits =
        usage == null || usage.hasEnoughCredits(_selectedProvider.creditCost);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ModelSelectorButton(
            selected: _selectedProvider,
            onPressed: _pickModel,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 56,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: !_isPromptReady || _starting
                  ? null
                  : isTierLocked
                      ? () => Navigator.of(context).push(paywallRoute())
                      : !hasEnoughCredits
                          ? () =>
                              Navigator.of(context).push(tokenPurchaseRoute())
                          : _startGeneration,
              icon: Icon(
                isTierLocked || !hasEnoughCredits
                    ? Icons.account_balance_wallet_rounded
                    : Icons.auto_fix_high,
                size: 24,
              ),
              label: Text(
                isTierLocked
                    ? 'Нужен PRO'
                    : !hasEnoughCredits
                        ? 'Купить кредиты'
                        : 'Создать за ${_selectedProvider.creditCost} кредитов',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.onAccent,
                disabledBackgroundColor: palette.surface,
                disabledForegroundColor: palette.textSecondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
