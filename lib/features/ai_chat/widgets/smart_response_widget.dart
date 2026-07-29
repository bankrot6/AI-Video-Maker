import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';
import '../providers/chat_providers.dart';
import '../utils/interactive_parser.dart';
import '../../subscription/purchase_routes.dart';
import '../../../services/localization/app_localization_service.dart';

/// Виджет умных быстрых ответов на последнее сообщение AI
/// Поддерживает как структурированные quickReplies, так и парсинг текста
class SmartResponseWidget extends ConsumerStatefulWidget {
  const SmartResponseWidget({super.key});

  @override
  ConsumerState<SmartResponseWidget> createState() =>
      _SmartResponseWidgetState();
}

class _SmartResponseWidgetState extends ConsumerState<SmartResponseWidget> {
  Timer? _delayTimer;
  String? _activeMessageId;
  bool _readyToShow = false;

  @override
  void dispose() {
    _delayTimer?.cancel();
    super.dispose();
  }

  void _resetDelayState() {
    _delayTimer?.cancel();
    _delayTimer = null;
    _activeMessageId = null;
    _readyToShow = false;
  }

  void _scheduleShow(String messageId) {
    if (_activeMessageId == messageId &&
        (_readyToShow || _delayTimer != null)) {
      return;
    }

    _delayTimer?.cancel();
    _activeMessageId = messageId;
    _readyToShow = false;
    _delayTimer = Timer(const Duration(milliseconds: 3500), () {
      if (!mounted) return;
      setState(() {
        _readyToShow = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);

    // Не показываем если загружается или чат пустой
    if (chatState.isLoading || chatState.messages.isEmpty) {
      _resetDelayState();
      return const SizedBox.shrink();
    }

    // Показываем быстрые ответы только для самого последнего сообщения AI
    final lastMessage = chatState.messages.last;
    if (lastMessage.type != MessageType.ai) {
      _resetDelayState();
      return const SizedBox.shrink();
    }

    // Приоритет: структурированные quickReplies
    List<QuickReply> quickReplies = lastMessage.quickReplies ?? [];

    // Fallback: парсим варианты из текста ТОЛЬКО если сообщение содержит явный вопрос
    if (quickReplies.isEmpty &&
        InteractiveParser.containsQuestion(lastMessage.content)) {
      final parsedOptions =
          InteractiveParser.extractOptions(lastMessage.content);
      quickReplies = parsedOptions
          .map((text) => QuickReply(
                id: 'parsed_${text.hashCode}',
                text: text,
              ))
          .toList();
    }

    // Если нет вариантов - не показываем
    if (quickReplies.isEmpty) {
      _resetDelayState();
      return const SizedBox.shrink();
    }

    if (_activeMessageId != lastMessage.id) {
      _scheduleShow(lastMessage.id);
      return const SizedBox.shrink();
    }

    if (!_readyToShow) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.touch_app, size: 14, color: Colors.black54),
                const SizedBox(width: 6),
                Text(
                  context.tr('quick_replies'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: quickReplies.map((reply) {
              return _EnhancedQuickReplyChip(
                quickReply: reply,
                onTap: () => _handleQuickReplyTap(context, ref, reply),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _handleQuickReplyTap(
      BuildContext context, WidgetRef ref, QuickReply reply) {
    // Действие: открыть экраны, иначе отправка запроса
    if (reply.isAction && reply.payload != null) {
      switch (reply.payload) {
        case 'ACTION_BUY_TOKENS':
          Navigator.of(context).push(tokenPurchaseRoute());
          return;
        case 'ACTION_GET_SUBSCRIPTION':
          Navigator.of(context).push(paywallRoute());
          return;
      }
    }

    final messageText =
        reply.isAction && reply.payload != null ? reply.payload! : reply.text;
    ref.read(chatProvider.notifier).sendMessageStreaming(messageText);
  }

}

/// Улучшенный чип для быстрого ответа с поддержкой QuickReply
class _EnhancedQuickReplyChip extends StatefulWidget {
  final QuickReply quickReply;
  final VoidCallback onTap;

  const _EnhancedQuickReplyChip({
    required this.quickReply,
    required this.onTap,
  });

  @override
  State<_EnhancedQuickReplyChip> createState() =>
      _EnhancedQuickReplyChipState();
}

class _EnhancedQuickReplyChipState extends State<_EnhancedQuickReplyChip>
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
      end: 0.96,
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
              decoration: BoxDecoration(
                color: widget.quickReply.isAction
                    ? Colors.green.shade50
                    : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: widget.quickReply.isAction
                      ? Colors.green.shade200
                      : Colors.blue.shade200,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.quickReply.isAction
                            ? Icons.play_arrow
                            : Icons.reply,
                        size: 14,
                        color: Colors.black,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          widget.quickReply.text,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
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
