import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../services/ai_dietitian_service.dart';
import '../services/deepseek_dietitian_service.dart';
import '../utils/interactive_parser.dart';

import '../../../data/chat_storage_repository.dart';
import '../../../services/localization/app_localization_service.dart';
import '../../../services/token_usage_service.dart';
import '../../../services/trial_protection_service.dart';
import '../../../providers/token_providers.dart';
import 'package:flutter/material.dart';

import '../../../services/voice_message_storage.dart';
import '../../../utils/text_cleaner.dart';

/// Провайдер сервиса ИИ‑друга
final aiDietitianServiceProvider = Provider<AiDietitianService>((ref) {
  return AiDietitianService();
});

/// Провайдер репозитория хранения чата
final chatStorageRepositoryProvider = Provider<ChatStorageRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ChatStorageRepository(prefs);
});

/// Состояние чата
class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? error;
  final bool isTyping;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.isTyping = false,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? error,
    bool? isTyping,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      isTyping: isTyping ?? this.isTyping,
    );
  }
}

/// Провайдер для управления состоянием чата
class ChatNotifier extends StateNotifier<ChatState> {
  final AiDietitianService _aiService;
  final Ref _ref;
  final TokenUsageService _tokenService = TokenUsageService();
  ChatStorageRepository? _storageRepository;

  // Храним BuildContext для показа диалогов
  BuildContext? _currentBuildContext;

  ChatNotifier(this._aiService, this._ref)
      : super(const ChatState()) {
    _initializeChat();
    // Реагируем на смену языка: очищаем историю и пересоздаём приветствие
    _ref.listen<AppLanguage>(currentLanguageProvider, (prev, next) async {
      if (prev == null || prev == next) return;
      try {
        _initStorageRepository();
        await _storageRepository?.clearAllHistory();
        state = const ChatState();
        _initializeChat();
      } catch (e) {
        debugPrint('🔴 CHAT: Ошибка при сбросе чата после смены языка: $e');
      }
    });
  }

  /// Инициализация чата с приветственным сообщением
  void _initializeChat() async {
    // Инициализируем репозиторий сохранения
    _initStorageRepository();

    // Пытаемся загрузить сохраненную историю
    final savedMessages = await _storageRepository?.loadCurrentSession();

    if (savedMessages != null && savedMessages.isNotEmpty) {
      // Загружаем сохраненную историю
      state = state.copyWith(messages: savedMessages);
      debugPrint(
          '📥 CHAT: Загружена история из ${savedMessages.length} сообщений');
    } else {
      // Создаем локализованное приветственное сообщение
      final localizationService = _ref.read(appLocalizationServiceProvider);
      final welcomeMessage = ChatMessage.ai(
        content: localizationService.translate('chat_welcome_message'),
        metadata: {'isWelcome': true},
      );

      state = state.copyWith(messages: [welcomeMessage]);
    }
  }

  /// Инициализация репозитория сохранения
  void _initStorageRepository() {
    try {
      _storageRepository = _ref.read(chatStorageRepositoryProvider);
    } catch (e) {
      debugPrint('🔴 CHAT: Ошибка инициализации репозитория сохранения: $e');
    }
  }

  /// Отправка сообщения пользователя
  Future<void> sendMessage(String content) async {
    if (content.isEmpty) return;

    // Оцениваем количество токенов для запроса
    final estimatedTokens = _tokenService.estimateTokensForText(content);

    // Проверяем лимиты токенов с учетом триальных ограничений
    final usageResult = await _tokenService.checkTokenUsage(estimatedTokens);
    if (!usageResult.allowed) {
      // Показываем сообщение об ошибке в чате
      final errorMessage = ChatMessage.ai(
        content: _getErrorMessageForUsageResult(usageResult),
        quickReplies: _buildTokenActionQuickReplies(),
        metadata: {
          'error': true,
          'tokenError': true,
          'usageResult': usageResult.reason,
          'streaming':
              true, // Добавляем флаг streaming для анимации печатной машинки
        },
      );

      state = state.copyWith(
        messages: [...state.messages, errorMessage],
        error: usageResult.reason,
        isLoading: false,
        isTyping: false,
      );

      return;
    }

    // Добавляем сообщение пользователя
    final userMessage = ChatMessage.user(content: content);
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isLoading: true,
      isTyping: true,
      error: null,
    );

