import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/localization/app_localization_service.dart';
import '../../services/notification/notification_manager.dart';
import '../../services/theme_service.dart';
import '../../utils/navigation.dart';
import 'data/messenger_storage_repository.dart';
import 'messenger_chat_screen.dart';
import 'messenger_create_friend_screen.dart';
import 'models/friend_profile.dart';
import 'models/messenger_contact.dart';
import 'models/messenger_message.dart';
import 'models/messenger_story.dart';
import 'models/messenger_thread.dart';
import 'messenger_providers.dart';
import '../../widgets/credit_counter_widget.dart';
import 'widgets/messenger_avatar.dart';
import 'widgets/messenger_avatar_viewer.dart';
import 'widgets/messenger_story_viewer.dart';

class MessengerHomeScreen extends ConsumerStatefulWidget {
  const MessengerHomeScreen({super.key});

  @override
  ConsumerState<MessengerHomeScreen> createState() =>
      _MessengerHomeScreenState();
}

class _MessengerHomeScreenState extends ConsumerState<MessengerHomeScreen>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  late final MessengerStorageRepository _storageRepository;
  StreamSubscription<MessengerThreadUpdate>? _threadUpdatesSub;
  StreamSubscription<void>? _storyUpdatesSub;
  final Set<String> _threadRefreshInFlight = {};
  final Set<String> _threadRefreshPending = {};
  Map<String, int> _unreadCounts = {};
  List<MessengerThread> _threads = [];
  List<MessengerStory> _stories = [];
  bool _isLoading = true;
  String? _loadError;
  String _query = '';
  bool _appearanceCheckScheduled = false;
  bool _appearanceCheckInFlight = false;
  bool _notificationPromptInFlight = false;
  bool _proactiveSyncInFlight = false;
  DateTime? _lastProactiveSyncAt;
  bool _pendingAiSyncInFlight = false;
  DateTime? _lastPendingAiSyncAt;
  bool _dailyStorySyncInFlight = false;
  bool _storyRefreshScheduled = false;
  bool _routeActionHandled = false;
  bool _avatarGenerationScheduled = false;
  bool _avatarGenerationCheckInFlight = false;
  final Set<String> _avatarGenerationInFlight = {};
  Timer? _pendingAiPollTimer;
  bool _isSearchVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(_handleSearchChanged);
    _storageRepository = ref.read(messengerStorageRepositoryProvider);
    _threadUpdatesSub = _storageRepository.threadUpdates.listen((update) {
      unawaited(_handleThreadUpdate(update));
    });
    _storyUpdatesSub =
        ref.read(messengerStoryRepositoryProvider).updates.listen((_) {
      _scheduleStoryRefresh();
    });
    _loadThreads();
    _scheduleAppearanceCheck();
    _pendingAiPollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_processPendingAiTasks());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeMessengerChatIdProvider.notifier).state = null;
      unawaited(_maybeRequestNotificationPermissions());
      unawaited(_processPendingAiTasks(force: true));
      unawaited(_syncProactiveMessages(force: true));
      unawaited(_syncDailyStories());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    _pendingAiPollTimer?.cancel();
    _threadUpdatesSub?.cancel();
    _storyUpdatesSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_processPendingAiTasks());
      unawaited(_syncProactiveMessages());
      unawaited(_syncDailyStories());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncHomeActive();
    _handleRouteAction();
  }

  void _handleSearchChanged() {
    final value = _searchController.text.trim().toLowerCase();
    if (value == _query) return;
    setState(() {
      _query = value;
    });
  }

  void _toggleSearch() {
    if (_isSearchVisible) {
      _closeSearch(clearQuery: true);
    } else {
      _openSearch();
    }
  }

  void _openSearch() {
    if (_isSearchVisible) {
      _searchFocus.requestFocus();
      return;
    }
    setState(() {
      _isSearchVisible = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocus.requestFocus();
    });
  }

  void _closeSearch({required bool clearQuery}) {
    if (!_isSearchVisible) return;
    if (clearQuery) {
      _searchController.clear();
    }
    setState(() {
      _isSearchVisible = false;
    });
    FocusScope.of(context).unfocus();
  }

  void _scheduleAppearanceCheck() {
    if (_appearanceCheckScheduled) return;
    _appearanceCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_ensureAppearanceDescriptionOnHome());
    });
  }

  void _scheduleStoryRefresh() {
    if (_storyRefreshScheduled) return;
    _storyRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _storyRefreshScheduled = false;
      if (!mounted) return;
      unawaited(_loadThreads());
    });
  }

  Future<void> _ensureAppearanceDescriptionOnHome() async {
    if (_appearanceCheckInFlight) return;
    _appearanceCheckInFlight = true;
    try {
      final profile = ref.read(friendProfileProvider);
      if (profile == null) return;
      if (profile.appearanceDescription.trim().isNotEmpty) return;
      final avatarPath = profile.avatarPath;
      File? avatarFile;
      if (avatarPath != null && avatarPath.isNotEmpty) {
        final candidate = File(avatarPath);
        if (candidate.existsSync()) {
          avatarFile = candidate;
        }
      }
      final appearanceService = ref.read(friendAppearanceServiceProvider);
      final updated = await appearanceService.ensureAppearanceDescription(
        profile: profile,
        avatarFile: avatarFile,
        contactId: 'friend',
      );
      if (!mounted) return;
      if (updated.appearanceDescription != profile.appearanceDescription) {
        ref.read(friendProfileProvider.notifier).state = updated;
      }
    } finally {
      _appearanceCheckInFlight = false;
    }
  }

  Future<void> _loadThreads() async {
    try {
      final threads = await _storageRepository.loadThreads();
      final stories = await _loadStories();
      final unreadCounts = await _buildUnreadCounts(threads);
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _stories = stories;
        _unreadCounts = unreadCounts;
        _isLoading = false;
        _loadError = null;
      });
      _scheduleAvatarGenerationCheck();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Не удалось загрузить чаты';
      });
    }
  }

  void _scheduleAvatarGenerationCheck() {
    if (_avatarGenerationScheduled) return;
    _avatarGenerationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _avatarGenerationScheduled = false;
      unawaited(_ensurePendingAvatars());
    });
  }

  Future<void> _ensurePendingAvatars() async {
    if (_avatarGenerationCheckInFlight) return;
    _avatarGenerationCheckInFlight = true;
    try {
      final repo = ref.read(friendProfileRepositoryProvider);
      final profiles = repo.loadAll();
      final pending = profiles.entries.where((entry) {
        final profile = entry.value;
        final hasAvatar =
            profile.avatarPath != null && profile.avatarPath!.isNotEmpty;
        return profile.avatarStatus == FriendProfile.avatarStatusPending &&
            !hasAvatar;
      }).toList();
      if (pending.isEmpty) return;
      final avatarService = ref.read(friendAvatarServiceProvider);
      for (final entry in pending) {
        if (!mounted) return;
        if (_avatarGenerationInFlight.contains(entry.key)) continue;
        _avatarGenerationInFlight.add(entry.key);
        try {
          final updated = await avatarService.generateAvatar(
            contactId: entry.key,
            profile: entry.value,
          );
          if (!mounted) return;
          if (entry.key == 'friend') {
            ref.read(friendProfileProvider.notifier).state = updated;
          }
        } finally {
          _avatarGenerationInFlight.remove(entry.key);
        }
      }
      if (mounted) {
        await _loadThreads();
      }
    } finally {
      _avatarGenerationCheckInFlight = false;
    }
  }

  Future<List<MessengerStory>> _loadStories() async {
    try {
      final repository = ref.read(messengerStoryRepositoryProvider);
      return await repository.loadStories();
    } catch (e) {
      debugPrint('🔴 MESSENGER: Ошибка загрузки сторис: $e');
      return [];
    }
  }

  List<MessengerThread> get _filteredThreads {
    if (_query.isEmpty) return _threads;
    return _threads
        .where((thread) => thread.contact.name.toLowerCase().contains(_query))
        .toList();
  }

  ImageProvider? _resolveAvatarImage(MessengerContact contact) {
    final path = contact.avatarPath;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return FileImage(file);
  }

  void _openAvatarViewer(MessengerContact contact) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessengerAvatarViewer(contact: contact),
      ),
    );
  }

  Future<void> _openCreateFriend() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const MessengerCreateFriendScreen()),
    );
    if (!mounted) return;
    if (created == true) {
      await _loadThreads();
    }
  }

  Future<void> _openChat(MessengerThread thread) async {
    await _markThreadRead(
      thread.contact.id,
      thread.messages.isNotEmpty ? thread.messages.last.time : DateTime.now(),
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessengerChatScreen(thread: thread),
      ),
    );
    if (!mounted) return;
    unawaited(_processPendingAiTasks(force: true));
    await _loadThreads();
  }

  Future<void> _openChatByContactId(String contactId) async {
    try {
      final thread = await _storageRepository.loadThreadById(contactId);
      if (!mounted) return;
      await _openChat(thread);
    } catch (e) {
      debugPrint('Не удалось открыть чат $contactId: $e');
    }
  }

  Future<void> _handleThreadUpdate(MessengerThreadUpdate update) async {
    if (!mounted) return;
    if (update.isIncomingMessage) {
      final activeChatId = ref.read(activeMessengerChatIdProvider);
      if (activeChatId == update.contactId) {
        final time = update.message?.time ?? DateTime.now();
        await _storageRepository.markThreadRead(update.contactId, time);
      } else {
        unawaited(_maybeNotifyIncoming(update));
      }
    }
    await _refreshThread(update.contactId);
  }

  Future<void> _refreshThread(String contactId) async {
    if (_threadRefreshInFlight.contains(contactId)) {
      _threadRefreshPending.add(contactId);
      return;
    }
    _threadRefreshInFlight.add(contactId);
    try {
      final updated = await _storageRepository.loadThreadById(contactId);
      final activeChatId = ref.read(activeMessengerChatIdProvider);
      final int unreadCount;
      if (activeChatId == contactId) {
        unreadCount = 0;
      } else {
        final lastReadAt = await _storageRepository.ensureLastReadAt(updated);
        unreadCount =
            _storageRepository.unreadCountForThread(updated, lastReadAt);
      }
      if (!mounted) return;
      setState(() {
        final index =
            _threads.indexWhere((thread) => thread.contact.id == contactId);
        if (index == -1) {
          _threads.add(updated);
        } else {
          _threads[index] = updated;
        }
        _threads.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
        _unreadCounts[contactId] = unreadCount;
      });
    } catch (e) {
      debugPrint('Не удалось обновить чат $contactId: $e');
    } finally {
      _threadRefreshInFlight.remove(contactId);
      if (_threadRefreshPending.remove(contactId)) {
        unawaited(_refreshThread(contactId));
      }
    }
  }

  Future<void> _maybeNotifyIncoming(MessengerThreadUpdate update) async {
    final message = update.message;
    if (message == null || message.isMine) return;
    final activeChatId = ref.read(activeMessengerChatIdProvider);
    if (activeChatId == update.contactId) return;
    final manager = NotificationManager();
    if (manager.isMessengerNotificationSuppressed(message.id)) return;
    final enabled = await manager.areNotificationsEnabled();
    if (!enabled) return;
    if (!mounted) return;
    final title = _resolveNotificationTitle(update.contactId);
    final body = _previewText(message);
    await manager.sendMessengerNotification(
      title: title,
      body: body.isEmpty ? 'Новое сообщение' : body,
      contactId: update.contactId,
      messageId: message.id,
    );
  }

  Future<Map<String, int>> _buildUnreadCounts(
    List<MessengerThread> threads,
  ) async {
    final result = <String, int>{};
    for (final thread in threads) {
      final lastReadAt = await _storageRepository.ensureLastReadAt(thread);
      result[thread.contact.id] =
          _storageRepository.unreadCountForThread(thread, lastReadAt);
    }
    return result;
  }

  Future<void> _markThreadRead(String contactId, DateTime readAt) async {
    await _storageRepository.markThreadRead(contactId, readAt);
    if (!mounted) return;
    setState(() {
      _unreadCounts[contactId] = 0;
    });
  }

  int _unreadCountForThread(MessengerThread thread) {
    return _unreadCounts[thread.contact.id] ?? 0;
  }

  String _formatUnreadCount(int count) {
    if (count <= 0) return '';
    if (count > 99) return '99+';
    return count.toString();
  }

  String _resolveNotificationTitle(String contactId) {
    for (final thread in _threads) {
      if (thread.contact.id == contactId) {
        return thread.contact.name;
      }
    }
    return 'Новое сообщение';
  }

  void _handleRouteAction() {
    if (_routeActionHandled) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! Map) return;
    final contactId = args['open_chat_contact_id'];
    if (contactId is! String || contactId.trim().isEmpty) return;
    final messageId = args['open_chat_message_id'];
    _routeActionHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (messageId is String && messageId.trim().isNotEmpty) {
        final service = ref.read(messengerProactiveServiceProvider);
        await service.deliverMessageById(messageId.trim());
      }
      await _syncProactiveMessages(force: true);
      if (!mounted) return;
      await _openChatByContactId(contactId);
    });
  }

  Future<void> _maybeRequestNotificationPermissions() async {
    if (_notificationPromptInFlight) return;
    _notificationPromptInFlight = true;
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      const promptKey = 'messenger_notifications_prompted';
      const promptAtKey = 'messenger_notifications_prompted_at';
      final manager = NotificationManager();
      final enabled = await manager.areNotificationsEnabled();
      if (enabled) return;
      final prompted = prefs.getBool(promptKey) ?? false;
      final lastPromptAtRaw = prefs.getString(promptAtKey);
      final lastPromptAt =
          lastPromptAtRaw == null ? null : DateTime.tryParse(lastPromptAtRaw);
      final shouldPrompt = !prompted ||
          (lastPromptAt != null &&
              DateTime.now().difference(lastPromptAt) >
                  const Duration(days: 7));
      if (!shouldPrompt || !mounted) return;
      final allow = await _showNotificationsDialog();
      await prefs.setBool(promptKey, true);
      await prefs.setString(
        promptAtKey,
        DateTime.now().toIso8601String(),
      );
      if (!mounted || allow != true) return;
      await manager.requestPermissions();
      unawaited(_syncProactiveMessages(force: true));
    } finally {
      _notificationPromptInFlight = false;
    }
  }

  Future<bool?> _showNotificationsDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Уведомления'),
          content: const Text(
            'Разрешить уведомления, чтобы друг мог написать первым, даже когда приложение закрыто?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Не сейчас'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Разрешить'),
            ),
          ],
        );
      },
    );
  }

  static const Duration _proactiveSyncThrottle = Duration(seconds: 30);
  static const Duration _pendingAiSyncThrottle = Duration(seconds: 5);

  Future<void> _processPendingAiTasks({bool force = false}) async {
    if (_pendingAiSyncInFlight) return;
    if (!force && _lastPendingAiSyncAt != null) {
      final elapsed = DateTime.now().difference(_lastPendingAiSyncAt!);
      if (elapsed < _pendingAiSyncThrottle) return;
    }
    _pendingAiSyncInFlight = true;
    try {
      final service = ref.read(messengerPendingAiTaskServiceProvider);
      await service.processPendingTasks();
      _lastPendingAiSyncAt = DateTime.now();
    } finally {
      _pendingAiSyncInFlight = false;
    }
  }

  Future<void> _syncProactiveMessages({bool force = false}) async {
    if (_proactiveSyncInFlight) return;
    if (!force && _lastProactiveSyncAt != null) {
      final elapsed = DateTime.now().difference(_lastProactiveSyncAt!);
      if (elapsed < _proactiveSyncThrottle) return;
    }
    _proactiveSyncInFlight = true;
    try {
      final manager = NotificationManager();
      final notificationsEnabled = await manager.areNotificationsEnabled();
      final service = ref.read(messengerProactiveServiceProvider);
      final delivered = await service.processDueMessages();
      if (delivered > 0 && mounted) {
        await _loadThreads();
      }
      await service.ensureQueue(notificationsEnabled: notificationsEnabled);
      _lastProactiveSyncAt = DateTime.now();
    } finally {
      _proactiveSyncInFlight = false;
    }
  }

  Future<void> _syncDailyStories() async {
    if (_dailyStorySyncInFlight) return;
    _dailyStorySyncInFlight = true;
    try {
      final service = ref.read(messengerDailyStoryServiceProvider);
      final created = await service.ensureDailyStories();
      if (created > 0 && mounted) {
        await _loadThreads();
      }
    } finally {
      _dailyStorySyncInFlight = false;
    }
  }

  Future<void> _openStoryViewer(
    List<MessengerStory> stories,
    int initialIndex,
  ) async {
    final targetStory = stories[initialIndex];
    if (targetStory.isLocked) {
      if (mounted) {
        AppNavigation.showPaywall(context);
      }
      return;
    }
    
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessengerStoryViewer(
          stories: stories,
          initialIndex: initialIndex,
          onStoryViewed: (story) {
            unawaited(_markStoryViewed(story));
          },
        ),
      ),
    );
    if (mounted) {
      await _loadThreads();
    }
  }

  Future<void> _markStoryViewed(MessengerStory story) async {
    final repository = ref.read(messengerStoryRepositoryProvider);
    await repository.markViewed(story.id, DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    _syncHomeActive();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;
    if (_isLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: colors.primary),
        ),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: Text(
            _loadError!,
            style: TextStyle(color: colors.onSurface),
          ),
        ),
      );
    }
    final threads = _filteredThreads;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        titleSpacing: 16,
        title: Text(
          'AI Video Maker',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: CreditCounterWidget(),
          ),
          IconButton(
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
            icon: Icon(
              isDarkMode ? Icons.light_mode : Icons.dark_mode,
              color: colors.onSurface.withOpacity(0.8),
            ),
          ),
          IconButton(
            onPressed: _toggleSearch,
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) {
              return SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1,
                child: child,
              );
            },
            child: _isSearchVisible
                ? Padding(
                    key: const ValueKey('search'),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: _SearchField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      onClose: () => _closeSearch(clearQuery: true),
                    ),
                  )
                : const SizedBox(key: ValueKey('search-hidden')),
          ),
          if (_stories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _StoriesRow(
                stories: _stories,
                threads: _threads,
                onStoryTap: (stories, index) {
                  unawaited(_openStoryViewer(stories, index));
                },
              ),
            ),
          const FreeUserBanner(),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: threads.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                indent: 84,
                endIndent: 16,
                color: colors.onSurface.withOpacity(isDarkMode ? 0.12 : 0.08),
              ),
              itemBuilder: (context, index) {
                final thread = threads[index];
                final lastMessage = _lastMessage(thread);
                final lastTime = lastMessage?.time ?? thread.lastUpdated;
                final previewText =
                    lastMessage == null ? null : _previewText(lastMessage);
                final avatarImage = _resolveAvatarImage(thread.contact);
                final isOnline = _isOnlineStatus(thread.contact.status);
                final unreadCount = _unreadCountForThread(thread);
                final hasUnread = unreadCount > 0;
                return ListTile(
                  onTap: () => _openChat(thread),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: InkWell(
                    onTap: () => _openAvatarViewer(thread.contact),
                    customBorder: const CircleBorder(),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Hero(
                          tag: messengerAvatarHeroTag(thread.contact),
                          child: MessengerAvatar(
                            size: 52,
                            backgroundColor: thread.contact.avatarColor,
                            image: avatarImage,
                            initials: thread.contact.initials,
                            isLoading: thread.contact.isAvatarGenerating,
                            initialsStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (isOnline)
                          const Positioned(
                            bottom: -1,
                            right: -1,
                            child: _OnlineIndicator(),
                          ),
                      ],
                    ),
                  ),
                  title: Text(
                    thread.contact.name,
                    style: TextStyle(
                      fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  subtitle: previewText != null && previewText.isNotEmpty
                      ? Text(
                          previewText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: hasUnread
                                ? colors.onSurface
                                : colors.onSurfaceVariant,
                            fontWeight:
                                hasUnread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        )
                      : null,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatTime(lastTime),
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurface.withOpacity(0.55),
                        ),
                      ),
                      if (unreadCount > 0) ...[
                        const SizedBox(height: 6),
                        _UnreadBadge(
                          text: _formatUnreadCount(unreadCount),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateFriend,
        backgroundColor: colors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  MessengerMessage? _lastMessage(MessengerThread thread) {
    if (thread.messages.isEmpty) return null;
    return thread.messages.last;
  }

  String _previewText(MessengerMessage message) {
    final hasAudio =
        (message.audioPath != null && message.audioPath!.isNotEmpty) ||
            (message.audioUrl != null && message.audioUrl!.isNotEmpty);
    if (hasAudio) return 'Голосовое сообщение';
    final text = message.text.trim();
    if (text.isNotEmpty) return text;
    if (message.imagePath != null || message.imageUrl != null) {
      return 'Изображение';
    }
    return '';
  }

  String _formatTime(DateTime time) {
    final hours = time.hour.toString().padLeft(2, '0');
    final minutes = time.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  bool _isOnlineStatus(String status) {
    final lowered = status.toLowerCase();
    return lowered.contains('онлайн') || lowered.contains('в сети');
  }

  void _syncHomeActive() {
    final route = ModalRoute.of(context);
    if (route?.isCurrent != true) return;
    final activeChat = ref.read(activeMessengerChatIdProvider.notifier);
    if (activeChat.state == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ModalRoute.of(context);
      if (current?.isCurrent != true) return;
      final notifier = ref.read(activeMessengerChatIdProvider.notifier);
      if (notifier.state != null) {
        notifier.state = null;
      }
    });
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClose;

  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final borderColor = colors.onSurface.withOpacity(0.12);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasText = value.text.trim().isNotEmpty;
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Поиск',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              onPressed: () {
                if (hasText) {
                  controller.clear();
                } else {
                  onClose();
                }
              },
              icon: Icon(hasText ? Icons.close : Icons.keyboard_arrow_up),
            ),
            filled: true,
            fillColor: colors.surfaceContainerHighest,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colors.primary),
            ),
          ),
        );
      },
    );
  }
}

