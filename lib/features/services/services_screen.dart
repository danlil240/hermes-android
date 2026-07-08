// Services screen — list and run predefined Hermes services with
// risk-based confirmation flows.
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/models/service.dart';
import '../../core/network/connection_manager.dart';

class ServicesScreen extends StatefulWidget {
  final SavedConnection connection;
  const ServicesScreen({required this.connection, super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  late final ApiClient _client;
  List<ServiceDefinition> _services = [];
  Map<String, ServiceRun> _activeRuns = {};
  bool _loading = true;
  String? _error;

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
    _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _client.getServices();
      if (!mounted) return;
      setState(() {
        _services = raw.map((s) => ServiceDefinition.fromJson(s)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Group services by category.
  Map<String, List<ServiceDefinition>> get _grouped {
    final map = <String, List<ServiceDefinition>>{};
    for (final s in _services) {
      final cat = s.category.isEmpty ? 'General' : s.category;
      map.putIfAbsent(cat, () => []).add(s);
    }
    return map;
  }

  Future<void> _runService(ServiceDefinition service) async {
    if (service.needsConfirmation) {
      final confirmed = await _showConfirmationDialog(service);
      if (confirmed != true || !mounted) return;
    }

    setState(() => _loading = true);
    try {
      final result = await _client.runService(service.id);
      if (!mounted) return;
      final run = ServiceRun.fromJson(result);
      setState(() {
        _activeRuns[run.runId] = run;
        _loading = false;
      });

      if (run.isAwaitingConfirmation) {
        _showAwaitingConfirmation(run);
      } else if (run.isRunning) {
        _pollRunStatus(run.runId);
      } else if (run.isCompleted || run.isFailed) {
        _showRunResult(run);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to run service: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool?> _showConfirmationDialog(ServiceDefinition service) {
    final riskColor = _riskColor(service.riskLevel);
    final riskLabel = _riskLabel(service.riskLevel);
    bool typedValid = false;

    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber, color: riskColor),
              const SizedBox(width: 8),
              Expanded(child: Text(service.name)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (service.description.isNotEmpty) ...[
                Text(service.description),
                const SizedBox(height: 12),
              ],
              _buildInfoRow('Risk level', riskLabel, riskColor),
              _buildInfoRow('Service ID', service.id, null),
              _buildInfoRow('Category', service.category, null),
              if (service.timeoutSeconds != null)
                _buildInfoRow(
                  'Timeout', '${service.timeoutSeconds}s', null,
                ),
              const SizedBox(height: 16),
              if (service.needsTypedConfirmation) ...[
                Text(
                  'Type "${service.name}" to confirm:',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                _TypedConfirmationField(
                  expectedText: service.name,
                  onValidChanged: (valid) =>
                      setDialogState(() => typedValid = valid),
                ),
              ] else ...[
                Text(
                  'Are you sure you want to run this service?',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: (service.needsTypedConfirmation && !typedValid)
                  ? null
                  : () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: riskColor),
              child: Text(
                service.needsTypedConfirmation ? 'Confirm' : 'Run',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color? color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  void _showAwaitingConfirmation(ServiceRun run) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmation Required'),
        content: Text(
          'Service "${run.serviceId}" is awaiting confirmation from the '
          'backend. You will be notified when it completes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _pollRunStatus(String runId) {
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final result = await _client.getServiceRun(runId);
        if (!mounted) {
          timer.cancel();
          return;
        }
        final run = ServiceRun.fromJson(result);
        setState(() => _activeRuns[runId] = run);
        if (run.isDone) {
          timer.cancel();
          _showRunResult(run);
        }
      } catch (e) {
        timer.cancel();
      }
    });
  }

  void _showRunResult(ServiceRun run) {
    if (!mounted) return;
    final color = run.isCompleted ? Colors.green : Colors.red;
    final icon = run.isCompleted ? Icons.check_circle : Icons.error;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                run.isCompleted ? 'Service Completed' : 'Service Failed',
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Service', run.serviceId, null),
            _buildInfoRow('Run ID', run.runId, null),
            if (run.duration != null)
              _buildInfoRow(
                'Duration',
                '${run.duration!.inSeconds}s',
                null,
              ),
            if (run.resultSummary != null) ...[
              const SizedBox(height: 12),
              Text(
                'Result:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(run.resultSummary!),
              ),
            ],
            if (run.logsTail != null && run.logsTail!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Logs (tail):',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    run.logsTail!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.green,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Color _riskColor(ServiceRiskLevel risk) {
    switch (risk) {
      case ServiceRiskLevel.low:
        return Colors.green;
      case ServiceRiskLevel.medium:
        return Colors.orange;
      case ServiceRiskLevel.high:
        return Colors.deepOrange;
      case ServiceRiskLevel.critical:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _riskLabel(ServiceRiskLevel risk) {
    switch (risk) {
      case ServiceRiskLevel.low:
        return 'Low';
      case ServiceRiskLevel.medium:
        return 'Medium';
      case ServiceRiskLevel.high:
        return 'High';
      case ServiceRiskLevel.critical:
        return 'Critical';
      default:
        return 'Unknown';
    }
  }

  IconData _riskIcon(ServiceRiskLevel risk) {
    switch (risk) {
      case ServiceRiskLevel.low:
        return Icons.info_outline;
      case ServiceRiskLevel.medium:
        return Icons.warning_amber;
      case ServiceRiskLevel.high:
        return Icons.warning;
      case ServiceRiskLevel.critical:
        return Icons.dangerous;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Services (${_services.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _services.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

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
                'Failed to load services',
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

    if (_services.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.build_outlined, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'No services available',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'The Hermes backend may not have the Services Runner enabled.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Show active runs at the top
    final activeRunWidgets = _activeRuns.values
        .where((r) => !r.isDone)
        .map((r) => _ActiveRunCard(
              run: r,
              riskColor: _riskColor(r.riskLevel),
            ))
        .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (activeRunWidgets.isNotEmpty) ...[
            ...activeRunWidgets,
            const Divider(height: 32),
          ],
          ..._grouped.entries.map((entry) {
            return _buildCategorySection(entry.key, entry.value);
          }),
        ],
      ),
    );
  }

  Widget _buildCategorySection(
    String category,
    List<ServiceDefinition> services,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(
            category,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFFD4AF37),
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        ...services.map((s) => _buildServiceCard(s)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildServiceCard(ServiceDefinition service) {
    final riskColor = _riskColor(service.riskLevel);
    final riskLabel = _riskLabel(service.riskLevel);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Icon(_riskIcon(service.riskLevel), color: riskColor),
        title: Text(service.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (service.description.isNotEmpty)
              Text(
                service.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: riskColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    riskLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: riskColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (service.requiresConfirmation) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.lock_outline, size: 12),
                  const SizedBox(width: 2),
                  Text(
                    'Confirm',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        isThreeLine: service.description.isNotEmpty,
        trailing: const Icon(Icons.play_arrow, size: 20),
        onTap: _loading ? null : () => _runService(service),
      ),
    );
  }
}

/// A text field that requires the user to type the exact service name
/// before the confirm button is enabled.
class _TypedConfirmationField extends StatefulWidget {
  final String expectedText;
  final ValueChanged<bool> onValidChanged;

  const _TypedConfirmationField({
    required this.expectedText,
    required this.onValidChanged,
  });

  @override
  State<_TypedConfirmationField> createState() =>
      _TypedConfirmationFieldState();
}

class _TypedConfirmationFieldState extends State<_TypedConfirmationField> {
  final _controller = TextEditingController();
  bool _valid = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_check);
  }

  @override
  void dispose() {
    _controller.removeListener(_check);
    _controller.dispose();
    super.dispose();
  }

  void _check() {
    final valid = _controller.text.trim() == widget.expectedText;
    if (valid != _valid) {
      setState(() => _valid = valid);
      widget.onValidChanged(valid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: widget.expectedText,
        errorText: _controller.text.isNotEmpty && !_valid
            ? 'Does not match'
            : null,
      ),
      autocorrect: false,
    );
  }
}

/// Card showing an active service run with a progress indicator.
class _ActiveRunCard extends StatelessWidget {
  final ServiceRun run;
  final Color riskColor;

  const _ActiveRunCard({required this.run, required this.riskColor});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: riskColor.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    run.serviceId,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    'Status: ${run.status.name}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
