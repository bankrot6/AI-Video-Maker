import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../config/credit_config.dart';
import '../../models/credit_usage_model.dart';
import '../../providers/credit_providers.dart';
import '../../services/android_system_ui_controller.dart';
import '../personalization/friend_personalization_screen.dart';
import 'friend_voice_screen.dart';
import '../personalization/personalization_providers.dart';
import 'data/messenger_storage_repository.dart';
import 'data/messenger_pending_ai_task_repository.dart';
import 'messenger_providers.dart';
import 'messenger_mood_screen.dart';
import 'models/friend_profile.dart';
import 'models/messenger_mood_state.dart';
import 'models/messenger_contact.dart';
import 'models/messenger_message.dart';
import 'models/messenger_pending_ai_task.dart';
import 'models/messenger_thread.dart';
import 'services/messenger_pending_ai_task_service.dart';
import 'services/messenger_activity_suggester.dart';
import 'services/messenger_ai_service.dart';
import 'services/messenger_image_prompt_builder.dart';
import 'services/messenger_outfit_service.dart';
import 'widgets/messenger_avatar.dart';
import 'widgets/messenger_avatar_viewer.dart';
import 'widgets/messenger_image_viewer.dart';
import '../../services/credit_service.dart';
import '../../services/localization/app_localization_service.dart';
import '../../services/notification/notification_manager.dart';
import '../../services/providers.dart';
import '../../services/voice_message_storage.dart';
import '../../utils/navigation.dart';

enum _MessageAction {
  reply,
  forward,
  save,
  copy,
  delete,
}

class MessengerChatScreen extends ConsumerStatefulWidget {
  final MessengerThread thread;

  const MessengerChatScreen({
    super.key,
    required this.thread,
  });

  @override
  ConsumerState<MessengerChatScreen> createState() =>
      _MessengerChatScreenState();
}

