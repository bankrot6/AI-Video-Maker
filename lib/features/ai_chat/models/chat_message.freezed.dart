// dart format width=80
// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat_message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ChatMessage {
  String get id;
  String get content;
  MessageType get type;
  DateTime get timestamp;
  MessageStatus get status;
  String? get errorMessage;
  Map<String, dynamic>? get metadata;
  List<QuickReply>? get quickReplies;
  @JsonKey(includeFromJson: false, includeToJson: false)
  List<ExerciseSuggestion>?
      get exerciseSuggestions; // Поля для голосовых сообщений
  String? get audioPath;
  int? get audioDurationMs;

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ChatMessageCopyWith<ChatMessage> get copyWith =>
      _$ChatMessageCopyWithImpl<ChatMessage>(this as ChatMessage, _$identity);

  /// Serializes this ChatMessage to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ChatMessage &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage) &&
            const DeepCollectionEquality().equals(other.metadata, metadata) &&
            const DeepCollectionEquality()
                .equals(other.quickReplies, quickReplies) &&
            const DeepCollectionEquality()
                .equals(other.exerciseSuggestions, exerciseSuggestions) &&
            (identical(other.audioPath, audioPath) ||
                other.audioPath == audioPath) &&
            (identical(other.audioDurationMs, audioDurationMs) ||
                other.audioDurationMs == audioDurationMs));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      content,
      type,
      timestamp,
      status,
      errorMessage,
      const DeepCollectionEquality().hash(metadata),
      const DeepCollectionEquality().hash(quickReplies),
      const DeepCollectionEquality().hash(exerciseSuggestions),
      audioPath,
      audioDurationMs);

  @override
  String toString() {
    return 'ChatMessage(id: $id, content: $content, type: $type, timestamp: $timestamp, status: $status, errorMessage: $errorMessage, metadata: $metadata, quickReplies: $quickReplies, exerciseSuggestions: $exerciseSuggestions, audioPath: $audioPath, audioDurationMs: $audioDurationMs)';
  }
}

/// @nodoc
abstract mixin class $ChatMessageCopyWith<$Res> {
  factory $ChatMessageCopyWith(
          ChatMessage value, $Res Function(ChatMessage) _then) =
      _$ChatMessageCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String content,
      MessageType type,
      DateTime timestamp,
      MessageStatus status,
      String? errorMessage,
      Map<String, dynamic>? metadata,
      List<QuickReply>? quickReplies,
      @JsonKey(includeFromJson: false, includeToJson: false)
      List<ExerciseSuggestion>? exerciseSuggestions,
      String? audioPath,
      int? audioDurationMs});
}

/// @nodoc
class _$ChatMessageCopyWithImpl<$Res> implements $ChatMessageCopyWith<$Res> {
  _$ChatMessageCopyWithImpl(this._self, this._then);