    try {
      // Получаем ответ от ИИ с контекстом (используем streaming для совместимости)
      String fullResponse = '';
      await for (final chunk in _aiService.sendMessageStream(
        message: content,
        context: state.messages,
        buildContext: _currentBuildContext,
      )) {
        fullResponse += chunk;
      }

      // Списываем токены после успешного получения ответа
      final actualTokensUsed =
          _tokenService.estimateTokensForText(content + fullResponse);
      final tokenDeducted = await _tokenService.useTokens(actualTokensUsed);

      if (tokenDeducted) {
        final updatedUsage = await _tokenService.getTokenUsage();
        debugPrint(
            '💎 CHAT: Списано $actualTokensUsed токенов за запрос. Осталось: ${updatedUsage.remainingTokens}');
        // Обновляем состояние провайдера токенов для динамического обновления счётчика
        _ref
            .read(tokenUsageNotifierProvider.notifier)
            .refreshFromSubscription();
      } else {
        debugPrint('⚠️ CHAT: Не удалось списать токены, но ответ уже получен');
        // Обновляем счётчик, чтобы отобразить актуальный баланс (может быть 0)
        _ref
            .read(tokenUsageNotifierProvider.notifier)
            .refreshFromSubscription();
      }

      final aiResponse = ChatMessage.ai(
        content: _stripEmojisForChat(fullResponse),
        metadata: {
          'timestamp': DateTime.now().toIso8601String(),
          'model': 'deepseek-v4-flash',
          'tokensUsed': actualTokensUsed,
        },
      );

      // Обновляем статус сообщения пользователя
      final updatedMessages = state.messages.map((msg) {
        if (msg.id == userMessage.id) {
          return msg.copyWith(status: MessageStatus.delivered);
        }
        return msg;
      }).toList();

      // Добавляем ответ ИИ
      state = state.copyWith(
        messages: [...updatedMessages, aiResponse],
        isLoading: false,
        isTyping: false,
      );

      // Автоматически сохраняем обновленную историю
      await _autoSaveChat();
    } catch (e) {
      // Обрабатываем ошибку
      final errorMessage = ChatMessage.ai(
        content:
            'Извините, произошла ошибка при обработке вашего запроса. Попробуйте еще раз.',
        metadata: {'error': true},
      );

      // Обновляем статус сообщения пользователя на ошибку
      final updatedMessages = state.messages.map((msg) {
        if (msg.id == userMessage.id) {
          return msg.copyWith(
            status: MessageStatus.error,
            errorMessage: e.toString(),
          );
        }
        return msg;
      }).toList();

      state = state.copyWith(
        messages: [...updatedMessages, errorMessage],
        isLoading: false,
        isTyping: false,
        error: e.toString(),
      );
    }
  }

  /// Отправка быстрого запроса
  Future<void> sendQuickQuery(QuickQuery query) async {
    await sendMessageStreaming(query.content);
  }

  /// Повторная отправка сообщения с ошибкой
  Future<void> retryMessage(String messageId) async {
    final message = state.messages.firstWhere(
      (msg) => msg.id == messageId,
      orElse: () => throw StateError('Сообщение не найдено'),
    );

    if (message.type == MessageType.user &&
        message.status == MessageStatus.error) {
      // Удаляем сообщение с ошибкой и отправляем заново
      final filteredMessages =
          state.messages.where((msg) => msg.id != messageId).toList();
      state = state.copyWith(messages: filteredMessages);
      await sendMessageStreaming(message.content);
    }
  }

  /// Очистка чата
  void clearChat() async {
    // Создаем новую сессию в хранилище
    // Перед сбросом удалим локальные аудиофайлы текущей сессии
    try {
      for (final m in state.messages) {
        if (m.type == MessageType.voice) {
          await VoiceMessageStorage.deleteIfExists(m.audioPath);
        }
      }
    } catch (_) {}

    await _storageRepository?.createNewSession();

    // Очищаем сохраненную позицию скролла
    await _storageRepository?.clearScrollPosition();

    state = const ChatState();
    _initializeChat();
  }

  /// Удаление конкретного сообщения
  void deleteMessage(String messageId) async {
    // Найдем удаляемое сообщение, чтобы удалить возможный аудиофайл
    final messageToDelete = state.messages.firstWhere(
      (m) => m.id == messageId,
      orElse: () => ChatMessage.system(content: ''),
    );

    final updatedMessages =
        state.messages.where((msg) => msg.id != messageId).toList();
    state = state.copyWith(messages: updatedMessages);

    // Автоматически сохраняем обновленную историю
    await _autoSaveChat();

    // Удаляем файл аудио, если это голосовое сообщение
    try {
      if (messageToDelete.type == MessageType.voice) {
        await VoiceMessageStorage.deleteIfExists(messageToDelete.audioPath);
      }
    } catch (_) {}
  }

  /// Помечает сообщение как уже озвученное (для приветствия)
  Future<void> markMessageAutoSpoken(String messageId) async {
    final updatedMessages = state.messages.map((msg) {
      if (msg.id != messageId) return msg;
      final newMeta = {...?msg.metadata, 'autoSpoken': true};
      return msg.copyWith(metadata: newMeta);
    }).toList();

    state = state.copyWith(messages: updatedMessages);
    await _autoSaveChat();
  }

  /// Отправка сообщения пользователя с потоковым получением ответа
  Future<void> sendMessageStreaming(String content) async {
    if (content.isEmpty) return;

    // Предварительная оценка токенов с запасом для ответа ИИ
    final estimatedTokens =
        _tokenService.estimateTokensForText(content) + 500;
    final usageResult = await _tokenService.checkTokenUsage(estimatedTokens);
    if (!usageResult.allowed) {
      // Показываем сообщение об ошибке и диалог
      final errorMessage = ChatMessage.ai(
        content: _getErrorMessageForUsageResult(usageResult),
        quickReplies: _buildTokenActionQuickReplies(),
        metadata: {
          'error': true,
          'tokenError': true,
          'usageResult': usageResult.reason,
          'streaming':
              true, // Добавляем флаг streaming для анимации печатной машинки
        },
      );

      state = state.copyWith(
        messages: [...state.messages, errorMessage],
        isLoading: false,
        isTyping: false,
        error: usageResult.reason,
      );

      return;
    }

    // Добавляем сообщение пользователя
    final userMessage = ChatMessage.user(content: content);

    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isLoading: true,
      isTyping: true,
      error: null,
    );

    // Создаем пустое сообщение ИИ для streaming
    final aiMessageId = const Uuid().v4();
    final aiMessage = ChatMessage.ai(
      content: '',
      metadata: {
        'id': aiMessageId,
        'streaming': true,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    state = state.copyWith(
      messages: [...state.messages, aiMessage],
      isLoading: true,
      isTyping: true,
      error: null,
    );

    try {
      // Получаем поток ответов от ИИ
      String accumulatedContent = '';
      String displayContent = '';
      bool userDeliveredMarked = false;
      await for (final chunk in _aiService.sendMessageStream(
        message: content,
        context: state.messages
            .where((msg) => msg.metadata?['id'] != aiMessageId)
            .toList(),
        buildContext: _currentBuildContext,
      )) {
        accumulatedContent += chunk;

        // Фильтруем JSON блоки и markdown символы для отображения в реальном времени
        displayContent = _filterJsonBlocks(accumulatedContent);
        displayContent = _filterMarkdownSymbols(displayContent);
        displayContent = _stripEmojisForChat(displayContent);

        // Пробуем извлечь quickReplies если они уже полностью получены
        List<QuickReply>? currentQuickReplies;
        try {
          final parsedResponse =
              _parseResponseWithQuickReplies(accumulatedContent);
          if (parsedResponse.quickReplies?.isNotEmpty == true) {
            currentQuickReplies = parsedResponse.quickReplies;
            debugPrint(
                '🎯 CHAT_PROVIDER: Найдены quickReplies во время streaming');
          }
        } catch (e) {
          // Игнорируем ошибки парсинга во время streaming
        }

        // Отладочная информация (можно убрать после тестирования)
        if (accumulatedContent != displayContent) {
          debugPrint('🔧 CHAT_PROVIDER: Отфильтрован JSON контент');
        }

        // Обновляем сообщение ИИ в реальном времени и отмечаем доставку пользователя на первом чанке
        final updatedMessages = state.messages.map((msg) {
          if (msg.metadata?['id'] == aiMessageId) {
            return msg.copyWith(
              content: displayContent,
              quickReplies: currentQuickReplies,
              metadata: {
                ...msg.metadata!,
                'streaming': true,
                'hasQuickReplies': currentQuickReplies?.isNotEmpty ?? false,
              },
            );
          } else if (!userDeliveredMarked &&
              msg.id == userMessage.id &&
              msg.status != MessageStatus.delivered) {
            return msg.copyWith(status: MessageStatus.delivered);
          }
          return msg;
        }).toList();

        state = state.copyWith(
          messages: updatedMessages,
          isTyping: true,
        );

        userDeliveredMarked = true;
      }

      // Завершаем streaming - обновляем статусы сообщений
      final finalMessages = state.messages.map((msg) {
        if (msg.id == userMessage.id) {
          return msg.copyWith(status: MessageStatus.delivered);
        } else if (msg.metadata?['id'] == aiMessageId) {
          // Парсим финальный ответ для извлечения quick replies
          final parsedResponse =
              _parseResponseWithQuickReplies(accumulatedContent);

          // Используем уже отфильтрованный displayContent без дополнительной обработки
          // displayContent уже правильно обработан во время streaming
          return msg.copyWith(
            content:
                displayContent, // Используем готовый отфильтрованный контент!
            quickReplies: parsedResponse.quickReplies,
            metadata: {
              ...msg.metadata!,
              'streaming': false,
              'hasQuickReplies':
                  parsedResponse.quickReplies?.isNotEmpty ?? false,
            },
          );
        }
        return msg;
      }).toList();

      state = state.copyWith(
        messages: finalMessages,
        isLoading: false,
        isTyping: false,
      );

      // Списываем токены после успешного получения ответа (streaming)
      final actualTokensUsed =
          _tokenService.estimateTokensForText(content + accumulatedContent);
      final tokenDeducted = await _tokenService.useTokens(actualTokensUsed);

      if (tokenDeducted) {
        final updatedUsage = await _tokenService.getTokenUsage();
        debugPrint(
            '💎 CHAT: Списано $actualTokensUsed токенов за запрос (streaming). Осталось: ${updatedUsage.remainingTokens}');
        // Обновляем состояние провайдера токенов для динамического обновления счётчика
        _ref
            .read(tokenUsageNotifierProvider.notifier)
            .refreshFromSubscription();
      } else {
        debugPrint(
            '⚠️ CHAT: Не удалось списать токены (streaming), но ответ уже получен');
        // Обновляем счётчик, чтобы показать фактический баланс (вероятно 0)
        _ref
            .read(tokenUsageNotifierProvider.notifier)
            .refreshFromSubscription();
      }

      // Автоматически сохраняем обновленную историю
      await _autoSaveChat();
    } catch (e) {
      // Обрабатываем ошибку
      debugPrint('❌ CHAT_PROVIDER: Ошибка при streaming: $e');

      final errorMessage = ChatMessage.ai(
        content:
            'Извините, произошла ошибка при обработке вашего запроса. Попробуйте еще раз.',
        metadata: {'error': true},
      );

      // Обновляем статус сообщения пользователя на ошибку и заменяем streaming сообщение на ошибку
      final updatedMessages = state.messages.map((msg) {
        if (msg.id == userMessage.id) {
          return msg.copyWith(
            status: MessageStatus.error,
            errorMessage: e.toString(),
          );
        } else if (msg.metadata?['id'] == aiMessageId) {
          return errorMessage;
        }
        return msg;
      }).toList();

      state = state.copyWith(
        messages: updatedMessages,
        isLoading: false,
        isTyping: false,
        error: e.toString(),
      );
    }
  }

  /// Отправка голосового сообщения пользователя
  Future<void> sendVoiceMessage({
    required String audioPath,
    required int durationMs,
    String? transcription,
    String? placeholderId,
  }) async {
    // Если есть транскрипция, показываем её как пользовательское текстовое сообщение
    final text = transcription?.trim();
    if (text != null && text.isNotEmpty) {
      // Обновляем существующий placeholder или создаем новое сообщение, если placeholder не передан
      if (placeholderId != null) {
        final updated = state.messages.map((m) {
          if (m.id == placeholderId) {
            final newMeta = {
              ...?m.metadata,
              'source': 'voice_transcript',
              'transcribing': false,
              'streaming': true, // краткая анимация печати для пользователя
            };
            return m.copyWith(content: text, metadata: newMeta);
          }
          return m;
        }).toList();
        state = state.copyWith(
          messages: updated,
          isLoading: true,
          isTyping: true,
          error: null,
        );
      } else {
        final userMessage = ChatMessage.user(
          content: text,
          metadata: {
            'source': 'voice_transcript',
            'streaming': true, // краткая анимация печати для пользователя
          },
        );

        state = state.copyWith(
          messages: [...state.messages, userMessage],
          isLoading: true,
          isTyping: true,
          error: null,
        );

        // Снимаем анимацию печати через короткую задержку
        Future.delayed(const Duration(milliseconds: 600), () {
          final updated = state.messages.map((m) {
            if (m.id == userMessage.id) {
              final newMeta = {...?m.metadata};
              newMeta['streaming'] = false;
              return m.copyWith(metadata: newMeta);
            }
            return m;
          }).toList();
          state = state.copyWith(messages: updated);
        });
      }
    } else {
      // Без транскрипции ничего не добавляем в ленту
      state = state.copyWith(isLoading: false, isTyping: false);
      // Удаляем ненужный аудиофайл
      try {
        await VoiceMessageStorage.deleteIfExists(audioPath);
      } catch (_) {}
      // Удаляем placeholder, если он был создан
      if (placeholderId != null) {
        final filtered =
            state.messages.where((m) => m.id != placeholderId).toList();
        state = state.copyWith(messages: filtered);
      }
      await _autoSaveChat();
      return;
    }

    // Готовим AI streaming-ответ на транскрипцию
    final aiMessageId = const Uuid().v4();
    final aiMessage = ChatMessage.ai(
      content: '',
      metadata: {
        'id': aiMessageId,
        'streaming': true,
        'timestamp': DateTime.now().toIso8601String(),
        'source': 'voice_transcript',
      },
    );

    state = state.copyWith(
      messages: [...state.messages, aiMessage],
      isLoading: true,
      isTyping: true,
    );

    try {
      String accumulatedContent = '';
      String displayContent = '';
      bool userDeliveredMarked = false;
      String? userMsgId = placeholderId;
      await for (final chunk in _aiService.sendMessageStream(
        message: text,
        context: state.messages
            .where((m) => m.metadata?['id'] != aiMessageId)
            .toList(),
        buildContext: _currentBuildContext,
      )) {
        accumulatedContent += chunk;
        displayContent = _filterJsonBlocks(accumulatedContent);
        displayContent = _filterMarkdownSymbols(displayContent);
        displayContent = _stripEmojisForChat(displayContent);

        final updatedMessages = state.messages.map((msg) {
          if (msg.metadata?['id'] == aiMessageId) {
            return msg.copyWith(
              content: displayContent,
              metadata: {
                ...msg.metadata!,
                'streaming': true,
              },
            );
          } else if (!userDeliveredMarked &&
              msg.type == MessageType.user &&
              (msg.metadata?['source'] == 'voice_transcript') &&
              (userMsgId == null || msg.id == userMsgId) &&
              msg.status != MessageStatus.delivered) {
            // Отмечаем доставку пользовательского сообщения при первом чанке AI
            userMsgId = msg.id;
            return msg.copyWith(status: MessageStatus.delivered);
          }
          return msg;
        }).toList();

        state = state.copyWith(messages: updatedMessages, isTyping: true);

        userDeliveredMarked = true;
      }

      final finalMessages = state.messages.map((msg) {
        if (msg.metadata?['id'] == aiMessageId) {
          return msg.copyWith(
            content: displayContent,
            metadata: {
              ...msg.metadata!,
              'streaming': false,
            },
          );
        } else if (msg.type == MessageType.user &&
            (msg.metadata?['source'] == 'voice_transcript')) {
          // Обновляем статус пользовательского сообщения как доставлено
          return msg.copyWith(status: MessageStatus.delivered, metadata: {
            ...?msg.metadata,
            'streaming': false,
          });
        }
        return msg;
      }).toList();

      state = state.copyWith(
        messages: finalMessages,
        isLoading: false,
        isTyping: false,
      );

      // Удаляем аудиофайл после успешной обработки
      try {
        await VoiceMessageStorage.deleteIfExists(audioPath);
      } catch (_) {}

      // Токены учитываем по транскрипции + ответу
      final actualTokensUsed =
          _tokenService.estimateTokensForText(text + accumulatedContent);
      await _tokenService.useTokens(actualTokensUsed);
      _ref.read(tokenUsageNotifierProvider.notifier).refreshFromSubscription();

      await _autoSaveChat();
    } catch (e) {
      debugPrint('❌ CHAT_PROVIDER: Ошибка при обработке voice: $e');

      final errorMessage = ChatMessage.ai(
        content:
            'Извините, произошла ошибка при обработке голосового сообщения. Попробуйте еще раз.',
        metadata: {'error': true},
      );

      final updatedMessages = state.messages.map((msg) {
        if (msg.metadata?['id'] == aiMessageId) {
          return errorMessage;
        }
        return msg;
      }).toList();

      state = state.copyWith(
        messages: updatedMessages,
        isLoading: false,
        isTyping: false,
        error: e.toString(),
      );

      // Пытаемся удалить аудиофайл даже при ошибке
      try {
        await VoiceMessageStorage.deleteIfExists(audioPath);
      } catch (_) {}
    }
  }

  /// Создает пустой пользовательский пузырь для распознавания речи
  String createVoiceTranscriptionPlaceholder() {
    final placeholder = ChatMessage.user(
      content: '',
      metadata: {
        'source': 'voice_transcript',
        'transcribing': true,
        'streaming': false,
      },
    );

    state = state.copyWith(
      messages: [...state.messages, placeholder],
      isLoading: true,
      isTyping: true,
    );
    return placeholder.id;
  }

  /// Удаляет сообщение по ID
  void removeMessageById(String id) {
    final filtered = state.messages.where((m) => m.id != id).toList();
    state = state.copyWith(messages: filtered);
  }

  /// Фильтрует JSON блоки из текста для отображения в реальном времени
  String _filterJsonBlocks(String content) {
    String filtered = content;

    // Убираем полные JSON блоки с ```json
    filtered = filtered.replaceAll(RegExp(r'```json\s*\{[\s\S]*?\}\s*```'), '');

    // Убираем незавершенные JSON блоки (начинающиеся с ```json но не завершенные)
    filtered = filtered.replaceAll(RegExp(r'```json[\s\S]*$'), '');

    // Убираем обычные JSON объекты (завершенные и незавершенные)
    filtered =
        filtered.replaceAll(RegExp(r'\s*\{[\s\S]*"quickReplies"[\s\S]*'), '');

    // Убираем незавершенные JSON объекты в конце
    filtered = filtered.replaceAll(RegExp(r'\s*\{\s*$'), '');
    filtered = filtered.replaceAll(RegExp(r'\s*\{\s*"[\s\S]*$'), '');

    // Убираем лишние пустые строки и пробелы
    filtered = filtered.replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n');
    filtered = filtered.replaceAll(RegExp(r'\s+$'), '');

    return filtered.trim();
  }

  /// Фильтрует markdown символы из текста для улучшения UX в streaming режиме
  /// Использует продвинутый алгоритм для полного скрытия markdown символов
  String _filterMarkdownSymbols(String content) {
    String filtered = content;

    // Продвинутая фильтрация - обрабатываем все случаи появления markdown символов

    // 1. Убираем ** в середине текста если они не завершены
    filtered = _processIncompleteStars(filtered);

    // 2. Убираем ### символы полностью
    filtered = _processHashHeaders(filtered);

    // 3. Обрабатываем концовки текста
    filtered = _processTextEndings(filtered);

    // 4. Убираем горизонтальные линии полностью
    filtered =
        filtered.replaceAll(RegExp(r'^[-*_]{3,}\s*$', multiLine: true), '');

    // 5. Финальная очистка
    filtered = filtered.replaceAll(RegExp(r'\n\s*$'), '');

    return filtered;
  }

  String _stripEmojisForChat(String content) {
    return TextCleaner.removeEmojis(content);
  }

  /// Обрабатывает незавершенные звездочки в тексте
  String _processIncompleteStars(String text) {
    // Паттерны обработки markdown звездочек:
    // 1. "1️⃣ **Завтрак: Творожная запеканка с яблоками**" -> "1️⃣ Завтрак: Творожная запеканка с яблоками"
    // 2. "😊 **МОЙ СОВЕТ" -> "😊 МОЙ СОВЕТ"

    String result = text;

    // Обрабатываем каждую строку отдельно
    final lines = result.split('\n');
    final processedLines = lines.map((line) {
      final trimmedLine = line.trim();

      // Проверяем если строка содержит ** символы
      if (!trimmedLine.contains('**')) {
        return line;
      }

      // Случай 1: Завершенные жирные заголовки **текст** (включая с эмодзи)
      // Пример: "🍗 **Обед (~900 ккал)**", "1️⃣ **Завтрак**"
      if (RegExp(r'\*\*[^*]+\*\*').hasMatch(trimmedLine)) {
        return line.replaceAll(RegExp(r'\*\*'), '');
      }

      // Случай 2: Незавершенные заголовки с ** в начале
      // Пример: "😊 **МОЙ СОВЕТ", "**Заголовок"
      if (trimmedLine.contains('**') &&
          !RegExp(r'\*\*[^*]*\*\*').hasMatch(trimmedLine)) {
        return line.replaceAll(RegExp(r'\*\*'), '');
      }

      // Случай 3: Одиночная * в конце строки
      if (line.endsWith('*') && !line.endsWith('**')) {
        return line.substring(0, line.length - 1);
      }

      return line;
    }).toList();

    return processedLines.join('\n');
  }

  /// Обрабатывает заголовки с символами #
  String _processHashHeaders(String text) {
    String result = text;

    final lines = result.split('\n');
    final processedLines = lines.map((line) {
      // Удаляем ### если после них только пробелы или ничего
      if (RegExp(r'^#{1,6}\s*$').hasMatch(line.trim())) {
        return '';
      }

      // Удаляем ### если они в конце строки
      return line.replaceAll(RegExp(r'#{1,6}\s*$'), '');
    }).toList();

    return processedLines.join('\n');
  }

  /// Обрабатывает концовки текста
  String _processTextEndings(String text) {
    String result = text;

    // Убираем ** в самом конце всего текста
    while (result.endsWith('**') || result.endsWith('*')) {
      if (result.endsWith('**')) {
        result = result.substring(0, result.length - 2);
      } else if (result.endsWith('*')) {
        result = result.substring(0, result.length - 1);
      }
    }

    return result;
  }

  /// Парсит ответ ИИ для извлечения quick replies (копия из DeepSeekDietitianService)
  ParsedResponse _parseResponseWithQuickReplies(String response) {
    try {
      // Ищем JSON блок с quickReplies
      final jsonMatch = RegExp(r'```json\s*(\{.*?\})\s*```', dotAll: true)
          .firstMatch(response);

      List<QuickReply>? quickReplies;
      String cleanContent = response;

      if (jsonMatch != null) {
        try {
          final jsonString = jsonMatch.group(1);
          if (jsonString != null) {
            final jsonData =
                Map<String, dynamic>.from(jsonDecode(jsonString) as Map);

            if (jsonData.containsKey('quickReplies')) {
              final repliesJson = jsonData['quickReplies'] as List;
              quickReplies = repliesJson
                  .map((reply) =>
                      QuickReply.fromJson(reply as Map<String, dynamic>))
                  .toList();
            }
          }

          // Убираем JSON блок из текста ответа
          cleanContent = response.replaceAll(jsonMatch.group(0)!, '').trim();
        } catch (e) {
          debugPrint('⚠️ CHAT_PROVIDER: Ошибка парсинга JSON quickReplies: $e');
        }
      }

      // Если не нашли JSON, пытаемся найти обычные варианты с 🔹
      if (quickReplies == null || quickReplies.isEmpty) {
        final textOptions = InteractiveParser.extractOptions(cleanContent);
        if (textOptions.isNotEmpty) {
          quickReplies = textOptions
              .map((text) => QuickReply(
                    id: 'text_${text.hashCode}',
                    text: text,
                  ))
              .toList();

          debugPrint(
              '✅ CHAT_PROVIDER: Найдено ${quickReplies.length} quickReplies из текста');
        }
      }

      return ParsedResponse(
        content: cleanContent,
        quickReplies: quickReplies,
      );
    } catch (e) {
      debugPrint('❌ CHAT_PROVIDER: Ошибка при парсинге ответа: $e');
      return ParsedResponse(
        content: response,
        quickReplies: null,
      );
    }
  }

  /// Отметка всех сообщений как прочитанных
  void markAllAsRead() async {
    final updatedMessages = state.messages.map((msg) {
      if (msg.type == MessageType.ai && msg.status != MessageStatus.delivered) {
        return msg.copyWith(status: MessageStatus.delivered);
      }
      return msg;
    }).toList();

    state = state.copyWith(messages: updatedMessages);

    // Автоматически сохраняем обновленную историю
    await _autoSaveChat();
  }

  /// Автоматическое сохранение истории чата
  Future<void> _autoSaveChat() async {
    if (_storageRepository != null && state.messages.isNotEmpty) {
      // Не сохраняем пустые чаты или только приветственные сообщения
      if (_isOnlyWelcomeMessage(state.messages)) {
        return;
      }
      await _storageRepository!.saveCurrentSession(state.messages);
    }
  }

  /// Загрузка конкретной сессии
  Future<void> loadSession(String sessionId) async {
    if (_storageRepository == null) {
      _initStorageRepository();
    }

    final messages = await _storageRepository?.loadSession(sessionId);
    if (messages != null) {
      state = state.copyWith(messages: messages);
    }
  }

  /// Получение всех сохраненных сессий
  Future<List<ChatSession>> getAllSessions() async {
    if (_storageRepository == null) {
      _initStorageRepository();
    }

    return await _storageRepository?.getAllSessions() ?? [];
  }

  /// Удаление сессии
  Future<void> deleteSession(String sessionId) async {
    if (_storageRepository == null) {
      _initStorageRepository();
    }

    await _storageRepository?.deleteSession(sessionId);
  }

  /// Очистка всей истории
  Future<void> clearAllHistory() async {
    if (_storageRepository == null) {
      _initStorageRepository();
    }

    await _storageRepository?.clearAllHistory();

    // Сбрасываем состояние к начальному
    state = const ChatState();
    _initializeChat();
  }

  /// Экспорт чата в текстовый формат
  String exportChatToText() {
    if (_storageRepository == null) {
      return 'Репозиторий сохранения не инициализирован';
    }

    return _exportChatToText(state.messages);
  }

  /// Получение статистики чата
  ChatStatistics getChatStatistics() {
    if (_storageRepository == null) {
      return const ChatStatistics(
        totalMessages: 0,
        userMessages: 0,
        aiMessages: 0,
        systemMessages: 0,
      );
    }

    return _getChatStatistics(state.messages);
  }

  /// Проверка, содержит ли чат только приветственное сообщение
  bool _isOnlyWelcomeMessage(List<ChatMessage> messages) {
    if (messages.length != 1) return false;

    final message = messages.first;
    return message.type == MessageType.ai &&
        message.metadata?['isWelcome'] == true;
  }

  /// Экспорт чата в текстовый формат
  String _exportChatToText(List<ChatMessage> messages) {
    final buffer = StringBuffer();
    buffer.writeln('=== ЭКСПОРТ ЧАТА С ИИ-ДРУГОМ ===');
    buffer.writeln('Дата экспорта: ${DateTime.now().toLocal()}');
    buffer.writeln('Количество сообщений: ${messages.length}');
    buffer.writeln('=====================================\n');

    for (final message in messages) {
      final sender = _getSenderName(message.type);
      final timestamp = message.timestamp.toLocal();
      final timeStr =
          '${timestamp.day.toString().padLeft(2, '0')}.${timestamp.month.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

      buffer.writeln('[$timeStr] $sender:');
      buffer.writeln(message.content);
      buffer.writeln('');
    }

    buffer.writeln('=== КОНЕЦ ЭКСПОРТА ===');
    return buffer.toString();
  }

  /// Получение статистики чата
  ChatStatistics _getChatStatistics(List<ChatMessage> messages) {
    final userMessages =
        messages.where((msg) => msg.type == MessageType.user).length;
    final aiMessages =
        messages.where((msg) => msg.type == MessageType.ai).length;
    final systemMessages =
        messages.where((msg) => msg.type == MessageType.system).length;

    final firstMessage = messages.isNotEmpty ? messages.first.timestamp : null;
    final lastMessage = messages.isNotEmpty ? messages.last.timestamp : null;

    Duration? sessionDuration;
    if (firstMessage != null && lastMessage != null) {
      sessionDuration = lastMessage.difference(firstMessage);
    }

    return ChatStatistics(
      totalMessages: messages.length,
      userMessages: userMessages,
      aiMessages: aiMessages,
      systemMessages: systemMessages,
      sessionDuration: sessionDuration,
      firstMessageTime: firstMessage,
      lastMessageTime: lastMessage,
    );
  }

  /// Получение имени отправителя по типу сообщения
  String _getSenderName(MessageType type) {
    switch (type) {
      case MessageType.user:
        return 'Пользователь';
      case MessageType.ai:
        return 'ИИ-друг';
      case MessageType.system:
        return 'Система';
      case MessageType.quickAction:
        return 'Быстрое действие';
      case MessageType.voice:
        return 'Пользователь (голос)';
    }
  }

  /// Устанавливает BuildContext для показа диалогов
  void setBuildContext(BuildContext? context) {
    _currentBuildContext = context;
  }

  /// Метод для генерации сообщения об ошибке лимитов
  List<QuickReply> _buildTokenActionQuickReplies() {
    final subInfo = _ref.read(subscriptionTokensProvider).maybeWhen(
          data: (data) => data,
          orElse: () => {'subscriptionType': 'free'},
        );
    final type = subInfo['subscriptionType'] ?? 'free';

    final List<QuickReply> replies = [
      const QuickReply(
        id: 'buy_tokens',
        text: '💎 Купить токены',
        payload: 'ACTION_BUY_TOKENS',
        isAction: true,
      ),
    ];

    if (type != 'yearly' && type != 'lifetime') {
      replies.add(
        QuickReply(
          id: 'get_subscription',
          text: type == 'weekly' || type == 'monthly'
              ? '⭐ Изменить подписку'
              : '⭐ Получить подписку',
          payload: 'ACTION_GET_SUBSCRIPTION',
          isAction: true,
        ),
      );
    }
    return replies;
  }

  String _getErrorMessageForUsageResult(TokenUsageResult usageResult) {
    switch (usageResult.reason) {
      case 'daily_limit_exceeded':
        return 'Достигнут дневной лимит запросов.\n\nДля продолжения общения с ИИ‑другом, пожалуйста, приобретите дополнительные токены или оформите подписку.';
      case 'hourly_limit_exceeded':
        return 'Достигнут часовой лимит запросов.\n\nПожалуйста, попробуйте снова через некоторое время или приобретите дополнительные токены.';
      case 'hourly_requests_exceeded':
        return 'Слишком много запросов за короткий период.\n\nПожалуйста, сделайте небольшую паузу и попробуйте снова через несколько минут.';
      case 'requests_too_frequent':
        return 'Запросы отправляются слишком часто.\n\nПожалуйста, подождите немного перед следующим запросом.';
      case 'trial_total_limit_exceeded':
        return 'Достигнут лимит бесплатных запросов.\n\nДля продолжения общения с ИИ‑другом, пожалуйста, приобретите токены или оформите подписку.';
      case 'insufficient_tokens':
        return 'Для продолжения общения требуется достаточное количество токенов.\n\nПопробуйте позже или пополните баланс.';
      default:
        return 'Произошла ошибка при обработке запроса.\n\nПожалуйста, попробуйте позже или обратитесь в поддержку.';
    }
  }

}

