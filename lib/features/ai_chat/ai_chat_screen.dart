import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/chat_message.dart';
import 'providers/chat_providers.dart';
import '../../providers/token_providers.dart' as token_providers;
import '../../providers/token_providers.dart';
import 'widgets/message_bubble.dart';
import 'widgets/message_input.dart';
import 'widgets/quick_queries_widget.dart';
import 'widgets/no_tokens_notice_widget.dart';
import 'widgets/smart_response_widget.dart';
import 'widgets/chat_drawer.dart';

import '../../services/localization/app_localization_service.dart';
import '../../features/subscription/purchase_routes.dart';
import '../../utils/no_stretch_scroll_behavior.dart';
import '../../services/text_to_speech/tts_providers.dart';
import '../../services/text_to_speech/streaming_tts_orchestrator.dart';
import '../../utils/text_cleaner.dart';

/// Экран чата с ИИ‑другом с встроенной поддержкой восстановления позиции скролла
class AiChatScreen extends ConsumerStatefulWidget {
  final bool isActive;

  const AiChatScreen({super.key, this.isActive = true});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Простая и надежная логика автопрокрутки (как в Telegram/WhatsApp)
  bool _userIsScrolling = false;
  bool _autoScrollEnabled = true;

  // Для сохранения позиции скролла
  bool _scrollPositionRestored = false;

  // Флаг первого автоскролла при открытии
  bool _initialAutoScrolled = false;

  // Throttling для streaming
  DateTime _lastAutoScrollTime = DateTime.now();
  static const Duration _autoScrollThrottle = Duration(milliseconds: 200);

  String? _currentPlayingMessageId;
  Timer? _playbackMonitorTimer;
  final Set<String> _autoSpokenMessageIds = {};
  bool _initialAutoSpeechDone = false;
  StreamingTtsOrchestrator? _streamingTts;
  String? _streamingSpeechMessageId;
  String _lastStreamingSpeechText = '';
  bool _streamingSpeechFinal = false;

  @override
  void initState() {
    super.initState();
    // Подписываемся на события жизненного цикла приложения
    WidgetsBinding.instance.addObserver(this);

    // Настраиваем listener для детекции пользовательской прокрутки
    _setupScrollListener();

    // Обрабатываем начальное состояние после первого кадра
  }

  @override
  void didUpdateWidget(covariant AiChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isActive && !widget.isActive) {
      unawaited(_stopSpeechPlayback());
      return;
    }

