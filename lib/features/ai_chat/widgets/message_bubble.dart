import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/chat_message.dart';
import '../../../services/localization/app_localization_service.dart';

/// Виджет пузырька сообщения в стиле WhatsApp
class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;
  final VoidCallback? onTouch; // Callback для обработки касаний
  final VoidCallback? onVoiceToggle;
  final bool isVoicePlaying;
  final bool isVoiceAvailable;

  const MessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onDelete,
    this.onTouch,
    this.onVoiceToggle,
    this.isVoicePlaying = false,
    this.isVoiceAvailable = true,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _cursorAnimationController;
  late Animation<double> _cursorAnimation;
  // Audio playback removed

  @override
  void initState() {
    super.initState();
    _cursorAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _cursorAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _cursorAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // Запускаем анимацию курсора для streaming сообщений
    if (widget.message.metadata?['streaming'] == true) {
      _cursorAnimationController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Управляем анимацией в зависимости от состояния streaming
    if (widget.message.metadata?['streaming'] == true) {
      if (!_cursorAnimationController.isAnimating) {
        _cursorAnimationController.repeat(reverse: true);
      }
    } else {
      _cursorAnimationController.stop();
    }
  }

  @override
  void dispose() {
    _cursorAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.type == MessageType.user;
    final isSystem = widget.message.type == MessageType.system;
    final isAi = widget.message.type == MessageType.ai;

    if (isSystem) {
      return _buildSystemMessage(context);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) _buildAiAvatar(),
          if (!isUser) const SizedBox(width: 8),
          Flexible(
            child: GestureDetector(
              onTap: () => widget.onTouch?.call(),
              onPanStart: (_) => widget.onTouch?.call(),
              onPanUpdate: (_) => widget.onTouch?.call(),
              onLongPress: () => _showMessageOptions(context),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: isUser
                        ? const Color(0xFFE7F0FF)
                        : Colors.white,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMessageContent(isUser),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (isAi) ...[
                            _buildVoiceToggleButton(),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            _formatTime(widget.message.timestamp),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                          if (isUser) ...[
                            const SizedBox(width: 4),
                            _buildMessageStatus(),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (isUser) _buildUserAvatar(),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          widget.message.content,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black54,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceToggleButton() {
    final isEnabled = widget.onVoiceToggle != null && widget.isVoiceAvailable;
    final isPlaying = widget.isVoicePlaying;
    final baseColor = const Color(0xFF2E7D32);
    final activeColor = isPlaying ? Colors.red : baseColor;
    final backgroundColor = isPlaying
        ? Colors.red.withValues(alpha: 0.1)
        : baseColor.withValues(alpha: 0.1);

    return GestureDetector(
      onTap: isEnabled ? widget.onVoiceToggle : null,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.5,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: activeColor.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Icon(
            isPlaying ? Icons.stop : Icons.play_arrow,
            size: 18,
            color: isEnabled ? activeColor : Colors.black26,
          ),
        ),
      ),
    );
  }

  Widget _buildAiAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E1E6), width: 1),
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
    );
  }

  Widget _buildUserAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E1E6), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(
        Icons.person_outline,
        color: Color(0xFF1565C0),
        size: 18,
      ),
    );
  }

  Widget _buildMessageStatus() {
    IconData icon;

    switch (widget.message.status) {
      case MessageStatus.sending:
        icon = Icons.access_time;
        break;
      case MessageStatus.sent:
        icon = Icons.check;
        break;
      case MessageStatus.delivered:
        icon = Icons.done_all;
        break;
      case MessageStatus.error:
        icon = Icons.error_outline;
        break;
    }

    return Icon(icon, size: 16, color: Colors.black54);
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDate == today) {
      return DateFormat.Hm().format(dateTime);
    } else {
      return DateFormat.MMMd().format(dateTime);
    }
  }

  void _showMessageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(context.tr('copy')),
              onTap: () {
                Clipboard.setData(ClipboardData(text: widget.message.content));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.tr('text_copied')),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            if (widget.message.status == MessageStatus.error &&
                widget.onRetry != null)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text(context.tr('retry_sending')),
                onTap: () {
                  Navigator.pop(context);
                  widget.onRetry?.call();
                },
              ),
            if (widget.onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(context.tr('delete'),
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  widget.onDelete?.call();
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Строит содержимое сообщения с поддержкой markdown-форматирования и streaming
  Widget _buildMessageContent(bool isUser) {
    const textColor = Colors.black; // Чёрный текст по требованию
    const baseStyle = TextStyle(
      fontSize: 16,
      color: textColor,
      height: 1.4,
    );

    // Показываем загрузку в пользовательском пузыре пока идет распознавание
    final isTranscribing = widget.message.type == MessageType.user &&
        (widget.message.metadata?['transcribing'] == true);
    if (isTranscribing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.black)),
          ),
          const SizedBox(width: 8),
          Text('...', style: baseStyle),
        ],
      );
    }

    final isStreaming = widget.message.metadata?['streaming'] == true;
    final isAi = widget.message.type == MessageType.ai;

    // Контент: AI с markdown, остальные — простой текст
    final Widget contentWidget = isAi
        ? RichText(
            text: TextSpan(
              style: baseStyle,
              children:
                  _parseStreamingMarkdown(widget.message.content, baseStyle),
            ),
          )
        : Text(
            widget.message.content,
            style: baseStyle,
          );

    if (isStreaming) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: contentWidget),
          AnimatedBuilder(
            animation: _cursorAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: _cursorAnimation.value,
                child: Container(
                  width: 2,
                  height: 16,
                  margin: const EdgeInsets.only(left: 4, top: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              );
            },
          ),
        ],
      );
    }

    return contentWidget;
  }

  /// Упрощенный парсинг markdown для streaming (устойчивый к незавершенному markdown)
  List<TextSpan> _parseStreamingMarkdown(String text, TextStyle baseStyle) {
    final List<TextSpan> spans = [];
    // Нормализуем markdown перед обработкой
    final normalizedText = _normalizeMarkdown(text);
    final lines = normalizedText.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (i > 0) spans.add(const TextSpan(text: '\n'));

      // Обрабатываем markdown элементы в порядке приоритета
      if (_hasCompleteHeaders(line)) {
        // Заголовки ### Заголовок
        spans.addAll(_parseCompleteHeaders(line, baseStyle));
      } else if (_hasCompleteBlockquote(line)) {
        // Цитаты > текст
        spans.addAll(_parseCompleteBlockquote(line, baseStyle));
      } else if (_hasCompleteCodeBlock(line)) {
        // Инлайн код `код`
        spans.addAll(_parseCompleteCodeBlock(line, baseStyle));
      } else if (_hasCompleteBoldMarkdown(line) ||
          _hasCompleteItalicMarkdown(line)) {
        // Комбинированная обработка жирного и курсивного текста
        spans.addAll(_parseCompleteMarkdownText(line, baseStyle));
      } else if (_hasCompleteStrikethrough(line)) {
        // Зачеркнутый текст ~~текст~~
        spans.addAll(_parseCompleteStrikethrough(line, baseStyle));
      } else if (_hasCompleteList(line)) {
        // Списки - элемент, * элемент, 1. элемент, - [ ] задача
        spans.addAll(_parseCompleteList(line, baseStyle));
      } else if (_hasCompleteLink(line)) {
        // Ссылки [текст](url) и автоссылки
        spans.addAll(_parseCompleteLink(line, baseStyle));
      } else if (_hasCompleteHorizontalRule(line)) {
        // Горизонтальные линии --- или ***
        spans.addAll(_parseCompleteHorizontalRule(line, baseStyle));
      } else {
        // Обычный текст (включая незавершенный markdown)
        // Скрываем незавершенные markdown символы для лучшего UX
        spans.addAll(_parsePartialMarkdown(line, baseStyle));
      }
    }

    return spans;
  }

  /// Проверяет есть ли завершенный жирный markdown в строке
  bool _hasCompleteBoldMarkdown(String line) {
    final matches = RegExp(r'\*\*([^*]+)\*\*').allMatches(line);
    return matches.isNotEmpty;
  }

  /// Проверяет есть ли завершенный курсив markdown в строке
  bool _hasCompleteItalicMarkdown(String line) {
    // Проверяем одиночные звездочки, но не двойные
    final matches = RegExp(r'(?<!\*)\*([^*]+)\*(?!\*)').allMatches(line);
    return matches.isNotEmpty;
  }

  /// Проверяет есть ли завершенные заголовки
  bool _hasCompleteHeaders(String line) {
    final trimmed = line.trim();
    // Поддерживаем как ### Заголовок, так и ###Заголовок
    // Заголовок должен начинаться с 1-6 символов # и содержать текст
    if (!trimmed.startsWith('#')) return false;

    final match = RegExp(r'^(#{1,6})\s*(.+)').firstMatch(trimmed);
    return match != null && (match.group(2)?.trim().isNotEmpty ?? false);
  }

  /// Проверяет есть ли завершенная цитата
  bool _hasCompleteBlockquote(String line) {
    return line.trim().startsWith('> ');
  }

  /// Проверяет есть ли завершенный инлайн код
  bool _hasCompleteCodeBlock(String line) {
    final matches = RegExp(r'`([^`]+)`').allMatches(line);
    return matches.isNotEmpty;
  }

  /// Проверяет есть ли завершенный зачеркнутый текст
  bool _hasCompleteStrikethrough(String line) {
    final matches = RegExp(r'~~([^~]+)~~').allMatches(line);
    return matches.isNotEmpty;
  }

  /// Проверяет есть ли завершенный список
  bool _hasCompleteList(String line) {
    final trimmed = line.trim();
    return trimmed.startsWith('- ') ||
        trimmed.startsWith('* ') ||
        trimmed.startsWith('+ ') ||
        RegExp(r'^\d+\.\s').hasMatch(trimmed) ||
        trimmed.startsWith('- [ ]') ||
        trimmed.startsWith('- [x]');
  }

  /// Проверяет есть ли завершенная ссылка
  bool _hasCompleteLink(String line) {
    final linkMatches = RegExp(r'\[([^\]]+)\]\(([^)]+)\)').allMatches(line);
    final urlMatches = RegExp(r'https?://[^\s]+').allMatches(line);
    return linkMatches.isNotEmpty || urlMatches.isNotEmpty;
  }

  /// Проверяет есть ли горизонтальная линия
  bool _hasCompleteHorizontalRule(String line) {
    // Отключаем отображение горизонтальных линий в чате
    return false;
  }

  /// Комбинированная обработка жирного и курсивного текста
  List<TextSpan> _parseCompleteMarkdownText(String line, TextStyle baseStyle) {
    final List<TextSpan> spans = [];
    int currentIndex = 0;

    // Найдем все markdown элементы и отсортируем по позиции
    final allMatches = <_MarkdownMatch>[];

    // Добавляем жирный текст **текст**
    final boldRegex = RegExp(r'\*\*([^*]+)\*\*');
    final boldMatches = boldRegex.allMatches(line);
    allMatches
        .addAll(boldMatches.map((m) => _MarkdownMatch(m, _MarkdownType.bold)));

    // Добавляем курсив *текст* (исключая уже найденный жирный)
    final italicRegex = RegExp(r'(?<!\*)\*([^*]+)\*(?!\*)');
    for (final match in italicRegex.allMatches(line)) {
      // Проверяем что этот match не перекрывается с жирным текстом
      bool overlaps = false;
      for (final boldMatch in boldRegex.allMatches(line)) {
        if (match.start >= boldMatch.start && match.end <= boldMatch.end) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) {
        allMatches.add(_MarkdownMatch(match, _MarkdownType.italic));
      }
    }

    // Сортируем по позиции
    allMatches.sort((a, b) => a.match.start.compareTo(b.match.start));

    // Обрабатываем по порядку
    for (final markdownMatch in allMatches) {
      final match = markdownMatch.match;

      // Добавляем текст до текущего match
      if (match.start > currentIndex) {
        final beforeText = line.substring(currentIndex, match.start);
        if (beforeText.isNotEmpty) {
          spans.add(TextSpan(text: beforeText, style: baseStyle));
        }
      }

      // Добавляем форматированный текст
      final formattedText = match.group(1) ?? '';
      final textStyle = markdownMatch.type == _MarkdownType.bold
          ? baseStyle.copyWith(fontWeight: FontWeight.bold)
          : baseStyle.copyWith(fontStyle: FontStyle.italic);

      spans.add(TextSpan(text: formattedText, style: textStyle));
      currentIndex = match.end;
    }

    // Добавляем оставшийся текст
    if (currentIndex < line.length) {
      final remainingText = line.substring(currentIndex);
      if (remainingText.isNotEmpty) {
        spans.add(TextSpan(text: remainingText, style: baseStyle));
      }
    }

    return spans;
  }

  /// Обрабатывает заголовки ### Заголовок
  List<TextSpan> _parseCompleteHeaders(String line, TextStyle baseStyle) {
    // Поддерживаем как ### Заголовок, так и ###Заголовок
    final match = RegExp(r'^(#{1,6})\s*(.+)').firstMatch(line.trim());
    if (match == null) return [TextSpan(text: line, style: baseStyle)];

    final level = match.group(1)?.length ?? 1;
    final text = match.group(2) ?? '';

    // Размеры заголовков (H1 самый большой, H6 самый маленький)
    final headerSizes = [24.0, 20.0, 18.0, 16.0, 14.0, 12.0]; // H1-H6
    final headerSize = headerSizes[level - 1];

    return [
      TextSpan(
        text: text,
        style: baseStyle.copyWith(
          fontSize: headerSize,
          fontWeight: FontWeight.bold,
          height: 1.2,
        ),
      ),
    ];
  }

  /// Обрабатывает цитаты > текст
  List<TextSpan> _parseCompleteBlockquote(String line, TextStyle baseStyle) {
    final text = line.trim().substring(2); // Убираем "> "
    return [
      TextSpan(
        text: '❝ $text',
        style: baseStyle.copyWith(
          fontStyle: FontStyle.italic,
          color: baseStyle.color?.withOpacity(0.8),
        ),
      ),
    ];
  }

  /// Обрабатывает инлайн код `код`
  List<TextSpan> _parseCompleteCodeBlock(String line, TextStyle baseStyle) {
    final List<TextSpan> spans = [];
    final codeRegex = RegExp(r'`([^`]+)`');
    int lastEnd = 0;

    for (final match in codeRegex.allMatches(line)) {
      // Добавляем текст до кода
      if (match.start > lastEnd) {
        final beforeText = line.substring(lastEnd, match.start);
        if (beforeText.isNotEmpty) {
          spans.add(TextSpan(text: beforeText, style: baseStyle));
        }
      }

      // Добавляем код
      final codeText = match.group(1) ?? '';
      spans.add(TextSpan(
        text: codeText,
        style: baseStyle.copyWith(
          fontFamily: 'monospace',
          backgroundColor: Colors.grey.withOpacity(0.1),
          fontSize: (baseStyle.fontSize ?? 16) * 0.9,
        ),
      ));

      lastEnd = match.end;
    }

    // Добавляем оставшийся текст
    if (lastEnd < line.length) {
      final remainingText = line.substring(lastEnd);
      if (remainingText.isNotEmpty) {
        spans.add(TextSpan(text: remainingText, style: baseStyle));
      }
    }

    return spans;
  }

  /// Обрабатывает зачеркнутый текст ~~текст~~
  List<TextSpan> _parseCompleteStrikethrough(String line, TextStyle baseStyle) {
    final List<TextSpan> spans = [];
    final strikeRegex = RegExp(r'~~([^~]+)~~');
    int lastEnd = 0;

    for (final match in strikeRegex.allMatches(line)) {
      // Добавляем текст до зачеркивания
      if (match.start > lastEnd) {
        final beforeText = line.substring(lastEnd, match.start);
        if (beforeText.isNotEmpty) {
          spans.add(TextSpan(text: beforeText, style: baseStyle));
        }
      }

      // Добавляем зачеркнутый текст
      final strikeText = match.group(1) ?? '';
      spans.add(TextSpan(
        text: strikeText,
        style: baseStyle.copyWith(
          decoration: TextDecoration.lineThrough,
        ),
      ));

      lastEnd = match.end;
    }

    // Добавляем оставшийся текст
    if (lastEnd < line.length) {
      final remainingText = line.substring(lastEnd);
      if (remainingText.isNotEmpty) {
        spans.add(TextSpan(text: remainingText, style: baseStyle));
      }
    }

    return spans;
  }

  /// Обрабатывает списки
  List<TextSpan> _parseCompleteList(String line, TextStyle baseStyle) {
    final trimmed = line.trim();
    String listMarker = '';
    String listText = '';

    if (trimmed.startsWith('- [ ]')) {
      listMarker = '☐ ';
      listText = trimmed.substring(5);
    } else if (trimmed.startsWith('- [x]')) {
      listMarker = '☑ ';
      listText = trimmed.substring(5);
    } else if (trimmed.startsWith('- ') ||
        trimmed.startsWith('* ') ||
        trimmed.startsWith('+ ')) {
      listMarker = '• ';
      listText = trimmed.substring(2);
    } else {
      final numberMatch = RegExp(r'^(\d+)\.\s(.*)').firstMatch(trimmed);
      if (numberMatch != null) {
        listMarker = '${numberMatch.group(1)}. ';
        listText = numberMatch.group(2) ?? '';
      } else {
        return [TextSpan(text: line, style: baseStyle)];
      }
    }

    return [
      TextSpan(
        text: listMarker,
        style: baseStyle.copyWith(fontWeight: FontWeight.w600),
      ),
      TextSpan(
        text: listText,
        style: baseStyle,
      ),
    ];
  }

  /// Обрабатывает ссылки [текст](url) и автоссылки
  List<TextSpan> _parseCompleteLink(String line, TextStyle baseStyle) {
    final List<TextSpan> spans = [];
    int lastEnd = 0;

    // Обрабатываем [текст](url) ссылки
    final linkRegex = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
    final urlRegex = RegExp(r'https?://[^\s]+');

    final allMatches = <_LinkMatch>[];

    // Добавляем markdown ссылки
    for (final match in linkRegex.allMatches(line)) {
      allMatches.add(_LinkMatch(match, _LinkType.markdown));
    }

    // Добавляем автоссылки (URL которые не перекрываются с markdown)
    for (final match in urlRegex.allMatches(line)) {
      bool overlaps = false;
      for (final linkMatch in linkRegex.allMatches(line)) {
        if (match.start >= linkMatch.start && match.end <= linkMatch.end) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) {
        allMatches.add(_LinkMatch(match, _LinkType.auto));
      }
    }

    // Сортируем по позиции
    allMatches.sort((a, b) => a.match.start.compareTo(b.match.start));

    for (final linkMatch in allMatches) {
      final match = linkMatch.match;

      // Добавляем текст до ссылки
      if (match.start > lastEnd) {
        final beforeText = line.substring(lastEnd, match.start);
        if (beforeText.isNotEmpty) {
          spans.add(TextSpan(text: beforeText, style: baseStyle));
        }
      }

      // Добавляем ссылку
      String linkText = '';
      if (linkMatch.type == _LinkType.markdown) {
        linkText = match.group(1) ?? '';
      } else {
        linkText = match.group(0) ?? '';
      }

      spans.add(TextSpan(
        text: linkText,
        style: baseStyle.copyWith(
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
      ));

      lastEnd = match.end;
    }

    // Добавляем оставшийся текст
    if (lastEnd < line.length) {
      final remainingText = line.substring(lastEnd);
      if (remainingText.isNotEmpty) {
        spans.add(TextSpan(text: remainingText, style: baseStyle));
      }
    }

    return spans;
  }

  /// Обрабатывает горизонтальные линии
  List<TextSpan> _parseCompleteHorizontalRule(
      String line, TextStyle baseStyle) {
    return [
      TextSpan(
        text: '─────────────────────',
        style: baseStyle.copyWith(
          color: baseStyle.color?.withValues(alpha: 0.3),
          fontWeight: FontWeight.w100,
        ),
      ),
    ];
  }

  /// Обрабатывает частичный/незавершенный markdown
  List<TextSpan> _parsePartialMarkdown(String line, TextStyle baseStyle) {
    // Умное скрытие markdown символов для лучшего UX
    String displayLine = line;

    // Если строка начинается с ** и содержит текст после них, показываем как жирный
    if (RegExp(r'^\*\*\s*[\p{L}\p{N}]+', unicode: true).hasMatch(line)) {
      final textAfterStars = line.replaceFirst(RegExp(r'^\*\*\s*'), '');
      if (textAfterStars.trim().isNotEmpty) {
        return [
          TextSpan(
            text: textAfterStars,
            style: baseStyle.copyWith(fontWeight: FontWeight.bold),
          )
        ];
      }
    }

    // Если строка начинается с ### и содержит текст, показываем как заголовок
    if (RegExp(r'^#{1,6}\s*[\p{L}\p{N}]+', unicode: true).hasMatch(line)) {
      final match = RegExp(r'^(#{1,6})\s*(.+)').firstMatch(line);
      if (match != null) {
        final level = match.group(1)?.length ?? 1;
        final text = match.group(2) ?? '';
        final headerSizes = [24.0, 20.0, 18.0, 16.0, 14.0, 12.0];
        final headerSize = headerSizes[level - 1];

        return [
          TextSpan(
            text: text,
            style: baseStyle.copyWith(
              fontSize: headerSize,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          )
        ];
      }
    }

    // Убираем только "пустые" markdown символы без текста
    displayLine = displayLine.replaceAll(RegExp(r'^\*{1,2}$'), '');
    displayLine = displayLine.replaceAll(RegExp(r'^#{1,6}$'), '');
    displayLine = displayLine.replaceAll(RegExp(r'^\*{1,2}\s*$'), '');
    displayLine = displayLine.replaceAll(RegExp(r'^#{1,6}\s*$'), '');

    return [TextSpan(text: displayLine, style: baseStyle)];
  }

  /// Нормализует markdown символы для корректной обработки
  String _normalizeMarkdown(String text) {
    String result = text;

    // Исправляем случаи, когда AI генерирует ### без пробела
    result = result.replaceAllMapped(RegExp(r'^(#{1,6})([^\s#])'),
        (match) => '${match.group(1)} ${match.group(2)}');

    // Убираем лишние символы перед заголовками
    result = result.replaceAllMapped(
        RegExp(r'^([^#]*?)(#{1,6}\s+.+)$', multiLine: true), (match) {
      final prefix = match.group(1)?.trim() ?? '';
      final header = match.group(2) ?? '';
      // Если перед заголовком только emoji или пробелы, оставляем как есть
      if (prefix.isEmpty ||
          RegExp(r'^[\s🔹📋💭❓🎯⚖️📊🔥🥜👨‍🍳📅💧]+$').hasMatch(prefix)) {
        return '${match.group(1)}$header';
      }
      return match.group(0) ?? '';
    });

    return result;
  }
}

/// Типы markdown форматирования
enum _MarkdownType { bold, italic }

/// Хелпер класс для markdown match
class _MarkdownMatch {
  final RegExpMatch match;
  final _MarkdownType type;

  _MarkdownMatch(this.match, this.type);
}

/// Типы ссылок
enum _LinkType { markdown, auto }

/// Хелпер класс для ссылок
class _LinkMatch {
  final RegExpMatch match;
  final _LinkType type;

  _LinkMatch(this.match, this.type);
}