class _StoriesRow extends StatelessWidget {
  final List<MessengerStory> stories;
  final List<MessengerThread> threads;
  final void Function(List<MessengerStory>, int) onStoryTap;

  const _StoriesRow({
    required this.stories,
    required this.threads,
    required this.onStoryTap,
  });

  @override
  Widget build(BuildContext context) {
    final groups = _buildGroups();
    return SizedBox(
      height: 104,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final group = groups[index];
          final initialIndex = _firstUnviewedIndex(group.stories);
          return _StoryItem(
            title: group.title,
            initials: group.initials,
            avatarImage: group.avatarImage,
            backgroundColor: group.backgroundColor,
            isAvatarGenerating: group.isAvatarGenerating,
            viewedSegments:
                group.stories.map((story) => story.isViewed).toList(),
            hasLockedStories: group.hasLockedStories,
            onTap: () => onStoryTap(group.stories, initialIndex),
          );
        },
      ),
    );
  }

  List<_StoryGroup> _buildGroups() {
    final contactsById = <String, MessengerContact>{
      for (final thread in threads) thread.contact.id: thread.contact,
    };
    final grouped = <String, List<MessengerStory>>{};
    for (final story in stories) {
      grouped.putIfAbsent(story.contactId, () => []).add(story);
    }
    final groups = <_StoryGroup>[];
    for (final entry in grouped.entries) {
      final groupStories = List<MessengerStory>.of(entry.value);
      groupStories.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final contact = contactsById[entry.key];
      final title = contact?.name ?? groupStories.last.contactName;
      final avatarImage = _resolveAvatarImage(groupStories, contact);
      final fallbackColor = contact?.avatarColor ?? const Color(0xFF90A4AE);
      final initials = _initials(title);
      groups.add(
        _StoryGroup(
          contactId: entry.key,
          title: title,
          initials: initials,
          avatarImage: avatarImage,
          backgroundColor: fallbackColor,
          isAvatarGenerating: contact?.isAvatarGenerating ?? false,
          stories: groupStories,
        ),
      );
    }
    groups.sort((a, b) {
      if (a.hasUnviewed != b.hasUnviewed) {
        return a.hasUnviewed ? -1 : 1;
      }
      return b.latestAt.compareTo(a.latestAt);
    });
    return groups;
  }

  int _firstUnviewedIndex(List<MessengerStory> stories) {
    for (var i = 0; i < stories.length; i += 1) {
      if (!stories[i].isViewed) return i;
    }
    return 0;
  }

  ImageProvider? _resolveAvatarImage(
    List<MessengerStory> stories,
    MessengerContact? contact,
  ) {
    final contactPath = contact?.avatarPath;
    if (contactPath != null && contactPath.isNotEmpty) {
      final file = File(contactPath);
      if (file.existsSync()) return FileImage(file);
    }
    for (final story in stories) {
      final storyPath = story.avatarPath;
      if (storyPath == null || storyPath.isEmpty) continue;
      final file = File(storyPath);
      if (file.existsSync()) return FileImage(file);
    }
    return null;
  }

  String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return _firstChar(parts.first).toUpperCase();
    }
    final first = _firstChar(parts.first).toUpperCase();
    final second = _firstChar(parts[1]).toUpperCase();
    return '$first$second';
  }

  String _firstChar(String value) {
    if (value.isEmpty) return '';
    return String.fromCharCode(value.runes.first);
  }
}

