import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../../core/network/connection_manager.dart';
import '../../shared/errors/error_messages.dart';
import '../../shared/responsive.dart';
import '../../core/storage/session_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../chat/chat_screen.dart';
import '../settings/settings_screen.dart';
import '../memory/memory_screen.dart';
import '../cron/cron_screen.dart';
import '../skills/skills_screen.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../services/services_screen.dart';

class SessionListScreen extends StatefulWidget {
  final SavedConnection connection;
  final SharedPreferences prefs;
  const SessionListScreen({
    required this.connection,
    required this.prefs,
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
  String? _error;
  bool _healthOk = false;
  String _searchQuery = '';
  Timer? _backgroundRefresh;

  List<Session> get _filteredSessions {
    if (_searchQuery.isEmpty) return _sessions;
    final q = _searchQuery.toLowerCase();
    return _sessions.where((s) {
      return s.title.toLowerCase().contains(q) ||
          s.model.toLowerCase().contains(q) ||
          s.preview.toLowerCase().contains(q) ||
          s.id.toLowerCase().contains(q);
    }).toList();
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
      (_) => _fetchSessions(silent: true),
    );
  }

  Future<void> _checkHealth() async {
    bool ok = false;
    int attempts = 0;
    const maxAttempts = 3;
    while (attempts < maxAttempts && !ok) {
      ok = await _client.healthCheck();
      if (!ok && attempts < maxAttempts - 1) {
        await Future.delayed(Duration(seconds: 1 << attempts));
      }
      attempts++;
    }
    if (!mounted) return;
    setState(() => _healthOk = ok);
    if (ok) _fetchSessions();
  }

  @override
  void dispose() {
    _backgroundRefresh?.cancel();
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
      });
      final previousSessions = _cache.loadSessions();
      await _cache.saveSessions(sessions);
      _prefetchMessages(sessions, previousSessions);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorMessages.format(e);
        _loading = false;
      });
      if (!isRetry) {
        _retryWithBackoff();
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

  Future<void> _deleteSession(Session session) async {
    try {
      await _client.deleteSession(session.id);
      if (!mounted) return;
      setState(() {
        _sessions.removeWhere((s) => s.id == session.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Session "${session.title}" deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete session: ${ErrorMessages.format(e)}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _confirmDeleteSession(Session session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Session?'),
        content: Text(
          'Are you sure you want to delete "${session.title}"?\n'
          'This action cannot be undone.',
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
              _deleteSession(session);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
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
          _sessions[idx] = Session(
            id: session.id,
            title: newTitle,
            model: session.model,
            source: session.source,
            messageCount: session.messageCount,
            isActive: session.isActive,
            preview: session.preview,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
          );
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
    Navigator.pop(context); // close drawer
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
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
        actions: [
          if (!_healthOk)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.warning_amber, color: Colors.orange, size: 20),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _fetchSessions,
          ),
        ],
      ),
      drawer: _buildDrawer(),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New Chat',
        onPressed: _createNewSession,
        child: const Icon(Icons.chat, color: Colors.black),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Brand header in drawer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              color: Colors.black,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'HERMES',
                    style: GoogleFonts.cinzel(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFD4AF37),
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.connection.label,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Switch Connection'),
              onTap: () {
                Navigator.pop(context); // close drawer
                Navigator.pop(context); // pop to connections list
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('Memory'),
              onTap: () =>
                  _openScreen(MemoryScreen(connection: widget.connection)),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Cron Jobs'),
              onTap: () =>
                  _openScreen(CronScreen(connection: widget.connection)),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('Skills'),
              onTap: () =>
                  _openScreen(SkillsScreen(connection: widget.connection)),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.dns),
              title: const Text('Diagnostics'),
              onTap: () => _openScreen(
                  DiagnosticsScreen(connection: widget.connection)),
            ),
            ListTile(
              leading: const Icon(Icons.build),
              title: const Text('Services'),
              onTap: () =>
                  _openScreen(ServicesScreen(connection: widget.connection)),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () =>
                  _openScreen(SettingsScreen(connection: widget.connection)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!_healthOk) {
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
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _checkHealth, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              'Connection issue',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _fetchSessions,
              child: const Text('Retry'),
            ),
          ],
        ),
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

    final filtered = _filteredSessions;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search sessions...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value);
            },
          ),
        ),
        if (filtered.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No sessions match "$_searchQuery"',
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
              child: Responsive.isTablet(context)
                  ? GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 400,
                        childAspectRatio: 2.8,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) =>
                          _buildSessionCard(filtered[index]),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) =>
                          _buildSessionCard(filtered[index]),
                    ),
            ),
          ),
      ],
    );
  }

  Widget _buildSessionCard(Session session) {
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
      confirmDismiss: (direction) async {
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
          leading: Icon(
            session.isActive
                ? Icons.chat
                : Icons.chat_bubble_outline,
            color: session.isActive
                ? const Color(0xFFD4AF37)
                : Colors.grey,
          ),
          title: Text(
            session.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
          trailing: PopupMenuButton<String>(
            onSelected: (action) {
              if (action == 'rename') {
                _renameSession(session);
              } else if (action == 'delete') {
                _confirmDeleteSession(session);
              }
            },
            itemBuilder: (ctx) => [
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
