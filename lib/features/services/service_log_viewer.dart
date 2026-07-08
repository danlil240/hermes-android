import 'package:flutter/material.dart';
import '../../core/network/connection_manager.dart';

/// Full-screen log viewer that streams real-time logs and progress steps
/// for a service run via SSE.
///
/// Shows:
/// - A progress stepper for multi-phase operations (pulling, rebuilding, etc.)
/// - A scrolling terminal-style log output
/// - Final status (completed / failed / cancelled) with result summary
class ServiceLogViewer extends StatefulWidget {
  final ApiClient client;
  final ServiceRun run;

  const ServiceLogViewer({
    required this.client,
    required this.run,
    super.key,
  });

  @override
  State<ServiceLogViewer> createState() => _ServiceLogViewerState();
}

class _ServiceLogViewerState extends State<ServiceLogViewer> {
  final List<String> _logLines = [];
  final List<ServiceRunStep> _steps = [];
  final ScrollController _scrollController = ScrollController();
  ServiceRunStreamController? _streamController;
  ServiceRunStatus _currentStatus = ServiceRunStatus.unknown;
  String? _resultSummary;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.run.status;
    _resultSummary = widget.run.resultSummary;
    if (widget.run.logsTail != null && widget.run.logsTail!.isNotEmpty) {
      _logLines.addAll(widget.run.logsTail!.split('\n'));
    }
    _startStreaming();
  }

  void _startStreaming() {
    _streamController = widget.client.streamServiceRunLogs(
      widget.run.runId,
      onProgress: _handleProgress,
      onDone: _handleDone,
      onError: _handleError,
    );
  }

  void _handleProgress(ServiceRunProgress progress) {
    if (!mounted) return;
    setState(() {
      if (progress.isLogEvent) {
        _logLines.add(progress.logLine!);
      }
      if (progress.isStepEvent && progress.step != null) {
        _upsertStep(progress.step!);
      }
      if (progress.isStatusEvent && progress.status != null) {
        _currentStatus = progress.status!;
      }
      if (progress.resultSummary != null) {
        _resultSummary = progress.resultSummary;
      }
      if (progress.error != null) {
        _error = progress.error;
      }
    });
    _scrollToBottom();
  }

  void _upsertStep(ServiceRunStep step) {
    final idx = _steps.indexWhere((s) => s.id == step.id);
    if (idx >= 0) {
      _steps[idx] = step;
    } else {
      _steps.add(step);
    }
  }

  void _handleDone() {
    if (!mounted) return;
    setState(() => _done = true);
  }

  void _handleError(String error) {
    if (!mounted) return;
    setState(() {
      _error = error;
      _done = true;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _streamController?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTerminal = _done ||
        _currentStatus == ServiceRunStatus.completed ||
        _currentStatus == ServiceRunStatus.failed ||
        _currentStatus == ServiceRunStatus.cancelled;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.run.serviceId),
        actions: [
          if (!isTerminal)
            TextButton(
              onPressed: _showCancelConfirm,
              child: const Text('Cancel'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Progress steps
          if (_steps.isNotEmpty) _buildStepProgress(),
          // Status bar
          _buildStatusBar(isTerminal),
          // Log output
          Expanded(child: _buildLogOutput()),
          // Result summary
          if (_resultSummary != null && isTerminal) _buildResultSummary(),
          if (_error != null) _buildErrorBanner(),
        ],
      ),
    );
  }

  Widget _buildStepProgress() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Progress',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: const Color(0xFFD4AF37),
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          ..._steps.map((step) => _buildStepRow(step)),
        ],
      ),
    );
  }

  Widget _buildStepRow(ServiceRunStep step) {
    IconData icon;
    Color color;
    switch (step.status) {
      case 'completed':
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case 'running':
        icon = Icons.sync;
        color = Colors.blue;
        break;
      case 'failed':
        icon = Icons.error;
        color = Colors.red;
        break;
      default:
        icon = Icons.radio_button_unchecked;
        color = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (step.isRunning)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            )
          else
            Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.label, style: const TextStyle(fontSize: 14)),
                if (step.detail != null && step.detail!.isNotEmpty)
                  Text(
                    step.detail!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(bool isTerminal) {
    Color statusColor;
    String statusLabel;
    switch (_currentStatus) {
      case ServiceRunStatus.running:
        statusColor = Colors.blue;
        statusLabel = 'Running';
        break;
      case ServiceRunStatus.completed:
        statusColor = Colors.green;
        statusLabel = 'Completed';
        break;
      case ServiceRunStatus.failed:
        statusColor = Colors.red;
        statusLabel = 'Failed';
        break;
      case ServiceRunStatus.cancelled:
        statusColor = Colors.orange;
        statusLabel = 'Cancelled';
        break;
      case ServiceRunStatus.awaitingConfirmation:
        statusColor = Colors.amber;
        statusLabel = 'Awaiting Confirmation';
        break;
      case ServiceRunStatus.pending:
        statusColor = Colors.grey;
        statusLabel = 'Pending';
        break;
      default:
        statusColor = Colors.grey;
        statusLabel = 'Unknown';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(color: statusColor.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          if (!isTerminal)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              _currentStatus == ServiceRunStatus.completed
                  ? Icons.check_circle
                  : Icons.error,
              size: 16,
              color: statusColor,
            ),
          const SizedBox(width: 12),
          Text(
            statusLabel,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Text(
            '${_logLines.length} lines',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogOutput() {
    if (_logLines.isEmpty && !_done) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Waiting for logs...',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.black87,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: _logLines.length,
        itemBuilder: (_, i) {
          final line = _logLines[i];
          Color lineColor = Colors.green;
          if (line.contains('[ERROR]') || line.contains('Error:')) {
            lineColor = Colors.red;
          } else if (line.contains('[WARN]') || line.contains('Warning:')) {
            lineColor = Colors.yellow;
          } else if (line.contains('[INFO]') || line.contains('INFO')) {
            lineColor = Colors.cyan;
          }
          return Text(
            line,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: lineColor,
            ),
          );
        },
      ),
    );
  }

  Widget _buildResultSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _currentStatus == ServiceRunStatus.completed
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        border: Border(
          top: BorderSide(
            color: _currentStatus == ServiceRunStatus.completed
                ? Colors.green.withValues(alpha: 0.3)
                : Colors.red.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Result',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(_resultSummary!),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.red.withValues(alpha: 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Error',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            style: const TextStyle(color: Colors.red),
          ),
        ],
      ),
    );
  }

  void _showCancelConfirm() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Service Run?'),
        content: const Text(
          'This will send a cancel request to the backend. '
          'The service may not stop immediately if it is in a '
          'non-interruptible phase.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await widget.client.cancelServiceRun(widget.run.runId);
              } catch (_) {
                // The stream will handle the terminal state
              }
            },
            child: const Text('Cancel Run'),
          ),
        ],
      ),
    );
  }
}
