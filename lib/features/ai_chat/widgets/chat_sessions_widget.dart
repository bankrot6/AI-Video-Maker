import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_providers.dart';
import '../../../data/chat_storage_repository.dart';
import '../../../services/localization/app_localization_service.dart';

/// Виджет для управления сессиями чата
class ChatSessionsWidget extends ConsumerStatefulWidget {
  const ChatSessionsWidget({super.key});

  @override
  ConsumerState<ChatSessionsWidget> createState() => _ChatSessionsWidgetState();
}

class _ChatSessionsWidgetState extends ConsumerState<ChatSessionsWidget> {
  List<ChatSession> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    try {
      final chatNotifier = ref.read(chatProvider.notifier);
      final sessions = await chatNotifier.getAllSessions();
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      debugPrint('Ошибка загрузки сессий: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('chat_history_title')),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createNewSession,
            tooltip: context.tr('chat_new'),
          ),
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    const Icon(Icons.download),
                    const SizedBox(width: 8),
                    Text(context.tr('chat_export_current')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    const Icon(Icons.delete_forever, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(context.tr('chat_clear_all')),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_sessions.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: ListView.builder(
        itemCount: _sessions.length,
        itemBuilder: (context, index) {
          final session = _sessions[index];
          return _buildSessionTile(session);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('chat_empty_title'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('chat_empty_subtitle'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _createNewSession,
            icon: const Icon(Icons.add),
            label: Text(context.tr('chat_new')),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionTile(ChatSession session) {
    final theme = Theme.of(context);
    final isToday = _isToday(session.lastUpdated);
    final isYesterday = _isYesterday(session.lastUpdated);

    String dateStr;
    if (isToday) {
      dateStr = context.tr('today');
    } else if (isYesterday) {
      dateStr = context.tr('yesterday');
    } else {
      dateStr = _formatDate(session.lastUpdated);
    }

    final timeStr = _formatTime(session.lastUpdated);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            Icons.chat,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          session.title,
          style: theme.textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$dateStr ${context.tr('at_time')} $timeStr',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              context
                  .trParams('chat_messages_count', ['${session.messageCount}']),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) => _handleSessionAction(action, session),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'load',
              child: Row(
                children: [
                  const Icon(Icons.open_in_new),
                  const SizedBox(width: 8),
                  Text(context.tr('open')),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  const Icon(Icons.delete, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(context.tr('delete')),
                ],
              ),
            ),
          ],
        ),
        onTap: () => _loadSession(session),
      ),
    );
  }

  Future<void> _createNewSession() async {
    try {
      final chatNotifier = ref.read(chatProvider.notifier);
      chatNotifier.clearChat();

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('chat_created')),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Ошибка создания новой сессии: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('chat_create_error')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadSession(ChatSession session) async {
    try {
      final chatNotifier = ref.read(chatProvider.notifier);
      await chatNotifier.loadSession(session.id);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.trParams('chat_loaded', [session.title])),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Ошибка загрузки сессии: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('chat_load_error')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleSessionAction(String action, ChatSession session) async {
    switch (action) {
      case 'load':
        await _loadSession(session);
        break;
      case 'delete':
        await _showDeleteConfirmation(session);
        break;
    }
  }

  Future<void> _handleMenuAction(String action) async {
    switch (action) {
      case 'export':
        await _exportCurrentChat();
        break;
      case 'clear_all':
        await _showClearAllConfirmation();
        break;
    }
  }

  Future<void> _showDeleteConfirmation(ChatSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('chat_delete_title')),
        content: Text(context.trParams('chat_delete_confirm', [session.title])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final chatNotifier = ref.read(chatProvider.notifier);
        await chatNotifier.deleteSession(session.id);
        await _loadSessions(); // Обновляем список

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('chat_deleted')),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        debugPrint('Ошибка удаления сессии: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('chat_delete_error')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _showClearAllConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('chat_clear_all_title')),
        content: Text(context.tr('chat_clear_all_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.tr('chat_clear_all_action')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final chatNotifier = ref.read(chatProvider.notifier);
        await chatNotifier.clearAllHistory();
        await _loadSessions(); // Обновляем список

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('chat_all_cleared')),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        debugPrint('Ошибка очистки истории: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('chat_clear_error')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _exportCurrentChat() async {
    try {
      final chatNotifier = ref.read(chatProvider.notifier);
      final exportText = chatNotifier.exportChatToText();

      // В реальном приложении здесь можно использовать share_plus или file_picker
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.tr('chat_export_title')),
            content: SingleChildScrollView(
              child: SelectableText(exportText),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.tr('close')),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Ошибка экспорта чата: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('chat_export_error')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  bool _isYesterday(DateTime date) {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day;
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
