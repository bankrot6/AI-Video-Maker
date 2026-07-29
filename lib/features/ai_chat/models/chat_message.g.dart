// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ChatMessage _$ChatMessageFromJson(Map<String, dynamic> json) => _ChatMessage(
      id: json['id'] as String,
      content: json['content'] as String,
      type: $enumDecode(_$MessageTypeEnumMap, json['type']),
      timestamp: DateTime.parse(json['timestamp'] as String),
      status: $enumDecodeNullable(_$MessageStatusEnumMap, json['status']) ??
          MessageStatus.sent,
      errorMessage: json['errorMessage'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      quickReplies: (json['quickReplies'] as List<dynamic>?)
          ?.map((e) => QuickReply.fromJson(e as Map<String, dynamic>))
          .toList(),
      audioPath: json['audioPath'] as String?,
      audioDurationMs: (json['audioDurationMs'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ChatMessageToJson(_ChatMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'content': instance.content,
      'type': _$MessageTypeEnumMap[instance.type]!,
      'timestamp': instance.timestamp.toIso8601String(),
      'status': _$MessageStatusEnumMap[instance.status]!,
      'errorMessage': instance.errorMessage,
      'metadata': instance.metadata,
      'quickReplies': instance.quickReplies,
      'audioPath': instance.audioPath,
      'audioDurationMs': instance.audioDurationMs,
    };

const _$MessageTypeEnumMap = {
  MessageType.user: 'user',
  MessageType.ai: 'ai',
  MessageType.system: 'system',
  MessageType.quickAction: 'quickAction',
  MessageType.voice: 'voice',
};

const _$MessageStatusEnumMap = {
  MessageStatus.sending: 'sending',
  MessageStatus.sent: 'sent',
  MessageStatus.delivered: 'delivered',
  MessageStatus.error: 'error',
};

_QuickReply _$QuickReplyFromJson(Map<String, dynamic> json) => _QuickReply(
      id: json['id'] as String,
      text: json['text'] as String,
      payload: json['payload'] as String?,
      isAction: json['isAction'] as bool? ?? false,
    );

Map<String, dynamic> _$QuickReplyToJson(_QuickReply instance) =>
    <String, dynamic>{
      'id': instance.id,
      'text': instance.text,
      'payload': instance.payload,
      'isAction': instance.isAction,
    };

_QuickQuery _$QuickQueryFromJson(Map<String, dynamic> json) => _QuickQuery(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      icon: json['icon'] as String,
    );

Map<String, dynamic> _$QuickQueryToJson(_QuickQuery instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'content': instance.content,
      'icon': instance.icon,
    };
