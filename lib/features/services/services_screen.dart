// Services screen — list and run predefined Hermes services with
// risk-based confirmation flows.
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/active_runs_manager.dart';
import '../../core/network/connection_manager.dart';
import '../../shared/errors/error_messages.dart';
import '../../shared/errors/hermes_error.dart';
import '../../shared/widgets/hermes_error_state.dart';
import 'service_log_viewer.dart';

class ServicesScreen extends StatefulWidget {
  final SavedConnection connection;
  const ServicesScreen({required this.connection, super.key});

  static final Map<String, List<Map<String, dynamic>>> cachedServices = {};

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen>
    with SingleTickerProviderStateMixin {
  late final ApiClient _client;
  late final TabController _tabController;
  List<ServiceDefinition> _services = [];
  final Map<String, ServiceRun> _activeRuns = {};
  final Map<String, ServiceRunStreamController> _streamControllers = {};
  final Map<String, List<String>> _streamedLogs = {};
  final Map<String, List<ServiceRunStep>> _streamedSteps = {};
  bool _loading = true;
  bool _refreshing = false;
  dynamic _error;

  // Service run history (audit log)
  List<ServiceRun> _history = [];
  bool _historyLoading = false;
  String? _historyError;
  int _historyOffset = 0;
  bool _hasMoreHistory = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _client = ApiClient(
      baseUrl: widget.connection.baseUrl,
      apiKey: widget.connection.apiKey,
      pathPrefix: widget.connection.gatewayPrefix ?? '',
      cfAccessClientId: widget.connection.cfAccessClientId,
      cfAccessClientSecret: widget.connection.cfAccessClientSecret,
    );
    _load();
  }

  @override
  void dispose() {
    for (final ctrl in _streamControllers.values) {
      ctrl.cancel();
    }
    _tabController.dispose();
    _client.close();
    super.dispose();
  }

