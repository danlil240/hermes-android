// Memory browser screen — read memory entries from Hermes config.
//
// Memory entries live in config.yaml under the 'memory' key as a list:
//   memory:
//     - target: user
//       content: "User name..."
//
// API: GET /api/config returns the full config including memory.
import 'package:flutter/material.dart';
import '../../core/network/connection_manager.dart';
import '../../shared/errors/hermes_error.dart';
import '../../shared/widgets/hermes_error_state.dart';

class MemoryScreen extends StatefulWidget {
  final SavedConnection connection;
  const MemoryScreen({required this.connection, super.key});

  static final Map<String, List<Map<String, dynamic>>> cachedEntries = {};

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  late DashboardClient _client;
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  bool _refreshing = false;
  dynamic _error;
  String? _source; // 'config' or 'api'

  @override
  void initState() {
    super.initState();
    _client = DashboardClient(
      host: widget.connection.dashboardHost,
      port: widget.connection.dashboardPort,
      pathPrefix: widget.connection.dashboardPrefix ?? "",
      proxied: widget.connection.dashboardProxied,
      useHttps: widget.connection.useHttps,
      username: widget.connection.dashboardUsername,
      password: widget.connection.dashboardPassword,
      cfAccessClientId: widget.connection.cfAccessClientId,
      cfAccessClientSecret: widget.connection.cfAccessClientSecret,
    );
    _loadMemory();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _loadMemory({bool silentRefresh = false}) async {
    final cacheKey = widget.connection.id;
    final hasCache = MemoryScreen.cachedEntries.containsKey(cacheKey);

    if (silentRefresh && hasCache) {
      setState(() => _refreshing = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    if (hasCache) {
      _entries = MemoryScreen.cachedEntries[cacheKey]!;
      if (!silentRefresh) {
        setState(() => _loading = false);
      }
    }

    try {
      List<Map<String, dynamic>> entries;
      String source = 'config';

      // Try dedicated /api/memory endpoint first
      try {
        final memData = await _client.apiGet('memory');
        final items =
            memData['entries'] as List? ?? memData['memory'] as List? ?? [];
        if (items.isNotEmpty) {
          entries = items.cast<Map<String, dynamic>>();
          source = 'api';
          MemoryScreen.cachedEntries[cacheKey] = entries;
          if (!mounted) return;
          setState(() {
            _entries = entries;
            _source = source;
            _loading = false;
            _refreshing = false;
          });
          return;
        }
      } catch (_) {
        // Endpoint not available — fall through to config
      }

      // Fallback: read memory from /api/config
      final config = await _client.apiGet('config');
      final mem = config['memory'];

      if (mem is List) {
        entries = mem.cast<Map<String, dynamic>>();
      } else if (mem is Map) {
        entries = <Map<String, dynamic>>[];
        mem.forEach((key, value) {
          entries.add({'target': key, 'content': value.toString()});
        });
      } else {
        entries = [];
      }

      MemoryScreen.cachedEntries[cacheKey] = entries;
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _source = source;
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _refreshing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Memory'),
            if (_source != null)
              Text(
                'Source: $_source',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: (_loading || _refreshing)
                ? null
                : () => _loadMemory(silentRefresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_refreshing) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return HermesErrorState(
        error: _error,
        connection: widget.connection,
        onRetry: _loadMemory,
        source: HermesErrorSource.dashboard,
        title: 'Failed to load memory',
      );
    }

    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No memory entries',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Memory entries are cross-session facts the agent remembers.\n'
              'They are configured in ~/.hermes/config.yaml',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMemory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          final target = entry['target'] as String? ?? 'memory';
          final content = entry['content'] as String? ?? '';

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Chip(
                        label: Text(
                          target,
                          style: const TextStyle(fontSize: 11),
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        backgroundColor: target == 'user'
                            ? Colors.blue.shade800
                            : Colors.grey.shade800,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(content, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