    if (!oldWidget.isActive && widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.isActive) return;
        final currentState = ref.read(chatProvider);
        _handleAutoSpeech(null, currentState);
      });
    }
  }

  @override
  void dispose() {
    // Отписываемся от наблюдателя
    WidgetsBinding.instance.removeObserver(this);
    // Сохраняем позицию скролла в SharedPreferences
    _saveScrollPositionToPrefs();
    _playbackMonitorTimer?.cancel();
    unawaited(_stopSpeechPlayback(updateState: false));
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);

    // Cкролл вниз один раз при открытии, если сообщений больше чем одно
    if (!_initialAutoScrolled && chatState.messages.length > 1) {
      _initialAutoScrolled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottomOnFirstLoad();
      });
    }

    // Слушаем изменения для автоскролла
    ref.listen<ChatState>(chatProvider, (previous, current) {
      _handleChatStateChange(previous, current);
    });

    // Передаем BuildContext в провайдер для показа диалогов
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(chatProvider.notifier).setBuildContext(context);
    });
    final serviceAvailability = ref.watch(serviceAvailabilityProvider);

    return WillPopScope(
      onWillPop: () async {
        _saveScrollPositionToPrefs();
        await _stopSpeechPlayback();
        return true;
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        extendBodyBehindAppBar: true,
        extendBody: true,
        resizeToAvoidBottomInset: false,
        appBar: null,
        drawer: const ChatDrawer(),
        body: Stack(
          children: [
            // Светлый фон как в онбординге
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                ),
              ),
            ),
            // Основной контент
            serviceAvailability.when(
              data: (isAvailable) {
                if (!isAvailable) {
                  return _buildErrorState();
                }
                return _buildChatBody(context, chatState);
              },
              loading: () => _buildLoadingState(),
              error: (error, stack) => _buildErrorState(),
            ),

            // Плавающие кнопки меню и "Назад"
            Positioned(
              left: 12,
              top: 0,
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFE1E1E6),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _scaffoldKey.currentState?.openDrawer(),
                          customBorder: const CircleBorder(),
                          child: const Icon(Icons.menu, color: Colors.black),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFE1E1E6),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _handleCloseChat,
                          customBorder: const CircleBorder(),
                          child: const Icon(Icons.close, color: Colors.black),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Плавающий виджет токенов (капсула, допускает большую ширину/триал)
            Positioned(
              right: 12,
              top: 0,
              child: SafeArea(
                bottom: false,
                child: _FloatingTokenCapsule(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Капсула токенов с чёрным текстом и поддержкой триала
  Widget _buildTokenCapsuleContent(BuildContext context) {
    final tokenUsageAsync =
        ref.watch(token_providers.tokenUsageNotifierProvider);
    final subscriptionInfoAsync = ref.watch(subscriptionTokensProvider);

    final String subscriptionType = subscriptionInfoAsync.when(
      data: (data) => (data['subscriptionType'] ?? 'free') as String,
      loading: () => 'free',
      error: (_, __) => 'free',
    );

    return tokenUsageAsync.when(
      data: (usage) {
        final isTrial = subscriptionType.toLowerCase().contains('trial');
        String format(int n) {
          if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
          if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}k';
          return n.toString();
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt, size: 16, color: Colors.black),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  format(usage.remainingTokens),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                if (isTrial)
                  Text(
                    context.tr('trial'),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black.withOpacity(0.6),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            const Icon(Icons.add_circle_outline, size: 16, color: Colors.black),
          ],
        );
      },
      loading: () => Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.black)),
          SizedBox(width: 8),
          Text('…', style: TextStyle(color: Colors.black)),
        ],
      ),
      error: (e, st) => Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.error_outline, size: 16, color: Colors.black),
          SizedBox(width: 6),
          Text('error', style: TextStyle(color: Colors.black)),
        ],
      ),
    );
  }

  /// Обёртка капсулы токенов
  Widget _FloatingTokenCapsule() {
    return Container(
      height: 48,
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
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Открываем экран покупки токенов через провайдер из TokenCounterWidget
            Navigator.of(context).push(tokenPurchaseRoute());
          },
          borderRadius: BorderRadius.circular(18),
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _buildTokenCapsuleContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildChatBody(BuildContext context, ChatState chatState) {
    final tokenUsageAsync =
        ref.watch(token_providers.tokenUsageNotifierProvider);
    final subscriptionInfoAsync = ref.watch(subscriptionTokensProvider);

    final String subscriptionType = subscriptionInfoAsync.when(
      data: (data) => (data['subscriptionType'] ?? 'free') as String,
      loading: () => 'free',
      error: (_, __) => 'free',
    );

    final bool hasTokens = tokenUsageAsync.when(
      data: (usage) => usage.remainingTokens > 0,
      loading: () => true,
      error: (_, __) => true,
    );

    return Stack(
      children: [
        // Основной контент
        SafeArea(
          bottom: false,
          child: _KeyboardAwareChatList(
            scrollController: _scrollController,
            onUserTouch: _handleUserTouch,
            onPanStart: (_) => _handleUserPanStart(),
            onPanUpdate: (_) => _handleUserPanUpdate(),
            onPanEnd: (_) => _handleUserPanEnd(),
            itemCount:
                chatState.messages.length + (chatState.isTyping ? 1 : 0) + 2,
            itemBuilder: (context, index) {
              // Показываем сообщения сначала
              if (index < chatState.messages.length) {
                final message = chatState.messages[index];

                return Column(
                  key: ValueKey(message.id),
                  children: [
                    RepaintBoundary(
                      child: MessageBubble(
                        message: message,
                        onVoiceToggle: _canToggleSpeech(message)
                            ? () => _toggleMessageSpeech(message)
                            : null,
                        isVoicePlaying: _currentPlayingMessageId == message.id,
                        isVoiceAvailable: _isSpeechAvailable(message),
                        onRetry: message.status == MessageStatus.error
                            ? () => ref
                                .read(chatProvider.notifier)
                                .retryMessage(message.id)
                            : null,
                        onDelete: () => ref
                            .read(chatProvider.notifier)
                            .deleteMessage(message.id),
                        onTouch: _handleUserTouch,
                      ),
                    ),

                  ],
                );
              }

              // Учитываем смещение индекса после сообщений
              final extraIndex = index - chatState.messages.length;

              // Показываем индикатор печати
              if (!hasTokens && extraIndex == 0) {
                // Нет токенов – показываем сообщение с кнопками
                return NoTokensNoticeWidget(subscriptionType: subscriptionType);
              }

              if (chatState.isTyping && extraIndex == 0) {
                return GestureDetector(
                  onTap: _handleUserTouch,
                  onPanStart: (_) => _handleUserPanStart(),
                  onPanUpdate: (_) => _handleUserPanUpdate(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: TypingIndicator(isVisible: true),
                  ),
                );
              }

              // Показываем умные ответы на вопросы AI
              if (hasTokens && extraIndex == (chatState.isTyping ? 1 : 0)) {
                return GestureDetector(
                  onTap: _handleUserTouch,
                  onPanStart: (_) => _handleUserPanStart(),
                  onPanUpdate: (_) => _handleUserPanUpdate(),
                  child: const SmartResponseWidget(),
                );
              }

              // Показываем популярные вопросы в самом конце - ТОЛЬКО если чат пустой
              if (extraIndex == (chatState.isTyping ? 2 : 1) && hasTokens) {
                // Показываем только если есть только приветственное сообщение
                final shouldShowQuickQueries = _isEmptyChat(chatState.messages);

                if (shouldShowQuickQueries) {
                  return GestureDetector(
                    onTap: _handleUserTouch,
                    onPanStart: (_) => _handleUserPanStart(),
                    onPanUpdate: (_) => _handleUserPanUpdate(),
                    child: const QuickQueriesWidget(),
                  );
                }
              }

              return const SizedBox.shrink();
            },
          ),
        ),

        // Кнопка прокрутки вниз — круглая
        Positioned(
          bottom: 120,
          right: 16,
          child: AnimatedBuilder(
            animation: _scrollController,
            builder: (context, child) {
              final shouldShow = _scrollController.hasClients &&
                  !_autoScrollEnabled &&
                  _scrollController.position.maxScrollExtent > 0 &&
                  (_scrollController.position.maxScrollExtent -
                          _scrollController.position.pixels) >
                      100;

              return AnimatedOpacity(
                opacity: shouldShow ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: shouldShow
                    ? Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFE1E1E6),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              _autoScrollEnabled = true;
                              _userIsScrolling = false;
                              _scrollToBottomSmooth();
                            },
                            customBorder: const CircleBorder(),
                            child: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              );
            },
          ),
        ),

        // Градиентная маска над полем ввода при открытой клавиатуре
        _KeyboardAwareFadeMask(),

        // Поле ввода — поверх блюра, у самого низа (изолирован от MediaQuery rebuild)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _KeyboardAwareMessageInput(
            onSendMessage: _sendMessage,
            isLoading: chatState.isLoading,
            enabled: !chatState.isLoading,
          ),
        ),
      ],
    );
  }

  bool _isEmptyChat(List<ChatMessage> messages) {
    if (messages.isEmpty) return true;
    if (messages.length == 1) {
      final message = messages.first;
      return message.type == MessageType.ai &&
          message.metadata?['isWelcome'] == true;
    }
    return false;
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.black)),
          const SizedBox(height: 16),
          Text(
            context.tr('connecting_to_ai_dietitian'),
            style: const TextStyle(fontSize: 16, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.black.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('service_temporarily_unavailable'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('please_try_later_or_check_internet'),
              style: const TextStyle(fontSize: 14, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => ref.refresh(serviceAvailabilityProvider),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.refresh, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          context.tr('retry'),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendMessage(String message) {
    ref.read(chatProvider.notifier).sendMessageStreaming(message);
    _scrollToBottomSmooth();
  }

  void _handleCloseChat() {
    final navigator = Navigator.of(context);
    unawaited(_stopSpeechPlayback());
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  /// Простая детекция пользовательского скролла
  void _setupScrollListener() {
    _scrollController.addListener(() {
      // Если пользователь скроллит - выключаем автопрокрутку
      if (_scrollController.position.isScrollingNotifier.value) {
        _userIsScrolling = true;
        _autoScrollEnabled = false;
      }

      // Если пользователь добрался до самого низа - включаем автопрокрутку
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final currentScroll = _scrollController.position.pixels;
        // Увеличили порог до 100px чтобы учесть кнопки
        if (maxScroll - currentScroll < 100) {
          _autoScrollEnabled = true;
          _userIsScrolling = false;
        }
      }
    });
  }

  /// Обработка любого касания - мгновенная остановка автопрокрутки
  void _handleUserTouch() {
    _autoScrollEnabled = false;
    _userIsScrolling = true;
  }

  /// Обработка начала скролла
  void _handleUserPanStart() {
    _autoScrollEnabled = false;
    _userIsScrolling = true;
  }

  /// Обработка процесса скролла
  void _handleUserPanUpdate() {
    _autoScrollEnabled = false;
    _userIsScrolling = true;
  }

  /// Обработка завершения скролла
  void _handleUserPanEnd() {
    // Автопрокрутка включится автоматически если пользователь доскроллил до низа
  }

  /// Простая проверка - можно ли автопрокручивать
  bool _canAutoScroll() {
    return _autoScrollEnabled && !_userIsScrolling;
  }

  /// Простая обработка изменений состояния чата
  void _handleChatStateChange(ChatState? previous, ChatState current) {
    // Восстанавливаем позицию при первом появлении сообщений
    if (!_scrollPositionRestored && current.messages.isNotEmpty) {
      _tryRestoreScrollPosition(current.messages);
    }

    // Новое сообщение пользователя - всегда прокручиваем
    if (previous != null &&
        current.messages.length > previous.messages.length) {
      final newMessage = current.messages.last;
      if (newMessage.type == MessageType.user) {
        _autoScrollEnabled = true;
        _userIsScrolling = false;
        _scrollToBottomSmooth();
        return;
      }
    }

    // Streaming - прокручиваем только если автопрокрутка включена
    if (current.isTyping && _canAutoScroll()) {
      _handleStreamingScroll();
    }

    _handleAutoSpeech(previous, current);
  }

  String? _prepareSpeechText(ChatMessage message) {
    if (message.type != MessageType.ai) return null;
    if (message.metadata?['error'] == true) return null;
    final cleaned =
        TextCleaner.cleanForSpeechPreserveContent(message.content).trim();
    final noEmojis = TextCleaner.removeEmojis(cleaned).trim();
    if (noEmojis.isEmpty) return null;
    return noEmojis;
  }

  bool _isSpeechAvailable(ChatMessage message) {
    return _prepareSpeechText(message) != null;
  }

  bool _canToggleSpeech(ChatMessage message) {
    if (!_isSpeechAvailable(message)) return false;
    if (message.metadata?['streaming'] == true) {
      return _currentPlayingMessageId == message.id;
    }
    return true;
  }

  Future<void> _toggleMessageSpeech(ChatMessage message) async {
    final ttsService = ref.read(attractionTTSServiceProvider);
    final isPlaying = ttsService.isPlaying || ttsService.hasQueuedItems;

    if (_currentPlayingMessageId == message.id && isPlaying) {
      await _stopSpeechPlayback();
      return;
    }

    if (!_canToggleSpeech(message)) return;

    await _startSpeechPlayback(message);
  }

  Future<void> _startSpeechPlayback(ChatMessage message) async {
    final cleaned = _prepareSpeechText(message);
    if (cleaned == null) return;

    await _stopSpeechPlayback();

    if (!mounted) return;
    setState(() {
      _currentPlayingMessageId = message.id;
    });

    final ttsService = ref.read(attractionTTSServiceProvider);
    if (cleaned.length < 20) {
      unawaited(ttsService.speak(cleaned, languageCode: 'ru-RU'));
    } else {
      await ttsService.addToQueue(cleaned, languageCode: 'ru-RU');
    }

    _startPlaybackMonitor();
  }

  void _startPlaybackMonitor() {
    _playbackMonitorTimer?.cancel();
    _playbackMonitorTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        final ttsService = ref.read(attractionTTSServiceProvider);
        final isPlaying = ttsService.isPlaying || ttsService.hasQueuedItems;

        if (!isPlaying) {
          if (_currentPlayingMessageId != null) {
            setState(() {
              _currentPlayingMessageId = null;
            });
          }
          if (_streamingSpeechFinal && _streamingTts != null) {
            _resetStreamingSpeech();
          }
          if (_currentPlayingMessageId == null &&
              (_streamingTts == null || _streamingSpeechFinal)) {
            timer.cancel();
          }
          return;
        }
      },
    );
  }

  Future<void> _stopSpeechPlayback({bool updateState = true}) async {
    _playbackMonitorTimer?.cancel();
    _playbackMonitorTimer = null;

    if (updateState && mounted) {
      setState(() {
        _currentPlayingMessageId = null;
      });
    } else {
      _currentPlayingMessageId = null;
    }

    _resetStreamingSpeech();

    try {
      final ttsService = ref.read(attractionTTSServiceProvider);
      await ttsService.stop();
      await ttsService.clearQueue();
    } catch (_) {}
  }

  void _resetStreamingSpeech() {
    _streamingTts?.dispose();
    _streamingTts = null;
    _streamingSpeechMessageId = null;
    _lastStreamingSpeechText = '';
    _streamingSpeechFinal = false;
  }

  void _handleAutoSpeech(ChatState? previous, ChatState current) {
    if (current.messages.isEmpty) {
      _autoSpokenMessageIds.clear();
      _initialAutoSpeechDone = false;
      return;
    }

    if (!widget.isActive) {
      return;
    }

    if (_handleStreamingSpeech(previous, current)) {
      return;
    }

    if (!_initialAutoSpeechDone) {
      final hasUserMessages = current.messages.any(
        (message) =>
            message.type == MessageType.user ||
            message.type == MessageType.voice,
      );
      final handledWelcome = _tryAutoSpeakWelcome(current);
      if (handledWelcome || hasUserMessages) {
        _initialAutoSpeechDone = true;
      }
    }

    final candidate = _findAutoSpeechCandidate(previous, current);
    if (candidate == null) return;
    if (_autoSpokenMessageIds.contains(candidate.id)) return;

    _autoSpokenMessageIds.add(candidate.id);
    unawaited(_startSpeechPlayback(candidate));
  }

  bool _tryAutoSpeakWelcome(ChatState current) {
    final welcome = _findWelcomeMessage(current);
    if (welcome == null) return false;

    final alreadySpoken = welcome.metadata?['autoSpoken'] == true;
    if (alreadySpoken || _autoSpokenMessageIds.contains(welcome.id)) {
      return true;
    }

    _autoSpokenMessageIds.add(welcome.id);
    ref.read(chatProvider.notifier).markMessageAutoSpoken(welcome.id);
    unawaited(_startSpeechPlayback(welcome));
    return true;
  }

  ChatMessage? _findWelcomeMessage(ChatState current) {
    for (final message in current.messages) {
      if (message.type == MessageType.ai &&
          message.metadata?['isWelcome'] == true) {
        return message;
      }
    }
    return null;
  }

  bool _handleStreamingSpeech(ChatState? previous, ChatState current) {
    if (!widget.isActive) return false;

    ChatMessage? candidate;
    bool isFinal = false;

    final previousById = previous == null
        ? <String, ChatMessage>{}
        : {for (final message in previous.messages) message.id: message};

    for (final message in current.messages) {
      if (message.type != MessageType.ai) continue;
      final prevMessage = previousById[message.id];
      final wasStreaming = prevMessage?.metadata?['streaming'] == true;
      final isStreaming = message.metadata?['streaming'] == true;
      if (isStreaming || wasStreaming) {
        candidate = message;
        isFinal = !isStreaming;
      }
    }

    if (candidate == null) return false;
    final message = candidate;

    final cleaned = _prepareSpeechText(message);
    if (cleaned == null) {
      if (_streamingSpeechMessageId == message.id) {
        _resetStreamingSpeech();
        if (_currentPlayingMessageId == message.id) {
          if (mounted) {
            setState(() {
              _currentPlayingMessageId = null;
            });
          } else {
            _currentPlayingMessageId = null;
          }
        }
      }
      _autoSpokenMessageIds.add(message.id);
      return true;
    }

    if (_streamingSpeechMessageId != message.id) {
      unawaited(_stopSpeechPlayback(updateState: false));
      _resetStreamingSpeech();
      _streamingSpeechMessageId = message.id;
      _lastStreamingSpeechText = '';
    }

    if (_currentPlayingMessageId != message.id) {
      if (mounted) {
        setState(() {
          _currentPlayingMessageId = message.id;
        });
      } else {
        _currentPlayingMessageId = message.id;
      }
    }

    if (cleaned == _lastStreamingSpeechText && !_streamingSpeechFinal) {
      return true;
    }

    _lastStreamingSpeechText = cleaned;
    _streamingSpeechFinal = isFinal;
    _autoSpokenMessageIds.add(message.id);

    final ttsService = ref.read(attractionTTSServiceProvider);
    _streamingTts ??= StreamingTtsOrchestrator(
      tts: ttsService,
      languageCode: 'ru-RU',
      minStartBufferChars: 180,
      targetQueueChunks: 3,
      maxQueueChunks: 8,
      minChunkChars: 80,
      maxChunkChars: 320,
      softLookAheadChars: 140,
    );

    _startPlaybackMonitor();
    unawaited(_streamingTts!.updateFullText(cleaned, isFinal: isFinal));
    return true;
  }

  ChatMessage? _findAutoSpeechCandidate(
      ChatState? previous, ChatState current) {
    if (previous == null) return null;

    final previousById = {
      for (final message in previous.messages) message.id: message
    };

    ChatMessage? candidate;
    for (final message in current.messages) {
      if (!_canToggleSpeech(message)) continue;

      final previousMessage = previousById[message.id];
      final wasStreaming = previousMessage?.metadata?['streaming'] == true;
      final isNewMessage = previousMessage == null;
      final finishedStreaming =
          wasStreaming && message.metadata?['streaming'] != true;

      if (isNewMessage || finishedStreaming) {
        candidate = message;
      }
    }

    return candidate;
  }

  /// Простая прокрутка во время streaming
  void _handleStreamingScroll() {
    final now = DateTime.now();
    if (now.difference(_lastAutoScrollTime) < _autoScrollThrottle) {
      return; // Throttling
    }

    _lastAutoScrollTime = now;
    _scrollToBottomSoft();
  }

  /// Плавная прокрутка вниз с учетом кнопок
  void _scrollToBottomSmooth() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController
            .animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        )
            .then((_) {
          // После анимации ждем еще немного и доскроливаем до реального конца
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_scrollController.hasClients) {
              final finalMaxExtent = _scrollController.position.maxScrollExtent;
              if (finalMaxExtent > _scrollController.position.pixels) {
                _scrollController.animateTo(
                  finalMaxExtent,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            }
          });
        });
      }
    });
  }

  /// Быстрая прокрутка для streaming с учетом кнопок
  void _scrollToBottomSoft() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController
            .animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        )
            .then((_) {
          // Для streaming делаем более быстрый доскролл
          Future.delayed(const Duration(milliseconds: 50), () {
            if (_scrollController.hasClients) {
              _scrollController
                  .jumpTo(_scrollController.position.maxScrollExtent);
            }
          });
        });
      }
    });
  }

  /// Надежная прокрутка при первой загрузке с несколькими попытками
  void _scrollToBottomOnFirstLoad() {
    // Первая попытка - немедленно после следующего кадра
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptScrollToBottom(0);
    });
  }

  /// Попытка прокрутки с повторами если необходимо
  void _attemptScrollToBottom(int attempt) {
    if (attempt > 15) return; // Еще больше попыток для кнопок

    if (_scrollController.hasClients &&
        _scrollController.position.maxScrollExtent > 0) {
      // Запоминаем текущий maxScrollExtent
      final currentMaxExtent = _scrollController.position.maxScrollExtent;

      // Прокручиваем к текущему максимуму
      _scrollController.jumpTo(currentMaxExtent);

      // Ждем еще один кадр и проверяем, не изменился ли maxScrollExtent
      // (это означает что появились новые элементы, например кнопки)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (_scrollController.hasClients) {
            final newMaxExtent = _scrollController.position.maxScrollExtent;
            if (newMaxExtent > currentMaxExtent) {
              // Появились новые элементы - прокручиваем до самого низа
              _scrollController.jumpTo(newMaxExtent);

              // Еще одна проверка через 100мс для надежности
              Future.delayed(const Duration(milliseconds: 100), () {
                if (_scrollController.hasClients) {
                  final finalMaxExtent =
                      _scrollController.position.maxScrollExtent;
                  if (finalMaxExtent > newMaxExtent) {
                    _scrollController.jumpTo(finalMaxExtent);
                  }
                }
              });
            }
          }
        });
      });
    } else {
      // Увеличили задержки для надежности
      Future.delayed(Duration(milliseconds: 150 + (attempt * 100)), () {
        _attemptScrollToBottom(attempt + 1);
      });
    }
  }

  /// Проверяет, нужно ли прокручивать вниз при открытии
  bool _shouldScrollOnOpen(List<ChatMessage> messages) {
    // Если нет сообщений - не прокручиваем
    if (messages.isEmpty) return false;

    // Если только одно сообщение и оно приветственное - не прокручиваем
    if (messages.length == 1) {
      final message = messages.first;
      return !(message.type == MessageType.ai &&
          message.metadata?['isWelcome'] == true);
    }

    // Если больше одного сообщения - прокручиваем
    return true;
  }

  /// Пытается восстановить позицию скролла или прокрутить вниз
  Future<void> _tryRestoreScrollPosition(List<ChatMessage> messages) async {
    if (_scrollPositionRestored) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 300));

      if (!_scrollController.hasClients) return;

      try {
        // Пытаемся получить сохраненную позицию

        if (_shouldScrollOnOpen(messages)) {
          _scrollToBottomOnFirstLoad();
        }

        _scrollPositionRestored = true;
      } catch (e) {
        debugPrint('📍 CHAT_SCREEN: Ошибка восстановления позиции: $e');
        // В случае ошибки просто прокручиваем вниз
        if (_shouldScrollOnOpen(messages)) {
          _scrollToBottomOnFirstLoad();
        }
        _scrollPositionRestored = true;
      }
    });
  }

  /// Сохраняет текущую позицию скролла в SharedPreferences
  void _saveScrollPositionToPrefs() {
    if (_scrollController.hasClients) {
      try {
        final position = _scrollController.position.pixels;
        final prefs = ref.read(sharedPreferencesProvider);
        prefs.setDouble('chat_scroll_position', position);
        debugPrint('📍 CHAT_SCREEN: Сохранена позиция: $position');
      } catch (e) {
        debugPrint('📍 CHAT_SCREEN: Ошибка сохранения позиции: $e');
      }
    }
  }

  /// Сохраняем позицию при сворачивании приложения
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveScrollPositionToPrefs();
    }
  }
}

