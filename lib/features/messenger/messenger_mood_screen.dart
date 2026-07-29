import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'messenger_providers.dart';
import 'models/messenger_mood_state.dart';

enum _MoodAxis { joyAnger, funSadness, humorBoring }

class MessengerMoodScreen extends ConsumerStatefulWidget {
  final String contactId;
  final String contactName;

  const MessengerMoodScreen({
    super.key,
    required this.contactId,
    required this.contactName,
  });

  @override
  ConsumerState<MessengerMoodScreen> createState() =>
      _MessengerMoodScreenState();
}

class _MessengerMoodScreenState extends ConsumerState<MessengerMoodScreen> {
  MessengerMoodState? _draft;
  bool _isEditing = false;

  @override
  Widget build(BuildContext context) {
    final moodAsync = ref.watch(messengerMoodProvider(widget.contactId));
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Настроение ${widget.contactName}'),
      ),
      body: moodAsync.when(
        data: (mood) {
          if (!_isEditing) {
            _draft = mood;
          }
          final state = _draft ?? mood;
          final joyAxis = _axisValue(state.joy, state.anger);
          final funAxis = _axisValue(state.fun, state.sadness);
          final humorAxis = _axisValue(state.humor, state.boring);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                'Ползунки задают баланс эмоций. Настроение обновляется по ходу чата.',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 16),
              _MoodAxisCard(
                title: 'Радость и злость',
                leftLabel: 'Злость',
                rightLabel: 'Радость',
                leftValue: state.anger,
                rightValue: state.joy,
                axisValue: joyAxis,
                onChangeStart: (_) => _startEditing(),
                onChanged: (value) =>
                    _updateAxis(state, _MoodAxis.joyAnger, value),
                onChangeEnd: (_) => _commitDraft(),
              ),
              const SizedBox(height: 16),
              _MoodAxisCard(
                title: 'Веселье и грусть',
                leftLabel: 'Грусть',
                rightLabel: 'Веселье',
                leftValue: state.sadness,
                rightValue: state.fun,
                axisValue: funAxis,
                onChangeStart: (_) => _startEditing(),
                onChanged: (value) =>
                    _updateAxis(state, _MoodAxis.funSadness, value),
                onChangeEnd: (_) => _commitDraft(),
              ),
              const SizedBox(height: 16),
              _MoodAxisCard(
                title: 'Юмор и занудство',
                leftLabel: 'Занудство',
                rightLabel: 'Юмор',
                leftValue: state.boring,
                rightValue: state.humor,
                axisValue: humorAxis,
                onChangeStart: (_) => _startEditing(),
                onChanged: (value) =>
                    _updateAxis(state, _MoodAxis.humorBoring, value),
                onChangeEnd: (_) => _commitDraft(),
              ),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (_, __) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Не удалось загрузить настроение'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  ref
                      .read(messengerMoodProvider(widget.contactId).notifier)
                      .refresh();
                },
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startEditing() {
    if (_isEditing) return;
    setState(() {
      _isEditing = true;
    });
  }

  double _axisValue(int right, int left) {
    final value = right - left;
    if (value > 100) return 100;
    if (value < -100) return -100;
    return value.toDouble();
  }

  void _updateAxis(MessengerMoodState base, _MoodAxis axis, double value) {
    final updated = _applyAxis(base, axis, value);
    setState(() {
      _draft = updated;
    });
  }

  MessengerMoodState _applyAxis(
    MessengerMoodState base,
    _MoodAxis axis,
    double axisValue,
  ) {
    final intValue = axisValue.round().clamp(-100, 100);
    switch (axis) {
      case _MoodAxis.joyAnger:
        if (intValue >= 0) {
          return base.copyWith(
            joy: intValue,
            anger: 0,
          );
        }
        return base.copyWith(
          joy: 0,
          anger: -intValue,
        );
      case _MoodAxis.funSadness:
        if (intValue >= 0) {
          return base.copyWith(
            fun: intValue,
            sadness: 0,
          );
        }
        return base.copyWith(
          fun: 0,
          sadness: -intValue,
        );
      case _MoodAxis.humorBoring:
        if (intValue >= 0) {
          return base.copyWith(
            humor: intValue,
            boring: 0,
          );
        }
        return base.copyWith(
          humor: 0,
          boring: -intValue,
        );
    }
  }

  Future<void> _commitDraft() async {
    final draft = _draft;
    if (draft == null) return;
    await ref
        .read(messengerMoodProvider(widget.contactId).notifier)
        .setManual(draft);
    if (!mounted) return;
    setState(() {
      _isEditing = false;
    });
  }
}

class _MoodAxisCard extends StatelessWidget {
  final String title;
  final String leftLabel;
  final String rightLabel;
  final int leftValue;
  final int rightValue;
  final double axisValue;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  const _MoodAxisCard({
    required this.title,
    required this.leftLabel,
    required this.rightLabel,
    required this.leftValue,
    required this.rightValue,
    required this.axisValue,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final activeLabel = _activeLabel();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  activeLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MoodValue(label: leftLabel, value: leftValue),
              _MoodValue(
                  label: rightLabel, value: rightValue, alignRight: true),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              showValueIndicator: ShowValueIndicator.onDrag,
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            ),
            child: Slider(
              value: axisValue,
              min: -100,
              max: 100,
              divisions: 100,
              label: activeLabel,
              onChanged: onChanged,
              onChangeStart: onChangeStart,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }

  String _activeLabel() {
    final rounded = axisValue.round();
    if (rounded == 0) return 'Баланс 0';
    if (rounded > 0) {
      return '$rightLabel $rightValue';
    }
    return '$leftLabel $leftValue';
  }
}

class _MoodValue extends StatelessWidget {
  final String label;
  final int value;
  final bool alignRight;

  const _MoodValue({
    required this.label,
    required this.value,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final align =
        alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: colors.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
        ),
      ],
    );
  }
}
