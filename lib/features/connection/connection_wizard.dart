import 'package:flutter/material.dart';
import '../../core/network/connection_manager.dart';

/// The connection type the user picks in Step 1 of the wizard.
enum _ConnectionType { homeWifi, tailscale, cloudflare, custom }

extension _ConnectionTypeX on _ConnectionType {
  String get label => switch (this) {
    _ConnectionType.homeWifi => 'Home Wi-Fi',
    _ConnectionType.tailscale => 'Tailscale',
    _ConnectionType.cloudflare => 'Cloudflare URL',
    _ConnectionType.custom => 'Custom',
  };

  String get subtitle => switch (this) {
    _ConnectionType.homeWifi =>
      'Hermes Gateway on your local network (e.g. 192.168.1.50)',
    _ConnectionType.tailscale =>
      'Reach your Gateway anywhere via Tailscale (e.g. 100.x.y.z)',
    _ConnectionType.cloudflare =>
      'Public domain or Cloudflare Tunnel (e.g. hermes.example.com)',
    _ConnectionType.custom => 'Advanced: manually configure every field',
  };

  IconData get icon => switch (this) {
    _ConnectionType.homeWifi => Icons.wifi,
    _ConnectionType.tailscale => Icons.vpn_lock,
    _ConnectionType.cloudflare => Icons.cloud,
    _ConnectionType.custom => Icons.settings_ethernet,
  };

  String get presetLabel => switch (this) {
    _ConnectionType.homeWifi => 'Hermes Gateway — local network',
    _ConnectionType.tailscale => 'Hermes Gateway — Tailscale',
    _ConnectionType.cloudflare => 'Hermes Gateway — Cloudflare',
    _ConnectionType.custom => 'Hermes Gateway — custom',
  };

  int get defaultPort => switch (this) {
    _ConnectionType.homeWifi => 8642,
    _ConnectionType.tailscale => 8642,
    _ConnectionType.cloudflare => 443,
    _ConnectionType.custom => 8642,
  };
}

/// A 3-step guided setup wizard that replaces the raw connection form.
///
/// Step 1 — pick a connection type (Home Wi-Fi, Tailscale, Cloudflare, Custom).
/// Step 2 — enter only the fields relevant to that type.
/// Step 3 — test the connection and show a human-readable result.
class ConnectionWizard extends StatefulWidget {
  /// Same callback signature as the old [_AddDialog.onSave].
  final void Function(
    String label,
    String host,
    int port,
    String apiKey, {
    String? gatewayPrefix,
    String? dashboardPrefix,
    bool dashboardProxied,
    int? dashboardPort,
    String? dashboardHost,
    String? dashboardUsername,
    String? dashboardPassword,
    String? cfAccessClientId,
    String? cfAccessClientSecret,
  })
  onSave;

  const ConnectionWizard({required this.onSave, super.key});

  @override
  State<ConnectionWizard> createState() => _ConnectionWizardState();
}

class _ConnectionWizardState extends State<ConnectionWizard> {
  int _step = 0;
  _ConnectionType? _selectedType;

  // Controllers for Step 2
  late final TextEditingController _label;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _apiKey;
  late final TextEditingController _cfAccessClientId;
  late final TextEditingController _cfAccessClientSecret;

  // Advanced / dashboard controllers (Custom only or optional dashboard setup)
  late final TextEditingController _gatewayPrefix;
  late final TextEditingController _dashboardPrefix;
  late final TextEditingController _dashPort;
  late final TextEditingController _dashHost;
  late final TextEditingController _dashUser;
  late final TextEditingController _dashPass;
  bool _dashboardProxied = false;
  bool _showAdvanced = false;

  // Step 3 state
  bool _testing = false;
  HealthCheckResult? _testResult;
  bool _connected = false;
  String? _error;

