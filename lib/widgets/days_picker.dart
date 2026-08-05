import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class DaysPicker extends StatefulWidget {
  final int initialDays;
  final int minValue;
  final int maxValue;
  final ValueChanged<int> onChanged;
  final double height;
  final Color backgroundColor;
  final bool showShadow;
  final Color? selectionColor;
  final Color? selectionBorderColor;
  final bool useSelectionOverlay;
  final EdgeInsetsGeometry selectionMargin;
  final bool showSelectionBackgroundBehind;
  final double selectionBorderRadius;

  const DaysPicker({
    super.key,
    required this.initialDays,
    required this.onChanged,
    this.minValue = 1,
    this.maxValue = 30,
    this.height = 152,
    this.backgroundColor = Colors.white,
    this.showShadow = true,
    this.selectionColor,
    this.selectionBorderColor,
    this.useSelectionOverlay = true,
    this.selectionMargin = const EdgeInsets.symmetric(horizontal: 20),
    this.showSelectionBackgroundBehind = false,
    this.selectionBorderRadius = 12,
  });

  @override
  State<DaysPicker> createState() => _DaysPickerState();
}

class _DaysPickerState extends State<DaysPicker> {
  late FixedExtentScrollController _controller;
  late int _selectedIndex;

  int get _minValue => widget.minValue;
  int get _maxValue =>
      widget.maxValue < widget.minValue ? widget.minValue : widget.maxValue;
  int get _itemCount => _maxValue - _minValue + 1;

  @override
  void initState() {
    super.initState();
    final initialValue =
        widget.initialDays.clamp(_minValue, _maxValue).toInt();
    final initialIndex = initialValue - _minValue;
    _selectedIndex = initialIndex;
    _controller = FixedExtentScrollController(initialItem: initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final selectionColor = widget.selectionColor ?? accent.withOpacity(0.08);
    final selectionBorderColor =
        widget.selectionBorderColor ?? accent.withOpacity(0.35);
    final selectionBackground = Center(
      child: Container(
        height: 44,
        margin: widget.selectionMargin,
        decoration: BoxDecoration(
          color: selectionColor,
          borderRadius: BorderRadius.circular(widget.selectionBorderRadius),
          border: Border.all(color: selectionBorderColor),
        ),
      ),
    );
    final picker = CupertinoPicker(
      itemExtent: 44,
      useMagnifier: true,
      magnification: 1.1,
      selectionOverlay: widget.useSelectionOverlay
          ? selectionBackground
          : const SizedBox.shrink(),
      scrollController: _controller,
      onSelectedItemChanged: (index) {
        if (_selectedIndex != index) {
          setState(() => _selectedIndex = index);
        }
        widget.onChanged(_minValue + index);
      },
      children: List<Widget>.generate(_itemCount, (index) {
        final days = _minValue + index;
        final isSelected = index == _selectedIndex;
        final text = AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          style: TextStyle(
            fontSize: isSelected ? 34 : 28,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color:
                isSelected ? Colors.black : Colors.black.withOpacity(0.35),
          ),
          child: Text('$days'),
        );
        if (!widget.useSelectionOverlay &&
            isSelected &&
            !widget.showSelectionBackgroundBehind) {
          return Padding(
            padding: widget.selectionMargin,
            child: Container(
              width: double.infinity,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selectionColor,
                borderRadius:
                    BorderRadius.circular(widget.selectionBorderRadius),
                border: Border.all(color: selectionBorderColor),
              ),
              child: text,
            ),
          );
        }
        return Center(child: text);
      }),
    );
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: widget.showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: widget.showSelectionBackgroundBehind
          ? Stack(
              alignment: Alignment.center,
              children: [
                selectionBackground,
                picker,
              ],
            )
          : picker,
    );
  }
}
