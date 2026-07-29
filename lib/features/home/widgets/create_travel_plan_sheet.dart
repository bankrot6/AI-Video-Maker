import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../travel_plans_provider.dart';
import '../../onboarding/widgets/onboarding_simple_button.dart';
import '../../../widgets/days_picker.dart';
import '../../../widgets/liquid_glass_card.dart';
import '../../../services/city_limit_service.dart';
import '../../../services/localization/app_localization_service.dart';

class CreateTravelPlanSheet extends ConsumerStatefulWidget {
  const CreateTravelPlanSheet({super.key});

  @override
  ConsumerState<CreateTravelPlanSheet> createState() =>
      _CreateTravelPlanSheetState();
}

class _CreateTravelPlanSheetState extends ConsumerState<CreateTravelPlanSheet> {
  final TextEditingController _placeController = TextEditingController();
  final FocusNode _placeFocus = FocusNode();

  int _stayDays = 3;
  final Set<String> _selectedInterests = <String>{};
  bool _isCreating = false;
  String? _errorText;

  static const List<String> _interestTags = [
    'Прогулки',
    'Культура',
    'Спорт',
    'Гастро',
    'Архитектура',
    'Музеи',
    'Парки',
    'Виды',
  ];

  @override
  void dispose() {
    _placeController.dispose();
    _placeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_placeFocus.hasFocus) {
        _placeFocus.requestFocus();
      }
    });

    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Material(
            color: const Color(0xFFF2F2F7),
            child: FractionallySizedBox(
              heightFactor: 0.92,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      children: [
                        LiquidGlassCard(
                          borderRadius: 18,
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Место',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _placeController,
                                focusNode: _placeFocus,
                                textInputAction: TextInputAction.done,
                                textCapitalization: TextCapitalization.words,
                                inputFormatters: const [
                                  _WordsCapitalizationFormatter(),
                                ],
                                onSubmitted:
                                    _isCreating ? null : (_) => _submit(),
                                decoration: InputDecoration(
                                  hintText: 'Город, область или страна',
                                  prefixIcon:
                                      const Icon(Icons.location_on_outlined),
                                  filled: true,
                                  fillColor: const Color(0xFFF2F2F7),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                  errorText: _errorText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        LiquidGlassCard(
                          borderRadius: 18,
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Срок',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              IgnorePointer(
                                ignoring: _isCreating,
                                child: Opacity(
                                  opacity: _isCreating ? 0.6 : 1.0,
                                  child: DaysPicker(
                                    initialDays: _stayDays,
                                    height: 132,
                                    backgroundColor: Colors.transparent,
                                    showShadow: false,
                                    selectionColor: const Color(0xFFF2F2F7),
                                    selectionBorderColor: Colors.transparent,
                                    useSelectionOverlay: false,
                                    selectionMargin: EdgeInsets.zero,
                                    showSelectionBackgroundBehind: true,
                                    selectionBorderRadius: 14,
                                    onChanged: (value) {
                                      setState(() => _stayDays = value);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        LiquidGlassCard(
                          borderRadius: 18,
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Интересы',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _interestTags
                                    .map(
                                      (tag) => FilterChip(
                                        label: Text(tag),
                                        selected:
                                            _selectedInterests.contains(tag),
                                        showCheckmark: false,
                                        labelStyle: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color:
                                              _selectedInterests.contains(tag)
                                                  ? const Color(0xFF007AFF)
                                                  : Colors.black87,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          side: BorderSide(
                                            color:
                                                _selectedInterests.contains(tag)
                                                    ? const Color(0xFF007AFF)
                                                        .withOpacity(0.22)
                                                    : Colors.black
                                                        .withOpacity(0.08),
                                          ),
                                        ),
                                        backgroundColor:
                                            const Color(0xFFF2F2F7),
                                        selectedColor: const Color(0xFF007AFF)
                                            .withOpacity(0.12),
                                        onSelected: _isCreating
                                            ? null
                                            : (value) => setState(() {
                                                  if (value) {
                                                    _selectedInterests.add(tag);
                                                  } else {
                                                    _selectedInterests
                                                        .remove(tag);
                                                  }
                                                }),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final screenHeight = MediaQuery.of(context).size.height;
                        final bottomPadding = screenHeight > 700 ? 16.0 : 12.0;
                        return Padding(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            bottomPadding,
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: IgnorePointer(
                              ignoring: _isCreating,
                              child: Opacity(
                                opacity: _isCreating ? 0.6 : 1.0,
                                child: OnboardingSimpleButton(
                                  text: _isCreating ? 'Создаём…' : 'Сохранить',
                                  isSelected: true,
                                  onPressed: _submit,
                                  margin: EdgeInsets.zero,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 14,
                                  ),
                                  leading: _isCreating
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.black,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
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

  Future<void> _submit() async {
    if (_isCreating) return;
    FocusScope.of(context).unfocus();
    final place = _placeController.text.trim();

    setState(() {
      _errorText = place.isEmpty ? 'Введите место поездки' : null;
    });
    if (place.isEmpty) return;

    setState(() => _isCreating = true);
    try {
      final notifier = ref.read(travelPlansProvider.notifier);
      await notifier.createPlan(
        placeQuery: place,
        stayDays: _stayDays,
        interests: _selectedInterests.toList(growable: false),
        keepOriginalPlaceLabel: true,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      if (e is CityLimitException) {
        setState(() => _errorText = _formatCityLimitError(context, e.result));
      } else {
        setState(() => _errorText = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
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
}

class _WordsCapitalizationFormatter extends TextInputFormatter {
  const _WordsCapitalizationFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final updatedText = text.replaceAllMapped(
      RegExp(r"(^|[\s\-'])(\S)"),
      (match) => '${match.group(1)}${match.group(2)!.toUpperCase()}',
    );
    if (updatedText == text) return newValue;

    return newValue.copyWith(text: updatedText);
  }
}