  // Post-success: optional dashboard setup
  bool _showDashboardSetup = false;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController();
    _host = TextEditingController();
    _port = TextEditingController(text: '8642');
    _apiKey = TextEditingController();
    _cfAccessClientId = TextEditingController();
    _cfAccessClientSecret = TextEditingController();
    _gatewayPrefix = TextEditingController();
    _dashboardPrefix = TextEditingController();
    _dashPort = TextEditingController();
    _dashHost = TextEditingController();
    _dashUser = TextEditingController();
    _dashPass = TextEditingController();
  }

  @override
  void dispose() {
    _label.dispose();
    _host.dispose();
    _port.dispose();
    _apiKey.dispose();
    _cfAccessClientId.dispose();
    _cfAccessClientSecret.dispose();
    _gatewayPrefix.dispose();
    _dashboardPrefix.dispose();
    _dashPort.dispose();
    _dashHost.dispose();
    _dashUser.dispose();
    _dashPass.dispose();
    super.dispose();
  }

  void _selectType(_ConnectionType type) {
    setState(() {
      _selectedType = type;
      _label.text = type.presetLabel;
      _port.text = type.defaultPort.toString();
      // Reset host/apiKey when switching types
      _host.clear();
      _apiKey.clear();
      _cfAccessClientId.clear();
      _cfAccessClientSecret.clear();
      _gatewayPrefix.clear();
      _dashboardPrefix.clear();
      _dashPort.clear();
      _dashHost.clear();
      _dashUser.clear();
      _dashPass.clear();
      _dashboardProxied = false;
      _showAdvanced = false;
      _step = 1;
    });
  }

  /// Auto-detect HTTPS, port, and Cloudflare config from a pasted URL.
  void _onHostChanged(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    // Detect https:// prefix
    final isHttps = trimmed.toLowerCase().startsWith('https://');
    final hasScheme = trimmed.contains('://');

    // Parse to extract host and port
    String parsedHost = trimmed;
    int? parsedPort;

    if (hasScheme) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.host.isNotEmpty) {
        parsedHost = uri.host;
        if (uri.hasPort) parsedPort = uri.port;
      }
    }

    // Auto-set port for Cloudflare type when HTTPS detected without explicit port
    if (_selectedType == _ConnectionType.cloudflare) {
      if (isHttps && parsedPort == null) {
        parsedPort = 443;
      }
    }

    // Detect Cloudflare-style domain (has a dot, not a local IP)
    // If user pasted a full URL, strip the scheme from the host field
    if (hasScheme && parsedHost != trimmed) {
      final portSuffix = parsedPort != null ? ':$parsedPort' : '';
      final hostValue = '$parsedHost$portSuffix';

      // Only update if different to avoid cursor jumps
      if (_host.text != hostValue) {
        _host.value = TextEditingValue(
          text: hostValue,
          selection: TextSelection.collapsed(offset: hostValue.length),
        );
      }
    }

    // Update port field if auto-detected
    if (parsedPort != null && _port.text != parsedPort.toString()) {
      _port.value = TextEditingValue(
        text: parsedPort.toString(),
        selection: TextSelection.collapsed(
          offset: parsedPort.toString().length,
        ),
      );
    }

    // If we detect HTTPS and the type is homeWifi/tailscale, suggest switching
    // (We don't auto-switch, but the port/https are handled at save time)
  }

  bool get _isStep2Valid {
    if (_host.text.trim().isEmpty) return false;
    if (_apiKey.text.trim().isEmpty &&
        _selectedType != _ConnectionType.custom) {
      // API key required for all preset types
      return false;
    }
    if (int.tryParse(_port.text.trim()) == null) return false;
    return true;
  }

  Future<void> _testConnection() async {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? _selectedType!.defaultPort;
    final apiKey = _apiKey.text.trim();
    final gatewayPrefix = _gatewayPrefix.text.trim();
    final cfId = _cfAccessClientId.text.trim();
    final cfSecret = _cfAccessClientSecret.text.trim();

    setState(() {
      _testing = true;
      _testResult = null;
      _error = null;
      _connected = false;
    });

    try {
      final normalized = SavedConnection.normalizeHostAndPort(host, port);
      final baseUrl = SavedConnection(
        id: '',
        label: '',
        host: normalized.host,
        port: normalized.port,
        apiKey: '',
        useHttps: normalized.useHttps,
      ).baseUrl;

      final client = ApiClient(
        baseUrl: baseUrl,
        apiKey: apiKey,
        pathPrefix: gatewayPrefix,
        cfAccessClientId: cfId.isEmpty ? null : cfId,
        cfAccessClientSecret: cfSecret.isEmpty ? null : cfSecret,
      );

      final result = await client.healthCheckDetail();
      client.close();

      if (!mounted) return;
      setState(() {
        _testResult = result;
        _testing = false;
        _connected = result.ok;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testResult = HealthCheckResult(
          ok: false,
          message: 'Connection failed: $e',
        );
        _testing = false;
      });
    }
  }

  void _saveConnection() {
    final label = _label.text.trim().isEmpty
        ? _selectedType!.presetLabel
        : _label.text.trim();
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? _selectedType!.defaultPort;
    final apiKey = _apiKey.text.trim();
    final gatewayPrefix = _gatewayPrefix.text.trim();
    final dashboardPrefix = _dashboardPrefix.text.trim();
    final dashPortText = _dashPort.text.trim();
    final dashHostText = _dashHost.text.trim();
    final dashUser = _dashUser.text.trim();
    final dashPass = _dashPass.text.trim();
    final dashPort = dashPortText.isEmpty ? null : int.tryParse(dashPortText);
    final dashHost = dashHostText.isEmpty ? null : dashHostText;
    final cfId = _cfAccessClientId.text.trim();
    final cfSecret = _cfAccessClientSecret.text.trim();

    widget.onSave(
      label,
      host,
      port,
      apiKey,
      gatewayPrefix: gatewayPrefix.isEmpty ? null : gatewayPrefix,
      dashboardPrefix: dashboardPrefix.isEmpty ? null : dashboardPrefix,
      dashboardProxied: _dashboardProxied,
      dashboardPort: dashPort,
      dashboardHost: dashHost,
      dashboardUsername: dashUser.isEmpty ? null : dashUser,
      dashboardPassword: dashPass.isEmpty ? null : dashPass,
      cfAccessClientId: cfId.isEmpty ? null : cfId,
      cfAccessClientSecret: cfSecret.isEmpty ? null : cfSecret,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Up Connection'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressIndicator(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildCurrentStep(),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          _buildStepDot(0, 'Type'),
          _buildStepLine(),
          _buildStepDot(1, 'Details'),
          _buildStepLine(),
          _buildStepDot(2, 'Connect'),
        ],
      ),
    );
  }

  Widget _buildStepDot(int step, String label) {
    final isActive = _step == step;
    final isDone = _step > step;
    final color = isDone
        ? const Color(0xFFD4AF37)
        : isActive
        ? const Color(0xFFD4AF37)
        : Colors.grey[600]!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone ? color : Colors.transparent,
            border: Border.all(color: color, width: 2),
          ),
          child: isDone
              ? const Icon(Icons.check, size: 16, color: Colors.black)
              : Center(
                  child: Text(
                    '${step + 1}',
                    style: TextStyle(
                      color: isActive ? color : Colors.grey[600],
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isActive ? color : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine() {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 20, left: 4, right: 4),
        color: Colors.grey[300],
      ),
    );
  }

  Widget _buildCurrentStep() {
    return switch (_step) {
      0 => _buildStep1(),
      1 => _buildStep2(),
      2 => _buildStep3(),
      _ => _buildStep1(),
    };
  }

  // ── Step 1: Choose connection type ───────────────────────────────────

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          'How do you connect to your Hermes Gateway?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Choose the option that matches your setup. You can change details later.',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        const SizedBox(height: 24),
        ..._ConnectionType.values.map(
          (type) => _ConnectionTypeCard(
            type: type,
            isSelected: _selectedType == type,
            onTap: () => _selectType(type),
          ),
        ),
      ],
    );
  }

  // ── Step 2: Enter details ────────────────────────────────────────────

  Widget _buildStep2() {
    final type = _selectedType!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          'Enter your connection details',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          type.subtitle,
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _label,
          decoration: const InputDecoration(
            labelText: 'Connection name',
            hintText: 'e.g. Home, Office, Cloud',
          ),
        ),
        const SizedBox(height: 16),
        _buildHostField(type),
        const SizedBox(height: 16),
        if (type == _ConnectionType.custom) ...[
          TextField(
            controller: _port,
            decoration: const InputDecoration(
              labelText: 'Port',
              hintText: '8642 (API Server)',
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _apiKey,
          decoration: const InputDecoration(
            labelText: 'API Key',
            hintText: 'API_SERVER_KEY from ~/.hermes/.env',
          ),
          obscureText: true,
        ),
        if (type == _ConnectionType.cloudflare) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _cfAccessClientId,
            decoration: const InputDecoration(
              labelText: 'Cloudflare Access Client ID (optional)',
              hintText: 'Service token Client ID, if Access is enabled',
            ),
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _cfAccessClientSecret,
            decoration: const InputDecoration(
              labelText: 'Cloudflare Access Client Secret (optional)',
              hintText: 'Service token Client Secret, if Access is enabled',
            ),
            obscureText: true,
            autocorrect: false,
          ),
        ],
        if (type == _ConnectionType.custom) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _cfAccessClientId,
            decoration: const InputDecoration(
              labelText: 'CF Access Client ID (optional)',
              hintText: 'Cloudflare Access service token Client ID',
            ),
            autocorrect: false,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _cfAccessClientSecret,
            decoration: const InputDecoration(
              labelText: 'CF Access Client Secret (optional)',
              hintText: 'Cloudflare Access service token Client Secret',
            ),
            obscureText: true,
            autocorrect: false,
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _showAdvanced ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Proxy and dashboard details',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          if (_showAdvanced) ..._buildAdvancedFields(),
        ],
        const SizedBox(height: 24),
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
      ],
    );
  }

  Widget _buildHostField(_ConnectionType type) {
    final hint = switch (type) {
      _ConnectionType.homeWifi => '192.168.1.50',
      _ConnectionType.tailscale => '100.x.y.z or machine.tailnet.ts.net',
      _ConnectionType.cloudflare => 'https://hermes.example.com',
      _ConnectionType.custom => 'host, IP, or full URL',
    };

    final label = switch (type) {
      _ConnectionType.homeWifi => 'Gateway IP address',
      _ConnectionType.tailscale => 'Tailscale IP or hostname',
      _ConnectionType.cloudflare => 'Gateway URL',
      _ConnectionType.custom => 'Host',
    };

    return TextField(
      controller: _host,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: type == _ConnectionType.cloudflare
            ? const Icon(Icons.link)
            : type == _ConnectionType.homeWifi
            ? const Icon(Icons.wifi)
            : type == _ConnectionType.tailscale
            ? const Icon(Icons.vpn_lock)
            : const Icon(Icons.dns),
      ),
      keyboardType: TextInputType.url,
      autocorrect: false,
      onChanged: _onHostChanged,
    );
  }

  List<Widget> _buildAdvancedFields() {
    return [
      const SizedBox(height: 8),
      TextField(
        controller: _gatewayPrefix,
        decoration: const InputDecoration(
          labelText: 'Gateway path prefix',
          hintText: 'e.g. /profile/peter (proxy path before /api/ and /v1/)',
        ),
        autocorrect: false,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _dashboardPrefix,
        decoration: const InputDecoration(
          labelText: 'Dashboard path prefix',
          hintText: 'e.g. /dashboard (proxy path before /api/)',
        ),
        autocorrect: false,
      ),
      const SizedBox(height: 8),
      SwitchListTile(
        value: _dashboardProxied,
        contentPadding: EdgeInsets.zero,
        title: const Text('Dashboard behind proxy'),
        subtitle: const Text('Nginx injects auth — app sends clean requests'),
        onChanged: (v) => setState(() => _dashboardProxied = v),
      ),
      TextField(
        controller: _dashPort,
        decoration: const InputDecoration(
          labelText: 'Dashboard Port',
          hintText: 'Leave blank for default (9119)',
        ),
        keyboardType: TextInputType.number,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _dashHost,
        decoration: const InputDecoration(
          labelText: 'Dashboard Host (optional)',
          hintText: 'e.g. hermes.example.com (defaults to gateway host)',
        ),
        autocorrect: false,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _dashUser,
        decoration: const InputDecoration(
          labelText: 'Dashboard Username (optional)',
        ),
        autocorrect: false,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _dashPass,
        decoration: const InputDecoration(
          labelText: 'Dashboard Password (optional)',
        ),
        obscureText: true,
      ),
    ];
  }

  // ── Step 3: Test & Success ───────────────────────────────────────────

  Widget _buildStep3() {
    if (_connected) {
      return _buildSuccessView();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Icon(
          _testResult?.ok == false ? Icons.error_outline : Icons.wifi_find,
          size: 48,
          color: _testResult?.ok == false
              ? Colors.red
              : const Color(0xFFD4AF37),
        ),
        const SizedBox(height: 16),
        Text(
          'Test your connection',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          "We'll verify that your Hermes Gateway is reachable and the API key works.",
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        _buildConnectionSummary(),
        const SizedBox(height: 24),
        if (_testResult != null) ...[
          _buildTestResultBanner(),
          const SizedBox(height: 16),
        ],
        if (_testing)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }

  Widget _buildConnectionSummary() {
    final host = _host.text.trim();
    final port = _port.text.trim();
    final type = _selectedType!;
    final https =
        type == _ConnectionType.cloudflare ||
        host.toLowerCase().startsWith('https://');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(type.icon, size: 20, color: const Color(0xFFD4AF37)),
                const SizedBox(width: 8),
                Text(
                  type.label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _summaryRow('Host', host),
            _summaryRow('Port', port),
            _summaryRow('Protocol', https ? 'HTTPS' : 'HTTP'),
            _summaryRow(
              'API Key',
              _apiKey.text.isNotEmpty ? '✓ Set' : '— Not set',
            ),
            if (_cfAccessClientId.text.isNotEmpty)
              _summaryRow('Cloudflare', '✓ Configured'),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildTestResultBanner() {
    final result = _testResult!;
    final ok = result.ok;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ok
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ok
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error_outline,
            color: ok ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ok
                  ? 'Gateway is reachable and the API key is valid.'
                  : (result.message ?? 'Connection failed.'),
              style: TextStyle(
                color: ok ? Colors.green[800] : Colors.red,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Icon(Icons.check_circle, size: 56, color: Color(0xFFD4AF37)),
        const SizedBox(height: 16),
        Text(
          'Chat is ready!',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Your Hermes Gateway connection has been saved.\n'
          'You can start chatting now.',
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        if (_showDashboardSetup) ...[
          _buildDashboardSetupSection(),
        ] else ...[
          OutlinedButton.icon(
            onPressed: () => setState(() => _showDashboardSetup = true),
            icon: const Icon(Icons.dashboard_outlined),
            label: const Text('Set up dashboard features'),
          ),
          const SizedBox(height: 8),
          Text(
            'Optional: enables Memory, Cron, Skills, and Settings tabs.\n'
            'You can skip this and set it up later.',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildDashboardSetupSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Dashboard details (optional)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'For the Memory/Cron/Skills/Settings tabs. Leave blank to use the '
          'default dashboard port (9119) with no login.',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _gatewayPrefix,
          decoration: const InputDecoration(
            labelText: 'Gateway path prefix (optional)',
            hintText: 'e.g. /profile/peter',
          ),
          autocorrect: false,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _dashboardPrefix,
          decoration: const InputDecoration(
            labelText: 'Dashboard path prefix (optional)',
            hintText: 'e.g. /dashboard',
          ),
          autocorrect: false,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: _dashboardProxied,
          contentPadding: EdgeInsets.zero,
          title: const Text('Dashboard behind proxy'),
          subtitle: const Text('Nginx injects auth — app sends clean requests'),
          onChanged: (v) => setState(() => _dashboardProxied = v),
        ),
        TextField(
          controller: _dashPort,
          decoration: const InputDecoration(
            labelText: 'Dashboard Port (optional)',
            hintText: 'Default: 9119',
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _dashHost,
          decoration: const InputDecoration(
            labelText: 'Dashboard Host (optional)',
            hintText: 'Defaults to gateway host',
          ),
          autocorrect: false,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _dashUser,
          decoration: const InputDecoration(
            labelText: 'Dashboard Username (optional)',
          ),
          autocorrect: false,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _dashPass,
          decoration: const InputDecoration(
            labelText: 'Dashboard Password (optional)',
          ),
          obscureText: true,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saveConnection,
          icon: const Icon(Icons.save),
          label: const Text('Save with dashboard'),
        ),
      ],
    );
  }

  // ── Bottom bar ───────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (_step > 0 && !_connected)
            TextButton(
              onPressed: () => setState(() {
                _step--;
                _testResult = null;
                _error = null;
              }),
              child: const Text('Back'),
            ),
          const Spacer(),
          if (_step == 0)
            // Step 1: no forward button, cards auto-advance
            const SizedBox.shrink()
          else if (_step == 1)
            FilledButton(
              onPressed: _isStep2Valid
                  ? () => setState(() {
                      _step = 2;
                      _testResult = null;
                      _error = null;
                    })
                  : null,
              child: const Text('Continue'),
            )
          else if (_step == 2 && !_connected)
            FilledButton(
              onPressed: _testing ? null : _testConnection,
              child: _testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Test connection'),
            )
          else if (_step == 2 && _connected && !_showDashboardSetup)
            FilledButton(onPressed: _saveConnection, child: const Text('Done'))
          else if (_step == 2 && _connected && _showDashboardSetup)
            const SizedBox.shrink()
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

/// A selectable card for choosing a connection type in Step 1.
class _ConnectionTypeCard extends StatelessWidget {
  final _ConnectionType type;
  final bool isSelected;
  final VoidCallback onTap;

  const _ConnectionTypeCard({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFD4AF37)
                  : Colors.grey.withValues(alpha: 0.2),
              width: isSelected ? 2 : 1,
            ),
            color: isSelected
                ? const Color(0xFFD4AF37).withValues(alpha: 0.05)
                : null,
          ),
          child: Row(
            children: [
              Icon(
                type.icon,
                size: 28,
                color: isSelected ? const Color(0xFFD4AF37) : Colors.grey[500],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? const Color(0xFFD4AF37) : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      type.subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle, color: Color(0xFFD4AF37)),
            ],
          ),
        ),
      ),
    );
  }
}