  final ChatMessage _self;
  final $Res Function(ChatMessage) _then;

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? content = null,
    Object? type = null,
    Object? timestamp = null,
    Object? status = null,
    Object? errorMessage = freezed,
    Object? metadata = freezed,
    Object? quickReplies = freezed,
    Object? exerciseSuggestions = freezed,
    Object? audioPath = freezed,
    Object? audioDurationMs = freezed,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      content: null == content
          ? _self.content
          : content // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as MessageType,
      timestamp: null == timestamp
          ? _self.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      status: null == status
          ? _self.status
          : status // ignore: cast_nullable_to_non_nullable
              as MessageStatus,
      errorMessage: freezed == errorMessage
          ? _self.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      metadata: freezed == metadata
          ? _self.metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      quickReplies: freezed == quickReplies
          ? _self.quickReplies
          : quickReplies // ignore: cast_nullable_to_non_nullable
              as List<QuickReply>?,
      exerciseSuggestions: freezed == exerciseSuggestions
          ? _self.exerciseSuggestions
          : exerciseSuggestions // ignore: cast_nullable_to_non_nullable
              as List<ExerciseSuggestion>?,
      audioPath: freezed == audioPath
          ? _self.audioPath
          : audioPath // ignore: cast_nullable_to_non_nullable
              as String?,
      audioDurationMs: freezed == audioDurationMs
          ? _self.audioDurationMs
          : audioDurationMs // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _ChatMessage implements ChatMessage {
  const _ChatMessage(
      {required this.id,
      required this.content,
      required this.type,
      required this.timestamp,
      this.status = MessageStatus.sent,
      this.errorMessage,
      final Map<String, dynamic>? metadata,
      final List<QuickReply>? quickReplies,
      @JsonKey(includeFromJson: false, includeToJson: false)
      final List<ExerciseSuggestion>? exerciseSuggestions,
      this.audioPath,
      this.audioDurationMs})
      : _metadata = metadata,
        _quickReplies = quickReplies,
        _exerciseSuggestions = exerciseSuggestions;
  factory _ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);

  @override
  final String id;
  @override
  final String content;
  @override
  final MessageType type;
  @override
  final DateTime timestamp;
  @override
  @JsonKey()
  final MessageStatus status;
  @override
  final String? errorMessage;
  final Map<String, dynamic>? _metadata;
  @override
  Map<String, dynamic>? get metadata {
    final value = _metadata;
    if (value == null) return null;
    if (_metadata is EqualUnmodifiableMapView) return _metadata;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  final List<QuickReply>? _quickReplies;
  @override
  List<QuickReply>? get quickReplies {
    final value = _quickReplies;
    if (value == null) return null;
    if (_quickReplies is EqualUnmodifiableListView) return _quickReplies;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  final List<ExerciseSuggestion>? _exerciseSuggestions;
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  List<ExerciseSuggestion>? get exerciseSuggestions {
    final value = _exerciseSuggestions;
    if (value == null) return null;
    if (_exerciseSuggestions is EqualUnmodifiableListView)
      return _exerciseSuggestions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

// Поля для голосовых сообщений
  @override
  final String? audioPath;
  @override
  final int? audioDurationMs;

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$ChatMessageCopyWith<_ChatMessage> get copyWith =>
      __$ChatMessageCopyWithImpl<_ChatMessage>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$ChatMessageToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _ChatMessage &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage) &&
            const DeepCollectionEquality().equals(other._metadata, _metadata) &&
            const DeepCollectionEquality()
                .equals(other._quickReplies, _quickReplies) &&
            const DeepCollectionEquality()
                .equals(other._exerciseSuggestions, _exerciseSuggestions) &&
            (identical(other.audioPath, audioPath) ||
                other.audioPath == audioPath) &&
            (identical(other.audioDurationMs, audioDurationMs) ||
                other.audioDurationMs == audioDurationMs));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      content,
      type,
      timestamp,
      status,
      errorMessage,
      const DeepCollectionEquality().hash(_metadata),
      const DeepCollectionEquality().hash(_quickReplies),
      const DeepCollectionEquality().hash(_exerciseSuggestions),
      audioPath,
      audioDurationMs);

  @override
  String toString() {
    return 'ChatMessage(id: $id, content: $content, type: $type, timestamp: $timestamp, status: $status, errorMessage: $errorMessage, metadata: $metadata, quickReplies: $quickReplies, exerciseSuggestions: $exerciseSuggestions, audioPath: $audioPath, audioDurationMs: $audioDurationMs)';
  }
}

/// @nodoc
abstract mixin class _$ChatMessageCopyWith<$Res>
    implements $ChatMessageCopyWith<$Res> {
  factory _$ChatMessageCopyWith(
          _ChatMessage value, $Res Function(_ChatMessage) _then) =
      __$ChatMessageCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String content,
      MessageType type,
      DateTime timestamp,
      MessageStatus status,
      String? errorMessage,
      Map<String, dynamic>? metadata,
      List<QuickReply>? quickReplies,
      @JsonKey(includeFromJson: false, includeToJson: false)
      List<ExerciseSuggestion>? exerciseSuggestions,
      String? audioPath,
      int? audioDurationMs});
}

/// @nodoc
class __$ChatMessageCopyWithImpl<$Res> implements _$ChatMessageCopyWith<$Res> {
  __$ChatMessageCopyWithImpl(this._self, this._then);

