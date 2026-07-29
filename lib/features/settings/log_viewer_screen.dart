import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/app_logger.dart';
import '../../services/localization/app_localization_service.dart';
import 'dart:async';

final _logFilterProvider = StateProvider<Set<String>>((ref) => {
      'RUSTORE',
      'RUSTORE_BILLING',
      'STORE_DETECTION',
      'PAYWALL',
      'PURCHASES',
      'TOKEN_RESTORE',
    });

class LogViewerScreen extends ConsumerStatefulWidget {
  const LogViewerScreen({super.key});

  @override
  ConsumerState<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends ConsumerState<LogViewerScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _autoScroll = true;

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeTags = ref.watch(_logFilterProvider);
    final search = _searchController.text.trim().toLowerCase();

    final initial = AppLogger.bufferedLogs
        .where((e) => _match(e, activeTags, search))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('logs_payments_temp_title')),
        actions: [
          IconButton(
            icon: Icon(_autoScroll ? Icons.pause : Icons.play_arrow),
            tooltip: _autoScroll
                ? context.tr('autoscroll_disable')
                : context.tr('autoscroll_enable'),
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
        ],
      ),
      body: Column(
        children: [
          _FiltersBar(searchController: _searchController),
          const Divider(height: 1),
          Expanded(
            child: _LogsList(
              initial: initial,
              controller: _scrollController,
              autoScroll: _autoScroll,
              predicate: (e) => _match(e, activeTags, search),
            ),
          ),
        ],
      ),
    );
  }

  bool _match(LogEntry e, Set<String> tags, String search) {
    final hasFilter =
        tags.any((t) => e.tag.contains(t) || e.message.contains(t));
    if (!hasFilter) return false;
    if (search.isEmpty) return true;
    return e.message.toLowerCase().contains(search) ||
        e.tag.toLowerCase().contains(search);
  }
}

class _FiltersBar extends ConsumerWidget {
  final TextEditingController searchController;
  const _FiltersBar({required this.searchController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(_logFilterProvider);
    final tags = const [
      'RUSTORE',
      'RUSTORE_BILLING',
      'STORE_DETECTION',
      'PAYWALL',
      'PURCHASES',
      'TOKEN_RESTORE',
    ];

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: context.tr('search_by_message_or_tag'),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => ref.invalidate(_logFilterProvider),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  searchController.clear();
                  ref.invalidate(_logFilterProvider);
                },
                icon: const Icon(Icons.clear),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in tags)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(t),
                      selected: active.contains(t),
                      onSelected: (val) {
                        final set = {...active};
                        if (val) {
                          set.add(t);
                        } else {
                          set.remove(t);
                        }
                        ref.read(_logFilterProvider.notifier).state = set;
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogsList extends StatefulWidget {
  final List<LogEntry> initial;
  final ScrollController controller;
  final bool autoScroll;
  final bool Function(LogEntry) predicate;

  const _LogsList({
    required this.initial,
    required this.controller,
    required this.autoScroll,
    required this.predicate,
  });

  @override
  State<_LogsList> createState() => _LogsListState();
}

class _LogsListState extends State<_LogsList> {
  late List<LogEntry> _items;
  late final StreamSubscription<LogEntry> _sub;

  @override
  void initState() {
    super.initState();
    _items = widget.initial;
    _sub = AppLogger.logStream.listen((e) {
      if (!widget.predicate(e)) return;
      setState(() {
        _items = [..._items, e];
      });
      if (widget.autoScroll && widget.controller.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.controller.jumpTo(widget.controller.position.maxScrollExtent);
        });
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return Center(child: Text(context.tr('no_logs_for_selected_filters')));
    }
    return ListView.builder(
      controller: widget.controller,
      itemCount: _items.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SelectableText(
          _items[i].toString(),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}
