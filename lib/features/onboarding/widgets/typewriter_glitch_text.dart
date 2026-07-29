import 'dart:async';
import 'package:flutter/material.dart';

/// Виджет с эффектом печатной машинки для заголовков онбоардинга
class TypewriterGlitchText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration typingSpeed;
  final bool autoStart;
  final VoidCallback? onTypingComplete;

  const TypewriterGlitchText({
    super.key,
    required this.text,
    this.style,
    this.typingSpeed = const Duration(milliseconds: 50),
    this.autoStart = true,
    this.onTypingComplete,
  });

  @override
  State<TypewriterGlitchText> createState() => _TypewriterGlitchTextState();
}

class _TypewriterGlitchTextState extends State<TypewriterGlitchText> {
  String _displayedText = '';
  Timer? _typingTimer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();

    if (widget.autoStart) {
      _startTyping();
    }
  }

  @override
  void didUpdateWidget(TypewriterGlitchText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _reset();
      if (widget.autoStart) {
        _startTyping();
      }
    }
  }

  void _reset() {
    _typingTimer?.cancel();
    setState(() {
      _currentIndex = 0;
      _displayedText = '';
    });
  }

  void _startTyping() {
    _typingTimer = Timer.periodic(widget.typingSpeed, (timer) {
      if (_currentIndex < widget.text.length) {
        setState(() {
          _currentIndex++;
          _displayedText = widget.text.substring(0, _currentIndex);
        });
      } else {
        timer.cancel();
        // Вызываем callback по завершении печати
        widget.onTypingComplete?.call();
      }
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Белая обводка (основной слой)
        Text(
          _displayedText,
          style: TextStyle(
            fontSize: widget.style?.fontSize ?? 32,
            fontWeight: widget.style?.fontWeight ?? FontWeight.w800,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = Colors.white,
          ),
        ),
        // Черный текст поверх
        Text(
          _displayedText,
          style: widget.style ??
              const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: Colors.black,
                shadows: [
                  Shadow(
                    color: Colors.black54,
                    offset: Offset(0, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
        ),
      ],
    );
  }
}
