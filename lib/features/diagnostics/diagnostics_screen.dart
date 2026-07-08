// Diagnostics screen — shows Hermes home PC health status.
// Fetches /health and /status from the Gateway API.
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/network/connection_manager.dart';

class DiagnosticsScreen extends StatefulWidget {
  final SavedConnection connection;
  const DiagnosticsScreen({required this.connection, super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late final ApiClient _client;
  Map<String, dynamic>? _statusData;
  bool _healthOk = false;
  bool _loading = true;
  String? _error;
  DateTime? _lastChecked;
  Timer? _autoRefresh;

  @override
  void initState() {
    super.initState();
    _client = ApiClient(
      baseUrl: widget.connection.baseUrl,
      apiKey: widget.connection.apiKey,
      pathPrefix: widget.connection.gatewayPrefix ?? '',
    );
    _load();
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ok = await _client.healthCheck();
      Map<String, dynamic>? status;
      if (ok) {
        try {
          status = await _client.getStatus();
        } catch (_) {
          status = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _healthOk = ok;
        _statusData = status;
        _loading = false;
        _lastChecked = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toggleAutoRefresh() {
    if (_autoRefresh != null) {
      _autoRefresh!.cancel();
      _autoRefresh = null;
      setState(() {});
      return;
    }
    _autoRefresh = Timer.periodic(const Duration(seconds: 10), (_) => _load());
    setState(() {});
  }

  bool get _autoRefreshing => _autoRefresh != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          if (_autoRefreshing)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: Icon(_autoRefreshing ? Icons.pause : Icons.autorenew),
            onPressed: _loading ? null : _toggleAutoRefresh,
            tooltip: _autoRefreshing ? 'Stop auto-refresh' : 'Auto-refresh',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                'Connection issue',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildOverallCard(),
          const SizedBox(height: 12),
          if (_statusData != null) ..._buildStatusSections(),
          if (_statusData == null && _healthOk) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue),
                    const SizedBox(height: 8),
                    Text(
                      'Gateway is online but /status is not available',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'The /status endpoint may not be implemented on this '
                      'Hermes version.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_lastChecked != null)
            Text(
              'Last checked: ${_formatTime(_lastChecked!)}',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Widget _buildOverallCard() {
    final isOnline = _healthOk;
    final color = isOnline ? Colors.green : Colors.red;
    final icon = isOnline ? Icons.check_circle : Icons.error;
    final label = isOnline ? 'Online' : 'Offline';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, color: color, size: 48),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gateway: $label',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.connection.host}:${widget.connection.port}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStatusSections() {
    final data = _statusData!;
    final widgets = <Widget>[];

    // Parse common status fields with flexible key names
    final sections = <_StatusSection>[
      _StatusSection(
        title: 'Gateway',
        icon: Icons.router,
        items: _extractFields(data, [
          'gateway_status', 'gateway', 'gateway_online',
        ]),
      ),
      _StatusSection(
        title: 'Agent',
        icon: Icons.smart_toy,
        items: _extractFields(data, [
          'agent_status', 'agent', 'agent_online',
        ]),
      ),
      _StatusSection(
        title: 'Model Server',
        icon: Icons.memory,
        items: _extractFields(data, [
          'model_status', 'model_server', 'ollama_status',
          'model', 'models',
        ]),
      ),
      _StatusSection(
        title: 'Cloudflare Tunnel',
        icon: Icons.cloud,
        items: _extractFields(data, [
          'tunnel_status', 'cloudflare_status', 'tunnel',
          'cloudflared',
        ]),
      ),
      _StatusSection(
        title: 'Database',
        icon: Icons.storage,
        items: _extractFields(data, [
          'database_status', 'db_status', 'database', 'postgres',
        ]),
      ),
      _StatusSection(
        title: 'System Resources',
        icon: Icons.computer,
        items: _extractFields(data, [
          'disk_usage', 'memory_usage', 'cpu_usage',
          'disk', 'memory', 'cpu',
        ]),
      ),
    ];

    for (final section in sections) {
      if (section.items.isEmpty) continue;
      widgets.add(_buildSectionCard(section));
      widgets.add(const SizedBox(height: 8));
    }

    // If no known fields matched, show all raw data
    if (widgets.isEmpty) {
      widgets.add(_buildRawDataCard(data));
    }

    return widgets;
  }

  List<_StatusItem> _extractFields(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    final items = <_StatusItem>[];
    for (final key in keys) {
      if (data.containsKey(key)) {
        final value = data[key];
        items.add(_StatusItem(
          label: _prettifyKey(key),
          value: _formatValue(value),
          isOnline: _isOnlineValue(value),
        ));
      }
    }
    return items;
  }

  String _prettifyKey(String key) {
    return key
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'null';
    if (value is bool) return value ? 'Online' : 'Offline';
    if (value is Map || value is List) {
      return value.toString();
    }
    return value.toString();
  }

  bool _isOnlineValue(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      final v = value.toLowerCase();
      return v == 'online' || v == 'ok' || v == 'healthy' || v == 'running';
    }
    return false;
  }

  Widget _buildSectionCard(_StatusSection section) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(section.icon, size: 20, color: const Color(0xFFD4AF37)),
                const SizedBox(width: 8),
                Text(
                  section.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...section.items.map((item) => _buildStatusRow(item)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(_StatusItem item) {
    final color = item.isOnline ? Colors.green : Colors.grey;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            item.isOnline ? Icons.check_circle : Icons.radio_button_unchecked,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(item.label, style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          Text(
            item.value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: item.isOnline ? Colors.green : null,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildRawDataCard(Map<String, dynamic> data) {
    final sortedKeys = data.keys.toList()..sort();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Raw Status Data',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...sortedKeys.map((key) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$key: ',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _formatValue(data[key]),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}

class _StatusSection {
  final String title;
  final IconData icon;
  final List<_StatusItem> items;

  const _StatusSection({
    required this.title,
    required this.icon,
    required this.items,
  });
}

class _StatusItem {
  final String label;
  final String value;
  final bool isOnline;

  const _StatusItem({
    required this.label,
    required this.value,
    required this.isOnline,
  });
}