/// Статистика чата
class ChatStatistics {
  final int totalMessages;
  final int userMessages;
  final int aiMessages;
  final int systemMessages;
  final Duration? sessionDuration;
  final DateTime? firstMessageTime;
  final DateTime? lastMessageTime;

  const ChatStatistics({
    required this.totalMessages,
    required this.userMessages,
    required this.aiMessages,
    required this.systemMessages,
    this.sessionDuration,
    this.firstMessageTime,
    this.lastMessageTime,
  });
}

/// Провайдер чата
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final aiService = ref.read(aiDietitianServiceProvider);
  return ChatNotifier(aiService, ref);
});

/// Провайдер быстрых запросов с локализацией
final quickQueriesProvider = Provider<List<QuickQuery>>((ref) {
  // Обновляем быстрые запросы при смене языка
  ref.watch(currentLanguageProvider);
  // Возвращаем localized версию быстрых запросов
  return _getLocalizedQuickQueries(ref);
});

/// Получает локализованные быстрые запросы
List<QuickQuery> _getLocalizedQuickQueries(Ref ref) {
  final language = ref.read(currentLanguageProvider);
  if (language == AppLanguage.ru) {
    return const [
      QuickQuery(
        id: 'friend_checkin',
        title: 'Как прошёл твой день?',
        content: 'Хочу рассказать, как прошёл мой день.',
        icon: '💬',
      ),
      QuickQuery(
        id: 'friend_ideas',
        title: 'Что бы поделать сегодня?',
        content: 'Подкинь пару идей, чем заняться сегодня.',
        icon: '✨',
      ),
      QuickQuery(
        id: 'friend_support',
        title: 'Нужна поддержка',
        content: 'Мне сейчас нелегко, можешь поддержать?',
        icon: '🤝',
      ),
      QuickQuery(
        id: 'friend_plans',
        title: 'Помоги с планом',
        content: 'Помоги составить простой план на ближайшие дни.',
        icon: '🗓️',
      ),
      QuickQuery(
        id: 'friend_fun',
        title: 'Давай поболтаем',
        content: 'Просто поболтаем? Я хочу отвлечься.',
        icon: '🙂',
      ),
    ];
  }
  return const [
    QuickQuery(
      id: 'friend_checkin',
      title: 'How was your day?',
      content: 'I want to tell you how my day went.',
      icon: '💬',
    ),
    QuickQuery(
      id: 'friend_ideas',
      title: 'What should I do today?',
      content: 'Give me a couple of ideas for today.',
      icon: '✨',
    ),
    QuickQuery(
      id: 'friend_support',
      title: 'I need support',
      content: 'I’m struggling right now, can you support me?',
      icon: '🤝',
    ),
    QuickQuery(
      id: 'friend_plans',
      title: 'Help me plan',
      content: 'Help me make a simple plan for the next few days.',
      icon: '🗓️',
    ),
    QuickQuery(
      id: 'friend_fun',
      title: 'Let’s chat',
      content: 'Just chat with me? I want to unwind.',
      icon: '🙂',
    ),
  ];
}

/// Провайдер для проверки доступности сервиса
final serviceAvailabilityProvider = FutureProvider<bool>((ref) async {
  final aiService = ref.read(aiDietitianServiceProvider);
  return await aiService.isServiceAvailable();
});
