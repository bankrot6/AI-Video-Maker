import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uuid/uuid.dart';
import 'ai_agent_action.dart';

part 'chat_message.freezed.dart';
part 'chat_message.g.dart';

/// Тип сообщения в чате
enum MessageType {
  user,
  ai,
  system,
  quickAction,
  voice,
}

/// Статус сообщения
enum MessageStatus {
  sending,
  sent,
  delivered,
  error,
}

/// Модель сообщения чата с ИИ диетологом
@freezed
abstract class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required String id,
    required String content,
    required MessageType type,
    required DateTime timestamp,
    @Default(MessageStatus.sent) MessageStatus status,
    String? errorMessage,
    Map<String, dynamic>? metadata,
    List<QuickReply>? quickReplies,
    @JsonKey(includeFromJson: false, includeToJson: false)
    List<ExerciseSuggestion>? exerciseSuggestions,
    // Поля для голосовых сообщений
    String? audioPath,
    int? audioDurationMs,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);

  /// Создает пользовательское сообщение
  factory ChatMessage.user({
    required String content,
    Map<String, dynamic>? metadata,
  }) =>
      ChatMessage(
        id: const Uuid().v4(),
        content: content,
        type: MessageType.user,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        metadata: metadata,
      );

  /// Создает сообщение от ИИ
  factory ChatMessage.ai({
    required String content,
    Map<String, dynamic>? metadata,
    List<QuickReply>? quickReplies,
    List<ExerciseSuggestion>? exerciseSuggestions,
  }) =>
      ChatMessage(
        id: const Uuid().v4(),
        content: content,
        type: MessageType.ai,
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
        metadata: metadata,
        quickReplies: quickReplies,
        exerciseSuggestions: exerciseSuggestions,
      );

  /// Создает голосовое сообщение пользователя
  factory ChatMessage.voice({
    required String audioPath,
    required int audioDurationMs,
    String? transcription,
    Map<String, dynamic>? metadata,
  }) =>
      ChatMessage(
        id: const Uuid().v4(),
        content: transcription ?? '',
        type: MessageType.voice,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        metadata: metadata,
        audioPath: audioPath,
        audioDurationMs: audioDurationMs,
      );

  /// Создает системное сообщение
  factory ChatMessage.system({
    required String content,
  }) =>
      ChatMessage(
        id: const Uuid().v4(),
        content: content,
        type: MessageType.system,
        timestamp: DateTime.now(),
        status: MessageStatus.sent,
      );
}

/// Модель быстрого ответа для структурированных ответов ИИ
@freezed
abstract class QuickReply with _$QuickReply {
  const factory QuickReply({
    required String id,
    required String text,
    String? payload,
    @Default(false) bool isAction,
  }) = _QuickReply;

  factory QuickReply.fromJson(Map<String, dynamic> json) =>
      _$QuickReplyFromJson(json);
}

/// Модель быстрого запроса для чата
@freezed
abstract class QuickQuery with _$QuickQuery {
  const factory QuickQuery({
    required String id,
    required String title,
    required String content,
    required String icon,
  }) = _QuickQuery;

  factory QuickQuery.fromJson(Map<String, dynamic> json) =>
      _$QuickQueryFromJson(json);
}

/// Предустановленные быстрые запросы для ИИ‑Гида
class PredefinedQueries {
  static const List<QuickQuery> dietitianQueries = [
    QuickQuery(
      id: 'city_walk_2h',
      title: 'Маршрут на 2 часа по центру',
      content:
          'Составь пеший маршрут на ~2 часа по центру города с 5–7 остановками, короткими историческими фактами и примерным таймингом.',
      icon: '🗺️',
    ),
    QuickQuery(
      id: 'evening_walk_views',
      title: 'Вечерняя прогулка и виды',
      content:
          'Подскажи маршрут для вечерней прогулки: красивые виды/набережная, безопасные улицы и где можно зайти на кофе по пути.',
      icon: '🌆',
    ),
    QuickQuery(
      id: 'historic_places',
      title: 'Исторические места города',
      content:
          'Назови главные исторические места и предложи компактный маршрут между ними для прогулки.',
      icon: '🏛️',
    ),
    QuickQuery(
      id: 'museums_architecture',
      title: 'Музеи и архитектура',
      content:
          'Подбери 2–3 музея или архитектурные объекты на полдня, с советами по очередям и билетам.',
      icon: '🖼️',
    ),
    QuickQuery(
      id: 'family_walk',
      title: 'Семейная прогулка',
      content:
          'Составь маршрут для семьи с детьми на 1–2 часа: парки, интерактивные места, остановки для отдыха.',
      icon: '👨‍👩‍👧‍👦',
    ),
  ];
}
