import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../../core/network/connection_manager.dart';
import '../../shared/errors/error_messages.dart';
import '../../shared/errors/hermes_error.dart';
import '../../shared/responsive.dart';
import '../../shared/widgets/hermes_error_state.dart';
import '../../core/storage/session_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../chat/chat_screen.dart';
import '../diagnostics/diagnostics_screen.dart';

enum _SortBy { recent, created, messageCount }

enum _FilterType { all, active, completed, pinned, archived, hasTool, hasQuestion }

class SessionListScreen extends StatefulWidget {
  final SavedConnection connection;
  final SharedPreferences prefs;
  final VoidCallback? onOpenDrawer;
  const SessionListScreen({
    required this.connection,
    required this.prefs,
    this.onOpenDrawer,
    super.key,
  });

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  late final ApiClient _client;
  late final SessionCache _cache;
  List<Session> _sessions = [];
  bool _loading = true;
  dynamic _error;
  bool _healthOk = false;
  bool _healthCheckDone = false;
  String? _healthMessage;
  String _searchQuery = '';
  Timer? _backgroundRefresh;

  // Library controls
  _SortBy _sortBy = _SortBy.recent;
  _FilterType _filterType = _FilterType.all;
  String? _filterModel;
  String? _filterSource;
  bool _showArchived = false;
  Set<String> _messageSearchResults = {};

  // Undo deletion
  Session? _pendingDeleteSession;
  Timer? _pendingDeleteTimer;

  List<String> get _availableModels =>
      _sessions.map((s) => s.model).toSet().toList()..sort();
  List<String> get _availableSources =>
      _sessions.map((s) => s.source).where((s) => s.isNotEmpty).toSet().toList()..sort();

