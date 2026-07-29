import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';
import '../providers/chat_providers.dart';
import '../../../services/localization/app_localization_service.dart';

/// Виджет с быстрыми запросами для чата с диетологом
class QuickQueriesWidget extends ConsumerStatefulWidget {
  const QuickQueriesWidget({super.key});

  @override
  ConsumerState<QuickQueriesWidget> createState() =>
      _QuickQueriesWidgetState();
}

class _QuickQueriesWidgetState extends ConsumerState<QuickQueriesWidget> {
  late final Future<void> _displayDelay;

  @override
  void initState() {
    super.initState();
    _displayDelay = Future.delayed(const Duration(milliseconds: 1000));
  }

  @override
  Widget build(BuildContext context) {
    final quickQueries = ref.watch(quickQueriesProvider);
    final chatState = ref.watch(chatProvider);

    // Всегда показываем компактно в конце чата

    if (chatState.isLoading) {
      return const SizedBox.shrink();
    }

    // Добавляем задержку перед показом блока "Вы можете спросить"
    return FutureBuilder<void>(
      future: _displayDelay,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.help_outline,
                      size: 16,
                      color: Colors.black.withOpacity(0.6),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.tr('you_can_ask'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.black.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              // Простая вертикальная колонка как в мессенджерах
              Column(
                children: quickQueries.map((query) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _QuickQueryChip(
                      query: query,
                      isCompact: true,
                      onTap: () => _onQueryTap(ref, query),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onQueryTap(WidgetRef ref, QuickQuery query) {
    ref.read(chatProvider.notifier).sendQuickQuery(query);
  }
}

/// Виджет чипа с быстрым запросом
class _QuickQueryChip extends StatefulWidget {
  final QuickQuery query;
  final bool isCompact;
  final VoidCallback onTap;

  const _QuickQueryChip({
    required this.query,
    required this.onTap,
    this.isCompact = false,
  });

  @override
  State<_QuickQueryChip> createState() => _QuickQueryChipState();
}

class _QuickQueryChipState extends State<_QuickQueryChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: GestureDetector(
            onTapDown: (_) => _animationController.forward(),
            onTapUp: (_) {
              _animationController.reverse();
              widget.onTap();
            },
            onTapCancel: () => _animationController.reverse(),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFFE1E1E6),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            widget.query.icon,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.query.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 12,
                        color: Colors.black54,
                      ),
                    ],
                  ),
                ),
              ),
        );
      },
    );
  }
}

/// Виджет индикатора печати ИИ
class TypingIndicator extends StatefulWidget {
  final bool isVisible;

  const TypingIndicator({
    super.key,
    this.isVisible = false,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    if (widget.isVisible) {
      _animationController.forward();
    }
  }

  @override
  void didUpdateWidget(TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        if (_fadeAnimation.value == 0.0) {
          return const SizedBox.shrink();
        }

        return Opacity(
          opacity: _fadeAnimation.value,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: const Color(0xFFE1E1E6), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.psychology_outlined,
                    color: Color(0xFF2E7D32),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                ClipRRect(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                        bottomLeft: Radius.circular(6),
                      ),
                      border: Border.all(
                        color: const Color(0xFFE1E1E6),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildDot(0),
                          const SizedBox(width: 4),
                          _buildDot(200),
                          const SizedBox(width: 4),
                          _buildDot(400),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDot(int delay) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final animationValue =
            (_animationController.value * 1000 - delay) / 600;
        final opacity = (0.4 + 0.6 * (1 + math.sin(animationValue * 2)) / 2)
            .clamp(0.4, 1.0);

        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(opacity * 0.6),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      },
    );
  }
}