  Future<void> _load({bool silentRefresh = false}) async {
    final cacheKey = widget.connection.id;
    final hasCache = ServicesScreen.cachedServices.containsKey(cacheKey);

    if (silentRefresh && hasCache) {
      setState(() => _refreshing = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    if (hasCache) {
      _services = ServicesScreen.cachedServices[cacheKey]!
          .map((s) => ServiceDefinition.fromJson(s))
          .toList();
      if (!silentRefresh) {
        setState(() => _loading = false);
      }
    }

    try {
      final raw = await _client.getServices();
      ServicesScreen.cachedServices[cacheKey] = raw;
      if (!mounted) return;
      setState(() {
        _services = raw.map((s) => ServiceDefinition.fromJson(s)).toList();
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

  Future<void> _loadHistory({bool reset = true}) async {
    if (_historyLoading) return;
    setState(() {
      _historyLoading = true;
      if (reset) {
        _historyError = null;
        _historyOffset = 0;
        _hasMoreHistory = true;
      }
    });
    try {
      final offset = reset ? 0 : _historyOffset;
      final runs = await _client.getServiceRuns(limit: 50, offset: offset);
      if (!mounted) return;
      setState(() {
        if (reset) {
          _history = runs;
        } else {
          _history.addAll(runs);
        }
        _historyOffset = offset + runs.length;
        _hasMoreHistory = runs.length >= 50;
        _historyLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyError = ErrorMessages.format(e);
        _historyLoading = false;
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

  /// Find the last successful and failed runs for a service from history.
  ({ServiceRun? lastSuccess, ServiceRun? lastFailure})
      _lastExecutionsFor(String serviceId) {
    ServiceRun? lastSuccess;
    ServiceRun? lastFailure;
    for (final run in _history) {
      if (run.serviceId != serviceId) continue;
      if (run.isCompleted &&
          (lastSuccess == null ||
              (run.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                  .isAfter(lastSuccess.startedAt ??
                      DateTime.fromMillisecondsSinceEpoch(0)))) {
        lastSuccess = run;
      }
      if (run.isFailed &&
          (lastFailure == null ||
              (run.startedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                  .isAfter(lastFailure.startedAt ??
                      DateTime.fromMillisecondsSinceEpoch(0)))) {
        lastFailure = run;
      }
    }
    return (lastSuccess: lastSuccess, lastFailure: lastFailure);
  }

  void _showServiceDetail(ServiceDefinition service) {
    final riskColor = _riskColor(service.riskLevel);
    final riskLabel = _riskLabel(service.riskLevel);
    final lastRuns = _lastExecutionsFor(service.id);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          bool typedValid = false;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Icon(_riskIcon(service.riskLevel),
                            color: riskColor, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            service.name,
                            style: Theme.of(ctx).textTheme.headlineSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (service.description.isNotEmpty) ...[
                      Text(service.description,
                          style: Theme.of(ctx).textTheme.bodyMedium),
                      const SizedBox(height: 16),
                    ],
                    _buildDetailSection(ctx, 'Risk Level', riskLabel,
                        color: riskColor),
                    if (service.riskExplanation != null &&
                        service.riskExplanation!.isNotEmpty)
                      _buildDetailSection(
                          ctx, 'Risk Explanation', service.riskExplanation!),
                    if (service.systemsAffected.isNotEmpty)
                      _buildDetailSection(ctx, 'Systems Affected',
                          service.systemsAffected.join(', ')),
                    if (service.expectedDuration != null &&
                        service.expectedDuration!.isNotEmpty)
                      _buildDetailSection(
                          ctx, 'Expected Duration', service.expectedDuration!),
                    if (service.prerequisites != null &&
                        service.prerequisites!.isNotEmpty)
                      _buildDetailSection(
                          ctx, 'Prerequisites', service.prerequisites!),
                    if (service.recoveryGuidance != null &&
                        service.recoveryGuidance!.isNotEmpty)
                      _buildDetailSection(
                          ctx, 'Recovery Guidance', service.recoveryGuidance!),
                    if (service.timeoutSeconds != null)
                      _buildDetailSection(
                          ctx, 'Timeout', '${service.timeoutSeconds}s'),
                    _buildDetailSection(ctx, 'Service ID', service.id,
                        mono: true),
                    if (service.verificationServiceId != null &&
                        service.verificationServiceId!.isNotEmpty)
                      _buildDetailSection(ctx, 'Verification Service',
                          service.verificationServiceId!,
                          mono: true),
                    const Divider(height: 32),
                    Text('Last Executions',
                        style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                              color: const Color(0xFFD4AF37),
                              fontWeight: FontWeight.bold,
                            )),
                    const SizedBox(height: 8),
                    _buildLastExecutionRow(ctx, 'Last successful',
                        lastRuns.lastSuccess),
                    _buildLastExecutionRow(ctx, 'Last failed',
                        lastRuns.lastFailure),
                    const SizedBox(height: 24),
                    if (service.needsTypedConfirmation) ...[
                      Text('Type "${service.name}" to confirm:',
                          style: Theme.of(ctx).textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      _TypedConfirmationField(
                        expectedText: service.name,
                        onValidChanged: (valid) =>
                            setSheetState(() => typedValid = valid),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: (service.needsTypedConfirmation &&
                                    !typedValid)
                                ? null
                                : () {
                                    Navigator.pop(ctx);
                                    _runService(service);
                                  },
                            style: FilledButton.styleFrom(
                                backgroundColor: riskColor),
                            child: Text(service.needsTypedConfirmation
                                ? 'Confirm & Run'
                                : 'Run ${service.name}'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailSection(
    BuildContext ctx,
    String label,
    String value, {
    Color? color,
    bool mono = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastExecutionRow(
    BuildContext ctx,
    String label,
    ServiceRun? run,
  ) {
    final color = run?.isCompleted == true
        ? Colors.green
        : run?.isFailed == true
            ? Colors.red
            : Colors.grey;
    final icon = run?.isCompleted == true
        ? Icons.check_circle
        : run?.isFailed == true
            ? Icons.error
            : Icons.history;

    String timeStr;
    if (run?.startedAt != null) {
      final diff = DateTime.now().difference(run!.startedAt!);
      if (diff.inMinutes < 1) {
        timeStr = 'just now';
      } else if (diff.inMinutes < 60) {
        timeStr = '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        timeStr = '${diff.inHours}h ago';
      } else {
        timeStr = '${diff.inDays}d ago';
      }
    } else {
      timeStr = '—';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          const Spacer(),
          Text(timeStr, style: TextStyle(fontSize: 12, color: color)),
          if (run?.duration != null) ...[
            const SizedBox(width: 8),
            Text('${run!.duration!.inSeconds}s',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
        ],
      ),
    );
  }

  Future<void> _runService(ServiceDefinition service) async {
    if (service.needsConfirmation && !service.needsTypedConfirmation) {
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

      ActiveRunsManager.instance.updateServiceRun(
        runId: run.runId,
        serviceId: run.serviceId,
        connectionId: widget.connection.id,
        connectionLabel: widget.connection.label,
        sessionId: run.sessionId,
        status: run.isRunning ? ActiveRunStatus.running : (run.isAwaitingConfirmation ? ActiveRunStatus.awaitingConfirmation : ActiveRunStatus.completed),
        lastAction: 'Service started',
      );

      if (run.isAwaitingConfirmation) {
        _showAwaitingConfirmation(run);
      } else if (run.isRunning) {
        _startLogStream(run);
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

  void _startLogStream(ServiceRun run) {
    _streamedLogs[run.runId] = [];
    _streamedSteps[run.runId] = [];

    final controller = _client.streamServiceRunLogs(
      run.runId,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          if (progress.isLogEvent) {
            _streamedLogs[run.runId]?.add(progress.logLine!);
          }
          if (progress.isStepEvent && progress.step != null) {
            final steps = _streamedSteps[run.runId] ?? [];
            final idx = steps.indexWhere((s) => s.id == progress.step!.id);
            if (idx >= 0) {
              steps[idx] = progress.step!;
            } else {
              steps.add(progress.step!);
            }
            _streamedSteps[run.runId] = steps;
          }
          if (progress.isStatusEvent && progress.status != null) {
            _activeRuns[run.runId] = ServiceRun(
              runId: run.runId,
              serviceId: run.serviceId,
              sessionId: run.sessionId,
              status: progress.status!,
              riskLevel: run.riskLevel,
              confirmationRequired: run.confirmationRequired,
              resultSummary: progress.resultSummary ?? run.resultSummary,
              startedAt: run.startedAt,
              completedAt: progress.status == ServiceRunStatus.completed ||
                      progress.status == ServiceRunStatus.failed ||
                      progress.status == ServiceRunStatus.cancelled
                  ? DateTime.now()
                  : null,
              confirmedAt: run.confirmedAt,
              createdAt: run.createdAt,
            );
            // Report status change to ActiveRunsManager
            final lastStep = (_streamedSteps[run.runId] ?? []).lastOrNull;
            ActiveRunsManager.instance.updateServiceRun(
              runId: run.runId,
              serviceId: run.serviceId,
              connectionId: widget.connection.id,
              connectionLabel: widget.connection.label,
              sessionId: run.sessionId,
              status: _mapServiceRunStatus(progress.status!),
              lastAction: lastStep != null
                  ? '${lastStep.label}: ${lastStep.status}'
                  : null,
            );
          }
        });
      },
      onDone: () {
        if (!mounted) return;
        final updated = _activeRuns[run.runId];
        if (updated != null && updated.isDone) {
          _streamControllers.remove(run.runId)?.cancel();
          _showRunResult(updated);
        }
      },
      onError: (error) {
        if (!mounted) return;
        _streamControllers.remove(run.runId)?.cancel();
        // Fall back to polling if SSE fails
        _pollRunStatus(run.runId);
      },
    );
    _streamControllers[run.runId] = controller;
  }

  ActiveRunStatus _mapServiceRunStatus(ServiceRunStatus status) {
    switch (status) {
      case ServiceRunStatus.running:
        return ActiveRunStatus.running;
      case ServiceRunStatus.pending:
        return ActiveRunStatus.pending;
      case ServiceRunStatus.awaitingConfirmation:
        return ActiveRunStatus.awaitingConfirmation;
      case ServiceRunStatus.completed:
        return ActiveRunStatus.completed;
      case ServiceRunStatus.failed:
        return ActiveRunStatus.failed;
      case ServiceRunStatus.cancellationRequested:
        return ActiveRunStatus.cancellationRequested;
      case ServiceRunStatus.cancelled:
        return ActiveRunStatus.cancelled;
      case ServiceRunStatus.unknown:
        return ActiveRunStatus.pending;
    }
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

  Future<void> _cancelRun(ServiceRun run) async {
    // Optimistic update: mark as cancellation requested immediately
    setState(() {
      _activeRuns[run.runId] = ServiceRun(
        runId: run.runId,
        serviceId: run.serviceId,
        sessionId: run.sessionId,
        status: ServiceRunStatus.cancellationRequested,
        riskLevel: run.riskLevel,
        confirmationRequired: run.confirmationRequired,
        resultSummary: run.resultSummary,
        startedAt: run.startedAt,
        confirmedAt: run.confirmedAt,
        createdAt: run.createdAt,
      );
    });

    ActiveRunsManager.instance.updateServiceRun(
      runId: run.runId,
      serviceId: run.serviceId,
      connectionId: widget.connection.id,
      connectionLabel: widget.connection.label,
      sessionId: run.sessionId,
      status: ActiveRunStatus.cancellationRequested,
      lastAction: 'Cancellation requested',
    );

    try {
      await _client.cancelServiceRun(run.runId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cancel request failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openLogViewer(ServiceRun run) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceLogViewer(
          client: _client,
          run: run,
        ),
      ),
    );
  }

  void _showRunResult(ServiceRun run) {
    if (!mounted) return;
    final color = run.isCompleted
        ? Colors.green
        : run.isCancelled
            ? Colors.orange
            : Colors.red;
    final icon = run.isCompleted
        ? Icons.check_circle
        : run.isCancelled
            ? Icons.cancel
            : Icons.error;
    final title = run.isCompleted
        ? 'Service Completed'
        : run.isCancelled
            ? 'Service Cancelled'
            : 'Service Failed';

    final serviceDef = _services.where((s) => s.id == run.serviceId).firstOrNull;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(icon, color: color, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(ctx).textTheme.headlineSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
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
                Text('Result:',
                    style: Theme.of(ctx).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(run.resultSummary!),
                ),
              ],
              if (run.logsTail != null && run.logsTail!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Logs (tail):',
                    style: Theme.of(ctx).textTheme.bodyMedium),
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
              if (!run.isCompleted &&
                  serviceDef?.recoveryGuidance != null &&
                  serviceDef!.recoveryGuidance!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.healing, size: 16,
                              color: Colors.orange),
                          const SizedBox(width: 8),
                          Text('Recovery Guidance',
                              style: Theme.of(ctx)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                  )),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(serviceDef.recoveryGuidance!),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.terminal, size: 18),
                    label: const Text('View full log'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openLogViewer(run);
                    },
                  ),
                  if (serviceDef?.verificationServiceId != null &&
                      serviceDef!.verificationServiceId!.isNotEmpty)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.verified, size: 18),
                      label: const Text('Run verification'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _runVerification(serviceDef);
                      },
                    ),
                  if (!run.isCompleted)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        if (serviceDef != null) _runService(serviceDef);
                      },
                    ),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Return to Services'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _runVerification(ServiceDefinition service) {
    final verId = service.verificationServiceId;
    if (verId == null || verId.isEmpty) return;
    final verDef = _services.where((s) => s.id == verId).firstOrNull;
    if (verDef != null) {
      _showServiceDetail(verDef);
    } else {
      _runService(ServiceDefinition(
        id: verId,
        name: 'Verification',
        category: 'verification',
      ));
    }
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
            onPressed: (_loading || _refreshing)
                ? null
                : () => _load(silentRefresh: true),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Services', icon: Icon(Icons.build_outlined)),
            Tab(text: 'History', icon: Icon(Icons.history)),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_refreshing) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBody(),
                _buildHistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _services.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return HermesErrorState(
        error: _error,
        connection: widget.connection,
        onRetry: _load,
        source: HermesErrorSource.dashboard,
        title: 'Failed to load services',
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
              steps: _streamedSteps[r.runId] ?? [],
              logCount: (_streamedLogs[r.runId] ?? []).length,
              onTap: () => _openLogViewer(r),
              onCancel: () => _cancelRun(r),
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

  Widget _buildHistoryTab() {
    if (_history.isEmpty && _historyLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_history.isEmpty && _historyError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                'Failed to load history',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _historyError!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _loadHistory(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text(
              'No service run history',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Past service runs will appear here once available.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _loadHistory(),
                child: const Text('Load History'),
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadHistory(reset: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollEndNotification &&
              notification.metrics.pixels >=
                  notification.metrics.maxScrollExtent - 100 &&
              _hasMoreHistory &&
              !_historyLoading) {
            _loadHistory(reset: false);
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _history.length + 1,
          itemBuilder: (context, index) {
            if (index == _history.length) {
              if (_historyLoading) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (!_hasMoreHistory) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'No more history',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            }
            return _buildHistoryCard(_history[index]);
          },
        ),
      ),
    );
  }

  Widget _buildHistoryCard(ServiceRun run) {
    final statusColor = run.isCompleted
        ? Colors.green
        : run.isFailed
            ? Colors.red
            : run.isCancelled
                ? Colors.orange
                : Colors.blue;
    final statusIcon = run.isCompleted
        ? Icons.check_circle
        : run.isFailed
            ? Icons.error
            : run.isCancelled
                ? Icons.cancel
                : Icons.sync;

    String formatTime(DateTime? dt) {
      if (dt == null) return '—';
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(statusIcon, color: statusColor),
        title: Text(run.serviceId),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    run.status.name,
                    style: TextStyle(
                      fontSize: 11,
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatTime(run.startedAt ?? run.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            if (run.resultSummary != null &&
                run.resultSummary!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                run.resultSummary!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
        isThreeLine: run.resultSummary != null &&
            run.resultSummary!.isNotEmpty,
        trailing: run.duration != null
            ? Text(
                '${run.duration!.inSeconds}s',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              )
            : null,
        onTap: () => _showRunResult(run),
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
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: _loading ? null : () => _showServiceDetail(service),
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

/// Card showing an active service run with elapsed timer, current phase,
/// progress steps, log count, and cancel button.
class _ActiveRunCard extends StatefulWidget {
  final ServiceRun run;
  final Color riskColor;
  final List<ServiceRunStep> steps;
  final int logCount;
  final VoidCallback onTap;
  final VoidCallback onCancel;

  const _ActiveRunCard({
    required this.run,
    required this.riskColor,
    required this.steps,
    required this.logCount,
    required this.onTap,
    required this.onCancel,
  });

  @override
  State<_ActiveRunCard> createState() => _ActiveRunCardState();
}

class _ActiveRunCardState extends State<_ActiveRunCard> {
  late Timer _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateElapsed();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateElapsed();
    });
  }

  @override
  void didUpdateWidget(_ActiveRunCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.run.startedAt != widget.run.startedAt) {
      _updateElapsed();
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _updateElapsed() {
    final start = widget.run.startedAt ?? widget.run.createdAt;
    if (start != null) {
      setState(() {
        _elapsed = DateTime.now().difference(start);
      });
    }
  }

  String get _elapsedLabel {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes.remainder(60);
    final s = _elapsed.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String? get _currentPhase {
    final runningStep = widget.steps.where((s) => s.isRunning).lastOrNull;
    if (runningStep != null) return runningStep.label;
    final lastStep = widget.steps.lastOrNull;
    if (lastStep != null && lastStep.isPending) return lastStep.label;
    return null;
  }

  bool get _isCancellationRequested =>
      widget.run.isCancellationRequested;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: widget.riskColor.withValues(alpha: 0.08),
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_isCancellationRequested)
                    const Icon(Icons.cancel_outlined, size: 24,
                        color: Colors.deepOrange)
                  else
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      widget.run.serviceId,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  // Elapsed timer
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _elapsedLabel,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
              if (_isCancellationRequested) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.deepOrange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_top,
                          size: 16, color: Colors.deepOrange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Cancellation requested — may take time',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.deepOrange[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (_currentPhase != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.bolt, size: 14, color: widget.riskColor),
                    const SizedBox(width: 4),
                    Text(
                      'Phase: $_currentPhase',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.riskColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
              if (widget.steps.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...widget.steps
                    .map((step) => _buildStepIndicator(context, step)),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.terminal, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.logCount} log lines',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const Spacer(),
                  if (!_isCancellationRequested)
                    TextButton.icon(
                      icon: const Icon(Icons.cancel, size: 16),
                      label: const Text('Cancel',
                          style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red[700],
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: const Size(0, 28),
                      ),
                      onPressed: widget.onCancel,
                    )
                  else
                    Text(
                      'Tap to view logs',
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.riskColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(BuildContext context, ServiceRunStep step) {
    IconData icon;
    Color color;
    if (step.isCompleted) {
      icon = Icons.check_circle;
      color = Colors.green;
    } else if (step.isRunning) {
      icon = Icons.sync;
      color = Colors.blue;
    } else if (step.isFailed) {
      icon = Icons.error;
      color = Colors.red;
    } else {
      icon = Icons.radio_button_unchecked;
      color = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          if (step.isRunning)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Text(step.label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