class _StoryGroup {
  final String contactId;
  final String title;
  final String initials;
  final ImageProvider? avatarImage;
  final Color backgroundColor;
  final bool isAvatarGenerating;
  final List<MessengerStory> stories;

  const _StoryGroup({
    required this.contactId,
    required this.title,
    required this.initials,
    required this.avatarImage,
    required this.backgroundColor,
    required this.isAvatarGenerating,
    required this.stories,
  });

  bool get hasUnviewed => stories.any((story) => !story.isViewed);
  bool get hasLockedStories => stories.any((story) => story.isLocked);

  DateTime get latestAt => stories.isEmpty
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : stories.last.createdAt;
}

class _StoryItem extends StatelessWidget {
  final String title;
  final String initials;
  final ImageProvider? avatarImage;
  final Color backgroundColor;
  final bool isAvatarGenerating;
  final List<bool> viewedSegments;
  final bool hasLockedStories;
  final VoidCallback onTap;

  const _StoryItem({
    required this.title,
    required this.initials,
    required this.avatarImage,
    required this.backgroundColor,
    required this.isAvatarGenerating,
    required this.viewedSegments,
    required this.hasLockedStories,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ring = _StoryRing(
      size: 56,
      strokeWidth: 3,
      viewedSegments: viewedSegments,
      viewedColor: colors.onSurface.withOpacity(0.2),
      unviewedColor: const Color(0xFF24C6FF),
      child: CircleAvatar(
        radius: 26,
        backgroundColor: colors.surface,
        child: Stack(
          children: [
            MessengerAvatar(
              size: 46,
              backgroundColor: backgroundColor,
              image: avatarImage,
              initials: initials,
              isLoading: isAvatarGenerating,
              initialsStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (hasLockedStories)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.lock,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 74,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ring,
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryRing extends StatelessWidget {
  final double size;
  final double strokeWidth;
  final List<bool> viewedSegments;
  final Color viewedColor;
  final Color unviewedColor;
  final Widget child;

  const _StoryRing({
    required this.size,
    required this.strokeWidth,
    required this.viewedSegments,
    required this.viewedColor,
    required this.unviewedColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _StoryRingPainter(
        strokeWidth: strokeWidth,
        viewedSegments: viewedSegments,
        viewedColor: viewedColor,
        unviewedColor: unviewedColor,
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(child: child),
      ),
    );
  }
}

class _StoryRingPainter extends CustomPainter {
  final double strokeWidth;
  final List<bool> viewedSegments;
  final Color viewedColor;
  final Color unviewedColor;

  const _StoryRingPainter({
    required this.strokeWidth,
    required this.viewedSegments,
    required this.viewedColor,
    required this.unviewedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = viewedSegments.isEmpty ? 1 : viewedSegments.length;
    final rect = Offset.zero & size;
    final radius = size.width / 2 - strokeWidth / 2;
    final center = rect.center;
    final segmentAngle = (2 * 3.141592653589793) / total;
    final gapAngle = total == 1 ? 0.0 : segmentAngle * 0.12;
    final startOffset = -3.141592653589793 / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < total; i += 1) {
      final isViewed =
          viewedSegments.isEmpty ? false : viewedSegments[i % total];
      paint.color = isViewed ? viewedColor : unviewedColor;
      final start = startOffset + (segmentAngle * i) + gapAngle / 2;
      final sweep = segmentAngle - gapAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StoryRingPainter oldDelegate) {
    return oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.viewedSegments.length != viewedSegments.length ||
        oldDelegate.viewedSegments
            .asMap()
            .entries
            .any((entry) => entry.value != viewedSegments[entry.key]) ||
        oldDelegate.viewedColor != viewedColor ||
        oldDelegate.unviewedColor != unviewedColor;
  }
}

class _UnreadBadge extends StatelessWidget {
  final String text;

  const _UnreadBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isSingleDigit = text.length == 1;
    final height = 18.0;
    return Container(
      width: isSingleDigit ? height : null,
      height: height,
      padding: isSingleDigit
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colors.primary,
        shape: isSingleDigit ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isSingleDigit ? null : BorderRadius.circular(height / 2),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _OnlineIndicator extends StatelessWidget {
  const _OnlineIndicator();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: const Color(0xFF2ECC71),
        shape: BoxShape.circle,
        border: Border.all(color: colors.surface, width: 2),
      ),
    );
  }
}
