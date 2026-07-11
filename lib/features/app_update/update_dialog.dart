import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/app_updater.dart';

/// Dialog shown when a newer GitHub release is available.
/// Downloads the APK and triggers Android's package installer.
class UpdateDialog extends StatefulWidget {
  final ReleaseInfo release;

  const UpdateDialog({required this.release, super.key});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;
  String? _downloadedPath;

  static const _platform = MethodChannel('hermes/app_updater');

  @override
  Widget build(BuildContext context) {
    final apk = AppUpdater.getBestApk(widget.release);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text('Update Available — v${widget.release.version}')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              'A new version of Hermes is available.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (widget.release.body.isNotEmpty) ...[
              Text(
                'Release notes:',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.release.body,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ],
            if (_downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(
                'Downloading… ${(_progress * 100).toInt()}%',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_downloading && _downloadedPath == null) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          if (apk != null)
            FilledButton.icon(
              onPressed: () => _downloadAndInstall(apk),
              icon: const Icon(Icons.download),
              label: const Text('Update Now'),
            )
          else
            FilledButton.icon(
              onPressed: () =>
                  launchUrl(Uri.parse(widget.release.htmlUrl)),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open Release'),
            ),
        ],
        if (_downloadedPath != null)
          FilledButton.icon(
            onPressed: _installApk,
            icon: const Icon(Icons.install_mobile),
            label: const Text('Install'),
          ),
      ],
    );
  }

  Future<void> _downloadAndInstall(ReleaseAsset apk) async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });

    try {
      final path = await AppUpdater.downloadApk(
        apk,
        onProgress: (received, total) {
          if (total > 0) {
            setState(() => _progress = received / total);
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadedPath = path;
      });

      // Auto-trigger installation right away.
      await _installApk();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = 'Download failed: $e';
      });
    }
  }

  Future<void> _installApk() async {
    if (_downloadedPath == null) return;
    try {
      await _platform.invokeMethod('installApk', {'path': _downloadedPath});
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // Fallback: open the release page in the browser.
      if (mounted) {
        setState(() {
          _error = 'Could not launch installer automatically. '
              'Opening browser instead…';
        });
        await launchUrl(Uri.parse(widget.release.htmlUrl));
      }
    }
  }
}