/// Изолированный виджет для ListView который реагирует на клавиатуру
/// Динамически изменяет padding при открытии клавиатуры
class _KeyboardAwareChatList extends StatelessWidget {
  final ScrollController scrollController;
  final VoidCallback onUserTouch;
  final Function(DragStartDetails) onPanStart;
  final Function(DragUpdateDetails) onPanUpdate;
  final Function(DragEndDetails) onPanEnd;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  const _KeyboardAwareChatList({
    required this.scrollController,
    required this.onUserTouch,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    // Только ЭТОТ виджет rebuild при изменении viewInsets
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final topPadding = MediaQuery.of(context).padding.top;

    // Динамически увеличиваем bottom padding при открытии клавиатуры
    final effectiveBottomPadding = 180.0 + viewInsets.bottom;

    // Верхний padding: SafeArea top + высота кнопок (48) + отступ (12)
    final effectiveTopPadding = topPadding + 48 + 20;

    return GestureDetector(
      onTap: onUserTouch,
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      child: ScrollConfiguration(
        behavior: NoStretchScrollBehavior(),
        child: ListView.builder(
          physics: const ClampingScrollPhysics(),
          controller: scrollController,
          padding: EdgeInsets.only(
            top: effectiveTopPadding,
            bottom: effectiveBottomPadding,
            left: 0,
            right: 0,
          ),
          cacheExtent: 500,
          addRepaintBoundaries: true,
          addAutomaticKeepAlives: true,
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        ),
      ),
    );
  }
}

/// Виджет размытия над клавиатурой (как внизу главного экрана)
class _KeyboardAwareFadeMask extends StatelessWidget {
  const _KeyboardAwareFadeMask();

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final isKeyboardOpen = viewInsets.bottom > 0;

    if (!isKeyboardOpen) return const SizedBox.shrink();

    const blurHeight = 150.0;
    // Опускаем вниз, чтобы уходило под клавиатуру
    const bottomOffset = -40.0;

    final background = Theme.of(context).scaffoldBackgroundColor;

    return Positioned(
      left: 0,
      right: 0,
      bottom: viewInsets.bottom + bottomOffset,
      height: blurHeight,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                background,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Изолированный виджет для MessageInput который реагирует только на keyboard
/// Предотвращает rebuild всего экрана при изменении viewInsets
class _KeyboardAwareMessageInput extends StatelessWidget {
  final Function(String) onSendMessage;
  final bool isLoading;
  final bool enabled;

  const _KeyboardAwareMessageInput({
    required this.onSendMessage,
    required this.isLoading,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    // Только ЭТОТ виджет rebuild при изменении viewInsets
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: MessageInput(
        onSendMessage: onSendMessage,
        isLoading: isLoading,
        enabled: enabled,
      ),
    );
  }
}
