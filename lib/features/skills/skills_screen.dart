// Skills browser — list installed skills with enabled/disabled status.
import 'package:flutter/material.dart';
import '../../core/network/connection_manager.dart';
import '../../shared/errors/hermes_error.dart';
import '../../shared/widgets/hermes_error_state.dart';

class SkillsScreen extends StatefulWidget {
  final SavedConnection connection;
  const SkillsScreen({required this.connection, super.key});

  static final Map<String, List<Map<String, dynamic>>> cachedSkills = {};

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  late DashboardClient _client;
  List<Map<String, dynamic>> _skills = [];
  bool _loading = true;
  bool _refreshing = false;
  dynamic _error;

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
    _load();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _load({bool silentRefresh = false}) async {
    final cacheKey = widget.connection.id;
    final hasCache = SkillsScreen.cachedSkills.containsKey(cacheKey);

    if (silentRefresh && hasCache) {
      setState(() => _refreshing = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    if (hasCache) {
      _skills = SkillsScreen.cachedSkills[cacheKey]!;
      if (!silentRefresh) {
        setState(() => _loading = false);
      }
    }

    try {
      final raw = await _client.getSkills();
      final skills = raw.whereType<Map<String, dynamic>>().toList();
      SkillsScreen.cachedSkills[cacheKey] = skills;
      if (!mounted) return;
      setState(() {
        _skills = skills;
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
        title: Text('Skills (${_skills.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: (_loading || _refreshing)
                ? null
                : () => _load(silentRefresh: true),
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
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return HermesErrorState(
        error: _error,
        connection: widget.connection,
        onRetry: _load,
        source: HermesErrorSource.dashboard,
        title: 'Failed to load skills',
      );
    }
    if (_skills.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension_off, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'No skills found',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _skills.length,
        itemBuilder: (_, i) {
          final skill = _skills[i];
          final name = skill['name'] as String? ?? '';
          final enabled = skill['enabled'] as bool? ?? false;
          final description = skill['description'] as String? ?? '';
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              title: Text(
                name,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              subtitle: description.isNotEmpty
                  ? Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    )
                  : null,
              trailing: Icon(
                enabled ? Icons.check_circle : Icons.block,
                color: enabled ? Colors.green : Colors.orange,
                size: 18,
              ),
            ),
          );
        },
      ),
    );
  }
}
