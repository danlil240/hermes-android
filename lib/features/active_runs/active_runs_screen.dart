import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/active_runs_manager.dart';
import '../../core/network/connection_manager.dart';
import '../chat/chat_screen.dart';
import '../services/service_log_viewer.dart';

/// Unified Active Runs surface.
///
/// Shows all active background work: chat runs, service runs, pending
/// questions, and reconnecting jobs. Each item displays status, elapsed
/// time, last tool/action, and where it continues.
class ActiveRunsScreen extends StatefulWidget {
  final SavedConnection connection;
  const ActiveRunsScreen({required this.connection, super.key});

  @override
  State<ActiveRunsScreen> createState() => _ActiveRunsScreenState();
}

class _ActiveRunsScreenState extends State<ActiveRunsScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ActiveRunsManager.instance,
      builder: (context, _) {
        final allRuns = ActiveRunsManager.instance.runs;
        final activeRuns = allRuns.where((r) => r.isActive).toList();
        final finishedRuns = allRuns.where((r) => !r.isActive).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Active Runs'),
            actions: [
              if (finishedRuns.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.cleaning_services_outlined),
                  tooltip: 'Clear finished',
                  onPressed: () => ActiveRunsManager.instance.clearFinished(),
                ),
            ],
          ),
          body: allRuns.isEmpty
              ? _buildEmptyState()
              : ListView(
                  children: [
                    if (activeRuns.isNotEmpty) ...[
                      _SectionHeader(
                        label: 'Active',
                        count: activeRuns.length,
                        color: const Color(0xFFD4AF37),
                      ),
                      ...activeRuns.map(
                        (r) => _RunCard(
                          run: r,
                          connection: widget.connection,
                          onTap: () => _navigateToRun(r),
                        ),
                      ),
                    ],
                    if (finishedRuns.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _SectionHeader(
                        label: 'Recently finished',
                        count: finishedRuns.length,
                        color: Colors.grey,
                      ),
                      ...finishedRuns.map(
                        (r) => _RunCard(
                          run: r,
                          connection: widget.connection,
                          onTap: () => _navigateToRun(r),
                        ),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.task_alt, size: 56, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No active runs',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Background chat runs, service executions,\n'
            'and pending questions will appear here.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  void _navigateToRun(ActiveRun run) {
    switch (run.type) {
      case ActiveRunType.chat:
        _navigateToChat(run);
        break;
      case ActiveRunType.service:
        _navigateToService(run);
        break;
      case ActiveRunType.question:
        _navigateToChat(run);
        break;
      case ActiveRunType.reconnecting:
        // No deep-link target for reconnecting state
        break;
    }
  }

  void _navigateToChat(ActiveRun run) {
    final session = Session(
      id: run.sessionId,
      title: run.sessionTitle ?? run.title,
      model: 'hermes-agent',
      source: 'mobile',
      messageCount: 0,
      isActive: run.isActive,
      preview: '',
      startedAt: run.startedAt.millisecondsSinceEpoch.toDouble() / 1000,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(connection: widget.connection, session: session),
      ),
    );
  }

  void _navigateToService(ActiveRun run) {
    final serviceRun = ServiceRun(
      runId: run.id.replaceFirst('service:', ''),
      serviceId: run.title,
      status: _mapRunStatus(run.status),
      riskLevel: ServiceRiskLevel.unknown,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceLogViewer(
          client: ApiClient(
            baseUrl: widget.connection.baseUrl,
            apiKey: widget.connection.apiKey,
            pathPrefix: widget.connection.gatewayPrefix ?? '',
            cfAccessClientId: widget.connection.cfAccessClientId,
            cfAccessClientSecret: widget.connection.cfAccessClientSecret,
          ),
          run: serviceRun,
        ),
      ),
    );
  }

  ServiceRunStatus _mapRunStatus(ActiveRunStatus status) {
    switch (status) {
      case ActiveRunStatus.running:
        return ServiceRunStatus.running;
      case ActiveRunStatus.pending:
        return ServiceRunStatus.pending;
      case ActiveRunStatus.awaitingConfirmation:
        return ServiceRunStatus.awaitingConfirmation;
      case ActiveRunStatus.completed:
        return ServiceRunStatus.completed;
      case ActiveRunStatus.failed:
        return ServiceRunStatus.failed;
      case ActiveRunStatus.cancelled:
        return ServiceRunStatus.cancelled;
      case ActiveRunStatus.cancellationRequested:
        return ServiceRunStatus.cancellationRequested;
      case ActiveRunStatus.reconnecting:
        return ServiceRunStatus.unknown;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  final ActiveRun run;
  final SavedConnection connection;
  final VoidCallback onTap;

  const _RunCard({
    required this.run,
    required this.connection,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isActive = run.isActive;

    final statusColor = _statusColor(run.status, isDark);
    final typeIcon = _typeIcon(run.type);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: type icon with status indicator
              Stack(
                children: [
                  Icon(typeIcon, size: 28, color: statusColor),
                  if (isActive)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? Colors.black : Colors.white,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // Center: title, status, last action
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            run.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isActive)
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: statusColor,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            run.statusLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          run.elapsedLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    if (run.lastAction != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.subdirectory_arrow_right,
                            size: 12,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              run.lastAction!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.dns, size: 11, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Text(
                          run.connectionLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[400],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.open_in_new,
                          size: 11,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _targetLabel(run.type),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Right: chevron
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(ActiveRunStatus status, bool isDark) {
    switch (status) {
      case ActiveRunStatus.running:
        return Colors.blue;
      case ActiveRunStatus.pending:
        return Colors.grey;
      case ActiveRunStatus.reconnecting:
        return Colors.orange;
      case ActiveRunStatus.awaitingConfirmation:
        return Colors.amber;
      case ActiveRunStatus.cancellationRequested:
        return Colors.deepOrange;
      case ActiveRunStatus.completed:
        return Colors.green;
      case ActiveRunStatus.failed:
        return Colors.red;
      case ActiveRunStatus.cancelled:
        return Colors.orange;
    }
  }

  IconData _typeIcon(ActiveRunType type) {
    switch (type) {
      case ActiveRunType.chat:
        return Icons.chat;
      case ActiveRunType.service:
        return Icons.build;
      case ActiveRunType.question:
        return Icons.help_outline;
      case ActiveRunType.reconnecting:
        return Icons.sync;
    }
  }

  String _targetLabel(ActiveRunType type) {
    switch (type) {
      case ActiveRunType.service:
        return 'Service log';
      case ActiveRunType.question:
        return 'Answer in chat';
      case ActiveRunType.reconnecting:
        return 'Connection';
      case ActiveRunType.chat:
        return 'Chat';
    }
  }
}