  final _ChatMessage _self;
  final $Res Function(_ChatMessage) _then;

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? content = null,
    Object? type = null,
    Object? timestamp = null,
    Object? status = null,
    Object? errorMessage = freezed,
    Object? metadata = freezed,
    Object? quickReplies = freezed,
    Object? exerciseSuggestions = freezed,
    Object? audioPath = freezed,
    Object? audioDurationMs = freezed,
  }) {
    return _then(_ChatMessage(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      content: null == content
          ? _self.content
          : content // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as MessageType,
      timestamp: null == timestamp
          ? _self.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      status: null == status
          ? _self.status
          : status // ignore: cast_nullable_to_non_nullable
              as MessageStatus,
      errorMessage: freezed == errorMessage
          ? _self.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      metadata: freezed == metadata
          ? _self._metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
      quickReplies: freezed == quickReplies
          ? _self._quickReplies
          : quickReplies // ignore: cast_nullable_to_non_nullable
              as List<QuickReply>?,
      exerciseSuggestions: freezed == exerciseSuggestions
          ? _self._exerciseSuggestions
          : exerciseSuggestions // ignore: cast_nullable_to_non_nullable
              as List<ExerciseSuggestion>?,
      audioPath: freezed == audioPath
          ? _self.audioPath
          : audioPath // ignore: cast_nullable_to_non_nullable
              as String?,
      audioDurationMs: freezed == audioDurationMs
          ? _self.audioDurationMs
          : audioDurationMs // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// @nodoc
mixin _$QuickReply {
  String get id;
  String get text;
  String? get payload;
  bool get isAction;

  /// Create a copy of QuickReply
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $QuickReplyCopyWith<QuickReply> get copyWith =>
      _$QuickReplyCopyWithImpl<QuickReply>(this as QuickReply, _$identity);

  /// Serializes this QuickReply to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is QuickReply &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.payload, payload) || other.payload == payload) &&
            (identical(other.isAction, isAction) ||
                other.isAction == isAction));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, text, payload, isAction);

  @override
  String toString() {
    return 'QuickReply(id: $id, text: $text, payload: $payload, isAction: $isAction)';
  }
}

/// @nodoc
abstract mixin class $QuickReplyCopyWith<$Res> {
  factory $QuickReplyCopyWith(
          QuickReply value, $Res Function(QuickReply) _then) =
      _$QuickReplyCopyWithImpl;
  @useResult
  $Res call({String id, String text, String? payload, bool isAction});
}

/// @nodoc
class _$QuickReplyCopyWithImpl<$Res> implements $QuickReplyCopyWith<$Res> {
  _$QuickReplyCopyWithImpl(this._self, this._then);

  final QuickReply _self;
  final $Res Function(QuickReply) _then;

  /// Create a copy of QuickReply
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? text = null,
    Object? payload = freezed,
    Object? isAction = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      text: null == text
          ? _self.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      payload: freezed == payload
          ? _self.payload
          : payload // ignore: cast_nullable_to_non_nullable
              as String?,
      isAction: null == isAction
          ? _self.isAction
          : isAction // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _QuickReply implements QuickReply {
  const _QuickReply(
      {required this.id,
      required this.text,
      this.payload,
      this.isAction = false});
  factory _QuickReply.fromJson(Map<String, dynamic> json) =>
      _$QuickReplyFromJson(json);

  @override
  final String id;
  @override
  final String text;
  @override
  final String? payload;
  @override
  @JsonKey()
  final bool isAction;

  /// Create a copy of QuickReply
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$QuickReplyCopyWith<_QuickReply> get copyWith =>
      __$QuickReplyCopyWithImpl<_QuickReply>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$QuickReplyToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _QuickReply &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.payload, payload) || other.payload == payload) &&
            (identical(other.isAction, isAction) ||
                other.isAction == isAction));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, text, payload, isAction);

  @override
  String toString() {
    return 'QuickReply(id: $id, text: $text, payload: $payload, isAction: $isAction)';
  }
}