class _MessengerChatScreenState extends ConsumerState<MessengerChatScreen>
    with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final FocusNode _inputFocus = FocusNode();
  final Random _random = Random();
  late final StateController<String?> _activeChatNotifier;
  late final MessengerActivitySuggester _activitySuggester =
      MessengerActivitySuggester(random: _random);
  final MessengerImagePromptBuilder _imagePromptBuilder =
      const MessengerImagePromptBuilder();
  static const List<String> _imageWaitReplies = [
    'Секунду, фото почти готово.',
    'Минутку, сейчас пришлю.',
    'Еще чуть-чуть, уже заканчиваю.',
    'Почти готово, еще пару секунд.',
    'Сейчас отправлю, буквально мгновение.',
  ];
  static const List<String> _photoRequestTokens = [
    'фото',
    'фотк',
    'селфи',
    'картин',
    'изображен',
    'снимок',
    'photo',
    'selfie',
    'picture',
    'pic',
  ];
  static const List<String> _photoRequestActions = [
    'покажи',
    'покажешь',
    'покажите',
    'скинь',
    'скиньте',
    'пришли',
    'пришлешь',
    'пришлите',
    'отправь',
    'отправите',
    'сфоткай',
    'сфотка',
    'сними',
    'сделай',
    'send',
    'show',
  ];
  static const List<String> _photoRequestTargets = [
    'себя',
    'лицо',
    'как ты',
    'как ты сейчас',
    'как выглядишь',
    'как ты выглядишь',
    'как ты выглядишь сейчас',
    'what do you look like',
  ];
  static const List<String> _voiceCommandPrefixes = [
    '/voice',
    '/голос',
    'voice:',
    'голос:',
    'голосом:',
  ];
  static const List<String> _voiceTriggerPhrases = [
    'расскажи',
    'расскажи голосом',
    'расскажи в чате',
  ];
  static const List<String> _photoDeclineTokens = [
    'хватит фото',
    'не надо фото',
    'не шли фото',
    'не присылай фото',
    'перестань слать фото',
    'не хочу фото',
    'достаточно фото',
    'больше не нужно фото',
    'хватит',
    'стоп фото',
    'без фото',
    'не нужно фото',
    'stop photo',
    'no photo',
    'enough photo',
  ];
  bool _isComposing = false;
  bool _isAwaitingResponse = false;
  bool _isFriendOnline = false;
  bool _isFriendTyping = false;
  bool _isGeneratingImage = false;
  MessengerImageReplyPlan? _pendingPhotoOffer;
  bool _isSendingPhotoStatus = false;
  bool _isSendingVoiceStatus = false;
  bool _isAvatarUpdating = false;
  bool _showScrollToBottom = false;
  bool _autoScrollEnabled = true;
  bool _hasInitialScroll = false;
  bool _keyboardTransition = false;
  bool _isProgrammaticScroll = false;
  double _lastViewInsets = 0;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  int _requestToken = 0;
  int _photoPresenceToken = 0;
  late MessengerThread _thread;
  late final MessengerStorageRepository _storageRepository;
  late final MessengerPendingAiTaskRepository _pendingAiTaskRepository;
  late final MessengerPendingAiTaskService _pendingAiTaskService;
  MessengerMessage? _replyToMessage;
  final AudioPlayer _voicePlayer = AudioPlayer();
  StreamSubscription<void>? _voicePlayerCompleteSubscription;
  StreamSubscription<Duration>? _voicePlayerDurationSubscription;
  StreamSubscription<MessengerThreadUpdate>? _threadUpdatesSub;
  Timer? _scrollButtonDebounce;
  Timer? _keyboardTransitionTimer;
  String? _playingVoiceMessageId;
  final Map<String, Duration> _voiceMessageDurations = {};
  DateTime? _recordingStartTime;
  final Set<String> _processingMessageIds = {};

  bool _isFriendContact(String contactId) {
    return contactId.startsWith('friend');
  }

  FriendProfile? _readFriendProfile(String contactId) {
    if (!_isFriendContact(contactId)) return null;
    return ref.read(friendProfileRepositoryProvider).load(contactId);
  }

  String? _readUserGender() {
    return ref.read(userGenderProvider);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AndroidSystemUiController.showNavigationBar();
    _thread = widget.thread;
    _storageRepository = ref.read(messengerStorageRepositoryProvider);
    _pendingAiTaskRepository = ref.read(messengerPendingAiTaskRepositoryProvider);
    _pendingAiTaskService = ref.read(messengerPendingAiTaskServiceProvider);
    _threadUpdatesSub = _storageRepository.threadUpdates.listen((update) {
      unawaited(_handleThreadUpdate(update));
    });
    _activeChatNotifier = ref.read(activeMessengerChatIdProvider.notifier);
    Future(() {
      if (!mounted) return;
      _activeChatNotifier.state = _thread.contact.id;
      NotificationManager().activeChatContactId = _thread.contact.id;
    });
    _isFriendOnline = _statusLooksOnline(_thread.contact.status);
    _textController.addListener(_handleTextChanged);
    _itemPositionsListener.itemPositions
        .addListener(_handleItemPositionsChanged);
    _voicePlayerCompleteSubscription =
        _voicePlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playingVoiceMessageId = null;
        });
      } else {
        _playingVoiceMessageId = null;
      }
    });
    _voicePlayerDurationSubscription =
        _voicePlayer.onDurationChanged.listen((duration) {
      final messageId = _playingVoiceMessageId;
      if (messageId == null || duration == Duration.zero) return;
      final existing = _voiceMessageDurations[messageId];
      if (existing != null &&
          existing.inMilliseconds == duration.inMilliseconds) {
        return;
      }
      if (mounted) {
        setState(() {
          _voiceMessageDurations[messageId] = duration;
        });
      } else {
        _voiceMessageDurations[messageId] = duration;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToInitialPosition();
      unawaited(_pendingAiTaskService.processPendingTasks());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AndroidSystemUiController.hideNavigationBar();
    _textController.removeListener(_handleTextChanged);
    _textController.dispose();
    _itemPositionsListener.itemPositions
        .removeListener(_handleItemPositionsChanged);
    _inputFocus.dispose();
    _voicePlayerCompleteSubscription?.cancel();
    _voicePlayerDurationSubscription?.cancel();
    _threadUpdatesSub?.cancel();
    _scrollButtonDebounce?.cancel();
    _keyboardTransitionTimer?.cancel();
    _voicePlayer.dispose();
    _markThreadReadUpToLatest();
    final contactId = _thread.contact.id;
    if (_activeChatNotifier.state == contactId) {
      _activeChatNotifier.state = null;
    }
    if (NotificationManager().activeChatContactId == contactId) {
      NotificationManager().activeChatContactId = null;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AndroidSystemUiController.refresh();
      });
      unawaited(_pendingAiTaskService.processPendingTasks());
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted || !_hasInitialScroll) return;
    final newInsets = WidgetsBinding
        .instance.platformDispatcher.views.first.viewInsets.bottom;
    final changed = (newInsets - _lastViewInsets).abs() > 10;
    _lastViewInsets = newInsets;
    if (!changed) return;
    _keyboardTransition = true;
    _keyboardTransitionTimer?.cancel();
    _keyboardTransitionTimer = Timer(const Duration(milliseconds: 400), () {
      _keyboardTransition = false;
      if (mounted) _updateScrollButton();
    });
  }

  bool get _isAppInForeground =>
      _appLifecycleState == AppLifecycleState.resumed;

  Future<void> _maybeNotifyIncomingMessage(
    MessengerMessage message, {
    String? overrideBody,
  }) async {
    if (message.isMine) return;
    if (_isAppInForeground) return;
    final manager = NotificationManager();
    if (manager.isMessengerNotificationSuppressed(message.id)) return;
    final isVoice =
        (message.audioPath != null && message.audioPath!.isNotEmpty) ||
            (message.audioUrl != null && message.audioUrl!.isNotEmpty);
    final body =
        isVoice ? 'Голосовое сообщение' : (overrideBody ?? message.text).trim();
    if (body.isEmpty) return;
    final enabled = await manager.areNotificationsEnabled();
    if (!enabled) return;
    await manager.sendMessengerNotification(
      title: _thread.contact.name,
      body: body,
      contactId: _thread.contact.id,
      messageId: message.id,
    );
  }

  void _handleTextChanged() {
    final hasText = _textController.text.isNotEmpty;
    if (hasText == _isComposing) return;
    setState(() {
      _isComposing = hasText;
    });
  }

  Future<void> _startRecording() async {
    final speech = ref.read(speechRecognitionServiceProvider);
    try {
      setState(() {
        _recordingStartTime = DateTime.now();
      });
      speech.setPreserveAudioFile(true);
      await speech.startListening();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось начать запись: $e')),
      );
    }
  }

  Future<String?> _stopRecordingRaw() async {
    final speech = ref.read(speechRecognitionServiceProvider);
    try {
      return await speech.stopRecording(transcribe: false);
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось остановить запись: $e')),
      );
    }
    return null;
  }

  Future<void> _cancelRecording() async {
    final speech = ref.read(speechRecognitionServiceProvider);
    try {
      final tempPath = await speech.stopRecording(transcribe: false);
      if (tempPath != null && tempPath.isNotEmpty) {
        try {
          await File(tempPath).delete();
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _recordingStartTime = null;
      });
    } else {
      _recordingStartTime = null;
    }
  }

  Future<void> _finalizeVoiceMessage() async {
    final tempPath = await _stopRecordingRaw();
    if (tempPath == null || tempPath.isEmpty) return;
    String audioPath;
    try {
      audioPath = await VoiceMessageStorage.saveFromTemp(tempPath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить запись: $e')),
      );
      return;
    }
    final durationMs = _recordingStartTime == null
        ? 0
        : DateTime.now().difference(_recordingStartTime!).inMilliseconds;
    final message = await _appendVoiceMessage(
      audioPath: audioPath,
      durationMs: durationMs,
    );
    if (message == null) return;
    unawaited(
      _transcribeVoiceMessage(
        messageId: message.id,
        audioPath: audioPath,
      ),
    );
  }

  String get _presenceLabel {
    if (!_thread.aiEnabled) return 'личное';
    if (_isSendingPhotoStatus) return 'отправляет фото...';
    if (_isSendingVoiceStatus) return 'отправляет голосовое...';
    if (_isFriendTyping) return 'печатает...';
    return _isFriendOnline ? 'онлайн' : 'был(а) недавно';
  }

  bool _statusLooksOnline(String status) {
    final lowered = status.toLowerCase();
    return lowered.contains('онлайн') || lowered.contains('в сети');
  }

  ImageProvider? _resolveAvatarImage(MessengerContact contact) {
    final path = contact.avatarPath;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return FileImage(file);
  }

  File? _resolveAvatarFile(MessengerContact contact) {
    final path = contact.avatarPath;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return file;
  }

  MessengerMessageQuote? _buildQuote(MessengerMessage? message) {
    if (message == null) return null;
    final text = message.text.trim();
    final hasImage = message.imagePath != null || message.imageUrl != null;
    final hasAudio = message.audioPath != null || message.audioUrl != null;
    final resolvedText = text.isNotEmpty
        ? text
        : hasAudio
            ? 'Голосовое сообщение'
            : '';
    final authorName = message.isMine ? 'Вы' : _thread.contact.name;
    return MessengerMessageQuote(
      messageId: message.id,
      authorName: authorName,
      text: resolvedText,
      hasImage: hasImage,
    );
  }

  void _setReplyToMessage(MessengerMessage message) {
    setState(() {
      _replyToMessage = message;
    });
    _inputFocus.requestFocus();
  }

  void _clearReplyToMessage() {
    if (_replyToMessage == null) return;
    setState(() {
      _replyToMessage = null;
    });
  }

  void _openAvatarViewer(MessengerContact contact) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessengerAvatarViewer(contact: contact),
      ),
    );
  }

  void _openMoodScreen(MessengerContact contact) {
    if (!_isFriendContact(contact.id)) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessengerMoodScreen(
          contactId: contact.id,
          contactName: contact.name,
        ),
      ),
    );
  }

  Future<MessengerMoodState?> _loadMoodState() async {
    if (!_isFriendContact(_thread.contact.id)) return null;
    final service = ref.read(messengerMoodServiceProvider);
    return service.load(_thread.contact.id);
  }

  void _setFriendOnline(bool value) {
    if (!mounted || _isFriendOnline == value) return;
    setState(() {
      _isFriendOnline = value;
    });
  }

  void _setFriendTyping(bool value) {
    if (!mounted || _isFriendTyping == value) return;
    setState(() {
      _isFriendTyping = value;
    });
  }

  void _setSendingPhotoStatus(bool value) {
    if (_isSendingPhotoStatus == value) return;
    if (mounted) {
      setState(() {
        _isSendingPhotoStatus = value;
      });
    } else {
      _isSendingPhotoStatus = value;
    }
  }

  void _setSendingVoiceStatus(bool value) {
    if (_isSendingVoiceStatus == value) return;
    if (mounted) {
      setState(() {
        _isSendingVoiceStatus = value;
      });
    } else {
      _isSendingVoiceStatus = value;
    }
  }

  void _startPhotoPresenceSequence(int token) {
    final sequence = ++_photoPresenceToken;
    _setFriendTyping(false);
    _setSendingPhotoStatus(false);
    _setFriendOnline(true);
    final sendDelay = _randomDelay(1200, 2000);
    unawaited(() async {
      await Future.delayed(sendDelay);
      if (!_isActiveRequest(token, allowBackground: true)) return;
      if (sequence != _photoPresenceToken) return;
      _setSendingPhotoStatus(true);
    }());
  }

  void _stopPhotoPresenceSequence() {
    _photoPresenceToken++;
    _setSendingPhotoStatus(false);
  }

  Future<void> _toggleVoicePlayback(MessengerMessage message) async {
    if (_playingVoiceMessageId == message.id) {
      await _stopVoicePlayback();
      return;
    }
    final audioPath = await _ensureVoiceAudioPath(message);
    if (audioPath == null || audioPath.isEmpty) {
      _showVoiceSnack('Не удалось воспроизвести аудио.');
      return;
    }
    await _voicePlayer.stop();
    if (mounted) {
      setState(() {
        _playingVoiceMessageId = message.id;
      });
    } else {
      _playingVoiceMessageId = message.id;
    }
    try {
      await _voicePlayer.play(DeviceFileSource(audioPath));
    } catch (e) {
      await _voicePlayer.stop();
      if (mounted) {
        setState(() {
          _playingVoiceMessageId = null;
        });
      } else {
        _playingVoiceMessageId = null;
      }
      _showVoiceSnack('Не удалось воспроизвести аудио.');
    }
  }

  Future<void> _stopVoicePlayback() async {
    await _voicePlayer.stop();
    if (mounted) {
      setState(() {
        _playingVoiceMessageId = null;
      });
    } else {
      _playingVoiceMessageId = null;
    }
  }

  Future<String?> _ensureVoiceAudioPath(MessengerMessage message) async {
    final existingPath = message.audioPath;
    if (existingPath != null && existingPath.isNotEmpty) {
      final file = File(existingPath);
      if (file.existsSync()) return existingPath;
    }
    final url = message.audioUrl?.trim();
    if (url == null || url.isEmpty) return null;
    final file = await _downloadVoiceAudio(url);
    if (file == null) return null;
    await _persistMessageUpdate(
      _storageRepository,
      message.id,
      audioPath: file.path,
      audioUrl: url,
    );
    return file.path;
  }

  Future<File?> _downloadVoiceAudio(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;
      final directory = await getApplicationDocumentsDirectory();
      final folder = Directory(path.join(directory.path, 'voice_messages'));
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      final extension = _guessAudioExtension(
        uri.path,
        response.headers['content-type'],
      );
      final fileName =
          'voice_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final filePath = path.join(folder.path, fileName);
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  String _guessAudioExtension(String pathValue, String? contentType) {
    final lowerPath = pathValue.toLowerCase();
    if (lowerPath.endsWith('.mp3')) return 'mp3';
    if (lowerPath.endsWith('.wav')) return 'wav';
    if (lowerPath.endsWith('.ogg') || lowerPath.endsWith('.opus')) return 'ogg';
    final lowerType = (contentType ?? '').toLowerCase();
    if (lowerType.contains('audio/mpeg')) return 'mp3';
    if (lowerType.contains('audio/wav') || lowerType.contains('audio/x-wav')) {
      return 'wav';
    }
    if (lowerType.contains('audio/ogg') || lowerType.contains('opus')) {
      return 'ogg';
    }
    return 'mp3';
  }

  void _markUserMessageRead(MessengerMessage userMessage) {
    _updateMessageStatus(userMessage.id, MessengerMessageStatus.read);
  }

  Duration _randomDelay(int minMs, int maxMs) {
    final safeMin = minMs < 0 ? 0 : minMs;
    final safeMax = maxMs < safeMin ? safeMin : maxMs;
    final value = safeMin + _random.nextInt(safeMax - safeMin + 1);
    return Duration(milliseconds: value);
  }

  Duration _typingDelayForText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Duration.zero;
    final length = min(trimmed.length, 220);
    final perCharMs = 14 + _random.nextInt(22);
    final rawMs = length * perCharMs;
    final cappedMs = rawMs.clamp(420, 5200).toInt();
    return Duration(milliseconds: cappedMs);
  }

  Future<void> _simulateFriendTyping({
    required int token,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (!_isActiveRequest(token, allowBackground: true)) return;
    _setFriendTyping(true);
    final delay = _typingDelayForText(trimmed);
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    if (!_isActiveRequest(token, allowBackground: true)) {
      _setFriendTyping(false);
      return;
    }
    _setFriendTyping(false);
  }

  void _scheduleFastReadReceipt({
    required int token,
    required MessengerMessage userMessage,
  }) {
    final delay = _randomDelay(180, 420);
    unawaited(() async {
      await Future.delayed(delay);
      if (!_isActiveRequest(token, allowBackground: true)) return false;
      _markUserMessageRead(userMessage);
    }());
  }

  String _pickImageWaitReply() {
    if (_imageWaitReplies.isEmpty) return 'Секунду.';
    return _imageWaitReplies[_random.nextInt(_imageWaitReplies.length)];
  }

  bool _isDelayedPhotoReply(String reply) {
    final text = reply.trim().toLowerCase();
    if (text.isEmpty) return false;
    const delayedPhrases = [
      'найду минутку',
      'найду время',
      'потом пришлю',
      'потом сделаю',
      'потом скину',
      'сделаю потом',
      'пришлю потом',
      'как найду минутку',
      'как сделаю',
      'сейчас найду',
      'найду и пришлю',
      'найду и сделаю',
    ];
    return delayedPhrases.any((phrase) => text.contains(phrase));
  }

  String _resolveImagePrompt({
    required String userMessage,
    required MessengerImageReplyPlan plan,
    required MessengerActivitySuggestion suggestion,
  }) {
    final planPrompt = plan.imagePrompt.trim();
    if (planPrompt.isNotEmpty) return planPrompt;
    final fallback = _mapActivityToEnglish(suggestion.fallback);
    if (fallback.isNotEmpty) {
      if (plan.isSelfie) {
        final lower = fallback.toLowerCase();
        if (lower.contains('light')) {
          return 'phone selfie, $fallback';
        }
        return 'phone selfie, $fallback, natural light';
      }
      return 'photorealistic phone photo of $fallback, natural light, no people';
    }
    return plan.isSelfie
        ? 'phone selfie, casual setting, natural light'
        : 'photorealistic phone photo, natural light, no people';
  }

  String _mapActivityToEnglish(String value) {
    final normalized = _normalizeMessage(value);
    if (normalized.isEmpty) return '';
    if (normalized.contains('пробеж') || normalized.contains('бег')) {
      return 'running outdoors, athletic wear, natural light';
    }
    if (normalized.contains('зал') || normalized.contains('трен')) {
      return 'working out at the gym';
    }
    if (normalized.contains('офис') || normalized.contains('работ')) {
      return 'working at the office';
    }
    if (normalized.contains('кофе') || normalized.contains('кафе')) {
      return 'having coffee in a cafe';
    }
    if (normalized.contains('ванн') || normalized.contains('душ')) {
      return 'in a clean bathroom, mirror selfie, soft indoor light';
    }
    if (normalized.contains('прогул') || normalized.contains('парк')) {
      return 'walking outside in a park';
    }
    if (normalized.contains('дома')) {
      return 'relaxing at home';
    }
    return '';
  }

  Future<void> _sendMessage({
    String? overrideText,
    String? audioPath,
    int? audioDurationMs,
  }) async {
    if (_isAwaitingResponse && !_isGeneratingImage) return;
    final rawText = overrideText ?? _textController.text;
    final text = rawText.trim();
    final hasAudio = audioPath != null && audioPath.isNotEmpty;
    if (text.isEmpty && !hasAudio) return;
    final voiceCommand = text.isEmpty ? null : _extractVoiceCommand(text);
    final hasVoiceCommand =
        voiceCommand != null && voiceCommand.trim().isNotEmpty;
    final hasVoiceTriggerPhrase =
        text.isNotEmpty && _hasVoiceTriggerPhrase(text);
    final wantsVoiceReply = hasVoiceCommand || hasVoiceTriggerPhrase;
    final effectiveText =
        text.isNotEmpty ? (hasVoiceCommand ? voiceCommand.trim() : text) : '';
    final shouldWaitForImage = _thread.aiEnabled && _isGeneratingImage;
    final shouldStory = text.isNotEmpty && _shouldPublishStory(text);
    final isImageChat = _thread.persona.chatMode == MessengerChatMode.image;
    final shouldAwaitResponse =
        _thread.aiEnabled && !shouldWaitForImage && effectiveText.isNotEmpty;
    final now = DateTime.now();
    final repository = ref.read(messengerStorageRepositoryProvider);
    final quote = _buildQuote(_replyToMessage);
    final userMessage = MessengerMessage(
      id: _id(now),
      text: effectiveText,
      time: now,
      isMine: true,
      status: _thread.aiEnabled && effectiveText.isNotEmpty
          ? MessengerMessageStatus.sending
          : MessengerMessageStatus.delivered,
      quote: quote,
      audioPath: hasAudio ? audioPath : null,
      audioDurationMs: hasAudio ? audioDurationMs : null,
    );
    setState(() {
      _thread.messages.add(userMessage);
      if (overrideText == null) {
        _textController.clear();
        _isComposing = false;
      }
      _isAwaitingResponse = shouldAwaitResponse;
      _replyToMessage = null;
    });
    _scrollToBottom(jump: true, force: true);
    await repository.upsertMessage(
      contactId: _thread.contact.id,
      message: userMessage,
    );
    if (!_thread.aiEnabled || effectiveText.isEmpty) {
      await repository.saveThread(_thread);
      return;
    }
    await _enqueuePendingAiTask(
      userMessage: userMessage,
      rawText: text,
      wantsVoiceReply: wantsVoiceReply,
      shouldWaitForImage: shouldWaitForImage,
      shouldStory: shouldStory,
      isImageChat: isImageChat,
      isVoiceMessage: false,
    );
    unawaited(_pendingAiTaskService.processPendingTasks());
    if (!mounted) {
      return;
    }
    final isCompleted = await _runAiFlowForUserMessage(
      userMessage: userMessage,
      rawText: text,
      wantsVoiceReply: wantsVoiceReply,
      shouldWaitForImage: shouldWaitForImage,
      shouldStory: shouldStory,
      isImageChat: isImageChat,
      isVoiceMessage: false,
    );
    if (isCompleted) {
      await _dequeuePendingAiTask(userMessage.id);
    }
  }

  Future<MessengerMessage?> _appendVoiceMessage({
    required String audioPath,
    required int durationMs,
  }) async {
    if (_isAwaitingResponse && !_isGeneratingImage) return null;
    final now = DateTime.now();
    final quote = _buildQuote(_replyToMessage);
    final message = MessengerMessage(
      id: _id(now),
      text: '',
      time: now,
      isMine: true,
      status: MessengerMessageStatus.delivered,
      quote: quote,
      audioPath: audioPath,
      audioDurationMs: durationMs,
    );
    if (mounted) {
      setState(() {
        _thread.messages.add(message);
        _replyToMessage = null;
      });
    } else {
      _thread.messages.add(message);
      _replyToMessage = null;
    }
    _scrollToBottom(jump: true, force: true);
    await _storageRepository.upsertMessage(
      contactId: _thread.contact.id,
      message: message,
    );
    return message;
  }

  Future<void> _enqueuePendingAiTask({
    required MessengerMessage userMessage,
    required String rawText,
    required bool wantsVoiceReply,
    required bool shouldWaitForImage,
    required bool shouldStory,
    required bool isImageChat,
    required bool isVoiceMessage,
  }) async {
    final existing = await _pendingAiTaskRepository.findByMessageId(
      contactId: _thread.contact.id,
      userMessageId: userMessage.id,
    );
    final now = DateTime.now();
    final task = MessengerPendingAiTask(
      id: existing?.id ?? _id(now),
      type: MessengerPendingAiTaskType.aiFlow,
      contactId: _thread.contact.id,
      userMessageId: userMessage.id,
      rawText: rawText,
      wantsVoiceReply: wantsVoiceReply,
      shouldWaitForImage: shouldWaitForImage,
      shouldStory: shouldStory,
      isImageChat: isImageChat,
      isVoiceMessage: isVoiceMessage,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      retryCount: existing?.retryCount ?? 0,
      nextRetryAt: null,
      lastError: null,
    );
    await _pendingAiTaskRepository.upsert(task);
  }

  Future<void> _dequeuePendingAiTask(String userMessageId) async {
    await _pendingAiTaskRepository.removeByMessageId(
      contactId: _thread.contact.id,
      userMessageId: userMessageId,
    );
  }

  Future<void> _transcribeVoiceMessage({
    required String messageId,
    required String audioPath,
  }) async {
    final speech = ref.read(speechRecognitionServiceProvider);
    String text;
    try {
      text = await speech.transcribeFile(audioPath);
    } catch (e) {
      debugPrint('🔴 MESSENGER: Ошибка транскрибации: $e');
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final voiceCommand = _extractVoiceCommand(trimmed);
    final hasVoiceCommand =
        voiceCommand != null && voiceCommand.trim().isNotEmpty;
    final effectiveText = hasVoiceCommand ? voiceCommand.trim() : trimmed;

    await _persistMessageUpdate(
      _storageRepository,
      messageId,
      text: effectiveText,
    );

    if (!_thread.aiEnabled || effectiveText.isEmpty) return;

    final hasVoiceTriggerPhrase = _hasVoiceTriggerPhrase(trimmed);
    final wantsVoiceReply = hasVoiceCommand || hasVoiceTriggerPhrase;
    final shouldWaitForImage = _thread.aiEnabled && _isGeneratingImage;
    final shouldStory = _shouldPublishStory(trimmed);
    final isImageChat = _thread.persona.chatMode == MessengerChatMode.image;
    final shouldAwaitResponse =
        _thread.aiEnabled && !shouldWaitForImage && effectiveText.isNotEmpty;

    if (mounted) {
      setState(() {
        _isAwaitingResponse = shouldAwaitResponse;
      });
    } else {
      _isAwaitingResponse = shouldAwaitResponse;
    }

    MessengerMessage? userMessage;
    try {
      final latestThread =
          await _storageRepository.loadThreadById(_thread.contact.id);
      for (final message in latestThread.messages) {
        if (message.id == messageId) {
          userMessage = message;
          break;
        }
      }
    } catch (_) {
      userMessage = null;
    }
    if (userMessage == null) {
      for (final message in _thread.messages) {
        if (message.id == messageId) {
          userMessage = message;
          break;
        }
      }
    }
    if (userMessage == null) return;

    await _enqueuePendingAiTask(
      userMessage: userMessage,
      rawText: trimmed,
      wantsVoiceReply: wantsVoiceReply,
      shouldWaitForImage: shouldWaitForImage,
      shouldStory: shouldStory,
      isImageChat: isImageChat,
      isVoiceMessage: true,
    );
    unawaited(_pendingAiTaskService.processPendingTasks());
    if (!mounted) {
      return;
    }
    final isCompleted = await _runAiFlowForUserMessage(
      userMessage: userMessage,
      rawText: trimmed,
      wantsVoiceReply: wantsVoiceReply,
      shouldWaitForImage: shouldWaitForImage,
      shouldStory: shouldStory,
      isImageChat: isImageChat,
      isVoiceMessage: true,
    );
    if (isCompleted) {
      await _dequeuePendingAiTask(userMessage.id);
    }
  }

  Future<bool> _runAiFlowForUserMessage({
    required MessengerMessage userMessage,
    required String rawText,
    required bool wantsVoiceReply,
    required bool shouldWaitForImage,
    required bool shouldStory,
    required bool isImageChat,
    required bool isVoiceMessage,
  }) async {
    if (!mounted) return false;
    await _dequeuePendingAiTask(userMessage.id);
    if (_processingMessageIds.contains(userMessage.id)) {
      return false;
    }
    _processingMessageIds.add(userMessage.id);
    try {
      return await _runAiFlowForUserMessageImpl(
        userMessage: userMessage,
        rawText: rawText,
        wantsVoiceReply: wantsVoiceReply,
        shouldWaitForImage: shouldWaitForImage,
        shouldStory: shouldStory,
        isImageChat: isImageChat,
        isVoiceMessage: isVoiceMessage,
      );
    } finally {
      _processingMessageIds.remove(userMessage.id);
    }
  }

  Future<bool> _runAiFlowForUserMessageImpl({
    required MessengerMessage userMessage,
    required String rawText,
    required bool wantsVoiceReply,
    required bool shouldWaitForImage,
    required bool shouldStory,
    required bool isImageChat,
    required bool isVoiceMessage,
  }) async {
    if (!mounted) return false;

    final creditUsage = await CreditService().getCreditUsage();
    final hasCredits = creditUsage.remainingCredits > 0;
    if (!hasCredits) {
      _showPaywallFromChat();
      return true;
    }
    final isFree = creditUsage.isFreeUser;

    final token = shouldWaitForImage ? _requestToken : ++_requestToken;
    _scheduleMessageStatus(
      messageId: userMessage.id,
      status: MessengerMessageStatus.delivered,
      delay: _randomDelay(120, 240),
    );
    _scheduleFastReadReceipt(token: token, userMessage: userMessage);
    final pendingOffer = _pendingPhotoOffer;
    _pendingPhotoOffer = null;
    if (!isFree && pendingOffer != null && _isPositivePhotoResponse(rawText)) {
      await _runAvatarImageReplyFlow(
        token: token,
        userMessage: userMessage,
        planOverride: pendingOffer,
        sendPlanReply: true,
      );
      return true;
    }
    final wantsVoice = _shouldUseVoiceReply(
      wantsVoiceReply: wantsVoiceReply,
      isVoiceMessage: isVoiceMessage,
    );
    final shouldVoiceReply = !isFree && wantsVoice;
    
    if (isFree && wantsVoice) {
      final canUseAudio = await CreditService().canUseFreeAudio();
      if (!canUseAudio) {
        await _sendFreeAudioLimitMessage(
          repository: ref.read(messengerStorageRepositoryProvider),
          userMessage: userMessage,
        );
        return true;
      }
      await CreditService().useFreeAudio();
    }
    
    if (shouldVoiceReply) {
      await _runVoiceReplyFlow(
        token: token,
        userMessage: userMessage,
      );
    }
    if (!isFree && shouldWaitForImage) {
      if (!shouldVoiceReply) {
        return _runImagePendingReplyFlow(
          token: token,
          userMessage: userMessage,
        );
      }
      return true;
    }
    if (!isFree && isImageChat) {
      return _runImageReplyFlow(
        token: token,
        userMessage: userMessage,
      );
    }
    if (!isFree && shouldStory) {
      return _runStoryPublishFlow(
        token: token,
        userMessage: userMessage,
      );
    }
    if (_looksLikePhotoDecline(rawText)) {
      await _handlePhotoDecline();
      return _runReplyFlow(
        token: token,
        userMessage: userMessage,
      );
    }
    
    final looksLikePhoto = _looksLikeImageRequest(rawText);
    
    if (looksLikePhoto) {
      await _clearPhotoDecline();
    }
    
    if (_thread.memory.userDeclinedPhotos && !looksLikePhoto) {
      debugPrint('🚫 PHOTO_DECLINE: Пропускаем фото-флоу, пользователь отказался');
      return _runReplyFlow(
        token: token,
        userMessage: userMessage,
      );
    }
    
    if (looksLikePhoto) {
      if (isFree) {
        final canUsePhoto = await CreditService().canUseFreePhoto();
        if (!canUsePhoto) {
          await _sendFreePhotoLimitMessage(
            repository: ref.read(messengerStorageRepositoryProvider),
            userMessage: userMessage,
          );
          return true;
        }
        await CreditService().useFreePhoto();
      }
      
      final plan = await _detectImageIntentPlan(
        userMessage: userMessage,
        fallbackReply: _pickImageWaitReply(),
        fallbackWantsPhoto: true,
        useFallbackPrompt: true,
      );
      if (_isActiveRequest(token, allowBackground: true) &&
          plan != null &&
          plan.wantsPhoto) {
        await _runAvatarImageReplyFlow(
          token: token,
          userMessage: userMessage,
          planOverride: plan,
          sendPlanReply: !shouldVoiceReply,
        );
        return true;
      }
      return _runReplyFlow(
        token: token,
        userMessage: userMessage,
      );
    }
    if (shouldVoiceReply) return true;
    if (!_thread.memory.userDeclinedPhotos) {
      final canUseFreePhoto = isFree
          ? await CreditService().canUseFreePhoto()
          : true;
      if (canUseFreePhoto) {
        final planFuture = _detectImageIntentPlan(
          userMessage: userMessage,
          fallbackReply: null,
          fallbackWantsPhoto: false,
          useFallbackPrompt: false,
        );
        unawaited(_runBackgroundImagePlan(
          token: token,
          userMessage: userMessage,
          planFuture: planFuture,
          isFreeUser: isFree,
        ));
      }
    }
    return _runReplyFlow(
      token: token,
      userMessage: userMessage,
    );
  }

  Future<bool> _runReplyFlow({
    required int token,
    required MessengerMessage userMessage,
  }) async {
    final repository = ref.read(messengerStorageRepositoryProvider);
    final responseFuture = _fetchAiReply(userMessage: userMessage);
    _scheduleMessageStatus(
      messageId: userMessage.id,
      status: MessengerMessageStatus.delivered,
      delay: _randomDelay(200, 450),
    );

    final wasOnline = _isFriendOnline;
    final onlineDelay = wasOnline ? Duration.zero : _randomDelay(3000, 8000);
    final readDelay =
        wasOnline ? _randomDelay(600, 1200) : _randomDelay(900, 1800);
    unawaited(() async {
      await _ensureOnlineAfterDelay(token, onlineDelay);
      if (!_isActiveRequest(token, allowBackground: true)) return false;
      await Future.delayed(readDelay);
      _updateMessageStatus(userMessage.id, MessengerMessageStatus.read);
    }());

    try {
      final response = await responseFuture;
      if (!_isActiveRequest(token, allowBackground: true)) return false;
      if (response == null) return false;
      _markUserMessageRead(userMessage);
      await _simulateFriendTyping(token: token, text: response);
      if (!_isActiveRequest(token, allowBackground: true)) return false;
      final aiMessageId =
          _id(DateTime.now().add(const Duration(milliseconds: 1)));
      await _appendMessage(
        repository,
        MessengerMessage(
          id: aiMessageId,
          text: response,
          time: DateTime.now(),
          isMine: false,
        ),
      );
      _markUserMessageRead(userMessage);
      if (mounted) {
        unawaited(_updateMemorySummary());
      }
      return true;
    } finally {
      if (mounted && token == _requestToken) {
        setState(() {
          _isAwaitingResponse = false;
        });
        _setFriendTyping(false);
      }
      _scheduleOfflineAfterReply(token);
    }
  }

  Future<bool> _runVoiceReplyFlow({
    required int token,
    required MessengerMessage userMessage,
  }) async {
    final repository = ref.read(messengerStorageRepositoryProvider);
    final voiceService = ref.read(messengerVoiceServiceProvider);
    final creditNotifier = ref.read(creditUsageNotifierProvider.notifier);
    final responseFuture = _fetchAiReply(userMessage: userMessage);
    _scheduleMessageStatus(
      messageId: userMessage.id,
      status: MessengerMessageStatus.delivered,
      delay: _randomDelay(200, 450),
    );

    final wasOnline = _isFriendOnline;
    final onlineDelay = wasOnline ? Duration.zero : _randomDelay(3000, 8000);
    final readDelay =
        wasOnline ? _randomDelay(600, 1200) : _randomDelay(900, 1800);
    unawaited(() async {
      await _ensureOnlineAfterDelay(token, onlineDelay);
      if (!_isActiveRequest(token, allowBackground: true)) return false;
      await Future.delayed(readDelay);
      _updateMessageStatus(userMessage.id, MessengerMessageStatus.read);
    }());

    try {
      final response = await responseFuture;
      if (!_isActiveRequest(token, allowBackground: true)) return false;
      if (response == null) return false;
      _markUserMessageRead(userMessage);
      _setFriendTyping(false);
      final voiceCost = CreditCost.forVoice(response.length);
      debugPrint('🎤 VOICE_FLOW: Ответ ${response.length} символов, '
          'стоимость $voiceCost кредитов');
      final voiceCostOk = await creditNotifier.useVoiceCredits(response);
      debugPrint('🎤 VOICE_FLOW: Списание кредитов: $voiceCostOk');
      if (!voiceCostOk) {
        debugPrint('🎤 VOICE_FLOW: Недостаточно кредитов → отправка текстом');
        await _appendMessage(
          repository,
          MessengerMessage(
            id: _id(DateTime.now().add(const Duration(milliseconds: 1))),
            text: response,
            time: DateTime.now(),
            isMine: false,
          ),
        );
        return true;
      }
      _setSendingVoiceStatus(true);
      final voiceResult = await voiceService.generateVoiceReply(
        text: response,
        contactId: _thread.contact.id,
        friendProfile: _readFriendProfile(_thread.contact.id),
      );
      if (!_isActiveRequest(token, allowBackground: true)) return false;
      _setSendingVoiceStatus(false);
      final aiMessageId =
          _id(DateTime.now().add(const Duration(milliseconds: 1)));
      if (voiceResult.isSuccess && voiceResult.audioPath != null) {
        await _appendMessage(
          repository,
          MessengerMessage(
            id: aiMessageId,
            text: response,
            time: DateTime.now(),
            isMine: false,
            audioPath: voiceResult.audioPath,
          ),
        );
      } else {
        if (voiceResult.errorMessage != null) {
          debugPrint(
            '🟣 VOICE: озвучка не удалась: ${voiceResult.errorMessage}',
          );
        }
        await _appendMessage(
          repository,
          MessengerMessage(
            id: aiMessageId,
            text: response,
            time: DateTime.now(),
            isMine: false,
          ),
        );
      }
      _markUserMessageRead(userMessage);
      if (mounted) {
        unawaited(_updateMemorySummary());
      }
      return true;
    } finally {
      _setSendingVoiceStatus(false);
      if (mounted && token == _requestToken) {
        setState(() {
          _isAwaitingResponse = false;
        });
        _setFriendTyping(false);
      }
      _scheduleOfflineAfterReply(token);
    }
  }

  Future<MessengerImageReplyPlan?> _detectImageIntentPlan({
    required MessengerMessage userMessage,
    String? fallbackReply,
    bool fallbackWantsPhoto = true,
    bool useFallbackPrompt = true,
    VoidCallback? onFirstChunk,
  }) async {
    if (!_isImageEligibleThread()) return null;
    final aiService = ref.read(messengerAiServiceProvider);
    final outfitService = ref.read(messengerOutfitServiceProvider);
    final friendPersona =
        ref.read(friendPersonaProvider(_thread.contact.id)).valueOrNull;
    final friendProfile = _readFriendProfile(_thread.contact.id);
    final moodState = await _loadMoodState();
    final context = _buildContextMessages(excludeMessageId: userMessage.id);
    final suggestion = _activitySuggester.buildSuggestion(
      userMessage: userMessage.text,
      recentMessages: context,
    );
    final outfitContext = await outfitService.buildPromptContext(
      contactId: _thread.contact.id,
    );
    final plan = await aiService.detectImageIntentPlan(
      thread: _thread,
      userMessage: userMessage.text,
      context: context,
      activityOptions: suggestion.options,
      fallbackWantsPhoto: fallbackWantsPhoto,
      fallbackReply: fallbackReply,
      useFallbackPrompt: useFallbackPrompt,
      friendPersona: friendPersona,
      friendProfile: friendProfile,
      moodState: moodState,
      userGender: _readUserGender(),
      onFirstChunk: onFirstChunk,
      previousOutfit: outfitContext.previousOutfit,
      previousSceneKey: outfitContext.previousSceneKey,
      minutesSinceOutfit: outfitContext.minutesSince,
      outfitTtlMinutes: outfitContext.outfitTtlMinutes,
    );
    return plan;
  }

  Future<void> _runBackgroundImagePlan({
    required int token,
    required MessengerMessage userMessage,
    required Future<MessengerImageReplyPlan?> planFuture,
    required bool isFreeUser,
  }) async {
    final plan = await planFuture;
    if (plan == null) return;
    if (!_isActiveRequest(token, allowBackground: true)) return;
    if (!plan.wantsPhoto) return;
    if (plan.imagePrompt.trim().isEmpty) return;
    if (_thread.memory.userDeclinedPhotos) {
      debugPrint('🚫 PHOTO_DECLINE: Пропускаем фоновое фото, пользователь отказался');
      return;
    }
    
    if (isFreeUser) {
      final canUsePhoto = await CreditService().canUseFreePhoto();
      if (!canUsePhoto) {
        debugPrint('🚫 FREE_PHOTO_LIMIT: Лимит фото исчерпан для бесплатного пользователя');
        return;
      }
      await CreditService().useFreePhoto();
    }
    
    await _runAvatarImageReplyFlow(
      token: token,
      userMessage: userMessage,
      planOverride: plan,
      sendPlanReply: false,
    );
  }

  Future<bool> _runImagePendingReplyFlow({
    required int token,
    required MessengerMessage userMessage,
  }) async {
    final repository = ref.read(messengerStorageRepositoryProvider);
    _setFriendTyping(false);
    _scheduleMessageStatus(
      messageId: userMessage.id,
      status: MessengerMessageStatus.delivered,
      delay: _randomDelay(180, 360),
    );

    final wasOnline = _isFriendOnline;
    final onlineDelay = wasOnline ? Duration.zero : _randomDelay(800, 1600);
    final readDelay =
        wasOnline ? _randomDelay(450, 900) : _randomDelay(700, 1200);
    unawaited(() async {
      await _ensureOnlineAfterDelay(token, onlineDelay);
      await Future.delayed(readDelay);
      _updateMessageStatus(userMessage.id, MessengerMessageStatus.read);
    }());

    try {
      await Future.delayed(_randomDelay(120, 240));
      if (!_isActiveRequest(token, allowBackground: true)) return false;
      final reply = _pickImageWaitReply();
      _markUserMessageRead(userMessage);
      await _simulateFriendTyping(token: token, text: reply);
      if (!_isActiveRequest(token, allowBackground: true)) return false;
      final replyMessage = MessengerMessage(
        id: _id(DateTime.now()),
        text: reply,
        time: DateTime.now(),
        isMine: false,
      );
      await _appendMessage(repository, replyMessage);
      return true;
    } finally {
      if (mounted && token == _requestToken) {
        setState(() {
          _isAwaitingResponse = false;
        });
      }
      _scheduleOfflineAfterReply(token);
    }
  }

  Future<bool> _runImageReplyFlow({
    required int token,
    required MessengerMessage userMessage,
  }) async {
    final repository = ref.read(messengerStorageRepositoryProvider);
    final imageService = ref.read(chatImageGenerationServiceProvider);
    final creditNotifier = ref.read(creditUsageNotifierProvider.notifier);
    _scheduleMessageStatus(
      messageId: userMessage.id,
      status: MessengerMessageStatus.delivered,
      delay: _randomDelay(200, 450),
    );

    final wasOnline = _isFriendOnline;
    final readDelay =
        wasOnline ? _randomDelay(500, 1100) : _randomDelay(800, 1600);
    unawaited(() async {
      await Future.delayed(readDelay);
      _updateMessageStatus(userMessage.id, MessengerMessageStatus.read);
    }());

    try {
      _isGeneratingImage = true;
      _startPhotoPresenceSequence(token);
      final aiMessageId =
          _id(DateTime.now().add(const Duration(milliseconds: 1)));
      final pendingMessage = MessengerMessage(
        id: aiMessageId,
        text: 'Генерирую изображение...',
        time: DateTime.now(),
        isMine: false,
      );
      await _appendMessage(repository, pendingMessage,
          notifyIfBackground: false);
      _markUserMessageRead(userMessage);

      final result =
          await imageService.generateImageFromPrompt(userMessage.text);
      if (!_isActiveRequest(token, allowBackground: true)) return false;
      _setFriendTyping(false);

      if (result.file != null) {
        unawaited(creditNotifier.useImageCredits());
        await _persistMessageUpdate(
          repository,
          aiMessageId,
          text: 'Готово! Вот изображение.',
          imagePath: result.file!.path,
        );
        return true;
      } else {
        if (result.errorMessage != null) {
          debugPrint(
              '🔴 MESSENGER: Ошибка генерации изображения: ${result.errorMessage}');
        }
        await _silentlyRemoveMessage(repository, aiMessageId);
        return false;
      }
    } finally {
      _isGeneratingImage = false;
      _stopPhotoPresenceSequence();
      if (mounted && token == _requestToken) {
        setState(() {
          _isAwaitingResponse = false;
        });
      }
      _scheduleOfflineAfterReply(token);
    }
  }

  Future<bool> _runAvatarImageReplyFlow({
    required int token,
    required MessengerMessage userMessage,
    MessengerImageReplyPlan? planOverride,
    bool sendPlanReply = true,
  }) async {
    if (!mounted) return false;
    final repository = ref.read(messengerStorageRepositoryProvider);
    final imageService = ref.read(avatarImageGenerationServiceProvider);
    final aiService = ref.read(messengerAiServiceProvider);
    final outfitService = ref.read(messengerOutfitServiceProvider);
    final creditNotifier = ref.read(creditUsageNotifierProvider.notifier);
    final friendPersona =
        ref.read(friendPersonaProvider(_thread.contact.id)).valueOrNull;
    var friendProfile = _readFriendProfile(_thread.contact.id);
    final moodState = await _loadMoodState();
    final avatarFile = _resolveAvatarFile(_thread.contact);
    Future<FriendProfile?>? appearanceFuture;
    if (friendProfile != null && avatarFile != null) {
      final appearanceService = ref.read(friendAppearanceServiceProvider);
      appearanceFuture = appearanceService.ensureAppearanceDescription(
        profile: friendProfile,
        avatarFile: avatarFile,
        contactId: _thread.contact.id,
      );
    }
    _isGeneratingImage = true;
    _scheduleMessageStatus(
      messageId: userMessage.id,
      status: MessengerMessageStatus.delivered,
      delay: _randomDelay(200, 450),
    );

    final wasOnline = _isFriendOnline;
    final onlineDelay = wasOnline ? Duration.zero : _randomDelay(2500, 5200);
    final readDelay =
        wasOnline ? _randomDelay(600, 1200) : _randomDelay(900, 1700);
    unawaited(() async {
      await _ensureOnlineAfterDelay(token, onlineDelay);
      await Future.delayed(readDelay);
      _updateMessageStatus(userMessage.id, MessengerMessageStatus.read);
    }());

    try {
      final context = _buildContextMessages(excludeMessageId: userMessage.id);
      final suggestion = _activitySuggester.buildSuggestion(
        userMessage: userMessage.text,
        recentMessages: context,
      );
      MessengerOutfitPromptContext? outfitContext;
      if (planOverride == null) {
        outfitContext = await outfitService.buildPromptContext(
          contactId: _thread.contact.id,
        );
      }
      final plan = planOverride ??
          await aiService.generateImageReplyPlan(
            thread: _thread,
            userMessage: userMessage.text,
            context: context,
            activityOptions: suggestion.options,
            fallbackCaption: suggestion.fallback,
            fallbackReply: _pickImageWaitReply(),
            friendPersona: friendPersona,
            friendProfile: friendProfile,
            moodState: moodState,
            userGender: _readUserGender(),
            previousOutfit: outfitContext?.previousOutfit,
            previousSceneKey: outfitContext?.previousSceneKey,
            minutesSinceOutfit: outfitContext?.minutesSince,
            outfitTtlMinutes: outfitContext?.outfitTtlMinutes,
          );
      if (!_isActiveRequest(token, allowBackground: true)) return false;
      debugPrint(
        '🟣 MESSENGER: DeepSeek image_prompt="${plan.imagePrompt}"',
      );
      if (sendPlanReply) {
        final replyTextToShow = _isDelayedPhotoReply(plan.replyText)
            ? _pickImageWaitReply()
            : plan.replyText;
        _markUserMessageRead(userMessage);
        await _simulateFriendTyping(token: token, text: replyTextToShow);
        if (!_isActiveRequest(token, allowBackground: true)) return false;
        final planMessage = MessengerMessage(
          id: _id(DateTime.now()),
          text: replyTextToShow,
          time: DateTime.now(),
          isMine: false,
        );
        await _appendMessage(repository, planMessage);
        _markUserMessageRead(userMessage);
        _setFriendTyping(false);
      }
      if (appearanceFuture != null) {
        final updatedProfile = await appearanceFuture;
        if (!_isActiveRequest(token, allowBackground: true)) return false;
        if (updatedProfile != null &&
            updatedProfile.appearanceDescription !=
                friendProfile?.appearanceDescription) {
          if (mounted) {
            if (_thread.contact.id == 'friend') {
              ref.read(friendProfileProvider.notifier).state = updatedProfile;
            }
          }
          friendProfile = updatedProfile;
        }
      }

      final isSelfie = plan.isSelfie;
      MessengerOutfitDecision? outfitDecision;
      if (isSelfie) {
        outfitDecision = await outfitService.resolveOutfit(
          contactId: _thread.contact.id,
          plan: plan,
        );
      }
      final resolvedPrompt = _resolveImagePrompt(
        userMessage: userMessage.text,
        plan: plan,
        suggestion: suggestion,
      );
      debugPrint('🟣 MESSENGER: Image prompt resolved="$resolvedPrompt"');
      final prompt = isSelfie
          ? _imagePromptBuilder.buildSelfiePrompt(
              userMessage: resolvedPrompt,
              caption: plan.imageCaption,
              friendName: _thread.contact.name,
              profile: friendProfile,
              allowRandomLocation: true,
              outfit: outfitDecision?.outfit,
              totalMessageCount: _thread.messages.length,
            )
          : _imagePromptBuilder.buildScenePrompt(
              userMessage: resolvedPrompt,
              caption: plan.imageCaption,
              allowRandomLocation: true,
            );
      debugPrint('🟣 MESSENGER: Final image prompt="$prompt"');
      _startPhotoPresenceSequence(token);
      final result = isSelfie && avatarFile != null
          ? await imageService.generateImageFromPromptWithReference(
              prompt: prompt,
              referenceImage: avatarFile,
            )
          : await imageService.generateImageFromPrompt(prompt);
      if (!_isActiveRequest(token, allowBackground: true)) return false;

      if (result.file != null) {
        unawaited(creditNotifier.useImageCredits());
        final caption = plan.imageCaption.trim().isEmpty
            ? 'Вот так я сейчас'
            : plan.imageCaption.trim();
        final imageMessage = MessengerMessage(
          id: _id(DateTime.now()),
          text: caption,
          time: DateTime.now(),
          isMine: false,
          imagePath: result.file!.path,
        );
        await _appendMessage(repository, imageMessage);
        _markUserMessageRead(userMessage);
        return true;
      } else {
        if (result.errorMessage != null) {
          debugPrint(
              '🔴 MESSENGER: Ошибка генерации фото: ${result.errorMessage}');
        }
        _markUserMessageRead(userMessage);
        return false;
      }
    } finally {
      if (mounted && token == _requestToken) {
        setState(() {
          _isAwaitingResponse = false;
        });
      }
      _isGeneratingImage = false;
      _stopPhotoPresenceSequence();
      _scheduleOfflineAfterReply(token);
    }
  }

  Future<bool> _runStoryPublishFlow({
    required int token,
    required MessengerMessage userMessage,
  }) async {
    final repository = ref.read(messengerStorageRepositoryProvider);
    final storyPublisher = ref.read(messengerStoryPublisherProvider);
    final friendPersona =
        ref.read(friendPersonaProvider(_thread.contact.id)).valueOrNull;
    var friendProfile = _readFriendProfile(_thread.contact.id);
    final moodState = await _loadMoodState();
    final avatarFile = _resolveAvatarFile(_thread.contact);
    _scheduleMessageStatus(
      messageId: userMessage.id,
      status: MessengerMessageStatus.delivered,
      delay: _randomDelay(200, 450),
    );

    final wasOnline = _isFriendOnline;
    final onlineDelay = wasOnline ? Duration.zero : _randomDelay(2500, 5200);
    final readDelay =
        wasOnline ? _randomDelay(600, 1200) : _randomDelay(900, 1700);
    unawaited(() async {
      await _ensureOnlineAfterDelay(token, onlineDelay);
      await Future.delayed(readDelay);
      _updateMessageStatus(userMessage.id, MessengerMessageStatus.read);
    }());

    try {
      if (friendProfile != null && avatarFile != null) {
        final appearanceService = ref.read(friendAppearanceServiceProvider);
        final updatedProfile =
            await appearanceService.ensureAppearanceDescription(
          profile: friendProfile,
          avatarFile: avatarFile,
          contactId: _thread.contact.id,
        );
        if (!_isActiveRequest(token, allowBackground: true)) return false;
        if (updatedProfile.appearanceDescription !=
            friendProfile.appearanceDescription) {
          if (mounted && _thread.contact.id == 'friend') {
            ref.read(friendProfileProvider.notifier).state = updatedProfile;
          }
          friendProfile = updatedProfile;
        }
      }

      final context = _buildContextMessages(excludeMessageId: userMessage.id);
      final suggestion = _activitySuggester.buildSuggestion(
        userMessage: userMessage.text,
        recentMessages: context,
      );
      final aiService = ref.read(messengerAiServiceProvider);
      final plan = await aiService.generateStoryPlan(
        thread: _thread,
        userMessage: userMessage.text,
        context: context,
        activityOptions: suggestion.options,
        fallbackCaption: suggestion.fallback,
        friendPersona: friendPersona,
        friendProfile: friendProfile,
        moodState: moodState,
        userGender: _readUserGender(),
      );
      if (!_isActiveRequest(token, allowBackground: true)) return false;
      _markUserMessageRead(userMessage);
      await _simulateFriendTyping(token: token, text: plan.replyText);
      if (!_isActiveRequest(token, allowBackground: true)) return false;
      final aiMessageId =
          _id(DateTime.now().add(const Duration(milliseconds: 1)));
      await _appendMessage(
        repository,
        MessengerMessage(
          id: aiMessageId,
          text: plan.replyText,
          time: DateTime.now(),
          isMine: false,
        ),
        notifyIfBackground: false,
      );
      _markUserMessageRead(userMessage);
      final result = await storyPublisher.publishStory(
        thread: _thread,
        userMessage: userMessage.text,
        context: context,
        friendPersona: friendPersona,
        friendProfile: friendProfile,
        moodState: moodState,
        avatarFile: avatarFile,
        plan: plan,
        userGender: _readUserGender(),
      );
      if (!_isActiveRequest(token, allowBackground: true)) return false;

      _setFriendTyping(false);
      if (result.story != null) {
        final caption = result.story!.caption.trim();
        final message = caption.isEmpty
            ? 'Сторис готова! Я выложил(а) её.'
            : 'Сторис готова: $caption';
        await _persistMessageUpdate(
          repository,
          aiMessageId,
          text: message,
          storyId: result.story!.id,
        );
        return true;
      } else {
        if (result.errorMessage != null) {
          debugPrint(
              '🔴 MESSENGER: Ошибка генерации сторис: ${result.errorMessage}');
        }
        await _silentlyRemoveMessage(repository, aiMessageId);
        return false;
      }
    } finally {
      if (mounted && token == _requestToken) {
        setState(() {
          _isAwaitingResponse = false;
        });
        _setFriendTyping(false);
      }
      _scheduleOfflineAfterReply(token);
    }
  }

  bool _isActiveRequest(int token, {bool allowBackground = false}) {
    if (token != _requestToken) return false;
    if (mounted) return true;
    return allowBackground;
  }

  bool _shouldPublishStory(String message) {
    if (!_isStoryEligibleThread()) return false;
    final normalized = _normalizeMessage(message);
    if (normalized.isEmpty) return false;
    const storyTriggers = [
      'сторис',
      'стори',
      'story',
      'stories',
      'reels',
      'reel',
      'рилс',
      'шортс',
      'shorts',
      'ролик',
      'клип',
    ];
    return _containsAny(normalized, storyTriggers);
  }

  bool _isStoryEligibleThread() {
    if (!_thread.aiEnabled) return false;
    return _thread.persona.chatMode == MessengerChatMode.text;
  }

  bool _isImageEligibleThread() {
    final id = _thread.contact.id;
    if (_thread.persona.chatMode == MessengerChatMode.image) return false;
    return id.startsWith('friend');
  }

  String _normalizeMessage(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _containsAny(String text, List<String> needles) {
    for (final needle in needles) {
      if (text.contains(needle)) return true;
    }
    return false;
  }

  bool _isPositivePhotoResponse(String message) {
    final normalized = message.toLowerCase().trim();
    if (normalized.isEmpty) return false;
    const tokens = [
      'да',
      'давай',
      'ок',
      'окей',
      'конечно',
      'скинь',
      'покажи',
      'хочу',
      'го',
      'кидай',
      'присылай',
      'отправь',
      'скидывай',
      'ага',
      'угу',
      'жду',
      'пришли',
      'показывай',
      'канеш',
      'конеш',
      'ладно',
      'лан',
      'валяй',
      'скорее',
      'давай скинь',
      'хочу посмотреть',
      'было бы круто',
      'с удовольствием',
    ];
    for (final token in tokens) {
      if (normalized.contains(token)) return true;
    }
    return false;
  }

  bool _looksLikeImageRequest(String message) {
    final normalized = _normalizeMessage(message);
    if (normalized.isEmpty) return false;
    if (_looksLikePhotoDecline(message)) return false;
    if (_containsAny(normalized, _photoRequestTokens)) return true;
    final hasAction = _containsAny(normalized, _photoRequestActions);
    final hasTarget = _containsAny(normalized, _photoRequestTargets);
    return hasAction && hasTarget;
  }

  bool _looksLikePhotoDecline(String message) {
    final normalized = _normalizeMessage(message);
    if (normalized.isEmpty) return false;
    return _containsAny(normalized, _photoDeclineTokens);
  }

  Future<void> _handlePhotoDecline() async {
    final repository = ref.read(messengerStorageRepositoryProvider);
    final updated = _thread.memory.copyWith(
      userDeclinedPhotos: true,
      photoDeclineTimestamp: DateTime.now(),
    );
    setState(() {
      _thread = _thread.copyWith(memory: updated);
    });
    await repository.updateMemory(_thread.contact.id, updated);
    debugPrint('🚫 PHOTO_DECLINE: Пользователь отказался от фото');
  }

  Future<void> _clearPhotoDecline() async {
    if (!_thread.memory.userDeclinedPhotos) return;
    final repository = ref.read(messengerStorageRepositoryProvider);
    final updated = _thread.memory.copyWith(
      userDeclinedPhotos: false,
      photoDeclineTimestamp: null,
    );
    setState(() {
      _thread = _thread.copyWith(memory: updated);
    });
    await repository.updateMemory(_thread.contact.id, updated);
    debugPrint('✅ PHOTO_DECLINE: Отказ от фото снят');
  }

  String? _extractVoiceCommand(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return null;
    final lowered = trimmed.toLowerCase();
    for (final prefix in _voiceCommandPrefixes) {
      if (lowered.startsWith(prefix)) {
        final raw = trimmed.substring(prefix.length).trim();
        return raw;
      }
    }
    return null;
  }

  bool _hasVoiceTriggerPhrase(String message) {
    final normalized = _normalizeMessage(message);
    if (normalized.isEmpty) return false;
    for (final trigger in _voiceTriggerPhrases) {
      if (normalized.startsWith(trigger)) return true;
    }
    return false;
  }

  bool _isVoiceEligibleThread() {
    if (!_thread.aiEnabled) return false;
    return _thread.persona.chatMode == MessengerChatMode.text;
  }

  bool _shouldUseVoiceReply({
    required bool wantsVoiceReply,
    required bool isVoiceMessage,
  }) {
    if (!_thread.aiEnabled) {
      debugPrint('🎤 VOICE_DECISION: AI выключен → текст');
      return false;
    }
    if (isVoiceMessage) {
      debugPrint('🎤 VOICE_DECISION: Пользователь отправил голосовое → голос');
      return true;
    }
    if (!wantsVoiceReply) {
      debugPrint('🎤 VOICE_DECISION: Нет команды голоса → текст');
      return false;
    }
    final eligible = _isVoiceEligibleThread();
    debugPrint('🎤 VOICE_DECISION: Команда голоса, eligible=$eligible');
    return eligible;
  }

  Future<void> _ensureOnlineAfterDelay(int token, Duration delay) async {
    if (!_isActiveRequest(token)) return;
    if (delay == Duration.zero) {
      _setFriendOnline(true);
      return;
    }
    _setFriendOnline(true);
    await Future.delayed(delay);
    if (!_isActiveRequest(token)) return;
    _setFriendOnline(true);
  }

  void _scheduleOfflineAfterReply(int token) {
    final delay = _randomDelay(5000, 15000);
    Future.delayed(delay, () {
      if (!_isActiveRequest(token)) return;
      if (_isFriendTyping || _isGeneratingImage || _isSendingPhotoStatus)
        return;
      _setFriendOnline(false);
    });
  }

  void _scheduleMessageStatus({
    required String messageId,
    required MessengerMessageStatus status,
    required Duration delay,
  }) {
    Future.delayed(delay, () {
      _updateMessageStatus(messageId, status);
    });
  }

  void _updateMessageStatus(String messageId, MessengerMessageStatus status) {
    final index =
        _thread.messages.indexWhere((message) => message.id == messageId);
    if (index != -1) {
      final current = _thread.messages[index];
      if (_shouldAdvanceStatus(current.status, status)) {
        final updated = current.copyWith(status: status);
        if (mounted) {
          setState(() {
            _thread.messages[index] = updated;
          });
        } else {
          _thread.messages[index] = updated;
        }
      }
    }
    unawaited(
      _storageRepository.updateMessage(
        contactId: _thread.contact.id,
        messageId: messageId,
        update: (message) => _shouldAdvanceStatus(message.status, status)
            ? message.copyWith(status: status)
            : message,
      ),
    );
  }

  bool _shouldAdvanceStatus(
    MessengerMessageStatus current,
    MessengerMessageStatus next,
  ) {
    return _statusOrder(next) > _statusOrder(current);
  }

  int _statusOrder(MessengerMessageStatus status) {
    switch (status) {
      case MessengerMessageStatus.sending:
        return 0;
      case MessengerMessageStatus.delivered:
        return 1;
      case MessengerMessageStatus.read:
        return 2;
    }
  }

  void _showPaywallFromChat() {
    if (!mounted) return;
    AppNavigation.showPaywall(context);
  }

  Future<void> _sendFreePhotoLimitMessage({
    required MessengerStorageRepository repository,
    required MessengerMessage userMessage,
  }) async {
    final creditUsage = await CreditService().getCreditUsage();
    final remaining = creditUsage.remainingPhotos;
    final total = CreditUsageModel.freePhotoLimit;
    
    final aiMessageId = _id(DateTime.now().add(const Duration(milliseconds: 1)));
    await _appendMessage(
      repository,
      MessengerMessage(
        id: aiMessageId,
        text: 'К сожалению, вы исчерпали лимит на фото ($remaining/$total). '
            'Чтобы получать фото без ограничений, оформите подписку!',
        time: DateTime.now(),
        isMine: false,
        paywallAction: 'photo_limit',
      ),
    );
    _markUserMessageRead(userMessage);
  }

  Future<void> _sendFreeAudioLimitMessage({
    required MessengerStorageRepository repository,
    required MessengerMessage userMessage,
  }) async {
    final creditUsage = await CreditService().getCreditUsage();
    final remaining = creditUsage.remainingAudios;
    final total = CreditUsageModel.freeAudioLimit;
    
    final aiMessageId = _id(DateTime.now().add(const Duration(milliseconds: 1)));
    await _appendMessage(
      repository,
      MessengerMessage(
        id: aiMessageId,
        text: 'К сожалению, вы исчерпали лимит на голосовые сообщения ($remaining/$total). '
            'Чтобы получать голосовые без ограничений, оформите подписку!',
        time: DateTime.now(),
        isMine: false,
        paywallAction: 'audio_limit',
      ),
    );
    _markUserMessageRead(userMessage);
  }

  Future<String?> _fetchAiReply({
    required MessengerMessage userMessage,
  }) async {
    final hasCredits = await CreditService().hasCreditsForText();
    if (!hasCredits) {
      _showPaywallFromChat();
      return null;
    }

    final aiService = ref.read(messengerAiServiceProvider);
    final friendPersona =
        ref.read(friendPersonaProvider(_thread.contact.id)).valueOrNull;
    final moodNotifier = _isFriendContact(_thread.contact.id)
        ? ref.read(messengerMoodProvider(_thread.contact.id).notifier)
        : null;
    final creditNotifier = ref.read(creditUsageNotifierProvider.notifier);
    final friendProfile = _readFriendProfile(_thread.contact.id);
    final moodState = await _loadMoodState();
    final context = _buildContextMessages(excludeMessageId: userMessage.id);
    String accumulated = '';
    try {
      await for (final chunk in aiService.generateReplyStream(
        thread: _thread,
        userMessage: userMessage.text,
        context: context,
        friendPersona: friendPersona,
        friendProfile: friendProfile,
        moodState: moodState,
        userGender: _readUserGender(),
      )) {
        accumulated += chunk;
      }
    } catch (e) {
      debugPrint('🔴 MESSENGER: Ошибка ответа: $e');
    }
    final parsed = aiService.parseChatReply(accumulated);
    if (parsed.photoOffer != null && _isFriendContact(_thread.contact.id)) {
      _pendingPhotoOffer = parsed.photoOffer;
    }
    if (parsed.moodDelta != null && moodNotifier != null) {
      await moodNotifier.applyDelta(parsed.moodDelta!);
    }
    if (parsed.reply.trim().isNotEmpty) {
      unawaited(creditNotifier.useTextCredits(userMessage.text, parsed.reply));
      return parsed.reply.trim();
    }
    return null;
  }

  List<MessengerMessage> _buildContextMessages({String? excludeMessageId}) {
    final allMessages = _thread.messages
        .where((message) =>
            message.text.trim().isNotEmpty && message.id != excludeMessageId)
        .toList();
    
    if (allMessages.length <= 12) return allMessages;
    
    final recentCount = 8;
    final importantCount = 4;
    
    final recent = allMessages.sublist(allMessages.length - recentCount);
    final history = allMessages.sublist(0, allMessages.length - recentCount);
    
    final important = _selectImportantMessages(history, importantCount);
    
    return [...important, ...recent];
  }

  List<MessengerMessage> _selectImportantMessages(
    List<MessengerMessage> messages,
    int count,
  ) {
    if (messages.isEmpty) return [];
    if (messages.length <= count) return messages;
    
    final scored = <({MessengerMessage message, int score})>[];
    
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      final text = message.text.toLowerCase();
      var score = 0;
      
      if (message.isMine) {
        if (text.contains('?') || text.contains('как') || text.contains('что') ||
            text.contains('где') || text.contains('когда') || text.contains('почему')) {
          score += 3;
        }
        if (text.length > 80) score += 2;
      } else {
        if (i < messages.length - 1 && messages[i + 1].isMine) {
          final nextText = messages[i + 1].text.toLowerCase();
          if (nextText.contains('?')) score += 2;
        }
        if (text.length > 100) score += 1;
      }
      
      if (text.contains('важно') || text.contains('срочно') || 
          text.contains('проблем') || text.contains('помог')) {
        score += 4;
      }
      
      final recencyBonus = (i * 1.0 / messages.length * 2).round();
      score += recencyBonus;
      
      scored.add((message: message, score: score));
    }
    
    scored.sort((a, b) => b.score.compareTo(a.score));
    
    final selected = scored.take(count).map((e) => e.message).toList();
    selected.sort((a, b) => 
      messages.indexOf(a).compareTo(messages.indexOf(b))
    );
    
    return selected;
  }

  Future<void> _updateMemorySummary() async {
    final aiService = ref.read(messengerAiServiceProvider);
    final repository = ref.read(messengerStorageRepositoryProvider);
    final recentMessages = _buildContextMessages();
    final updatedSummary = await aiService.updateMemorySummary(
      thread: _thread,
      recentMessages: recentMessages,
      userGender: _readUserGender(),
    );
    if (updatedSummary.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _thread = _thread.copyWith(
        memory: _thread.memory.copyWith(
          summary: updatedSummary,
          updatedAt: DateTime.now(),
        ),
      );
    });
    await repository.updateMemory(_thread.contact.id, _thread.memory);
  }

  void _updateMessageMedia(
    String messageId, {
    String? text,
    String? imagePath,
    String? imageUrl,
    String? audioPath,
    String? audioUrl,
    int? audioDurationMs,
    String? storyId,
  }) {
    final index =
        _thread.messages.indexWhere((message) => message.id == messageId);
    if (index == -1) return;
    final existing = _thread.messages[index];
    _thread.messages[index] = existing.copyWith(
      text: text ?? existing.text,
      imagePath: imagePath ?? existing.imagePath,
      imageUrl: imageUrl ?? existing.imageUrl,
      audioPath: audioPath ?? existing.audioPath,
      audioUrl: audioUrl ?? existing.audioUrl,
      audioDurationMs: audioDurationMs ?? existing.audioDurationMs,
      storyId: storyId ?? existing.storyId,
    );
  }

  Future<void> _appendMessage(
    MessengerStorageRepository repository,
    MessengerMessage message, {
    bool notifyIfBackground = true,
  }) async {
    final shouldScroll = message.isMine || _autoScrollEnabled;
    if (mounted) {
      setState(() {
        _thread.messages.add(message);
      });
      if (shouldScroll) {
        _scrollToBottom(jump: true, force: true);
      }
    } else {
      _thread.messages.add(message);
    }
    if (!message.isMine && mounted) {
      _markThreadReadUpToLatest();
    }
    await repository.upsertMessage(
      contactId: _thread.contact.id,
      message: message,
    );
    if (notifyIfBackground) {
      unawaited(_maybeNotifyIncomingMessage(message));
    }
  }

  Future<void> _silentlyRemoveMessage(
    MessengerStorageRepository repository,
    String messageId,
  ) async {
    final index =
        _thread.messages.indexWhere((message) => message.id == messageId);
    if (index == -1) return;
    final updatedMessages = List<MessengerMessage>.from(_thread.messages)
      ..removeAt(index);
    if (mounted) {
      setState(() {
        _thread = _thread.copyWith(messages: updatedMessages);
      });
    } else {
      _thread = _thread.copyWith(messages: updatedMessages);
    }
    try {
      await repository.deleteMessage(
        contactId: _thread.contact.id,
        messageId: messageId,
      );
    } catch (e) {
      debugPrint('🔴 MESSENGER: Не удалось удалить placeholder: $e');
    }
  }

  Future<void> _persistMessageUpdate(
    MessengerStorageRepository repository,
    String messageId, {
    String? text,
    String? imagePath,
    String? imageUrl,
    String? audioPath,
    String? audioUrl,
    int? audioDurationMs,
    String? storyId,
  }) async {
    final index =
        _thread.messages.indexWhere((message) => message.id == messageId);
    final previous = index == -1 ? null : _thread.messages[index];
    void apply() {
      _updateMessageMedia(
        messageId,
        text: text,
        imagePath: imagePath,
        imageUrl: imageUrl,
        audioPath: audioPath,
        audioUrl: audioUrl,
        audioDurationMs: audioDurationMs,
        storyId: storyId,
      );
    }

    if (mounted) {
      setState(apply);
    } else {
      apply();
    }

    if (index != -1 && previous != null) {
      final updated = _thread.messages[index];
      final prevText = previous.text.trim();
      final nextText = updated.text.trim();
      final shouldNotify = !updated.isMine &&
          !_isAppInForeground &&
          nextText.isNotEmpty &&
          nextText != prevText;
      if (shouldNotify) {
        unawaited(_maybeNotifyIncomingMessage(updated, overrideBody: nextText));
      }
    }

    await repository.updateMessage(
      contactId: _thread.contact.id,
      messageId: messageId,
      update: (message) => message.copyWith(
        text: text ?? message.text,
        imagePath: imagePath ?? message.imagePath,
        imageUrl: imageUrl ?? message.imageUrl,
        audioPath: audioPath ?? message.audioPath,
        audioUrl: audioUrl ?? message.audioUrl,
        audioDurationMs: audioDurationMs ?? message.audioDurationMs,
        storyId: storyId ?? message.storyId,
      ),
    );
  }

  void _handleItemPositionsChanged() {
    if (!_hasInitialScroll) return;
    if (_keyboardTransition) return;
    if (_isProgrammaticScroll) return;
    _updateScrollButton();
  }

  void _updateScrollButton() {
    if (!mounted) return;
    final atBottom = _isAtBottom();
    if (atBottom && !_autoScrollEnabled) {
      _autoScrollEnabled = true;
    }
    if (!atBottom && _autoScrollEnabled) {
      _autoScrollEnabled = false;
    }
    _scheduleScrollButtonUpdate(atBottom);
  }

  void _scheduleScrollButtonUpdate(bool atBottom) {
    final shouldShow = !atBottom;
    if (shouldShow == _showScrollToBottom) return;
    _scrollButtonDebounce?.cancel();
    if (!shouldShow) {
      setState(() {
        _showScrollToBottom = false;
      });
      return;
    }
    _scrollButtonDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (_isAtBottom()) return;
      setState(() {
        _showScrollToBottom = true;
      });
    });
  }

  bool _isAtBottom() {
    if (_thread.messages.isEmpty) return true;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return true;
    return positions.any((p) => p.index == 0);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!_hasInitialScroll) return false;
    if (_keyboardTransition) return false;
    if (_isProgrammaticScroll) return false;
    if (notification is UserScrollNotification) {
      if (notification.direction != ScrollDirection.idle) {
        _autoScrollEnabled = false;
      }
    }
    return false;
  }

  Future<void> _handleThreadUpdate(MessengerThreadUpdate update) async {
    if (update.contactId != _thread.contact.id) return;
    if (!update.isIncomingMessage) return;
    final message = update.message;
    if (message == null) return;
    final alreadyExists =
        _thread.messages.any((existing) => existing.id == message.id);
    if (alreadyExists) return;
    if (!mounted) return;
    final shouldScroll = _autoScrollEnabled;
    setState(() {
      _thread.messages.add(message);
    });
    _markThreadReadUpToLatest();
    if (shouldScroll) {
      _scrollToBottom(jump: true, force: true);
    }
  }

  int? _firstUnreadIndex(DateTime lastReadAt) {
    for (var i = 0; i < _thread.messages.length; i += 1) {
      final message = _thread.messages[i];
      if (!message.isMine && message.time.isAfter(lastReadAt)) {
        return i;
      }
    }
    return null;
  }

  Future<void> _scrollToInitialPosition() async {
    if (_hasInitialScroll) return;
    if (_thread.messages.isEmpty) {
      _hasInitialScroll = true;
      return;
    }
    if (!_itemScrollController.isAttached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToInitialPosition();
      });
      return;
    }
    final lastReadAt = _storageRepository.getLastReadAt(_thread.contact.id) ??
        await _storageRepository.ensureLastReadAt(_thread);
    if (!mounted) return;
    final unreadIndex = _firstUnreadIndex(lastReadAt);
    if (unreadIndex != null) {
      _autoScrollEnabled = false;
      _scrollToIndex(unreadIndex, alignment: 0.3, jump: true);
    } else {
      _autoScrollEnabled = true;
      _itemScrollController.jumpTo(index: 0);
    }
    _hasInitialScroll = true;
    _markThreadReadUpToLatest();
  }

  void _scrollToIndex(
    int messageIndex, {
    double alignment = 0,
    bool jump = false,
  }) {
    if (!_itemScrollController.isAttached) return;
    if (messageIndex < 0 || messageIndex >= _thread.messages.length) return;
    final reversedIndex = _thread.messages.length - 1 - messageIndex;
    if (jump) {
      _itemScrollController.jumpTo(index: reversedIndex, alignment: alignment);
      return;
    }
    _itemScrollController.scrollTo(
      index: reversedIndex,
      alignment: alignment,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _scrollToBottom({bool jump = false, bool force = false}) {
    if (_thread.messages.isEmpty) return;
    if (!force && !_autoScrollEnabled) return;
    _autoScrollEnabled = true;
    _isProgrammaticScroll = true;
    _scrollButtonDebounce?.cancel();
    if (_showScrollToBottom && mounted) {
      setState(() {
        _showScrollToBottom = false;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _thread.messages.isEmpty) {
        _isProgrammaticScroll = false;
        return;
      }
      if (!_itemScrollController.isAttached) {
        _isProgrammaticScroll = false;
        return;
      }
      if (jump) {
        _itemScrollController.jumpTo(index: 0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _isProgrammaticScroll = false;
        });
      } else {
        _itemScrollController
            .scrollTo(
          index: 0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        )
            .whenComplete(() {
          _isProgrammaticScroll = false;
          if (mounted) _updateScrollButton();
        });
      }
    });
  }

  void _markThreadReadUpToLatest() {
    if (_thread.messages.isEmpty) return;
    unawaited(
      _storageRepository.markThreadRead(
        _thread.contact.id,
        _thread.messages.last.time,
      ),
    );
  }

  void _openImageViewer(MessengerMessage message) {
    final images = _thread.messages
        .where((item) => item.imagePath != null || item.imageUrl != null)
        .toList();
    if (images.isEmpty) return;
    final initialIndex = images.indexWhere((item) => item.id == message.id);
    if (initialIndex == -1) return;
    final canSetAvatar = _isFriendContact(_thread.contact.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessengerImageViewer(
          images: images,
          initialIndex: initialIndex,
          onSetAvatar: canSetAvatar ? _setAvatarFromMessage : null,
        ),
      ),
    );
  }

  static const String _changeAvatarHint =
      'Одежда, комната, место, фон, поза, аксессуары…';

  Future<void> _showChangeAvatarDialog(MessengerContact contact) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Сменить аватар'),
          content: SingleChildScrollView(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(ctx).colorScheme.outline.withOpacity(0.3),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: TextField(
                controller: controller,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: _changeAvatarHint,
                  border: InputBorder.none,
                  isDense: true,
                  hintStyle: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.45),
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(context.tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Создать'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (confirmed == true && mounted) {
      final wishes = controller.text.trim();
      await _changeAvatar(contact, userWishes: wishes.isEmpty ? null : wishes);
    }
  }

  Future<void> _changeAvatar(MessengerContact contact,
      {String? userWishes}) async {
    if (_isAvatarUpdating) return;
    if (!_isFriendContact(contact.id)) {
      _showAvatarSnack('Аватар можно менять только у друга.');
      return;
    }
    final profile = ref.read(friendProfileRepositoryProvider).load(contact.id);
    if (profile == null) {
      _showAvatarSnack('Профиль друга не найден.');
      return;
    }
    _isAvatarUpdating = true;
    if (mounted) {
      setState(() {
        _thread = _thread.copyWith(
          contact: _thread.contact.copyWith(isAvatarGenerating: true),
        );
      });
    }
    try {
      final avatarService = ref.read(friendAvatarServiceProvider);
      final updated = await avatarService.generateAvatar(
        contactId: contact.id,
        profile: profile,
        userWishes: userWishes,
      );
      if (!mounted) return;
      final success = updated.avatarStatus == FriendProfile.avatarStatusReady;
      setState(() {
        _thread = _thread.copyWith(
          contact: _thread.contact.copyWith(
            avatarPath: updated.avatarPath,
            isAvatarGenerating: false,
          ),
        );
      });
      if (contact.id == 'friend') {
        ref.read(friendProfileProvider.notifier).state = updated;
      }
      _showAvatarSnack(
        success ? 'Аватар обновлён.' : 'Не удалось сгенерировать аватар.',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _thread = _thread.copyWith(
            contact: _thread.contact.copyWith(isAvatarGenerating: false),
          );
        });
        _showAvatarSnack('Не удалось сгенерировать аватар.');
      }
    } finally {
      _isAvatarUpdating = false;
    }
  }

  Future<void> _setAvatarFromMessage(MessengerMessage message) async {
    if (_isAvatarUpdating) return;
    if (!_isFriendContact(_thread.contact.id)) {
      _showAvatarSnack('Аватар можно менять только у друга.');
      return;
    }
    final profileRepo = ref.read(friendProfileRepositoryProvider);
    final currentProfile = profileRepo.load(_thread.contact.id);
    if (currentProfile == null) {
      _showAvatarSnack('Профиль друга не найден.');
      return;
    }
    final avatarFile = await _resolveAvatarFileFromMessage(message);
    if (avatarFile == null) {
      _showAvatarSnack('Не удалось получить изображение.');
      return;
    }
    _isAvatarUpdating = true;
    try {
      final updatedProfile = currentProfile.copyWith(
        avatarPath: avatarFile.path,
        appearanceDescription: '',
        appearanceCheckAvatarPath: null,
        avatarStatus: FriendProfile.avatarStatusReady,
        hairstyle: '',
      );
      await profileRepo.save(_thread.contact.id, updatedProfile);
      if (_thread.contact.id == 'friend') {
        ref.read(friendProfileProvider.notifier).state = updatedProfile;
      }
      if (mounted) {
        setState(() {
          _thread = _thread.copyWith(
            contact: _thread.contact.copyWith(
              avatarPath: avatarFile.path,
              isAvatarGenerating: false,
            ),
          );
        });
      }
      final appearanceService = ref.read(friendAppearanceServiceProvider);
      final refreshed = await appearanceService.ensureAppearanceDescription(
        profile: updatedProfile,
        avatarFile: avatarFile,
        contactId: _thread.contact.id,
      );
      if (mounted &&
          refreshed.appearanceDescription !=
              updatedProfile.appearanceDescription &&
          _thread.contact.id == 'friend') {
        ref.read(friendProfileProvider.notifier).state = refreshed;
      }
      _showAvatarSnack('Аватар обновлен.');
    } catch (e) {
      _showAvatarSnack('Не удалось обновить аватар.');
    } finally {
      _isAvatarUpdating = false;
    }
  }

  Future<File?> _resolveAvatarFileFromMessage(MessengerMessage message) async {
    final imagePath = message.imagePath;
    if (imagePath != null && imagePath.isNotEmpty) {
      final file = File(imagePath);
      if (file.existsSync()) return file;
    }
    final imageUrl = message.imageUrl?.trim();
    if (imageUrl == null || imageUrl.isEmpty) return null;
    return _downloadAvatarImage(imageUrl);
  }

  Future<File?> _downloadAvatarImage(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;
      final directory = await getApplicationDocumentsDirectory();
      final extension = _guessImageExtension(
        uri.path,
        response.headers['content-type'],
      );
      final fileName =
          'friend_avatar_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final filePath = path.join(directory.path, fileName);
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  String _guessImageExtension(String pathValue, String? contentType) {
    final lowerPath = pathValue.toLowerCase();
    if (lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg')) return 'jpg';
    if (lowerPath.endsWith('.webp')) return 'webp';
    if (lowerPath.endsWith('.png')) return 'png';
    final lowerType = (contentType ?? '').toLowerCase();
    if (lowerType.contains('image/jpeg')) return 'jpg';
    if (lowerType.contains('image/webp')) return 'webp';
    if (lowerType.contains('image/png')) return 'png';
    return 'jpg';
  }

  void _showAvatarSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showVoiceSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _showDeleteChatConfirmation(MessengerContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('chat_delete_title')),
        content: Text(
          context.trParams('chat_delete_confirm', [contact.name]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _storageRepository.clearThread(contact.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('chat_deleted')),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Ошибка удаления переписки: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('chat_delete_error')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _showMessageActions(MessengerMessage message) async {
    final actions = <_MessageAction>[
      _MessageAction.reply,
      _MessageAction.forward,
      _MessageAction.save,
      if (message.text.trim().isNotEmpty) _MessageAction.copy,
      _MessageAction.delete,
    ];

    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: actions.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = actions[index];
              final color = item == _MessageAction.delete
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.onSurface;
              return ListTile(
                leading: Icon(
                  _actionIcon(item),
                  color: color,
                ),
                title: Text(
                  _actionLabel(item),
                  style: TextStyle(color: color),
                ),
                onTap: () => Navigator.of(context).pop(item),
              );
            },
          ),
        );
      },
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _MessageAction.reply:
        _setReplyToMessage(message);
        break;
      case _MessageAction.forward:
        await _forwardMessage(message);
        break;
      case _MessageAction.save:
        await _saveMessage(message);
        break;
      case _MessageAction.copy:
        await _copyMessage(message);
        break;
      case _MessageAction.delete:
        await _deleteMessage(message);
        break;
    }
  }

  String _actionLabel(_MessageAction action) {
    switch (action) {
      case _MessageAction.reply:
        return 'Ответить';
      case _MessageAction.forward:
        return 'Переслать';
      case _MessageAction.save:
        return 'Сохранить';
      case _MessageAction.copy:
        return 'Копировать';
      case _MessageAction.delete:
        return 'Удалить';
    }
  }

  IconData _actionIcon(_MessageAction action) {
    switch (action) {
      case _MessageAction.reply:
        return Icons.reply;
      case _MessageAction.forward:
        return Icons.forward;
      case _MessageAction.save:
        return Icons.bookmark_border;
      case _MessageAction.copy:
        return Icons.copy;
      case _MessageAction.delete:
        return Icons.delete_outline;
    }
  }

  Future<void> _deleteMessage(MessengerMessage message) async {
    final confirmed = await _confirmDeleteMessage();
    if (!mounted || confirmed != true) return;
    final index =
        _thread.messages.indexWhere((existing) => existing.id == message.id);
    if (index == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сообщение уже удалено')),
      );
      return;
    }
    final updatedMessages = List<MessengerMessage>.from(_thread.messages)
      ..removeAt(index);
    setState(() {
      _thread = _thread.copyWith(messages: updatedMessages);
      if (_replyToMessage?.id == message.id) {
        _replyToMessage = null;
      }
    });
    final repository = ref.read(messengerStorageRepositoryProvider);
    try {
      final updatedThread = await repository.deleteMessage(
        contactId: _thread.contact.id,
        messageId: message.id,
      );
      if (updatedThread == null) {
        await repository.saveThread(_thread);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить сообщение')),
      );
    }
  }

  Future<bool?> _confirmDeleteMessage() {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Удалить сообщение?'),
          content: const Text('Это действие нельзя отменить.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: colors.error),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
  }

  Future<MessengerThread?> _selectForwardThread() async {
    final repository = ref.read(messengerStorageRepositoryProvider);
    return showModalBottomSheet<MessengerThread>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: FutureBuilder<List<MessengerThread>>(
            future: repository.loadThreads(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return const SizedBox(
                  height: 220,
                  child: Center(child: Text('Не удалось загрузить чаты')),
                );
              }
              final threads = snapshot.data ?? [];
              if (threads.isEmpty) {
                return const SizedBox(
                  height: 220,
                  child: Center(child: Text('Нет доступных чатов')),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: threads.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final thread = threads[index];
                  final avatarImage = _resolveAvatarImage(thread.contact);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: thread.contact.avatarColor,
                      backgroundImage: avatarImage,
                      child: avatarImage == null
                          ? Text(
                              thread.contact.initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : null,
                    ),
                    title: Text(thread.contact.name),
                    subtitle: Text(
                      thread.contact.status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: () => Navigator.of(context).pop(thread),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  MessengerMessage _buildForwardedMessage(MessengerMessage message) {
    final now = DateTime.now();
    return MessengerMessage(
      id: _id(now),
      text: message.text,
      time: now,
      isMine: true,
      status: MessengerMessageStatus.delivered,
      imagePath: message.imagePath,
      imageUrl: message.imageUrl,
      audioPath: message.audioPath,
      audioUrl: message.audioUrl,
      audioDurationMs: message.audioDurationMs,
      storyId: message.storyId,
      forwardedFromName: _resolveForwardedFromName(message),
    );
  }

  String _resolveForwardedFromName(MessengerMessage message) {
    final forwarded = message.forwardedFromName?.trim();
    if (forwarded != null && forwarded.isNotEmpty) return forwarded;
    return message.isMine ? 'Вы' : _thread.contact.name;
  }

  Future<void> _forwardMessage(MessengerMessage message) async {
    final targetThread = await _selectForwardThread();
    if (!mounted || targetThread == null) return;
    final repository = ref.read(messengerStorageRepositoryProvider);
    final forwardedMessage = _buildForwardedMessage(message);
    if (targetThread.contact.id == _thread.contact.id) {
      setState(() {
        _thread.messages.add(forwardedMessage);
      });
      _scrollToBottom(jump: false, force: true);
      await repository.saveThread(_thread);
    } else {
      await repository.appendMessage(
        contactId: targetThread.contact.id,
        message: forwardedMessage,
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Переслано в ${targetThread.contact.name}')),
    );
  }

  Future<void> _saveMessage(MessengerMessage message) async {
    const savedId = 'saved_messages';
    final repository = ref.read(messengerStorageRepositoryProvider);
    final savedMessage = _buildForwardedMessage(message);
    if (_thread.contact.id == savedId) {
      setState(() {
        _thread.messages.add(savedMessage);
      });
      _scrollToBottom(jump: false, force: true);
      await repository.saveThread(_thread);
    } else {
      await repository.appendMessage(
        contactId: savedId,
        message: savedMessage,
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Сохранено в избранное')),
    );
  }

  Future<void> _copyMessage(MessengerMessage message) async {
    final text = message.text.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Текст скопирован')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contact = _thread.contact;
    final isImageChat = _thread.persona.chatMode == MessengerChatMode.image;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final avatarImage = _resolveAvatarImage(contact);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            InkWell(
              onTap: () => _openAvatarViewer(contact),
              customBorder: const CircleBorder(),
              child: Hero(
                tag: messengerAvatarHeroTag(contact),
                child: MessengerAvatar(
                  size: 40,
                  backgroundColor: contact.avatarColor,
                  image: avatarImage,
                  initials: contact.initials,
                  isLoading: contact.isAvatarGenerating,
                  initialsStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _presenceLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurface.withOpacity(0.55),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.call),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'personalization') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FriendPersonalizationScreen(
                      contactId: contact.id,
                      contactName: contact.name,
                      gender: _readFriendProfile(contact.id)?.gender ?? 'male',
                    ),
                  ),
                );
              } else if (value == 'voice') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FriendVoiceScreen(
                      contactId: contact.id,
                      contactName: contact.name,
                    ),
                  ),
                );
              } else if (value == 'mood') {
                _openMoodScreen(contact);
              } else if (value == 'change_avatar') {
                _showChangeAvatarDialog(contact);
              } else if (value == 'delete_chat') {
                _showDeleteChatConfirmation(contact);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'personalization',
                child: Row(
                  children: [
                    Icon(Icons.tune, size: 22),
                    SizedBox(width: 12),
                    Text('Персонализация'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'voice',
                child: Row(
                  children: [
                    Icon(Icons.record_voice_over, size: 22),
                    SizedBox(width: 12),
                    Text('Голос'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'mood',
                child: Row(
                  children: [
                    Icon(Icons.mood, size: 22),
                    SizedBox(width: 12),
                    Text('Настроение'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'change_avatar',
                child: Row(
                  children: [
                    Icon(Icons.photo_camera, size: 22),
                    SizedBox(width: 12),
                    Text('Сменить аватар'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'delete_chat',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 22, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Удалить переписку'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: _handleScrollNotification,
                  child: ScrollablePositionedList.builder(
                    reverse: true,
                    itemScrollController: _itemScrollController,
                    itemPositionsListener: _itemPositionsListener,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                    itemCount: _thread.messages.length,
                    itemBuilder: (context, index) {
                      final messageIndex = _thread.messages.length - 1 - index;
                      final message = _thread.messages[messageIndex];
                      final voiceDuration = message.audioDurationMs != null
                          ? Duration(milliseconds: message.audioDurationMs!)
                          : _voiceMessageDurations[message.id];
                      return _MessageBubble(
                        message: message,
                        onImageTap: _openImageViewer,
                        onVoiceTap: (message.audioPath != null ||
                                message.audioUrl != null)
                            ? () => _toggleVoicePlayback(message)
                            : null,
                        isVoicePlaying: _playingVoiceMessageId == message.id,
                        voiceDuration: voiceDuration,
                        onLongPress: () => _showMessageActions(message),
                      );
                    },
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: AnimatedOpacity(
                    opacity: _showScrollToBottom ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: IgnorePointer(
                      ignoring: !_showScrollToBottom,
                      child: FloatingActionButton(
                        mini: true,
                        onPressed: () =>
                            _scrollToBottom(force: true, jump: false),
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        elevation: 2,
                        child: const Icon(Icons.keyboard_arrow_down),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_replyToMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _ReplyPreview(
                message: _replyToMessage!,
                contactName: contact.name,
                onClose: _clearReplyToMessage,
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFFE1E1E6),
                        ),
                      ),
                      child: TextField(
                        controller: _textController,
                        focusNode: _inputFocus,
                        textInputAction: TextInputAction.send,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText:
                              isImageChat ? 'Опишите изображение' : 'Сообщение',
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(color: Colors.black),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _VoiceActionButton(
                    hasText: _isComposing,
                    isEnabled: !_isAwaitingResponse,
                    onSend: _sendMessage,
                    onStartRecording: _startRecording,
                    onStopRecording: _finalizeVoiceMessage,
                    onCancel: _cancelRecording,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _id(DateTime time) {
    return time.microsecondsSinceEpoch.toString();
  }
}

class _MessageBubble extends StatelessWidget {
  final MessengerMessage message;
  final ValueChanged<MessengerMessage>? onImageTap;
  final VoidCallback? onVoiceTap;
  final bool isVoicePlaying;
  final Duration? voiceDuration;
  final VoidCallback? onLongPress;

  const _MessageBubble({
    required this.message,
    this.onImageTap,
    this.onVoiceTap,
    this.isVoicePlaying = false,
    this.voiceDuration,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isMine = message.isMine;
    final bubbleColor = isMine ? colors.primary : colors.surface;
    final textColor = isMine ? colors.onPrimary : colors.onSurface;
    final trimmedText = message.text.trim();
    final hasImage = message.imagePath != null || message.imageUrl != null;
    final hasAudio = message.audioPath != null || message.audioUrl != null;
    final timeColor = isMine
        ? colors.onPrimary.withOpacity(0.7)
        : colors.onSurface.withOpacity(0.55);
    final shadowColor = theme.shadowColor.withOpacity(isDark ? 0.35 : 0.12);
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final radius = isMine
        ? const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(6),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(18),
          );

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.74,
        ),
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (_hasForwardLabel()) _buildForwardedLabel(context, isMine),
                if (_hasForwardLabel() || message.quote != null)
                  const SizedBox(height: 6),
                if (message.quote != null) _buildQuotePreview(context, isMine),
                if (message.quote != null) const SizedBox(height: 8),
                if (hasImage) _buildImage(context),
                if (hasImage && trimmedText.isNotEmpty && !hasAudio)
                  const SizedBox(height: 8),
                if (hasAudio)
                  _buildVoiceMessage(context, isMine, voiceDuration),
                if (hasAudio && trimmedText.isNotEmpty && !hasImage)
                  const SizedBox(height: 8),
                if (!hasAudio && (trimmedText.isNotEmpty || !hasImage))
                  Text(
                    trimmedText.isEmpty ? '...' : trimmedText,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                    ),
                  ),
                if (message.paywallAction != null) ...[
                  const SizedBox(height: 12),
                  _buildPaywallButton(context),
                ],
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(message.time),
                      style: TextStyle(
                        color: timeColor,
                        fontSize: 11,
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      _buildStatusIcon(context, timeColor),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _hasForwardLabel() {
    final forwarded = message.forwardedFromName?.trim();
    return forwarded != null && forwarded.isNotEmpty;
  }

  Widget _buildForwardedLabel(BuildContext context, bool isMine) {
    final colors = Theme.of(context).colorScheme;
    final name = message.forwardedFromName?.trim() ?? '';
    final color = isMine
        ? colors.onPrimary.withOpacity(0.7)
        : colors.onSurface.withOpacity(0.6);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.forward, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'Переслано от $name',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildQuotePreview(BuildContext context, bool isMine) {
    final colors = Theme.of(context).colorScheme;
    final quote = message.quote;
    if (quote == null) return const SizedBox.shrink();
    final background = isMine
        ? colors.onPrimary.withOpacity(0.14)
        : colors.surfaceContainerHighest;
    final borderColor =
        isMine ? colors.onPrimary.withOpacity(0.7) : colors.outline;
    final textColor =
        isMine ? colors.onPrimary.withOpacity(0.8) : colors.onSurface;
    final subtitleColor =
        isMine ? colors.onPrimary.withOpacity(0.65) : colors.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: borderColor, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            quote.authorName,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _quotePreviewText(quote),
            style: TextStyle(
              color: subtitleColor,
              fontSize: 12,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _quotePreviewText(MessengerMessageQuote quote) {
    final text = quote.text.trim();
    if (text.isNotEmpty) return text;
    if (quote.hasImage) return 'Фото';
    return '...';
  }

  Widget _buildPaywallButton(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () {
        AppNavigation.showPaywall(context);
      },
      icon: const Icon(Icons.star, size: 18),
      label: const Text('Оформить подписку'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    final imagePath = message.imagePath;
    final imageUrl = message.imageUrl;
    final maxWidth = MediaQuery.of(context).size.width * 0.62;
    final borderRadius = BorderRadius.circular(12);
    final heroTag = messengerImageHeroTag(message);

    Widget image;
    if (imagePath != null) {
      image = Image.file(
        File(imagePath),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _imageErrorPlaceholder(context),
      );
    } else if (imageUrl != null) {
      image = Image.network(
        imageUrl,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _imageErrorPlaceholder(context),
      );
    } else {
      image = _imageErrorPlaceholder(context);
    }

    return Hero(
      tag: heroTag,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onImageTap == null ? null : () => onImageTap!(message),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxWidth,
              ),
              child: AspectRatio(
                aspectRatio: 1,
                child: image,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceMessage(
    BuildContext context,
    bool isMine,
    Duration? duration,
  ) {
    final colors = Theme.of(context).colorScheme;
    final canPlay = onVoiceTap != null;
    final baseColor = isMine ? colors.onPrimary : colors.primary;
    final mutedColor =
        isMine ? colors.onPrimary.withOpacity(0.55) : colors.onSurfaceVariant;
    final iconColor = canPlay ? baseColor : mutedColor;
    final durationLabel = _formatDuration(duration);
    return _VoiceMessageView(
      onTap: canPlay ? onVoiceTap : null,
      isPlaying: isVoicePlaying,
      isEnabled: canPlay,
      durationLabel: durationLabel,
      durationColor: mutedColor,
      buttonBackgroundColor: isMine
          ? colors.onPrimary.withOpacity(0.18)
          : colors.primary.withOpacity(0.12),
      iconColor: iconColor,
      waveformColor: canPlay ? baseColor : mutedColor,
      inactiveWaveformColor: mutedColor.withOpacity(0.35),
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null || duration.inMilliseconds <= 0) {
      return '0:00';
    }
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _imageErrorPlaceholder(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      color: colors.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.broken_image_outlined,
        color: colors.onSurfaceVariant,
        size: 32,
      ),
    );
  }

  Widget _buildStatusIcon(BuildContext context, Color baseColor) {
    switch (message.status) {
      case MessengerMessageStatus.sending:
        return Icon(Icons.access_time, size: 14, color: baseColor);
      case MessengerMessageStatus.delivered:
        return Icon(Icons.check, size: 14, color: baseColor);
      case MessengerMessageStatus.read:
        return Icon(
          Icons.done_all,
          size: 14,
          color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.85),
        );
    }
  }

  String _formatTime(DateTime time) {
    final hours = time.hour.toString().padLeft(2, '0');
    final minutes = time.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }
}

class _VoiceMessageView extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isPlaying;
  final bool isEnabled;
  final String durationLabel;
  final Color durationColor;
  final Color buttonBackgroundColor;
  final Color iconColor;
  final Color waveformColor;
  final Color inactiveWaveformColor;

  const _VoiceMessageView({
    this.onTap,
    required this.isPlaying,
    required this.isEnabled,
    required this.durationLabel,
    required this.durationColor,
    required this.buttonBackgroundColor,
    required this.iconColor,
    required this.waveformColor,
    required this.inactiveWaveformColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _VoicePlayButton(
          onTap: onTap,
          isPlaying: isPlaying,
          isEnabled: isEnabled,
          backgroundColor: buttonBackgroundColor,
          iconColor: iconColor,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _VoiceWaveform(
                isActive: isPlaying && isEnabled,
                isEnabled: isEnabled,
                activeColor: waveformColor,
                inactiveColor: inactiveWaveformColor,
              ),
              const SizedBox(height: 4),
              Text(
                durationLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: durationColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VoicePlayButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isPlaying;
  final bool isEnabled;
  final Color backgroundColor;
  final Color iconColor;

  const _VoicePlayButton({
    this.onTap,
    required this.isPlaying,
    required this.isEnabled,
    required this.backgroundColor,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            size: 22,
            color: iconColor,
          ),
        ),
      ),
    );
  }
}

class _VoiceWaveform extends StatefulWidget {
  final bool isActive;
  final bool isEnabled;
  final Color activeColor;
  final Color inactiveColor;

  const _VoiceWaveform({
    required this.isActive,
    required this.isEnabled,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  State<_VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<_VoiceWaveform>
    with SingleTickerProviderStateMixin {
  static const List<double> _bars = [
    0.32,
    0.58,
    0.42,
    0.75,
    0.5,
    0.9,
    0.6,
    0.36,
    0.78,
    0.52,
    0.68,
    0.4,
    0.82,
    0.56,
    0.34,
    0.72,
    0.48,
    0.88,
    0.62,
    0.44,
    0.76,
    0.5,
    0.38,
    0.6,
  ];

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    if (widget.isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_VoiceWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 180.0;
        final width = min(maxWidth, 190.0);
        return SizedBox(
          width: width,
          height: 22,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final value =
                  widget.isActive && widget.isEnabled ? _controller.value : 0.0;
              return CustomPaint(
                painter: _WaveformPainter(
                  bars: _bars,
                  animationValue: value,
                  activeColor: widget.activeColor,
                  inactiveColor: widget.inactiveColor,
                  isActive: widget.isActive && widget.isEnabled,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final double animationValue;
  final Color activeColor;
  final Color inactiveColor;
  final bool isActive;

  _WaveformPainter({
    required this.bars,
    required this.animationValue,
    required this.activeColor,
    required this.inactiveColor,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || bars.isEmpty) return;
    const spacing = 2.0;
    final count = bars.length;
    final totalSpacing = spacing * (count - 1);
    final availableWidth = size.width - totalSpacing;
    if (availableWidth <= 0) return;
    final barWidth = availableWidth / count;
    final paint = Paint()
      ..color = isActive ? activeColor : inactiveColor
      ..style = PaintingStyle.fill;
    final centerY = size.height / 2;
    final t = animationValue * 2 * pi;

    for (var i = 0; i < count; i++) {
      final base = bars[i].clamp(0.1, 1.0);
      final phase = (i / count) * 2 * pi;
      final pulse = isActive ? (0.6 + 0.4 * sin(t + phase)) : 0.55;
      final height = max(2.0, base * size.height * pulse);
      final x = i * (barWidth + spacing);
      final rect = Rect.fromLTWH(x, centerY - height / 2, barWidth, height);
      final radius = Radius.circular(barWidth);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.isActive != isActive;
  }
}

class _ReplyPreview extends StatelessWidget {
  final MessengerMessage message;
  final String contactName;
  final VoidCallback onClose;

  const _ReplyPreview({
    required this.message,
    required this.contactName,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final authorName = message.isMine ? 'Вы' : contactName;
    final text = message.text.trim();
    final hasImage = message.imagePath != null || message.imageUrl != null;
    final hasAudio = message.audioPath != null || message.audioUrl != null;
    final preview = text.isNotEmpty
        ? text
        : hasAudio
            ? 'Голосовое сообщение'
            : hasImage
                ? 'Фото'
                : '...';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  authorName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: Icon(
              Icons.close,
              size: 18,
              color: colors.onSurface.withOpacity(0.55),
            ),
            splashRadius: 18,
          ),
        ],
      ),
    );
  }
}

class _VoiceActionButton extends StatefulWidget {
  final bool hasText;
  final bool isEnabled;
  final VoidCallback onSend;
  final Future<void> Function() onStartRecording;
  final Future<void> Function() onStopRecording;
  final Future<void> Function() onCancel;

  const _VoiceActionButton({
    required this.hasText,
    required this.isEnabled,
    required this.onSend,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onCancel,
  });

  @override
  State<_VoiceActionButton> createState() => _VoiceActionButtonState();
}

class _VoiceActionButtonState extends State<_VoiceActionButton>
    with TickerProviderStateMixin {
  bool _recording = false;
  late AnimationController _anim;
  bool _lock = false;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  Timer? _tick;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlay;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    _tick?.cancel();
    _removeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hasText) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: widget.isEnabled
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          borderRadius: BorderRadius.circular(24),
          boxShadow: widget.isEnabled
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.isEnabled ? widget.onSend : null,
            borderRadius: BorderRadius.circular(24),
            child: Center(
              child: Icon(
                Icons.send,
                color: widget.isEnabled ? Colors.white : Colors.white70,
                size: 20,
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) async {
        if (!widget.isEnabled) return;
        setState(() {
          _recording = true;
          _lock = false;
          _startedAt = DateTime.now();
          _elapsed = Duration.zero;
        });
        HapticFeedback.heavyImpact();
        _anim.repeat(reverse: true);
        _tick?.cancel();
        _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
          if (!_recording || _startedAt == null) return;
          _elapsed = DateTime.now().difference(_startedAt!);
          _overlay?.markNeedsBuild();
        });
        _showOverlay();
        await widget.onStartRecording();
      },
      onLongPressEnd: (_) async {
        if (!_recording) return;
        if (_lock) return;
        _tick?.cancel();
        setState(() {
          _recording = false;
        });
        _removeOverlay();
        _anim.stop();
        _anim.value = 1.0;
        HapticFeedback.lightImpact();
        try {
          await widget.onStopRecording();
        } catch (_) {}
      },
      onTap: () async {
        if (_recording && _lock) {
          _tick?.cancel();
          setState(() {
            _recording = false;
            _lock = false;
          });
          _removeOverlay();
          _anim.stop();
          _anim.value = 1.0;
          HapticFeedback.mediumImpact();
          try {
            await widget.onStopRecording();
          } catch (_) {}
        }
      },
      onLongPressMoveUpdate: (details) async {
        if (!_recording) return;
        final Offset o = details.offsetFromOrigin;
        final dx = o.dx;
        final dy = o.dy;
        if (dx < -60 && !_lock) {
          _tick?.cancel();
          await widget.onCancel();
          setState(() {
            _recording = false;
            _lock = false;
          });
          _removeOverlay();
          _anim.stop();
          _anim.value = 1.0;
          HapticFeedback.selectionClick();
          return;
        }
        if (dy < -60 && !_lock) {
          setState(() {
            _lock = true;
          });
          _overlay?.markNeedsBuild();
          HapticFeedback.mediumImpact();
        }
      },
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          return CompositedTransformTarget(
            link: _layerLink,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _recording ? Colors.black : Colors.white,
                  border: Border.all(
                    color: _recording ? Colors.black : const Color(0xFFE1E1E6),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    _recording ? Icons.mic : Icons.mic_none,
                    color: _recording ? Colors.white : Colors.black54,
                    size: 22,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  void _showOverlay() {
    _overlay ??= OverlayEntry(builder: (context) {
      return Stack(children: [
        CompositedTransformFollower(
          link: _layerLink,
          targetAnchor: Alignment.centerLeft,
          followerAnchor: Alignment.centerRight,
          offset: const Offset(-12, 0),
          showWhenUnlinked: false,
          child: Material(
            color: Colors.transparent,
            child: Builder(builder: (ctx) {
              final screenW = MediaQuery.of(ctx).size.width;
              final double width = (screenW - 8 - 8 - 8 - 48).clamp(
                160.0,
                screenW,
              );
              return Container(
                width: width,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.shade600.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  const Icon(Icons.fiber_manual_record,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Text(_formatDuration(_elapsed),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Opacity(
                      opacity: 0.8,
                      child: Text(
                        _lock ? 'Закреплено' : '↑ закрепить    ← отмена',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ),
                ]),
              );
            }),
          ),
        ),
        if (_lock)
          CompositedTransformFollower(
            link: _layerLink,
            targetAnchor: Alignment.centerRight,
            followerAnchor: Alignment.centerLeft,
            offset: const Offset(12, 0),
            showWhenUnlinked: false,
            child: Material(
              color: Colors.transparent,
              child: Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.send, color: Colors.white, size: 16),
                ),
              ]),
            ),
          ),
      ]);
    });

    final overlay = Overlay.of(context);
    if (_overlay != null) {
      overlay.insert(_overlay!);
    }
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }
}
