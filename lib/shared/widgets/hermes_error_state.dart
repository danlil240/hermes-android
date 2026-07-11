import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/models/connection.dart';
import '../../features/diagnostics/diagnostics_screen.dart';
import '../errors/hermes_error.dart';

/// A reusable full-screen error state for any remote screen.
///
/// Classifies the error into a known [HermesErrorType] and renders the
/// appropriate icon, title, message, and recovery actions:
///
/// - Auth failure → "Update API Key" (pops to connection list)
/// - Dashboard auth failure → "Configure Dashboard" (pops to connection list)
/// - Cloudflare Access required → "Configure Cloudflare Access"
/// - Connection failure → "Open Diagnostics"
/// - Unsupported endpoint → "Learn what this server version supports"
/// - Transient server failure → auto-retry with countdown
///
/// Use [source] to distinguish API-key errors from dashboard-credential
/// errors. Use [title] to override the default title for the screen context.
class HermesErrorState extends StatefulWidget {
  final dynamic error;
  final SavedConnection connection;
  final VoidCallback onRetry;
  final HermesErrorSource source;
  final String? title;

  const HermesErrorState({
    required this.error,
    required this.connection,
    required this.onRetry,
    this.source = HermesErrorSource.api,
    this.title,
    super.key,
  });

  @override
  State<HermesErrorState> createState() => _HermesErrorStateState();
}

class _HermesErrorStateState extends State<HermesErrorState> {
  HermesError? _classified;
  Timer? _retryTimer;
  int _countdown = 0;

  @override
  void initState() {
    super.initState();
    _classify();
  }

  @override
  void didUpdateWidget(HermesErrorState oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.error != widget.error ||
        oldWidget.source != widget.source) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _classify();
    }
  }

  void _classify() {
    _classified = HermesError.classify(
      widget.error,
      source: widget.source,
      connection: widget.connection,
    );
    if (_classified!.isTransient) {
      _startAutoRetry();
    }
  }

  void _startAutoRetry() {
    _countdown = 5;
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        timer.cancel();
        widget.onRetry();
      }
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final err = _classified!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconFor(err.type), size: 48, color: _colorFor(err.type)),
            const SizedBox(height: 16),
            Text(
              widget.title ?? _titleFor(err.type),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              err.message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ..._buildActions(err),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActions(HermesError err) {
    final actions = <Widget>[];

    // Auto-retry countdown for transient errors
    if (err.isTransient && _countdown > 0) {
      actions.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                'Retrying in $_countdown seconds…',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    // Primary retry button
    actions.add(
      ElevatedButton(
        onPressed: widget.onRetry,
        child: const Text('Retry now'),
      ),
    );

    // Type-specific secondary actions
    switch (err.type) {
      case HermesErrorType.authFailure:
        actions.add(const SizedBox(height: 8));
        actions.add(
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.key),
            label: const Text('Update API Key'),
          ),
        );
      case HermesErrorType.dashboardAuthRequired:
        actions.add(const SizedBox(height: 8));
        actions.add(
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.admin_panel_settings),
            label: const Text('Configure Dashboard'),
          ),
        );
      case HermesErrorType.cloudflareAccessRequired:
        actions.add(const SizedBox(height: 8));
        actions.add(
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.cloud),
            label: const Text('Configure Cloudflare Access'),
          ),
        );
      case HermesErrorType.networkUnavailable:
        actions.add(const SizedBox(height: 8));
        actions.add(
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    DiagnosticsScreen(connection: widget.connection),
              ),
            ),
            icon: const Icon(Icons.dns),
            label: const Text('Open Diagnostics'),
          ),
        );
      case HermesErrorType.unsupportedEndpoint:
        actions.add(const SizedBox(height: 8));
        actions.add(
          TextButton.icon(
            onPressed: _showUnsupportedInfo,
            icon: const Icon(Icons.info),
            label: const Text('Learn what this server version supports'),
          ),
        );
      case HermesErrorType.permissionDenied:
      case HermesErrorType.serverRestarting:
      case HermesErrorType.transientServerError:
      case HermesErrorType.unknown:
        break;
    }

    return actions;
  }

  void _showUnsupportedInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsupported Endpoint'),
        content: const Text(
          'This feature requires a newer version of the Hermes server.\n\n'
          'Check your server version with:\n'
          '  hermes --version\n\n'
          'Update your server to the latest release to enable this feature.',
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

  IconData _iconFor(HermesErrorType type) => switch (type) {
        HermesErrorType.networkUnavailable => Icons.cloud_off,
        HermesErrorType.serverRestarting => Icons.restart_alt,
        HermesErrorType.authFailure => Icons.key_off,
        HermesErrorType.dashboardAuthRequired => Icons.admin_panel_settings,
        HermesErrorType.cloudflareAccessRequired => Icons.shield,
        HermesErrorType.unsupportedEndpoint => Icons.extension_off,
        HermesErrorType.permissionDenied => Icons.block,
        HermesErrorType.transientServerError => Icons.error_outline,
        HermesErrorType.unknown => Icons.error_outline,
      };

  Color _colorFor(HermesErrorType type) => switch (type) {
        HermesErrorType.networkUnavailable => Colors.orange,
        HermesErrorType.serverRestarting => Colors.orange,
        HermesErrorType.authFailure => Colors.red,
        HermesErrorType.dashboardAuthRequired => Colors.red,
        HermesErrorType.cloudflareAccessRequired => Colors.orange,
        HermesErrorType.unsupportedEndpoint => Colors.blue,
        HermesErrorType.permissionDenied => Colors.red,
        HermesErrorType.transientServerError => Colors.orange,
        HermesErrorType.unknown => Colors.orange,
      };

  String _titleFor(HermesErrorType type) => switch (type) {
        HermesErrorType.networkUnavailable => 'Server unreachable',
        HermesErrorType.serverRestarting => 'Server restarting',
        HermesErrorType.authFailure => 'Authentication failed',
        HermesErrorType.dashboardAuthRequired => 'Dashboard login required',
        HermesErrorType.cloudflareAccessRequired => 'Cloudflare Access required',
        HermesErrorType.unsupportedEndpoint => 'Feature not available',
        HermesErrorType.permissionDenied => 'Permission denied',
        HermesErrorType.transientServerError => 'Server error',
        HermesErrorType.unknown => 'Connection issue',
      };
}