  List<_SessionGroup> get _groupedSessions {
    final filtered = _filteredSessions;
    if (!_groupByDate || _sortBy == _SortBy.messageCount) {
      return [_SessionGroup(label: null, sessions: filtered)];
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekAgo = today.subtract(const Duration(days: 7));
    final pinned = <Session>[];
    final todayList = <Session>[];
    final weekList = <Session>[];
    final earlierList = <Session>[];
    for (final s in filtered) {
      if (_cache.isPinned(s.id)) {
        pinned.add(s);
        continue;
      }
      final dt = DateTime.fromMillisecondsSinceEpoch((s.startedAt * 1000).toInt());
      if (dt.isAfter(today)) {
        todayList.add(s);
      } else if (dt.isAfter(weekAgo)) {
        weekList.add(s);
      } else {
        earlierList.add(s);
      }
    }
    final groups = <_SessionGroup>[];
    if (pinned.isNotEmpty) groups.add(_SessionGroup(label: 'Pinned', sessions: pinned));
    if (todayList.isNotEmpty) groups.add(_SessionGroup(label: 'Today', sessions: todayList));
    if (weekList.isNotEmpty) groups.add(_SessionGroup(label: 'This Week', sessions: weekList));
    if (earlierList.isNotEmpty) groups.add(_SessionGroup(label: 'Earlier', sessions: earlierList));
    return groups;
  }

  bool get _groupByDate => _sortBy != _SortBy.messageCount;

  List<Session> get _filteredSessions {
    var result = _sessions.where((s) {
      // Archive filter
      final isArchived = _cache.isArchived(s.id);
      if (!_showArchived && isArchived) return false;
      if (_showArchived && !isArchived) return false;

      // Type filter
      switch (_filterType) {
        case _FilterType.active:
          if (!s.isActive) return false;
          break;
        case _FilterType.completed:
          if (s.isActive) return false;
          break;
        case _FilterType.pinned:
          if (!_cache.isPinned(s.id)) return false;
          break;
        case _FilterType.archived:
          if (!_cache.isArchived(s.id)) return false;
          break;
        case _FilterType.hasTool:
          if (!_cache.hasToolActivity(s.id)) return false;
          break;
        case _FilterType.hasQuestion:
          if (!_cache.hasPendingQuestion(s.id)) return false;
          break;
        case _FilterType.all:
          break;
      }

      // Model filter
      if (_filterModel != null && s.model != _filterModel) return false;

      // Source filter
      if (_filterSource != null && s.source != _filterSource) return false;

      // Text search
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesMetadata = s.title.toLowerCase().contains(q) ||
            s.model.toLowerCase().contains(q) ||
            s.preview.toLowerCase().contains(q) ||
            s.id.toLowerCase().contains(q);
        final matchesMessages = _messageSearchResults.contains(s.id);
        if (!matchesMetadata && !matchesMessages) return false;
      }

      return true;
    }).toList();

    // Sort
    switch (_sortBy) {
      case _SortBy.recent:
        result.sort((a, b) => b.startedAt.compareTo(a.startedAt));
        break;
      case _SortBy.created:
        result.sort((a, b) => b.startedAt.compareTo(a.startedAt));
        break;
      case _SortBy.messageCount:
        result.sort((a, b) => b.messageCount.compareTo(a.messageCount));
        break;
    }

    return result;
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      if (value.isNotEmpty) {
        _messageSearchResults = _cache.searchMessages(value);
      } else {
        _messageSearchResults = {};
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _client = ApiClient(
      baseUrl: widget.connection.baseUrl,
      apiKey: widget.connection.apiKey,
      pathPrefix: widget.connection.gatewayPrefix ?? '',
      cfAccessClientId: widget.connection.cfAccessClientId,
      cfAccessClientSecret: widget.connection.cfAccessClientSecret,
    );
    _cache = SessionCache(widget.prefs, widget.connection.id);
    final cached = _cache.loadSessions();
    if (cached.isNotEmpty) {
      _sessions = cached;
      _loading = false;
    }
    _checkHealth();
    _backgroundRefresh = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (_healthOk) {
          _fetchSessions(silent: true);
        } else {
          _checkHealth();
        }
      },
    );
  }

  Future<void> _checkHealth() async {
    final result = await _client.healthCheckDetail();
    if (!mounted) return;
    setState(() {
      _healthOk = result.ok;
      _healthCheckDone = true;
      _healthMessage = result.ok ? null : result.message;
    });
    if (result.ok) {
      _fetchSessions();
    } else if (_sessions.isEmpty && _loading) {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _backgroundRefresh?.cancel();
    _pendingDeleteTimer?.cancel();
    _client.close();
    super.dispose();
  }

  Future<void> _fetchSessions({bool isRetry = false, bool silent = false}) async {
    if (!isRetry && !silent && _sessions.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final sessions = await _client.getSessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loading = false;
        _error = null;
        _healthOk = true;
        _healthCheckDone = true;
      });
      final previousSessions = _cache.loadSessions();
      await _cache.saveSessions(sessions);
      _prefetchMessages(sessions, previousSessions);
    } catch (e) {
      if (!mounted) return;
      if (_sessions.isNotEmpty) {
        // We have cached data — switch to offline mode instead of showing error
        setState(() {
          _healthOk = false;
          _healthCheckDone = true;
          _healthMessage = ErrorMessages.format(e);
          _loading = false;
          _error = null;
        });
      } else {
        setState(() {
          _error = e;
          _loading = false;
        });
        if (!isRetry) {
          _retryWithBackoff();
        }
      }
    }
  }

  Future<void> _prefetchMessages(
    List<Session> sessions,
    List<Session> previousSessions,
  ) async {
    // Do not make the list wait for conversation bodies. Each session gets
    // refreshed independently and becomes instant the next time it opens.
    final previousById = {
      for (final session in previousSessions) session.id: session,
    };
    await Future.wait(
      sessions.where((session) {
        final previous = previousById[session.id];
        return _cache.loadMessages(session.id).isEmpty ||
            previous == null ||
            previous.messageCount != session.messageCount;
      }).map((session) async {
        try {
          final messages = await _client.getMessages(session.id);
          await _cache.saveMessages(session.id, messages);
        } catch (_) {
          // A single deleted/remote session must not stop the other refreshes.
        }
      }),
    );
  }

  void _retryWithBackoff() {
    int attempt = 0;
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      attempt++;
      try {
        final sessions = await _client.getSessions();
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _sessions = sessions;
          _error = null;
          _loading = false;
        });
        timer.cancel();
      } catch (_) {
        if (attempt >= 3) {
          timer.cancel();
        }
      }
    });
  }

  Future<void> _deleteWithUndo(Session session) async {
    final removedIndex = _sessions.indexWhere((s) => s.id == session.id);
    if (removedIndex < 0) return;
    final removed = _sessions.removeAt(removedIndex);
    _pendingDeleteSession = removed;
    _pendingDeleteTimer?.cancel();
    setState(() {});

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Session "${session.title}" deleted'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            _pendingDeleteTimer?.cancel();
            if (_pendingDeleteSession != null) {
              setState(() {
                _sessions.insert(
                  removedIndex.clamp(0, _sessions.length),
                  _pendingDeleteSession!,
                );
                _pendingDeleteSession = null;
              });
            }
          },
        ),
      ),
    );

    _pendingDeleteTimer = Timer(const Duration(seconds: 5), () async {
      final toDelete = _pendingDeleteSession;
      _pendingDeleteSession = null;
      if (toDelete == null) return;
      try {
        await _client.deleteSession(toDelete.id);
        await _cache.removeFromArchive(toDelete.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete on server: ${ErrorMessages.format(e)}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });
  }

  void _confirmDeleteSession(Session session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Session?'),
        content: Text(
          'Are you sure you want to delete "${session.title}"?\n'
          'You can Undo within 5 seconds.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteWithUndo(session);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePin(Session session) async {
    await _cache.togglePinned(session.id);
    if (mounted) setState(() {});
  }

  Future<void> _toggleArchive(Session session) async {
    await _cache.toggleArchived(session.id);
    if (mounted) setState(() {});
  }

  void _renameSession(Session session) {
    final controller = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Session'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Session title',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (_) => _doRename(ctx, session, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _doRename(ctx, session, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _doRename(BuildContext ctx, Session session, String newTitle) {
    final title = newTitle.trim();
    if (title.isEmpty || title == session.title) {
      Navigator.pop(ctx);
      return;
    }
    Navigator.pop(ctx);
    _doRenameApi(session, title);
  }

  Future<void> _doRenameApi(Session session, String newTitle) async {
    try {
      await _client.updateSession(session.id, title: newTitle);
      if (!mounted) return;
      setState(() {
        final idx = _sessions.indexWhere((s) => s.id == session.id);
        if (idx >= 0) {
          _sessions[idx] = session.copyWith(title: newTitle);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session renamed to "$newTitle"')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to rename session: ${ErrorMessages.format(e)}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _createNewSession() {
    final sessionId = GatewayChatClient.generateSessionId();
    final session = Session(
      id: sessionId,
      title: 'New Chat',
      model: 'hermes-agent',
      source: 'mobile',
      messageCount: 0,
      isActive: true,
      preview: '',
      startedAt: DateTime.now().millisecondsSinceEpoch.toDouble() / 1000,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(connection: widget.connection, session: session),
      ),
    );
  }

  String _formatTime(double ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt());
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}/${dt.month}';
  }

  void _openScreen(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final offline = _healthCheckDone && !_healthOk;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'HERMES',
          style: GoogleFonts.cinzel(
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
        leading: widget.onOpenDrawer != null
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: widget.onOpenDrawer,
              )
            : null,
        actions: [
          if (offline)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.cloud_off, color: Colors.orange, size: 20),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: (_loading || offline) ? null : _fetchSessions,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: offline ? 'New Chat (unavailable offline)' : 'New Chat',
        onPressed: offline ? null : _createNewSession,
        child: const Icon(Icons.chat, color: Colors.black),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final offline = _healthCheckDone && !_healthOk;

    // Still waiting for first health check with no cached data
    if (!_healthCheckDone && _loading && _sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(),
            ),
            const SizedBox(height: 16),
            Text(
              'Connecting to ${widget.connection.baseUrl}...',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure the Gateway API Server is running\n(hermes gateway status)',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    // Health check done, server unreachable, no cached data
    if (offline && _sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              'Server unreachable',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (_healthMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _healthMessage!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _checkHealth,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Non-offline error with no cached data
    if (_error != null && _sessions.isEmpty) {
      return HermesErrorState(
        error: _error,
        connection: widget.connection,
        onRetry: () => _fetchSessions(),
        source: HermesErrorSource.api,
      );
    }

    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No sessions yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to start a new chat',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    final groups = _groupedSessions;
    final totalFiltered = groups.fold<int>(0, (sum, g) => sum + g.sessions.length);

    return Column(
      children: [
        if (offline) _buildOfflineBanner(),
        _buildSearchBar(),
        _buildFilterBar(),
        if (totalFiltered == 0)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    _searchQuery.isNotEmpty
                        ? 'No sessions match "$_searchQuery"'
                        : 'No sessions match the current filters',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchSessions,
              child: _buildGroupedList(groups),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search sessions & messages...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _onSearchChanged(''),
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildFilterBar() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _buildFilterChip(),
          const SizedBox(width: 8),
          _buildSortChip(),
          const SizedBox(width: 8),
          if (_availableModels.length > 1) ...[
            _buildModelChip(),
            const SizedBox(width: 8),
          ],
          if (_availableSources.length > 1) ...[
            _buildSourceChip(),
            const SizedBox(width: 8),
          ],
          FilterChip(
            label: const Text('Archived'),
            selected: _showArchived,
            onSelected: (v) => setState(() => _showArchived = v),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip() {
    final labels = {
      _FilterType.all: 'All',
      _FilterType.active: 'Active',
      _FilterType.completed: 'Completed',
      _FilterType.pinned: 'Pinned',
      _FilterType.archived: 'Archived',
      _FilterType.hasTool: 'Has Tools',
      _FilterType.hasQuestion: 'Has Question',
    };
    return PopupMenuButton<_FilterType>(
      child: FilterChip(
        label: Text(labels[_filterType]!),
        selected: _filterType != _FilterType.all,
        onSelected: (_) {},
        visualDensity: VisualDensity.compact,
      ),
      onSelected: (type) => setState(() {
        _filterType = type;
        if (type == _FilterType.archived) _showArchived = true;
      }),
      itemBuilder: (ctx) => [
        for (final type in _FilterType.values)
          PopupMenuItem(
            value: type,
            child: Row(children: [
              Icon(_filterType == type ? Icons.check : Icons.circle_outlined,
                  size: 16, color: _filterType == type ? const Color(0xFFD4AF37) : Colors.grey),
              const SizedBox(width: 8),
              Text(labels[type]!),
            ]),
          ),
      ],
    );
  }

  Widget _buildSortChip() {
    final labels = {
      _SortBy.recent: 'Recent Activity',
      _SortBy.created: 'Creation Date',
      _SortBy.messageCount: 'Message Count',
    };
    return PopupMenuButton<_SortBy>(
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort, size: 16),
            const SizedBox(width: 4),
            Text(labels[_sortBy]!),
          ],
        ),
        selected: false,
        onSelected: (_) {},
        visualDensity: VisualDensity.compact,
      ),
      onSelected: (sort) => setState(() => _sortBy = sort),
      itemBuilder: (ctx) => [
        for (final sort in _SortBy.values)
          PopupMenuItem(
            value: sort,
            child: Row(children: [
              Icon(_sortBy == sort ? Icons.check : Icons.circle_outlined,
                  size: 16, color: _sortBy == sort ? const Color(0xFFD4AF37) : Colors.grey),
              const SizedBox(width: 8),
              Text(labels[sort]!),
            ]),
          ),
      ],
    );
  }

  Widget _buildModelChip() {
    return PopupMenuButton<String>(
      child: FilterChip(
        label: Text(_filterModel ?? 'All Models'),
        selected: _filterModel != null,
        onSelected: (_) {},
        visualDensity: VisualDensity.compact,
      ),
      onSelected: (model) => setState(() {
        _filterModel = model == '__all__' ? null : model;
      }),
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: '__all__',
          child: Text('All Models'),
        ),
        for (final model in _availableModels)
          PopupMenuItem(value: model, child: Text(model)),
      ],
    );
  }

  Widget _buildSourceChip() {
    return PopupMenuButton<String>(
      child: FilterChip(
        label: Text(_filterSource ?? 'All Sources'),
        selected: _filterSource != null,
        onSelected: (_) {},
        visualDensity: VisualDensity.compact,
      ),
      onSelected: (source) => setState(() {
        _filterSource = source == '__all__' ? null : source;
      }),
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: '__all__',
          child: Text('All Sources'),
        ),
        for (final source in _availableSources)
          PopupMenuItem(value: source, child: Text(source)),
      ],
    );
  }

  Widget _buildGroupedList(List<_SessionGroup> groups) {
    final isTablet = Responsive.isTablet(context);
    final slivers = <Widget>[];

    for (final group in groups) {
      if (group.label != null) {
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              group.label!,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ));
      }
      if (isTablet) {
        slivers.add(SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 400,
            childAspectRatio: 2.8,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => _buildSessionCard(group.sessions[i]),
            childCount: group.sessions.length,
          ),
        ));
      } else {
        slivers.add(SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => _buildSessionCard(group.sessions[i]),
            childCount: group.sessions.length,
          ),
        ));
      }
    }

    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 4)),
        ...slivers,
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  Widget _buildOfflineBanner() {
    final syncedAt = _cache.sessionsSyncedAt();
    final syncLabel = syncedAt != null
        ? 'showing data synced ${_formatRelativeTime(syncedAt)}'
        : 'showing cached data';
    return Material(
      color: const Color(0xFF2D2D2D),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.cloud_off, color: Colors.orange, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Offline — $syncLabel',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_healthMessage != null)
                      Text(
                        _healthMessage!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.orange, size: 18),
                tooltip: 'Retry connection',
                onPressed: _checkHealth,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.dns, color: Colors.orange, size: 18),
                tooltip: 'Open Diagnostics',
                onPressed: () => _openScreen(
                    DiagnosticsScreen(connection: widget.connection)),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.orange, size: 18),
                tooltip: 'Switch Connection',
                onPressed: () {
                  Navigator.pop(context);
                },
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildSessionCard(Session session) {
    final offline = _healthCheckDone && !_healthOk;
    final isPinned = _cache.isPinned(session.id);
    final isArchived = _cache.isArchived(session.id);
    return Dismissible(
      key: Key(session.id),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.edit, color: Colors.white),
      ),
      confirmDismiss: offline
          ? (_) async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Actions are unavailable offline'),
                  duration: Duration(seconds: 2),
                ),
              );
              return false;
            }
          : (direction) async {
              if (direction == DismissDirection.startToEnd) {
                _confirmDeleteSession(session);
              } else {
                _renameSession(session);
              }
              return false;
            },
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Stack(
            children: [
              Icon(
                session.isActive
                    ? Icons.chat
                    : Icons.chat_bubble_outline,
                color: session.isActive
                    ? const Color(0xFFD4AF37)
                    : Colors.grey,
              ),
              if (isPinned)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Icon(Icons.push_pin, size: 12, color: Colors.amber[700]),
                ),
            ],
          ),
          title: Row(
            children: [
              if (isArchived)
                Icon(Icons.archive_outlined, size: 14, color: Colors.grey[500]),
              if (isArchived) const SizedBox(width: 4),
              Expanded(
                child: Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${session.messageCount} msgs \u2022 ${session.model} \u2022 ${_formatTime(session.startedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (session.preview.isNotEmpty)
                Text(
                  session.preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey[500]),
                ),
            ],
          ),
          isThreeLine: session.preview.isNotEmpty,
          trailing: offline
              ? const Icon(Icons.lock_outline, size: 20, color: Colors.grey)
              : PopupMenuButton<String>(
                  onSelected: (action) {
                    switch (action) {
                      case 'rename':
                        _renameSession(session);
                        break;
                      case 'pin':
                        _togglePin(session);
                        break;
                      case 'archive':
                        _toggleArchive(session);
                        break;
                      case 'delete':
                        _confirmDeleteSession(session);
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'pin',
                      child: Row(
                        children: [
                          Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
                          const SizedBox(width: 8),
                          Text(isPinned ? 'Unpin' : 'Pin'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'archive',
                      child: Row(
                        children: [
                          Icon(isArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
                          const SizedBox(width: 8),
                          Text(isArchived ? 'Unarchive' : 'Archive'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit),
                          SizedBox(width: 8),
                          Text('Rename'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete',
                              style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  connection: widget.connection,
                  session: session,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SessionGroup {
  final String? label;
  final List<Session> sessions;
  const _SessionGroup({this.label, required this.sessions});
}