/// @nodoc
abstract mixin class _$QuickReplyCopyWith<$Res>
    implements $QuickReplyCopyWith<$Res> {
  factory _$QuickReplyCopyWith(
          _QuickReply value, $Res Function(_QuickReply) _then) =
      __$QuickReplyCopyWithImpl;
  @override
  @useResult
  $Res call({String id, String text, String? payload, bool isAction});
}

/// @nodoc
class __$QuickReplyCopyWithImpl<$Res> implements _$QuickReplyCopyWith<$Res> {
  __$QuickReplyCopyWithImpl(this._self, this._then);

  final _QuickReply _self;
  final $Res Function(_QuickReply) _then;

  /// Create a copy of QuickReply
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? text = null,
    Object? payload = freezed,
    Object? isAction = null,
  }) {
    return _then(_QuickReply(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      text: null == text
          ? _self.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      payload: freezed == payload
          ? _self.payload
          : payload // ignore: cast_nullable_to_non_nullable
              as String?,
      isAction: null == isAction
          ? _self.isAction
          : isAction // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
mixin _$QuickQuery {
  String get id;
  String get title;
  String get content;
  String get icon;

  /// Create a copy of QuickQuery
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $QuickQueryCopyWith<QuickQuery> get copyWith =>
      _$QuickQueryCopyWithImpl<QuickQuery>(this as QuickQuery, _$identity);

  /// Serializes this QuickQuery to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is QuickQuery &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.icon, icon) || other.icon == icon));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, title, content, icon);

  @override
  String toString() {
    return 'QuickQuery(id: $id, title: $title, content: $content, icon: $icon)';
  }
}

/// @nodoc
abstract mixin class $QuickQueryCopyWith<$Res> {
  factory $QuickQueryCopyWith(
          QuickQuery value, $Res Function(QuickQuery) _then) =
      _$QuickQueryCopyWithImpl;
  @useResult
  $Res call({String id, String title, String content, String icon});
}

/// @nodoc
class _$QuickQueryCopyWithImpl<$Res> implements $QuickQueryCopyWith<$Res> {
  _$QuickQueryCopyWithImpl(this._self, this._then);

  final QuickQuery _self;
  final $Res Function(QuickQuery) _then;

  /// Create a copy of QuickQuery
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? content = null,
    Object? icon = null,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      content: null == content
          ? _self.content
          : content // ignore: cast_nullable_to_non_nullable
              as String,
      icon: null == icon
          ? _self.icon
          : icon // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _QuickQuery implements QuickQuery {
  const _QuickQuery(
      {required this.id,
      required this.title,
      required this.content,
      required this.icon});
  factory _QuickQuery.fromJson(Map<String, dynamic> json) =>
      _$QuickQueryFromJson(json);

  @override
  final String id;
  @override
  final String title;
  @override
  final String content;
  @override
  final String icon;

  /// Create a copy of QuickQuery
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$QuickQueryCopyWith<_QuickQuery> get copyWith =>
      __$QuickQueryCopyWithImpl<_QuickQuery>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$QuickQueryToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _QuickQuery &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.icon, icon) || other.icon == icon));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, title, content, icon);

  @override
  String toString() {
    return 'QuickQuery(id: $id, title: $title, content: $content, icon: $icon)';
  }
}

/// @nodoc
abstract mixin class _$QuickQueryCopyWith<$Res>
    implements $QuickQueryCopyWith<$Res> {
  factory _$QuickQueryCopyWith(
          _QuickQuery value, $Res Function(_QuickQuery) _then) =
      __$QuickQueryCopyWithImpl;
  @override
  @useResult
  $Res call({String id, String title, String content, String icon});
}

/// @nodoc
class __$QuickQueryCopyWithImpl<$Res> implements _$QuickQueryCopyWith<$Res> {
  __$QuickQueryCopyWithImpl(this._self, this._then);

  final _QuickQuery _self;
  final $Res Function(_QuickQuery) _then;

  /// Create a copy of QuickQuery
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? content = null,
    Object? icon = null,
  }) {
    return _then(_QuickQuery(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _self.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      content: null == content
          ? _self.content
          : content // ignore: cast_nullable_to_non_nullable
              as String,
      icon: null == icon
          ? _self.icon
          : icon // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

// dart format on
