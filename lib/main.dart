import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'core/auth/biometric_lock.dart';
import 'core/network/connection_manager.dart';
import 'core/storage/secure_storage.dart';
import 'core/storage/session_cache.dart';
import 'features/sessions/session_list_screen.dart';
import 'shared/responsive.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final secureStorage = SecureStorage();
  final connManager = ConnectionManager(prefs, secureStorage);
  await connManager.migrateSecretsToSecureStorage();
  final biometricLock = BiometricLock();
  runApp(HermesApp(
    connManager: connManager,
    biometricLock: biometricLock,
    prefs: prefs,
  ));
}

class HermesApp extends StatefulWidget {
  final ConnectionManager connManager;
  final BiometricLock biometricLock;
  final SharedPreferences prefs;
  const HermesApp({
    required this.connManager,
    required this.biometricLock,
    required this.prefs,
    super.key,
  });

  @override
  State<HermesApp> createState() => HermesAppState();

  static ThemeMode getThemeMode(SharedPreferences prefs) {
    final stored = prefs.getString('theme_mode') ?? 'system';
    switch (stored) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  static Future<void> setThemeMode(
    SharedPreferences prefs,
    ThemeMode mode,
  ) async {
    final value = mode == ThemeMode.dark
        ? 'dark'
        : mode == ThemeMode.light
        ? 'light'
        : 'system';
    await prefs.setString('theme_mode', value);
  }
}

class HermesAppState extends State<HermesApp> {
  bool _unlocked = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final available = await widget.biometricLock.isAvailable();
    final enabled = widget.prefs.getBool('biometric_lock') ?? false;
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
    });
    if (enabled && available) {
      await _promptBiometric();
    } else {
      if (!mounted) return;
      setState(() => _unlocked = true);
    }
  }

  Future<void> _promptBiometric() async {
    final result = await widget.biometricLock.authenticate(
      reason: 'Please authenticate to unlock Hermes',
    );
    if (!mounted) return;
    setState(() {
      _unlocked = result == BiometricAuthResult.success;
    });
    if (result != BiometricAuthResult.success) {
      // Retry after a short delay if the user canceled
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && !_unlocked) _promptBiometric();
      });
    }
  }

  Future<void> _toggleBiometricLock(bool enabled) async {
    await widget.prefs.setBool('biometric_lock', enabled);
    setState(() => _biometricEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);

    return MaterialApp(
      title: 'Hermes Agent',
      themeMode: HermesApp.getThemeMode(widget.connManager.prefs),
      theme: ThemeData(
        colorSchemeSeed: gold,
        brightness: Brightness.light,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: gold,
          foregroundColor: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: gold,
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1A1A1A),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: gold,
          foregroundColor: Colors.black,
        ),
      ),
      home: _unlocked
          ? HomeScreen(
              connManager: widget.connManager,
              biometricLock: widget.biometricLock,
              biometricAvailable: _biometricAvailable,
              biometricEnabled: _biometricEnabled,
              onToggleBiometric: _toggleBiometricLock,
            )
          : _LockScreen(
              onRetry: _promptBiometric,
            ),
    );
  }
}

/// Full-screen biometric lock shown when the app starts and biometric
/// lock is enabled.
class _LockScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const _LockScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 64, color: Color(0xFFD4AF37)),
            const SizedBox(height: 24),
            Text(
              'Hermes Locked',
              style: GoogleFonts.cinzel(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFD4AF37),
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Authenticate with biometrics to continue',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[500],
                  ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Brand header used across screens.
class HermesHeader extends StatelessWidget {
  final String? subtitle;
  const HermesHeader({super.key, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(
          bottom: BorderSide(color: Color(0xFFD4AF37), width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'HERMES',
            style: GoogleFonts.cinzel(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFD4AF37),
              letterSpacing: 6,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                letterSpacing: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final ConnectionManager connManager;
  final BiometricLock biometricLock;
  final bool biometricAvailable;
  final bool biometricEnabled;
  final ValueChanged<bool> onToggleBiometric;
  const HomeScreen({
    required this.connManager,
    required this.biometricLock,
    required this.biometricAvailable,
    required this.biometricEnabled,
    required this.onToggleBiometric,
    super.key,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  List<SavedConnection> _connections = [];
  bool _autoNavigated = false;
  Timer? _backgroundSync;
  static const String _lastConnectionKey = 'last_connection_id';

  Future<void> _refresh() async {
    final conns = await widget.connManager.getConnectionsWithSecrets();
    if (!mounted) return;
    setState(() => _connections = conns);
    if (!_autoNavigated && conns.isNotEmpty) {
      _autoNavigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeAutoNavigate();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _backgroundSync = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _syncAllConnections(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _backgroundSync?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Push one refresh before Android throttles Dart timers in the
      // background. The periodic loop continues when the process remains
      // alive, and retries when the app returns.
      _syncAllConnections();
    }
  }

  Future<void> _syncAllConnections() async {
    final connections = await widget.connManager.getConnectionsWithSecrets();
    await Future.wait(connections.map((connection) async {
      final client = ApiClient(
        baseUrl: connection.baseUrl,
        apiKey: connection.apiKey,
        pathPrefix: connection.gatewayPrefix ?? '',
        cfAccessClientId: connection.cfAccessClientId,
        cfAccessClientSecret: connection.cfAccessClientSecret,
      );
      try {
        final sessions = await client.getSessions();
        final cache = SessionCache(widget.connManager.prefs, connection.id);
        final previousById = {
          for (final session in cache.loadSessions()) session.id: session,
        };
        await cache.saveSessions(sessions);
        await Future.wait(sessions.where((session) {
          final previous = previousById[session.id];
          return cache.loadMessages(session.id).isEmpty ||
              previous == null ||
              previous.messageCount != session.messageCount;
        }).map((session) async {
          try {
            await cache.saveMessages(
              session.id,
              await client.getMessages(session.id),
            );
          } catch (_) {
            // Keep the last good copy for an individual session.
          }
        }));
      } catch (_) {
        // Offline connections are retried on the next interval.
      } finally {
        client.close();
      }
    }));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_autoNavigated && _connections.isNotEmpty) {
      _autoNavigated = true;
      _maybeAutoNavigate();
    }
  }

  void _maybeAutoNavigate() {
    final lastId = widget.connManager.prefs.getString(_lastConnectionKey);
    final conn = lastId == null
        ? (_connections.length == 1 ? _connections.first : null)
        : (_connections.where((c) => c.id == lastId).firstOrNull ??
            (_connections.length == 1 ? _connections.first : null));
    if (conn == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navigateToSessions(conn);
    });
  }

  void _navigateToSessions(SavedConnection conn) {
    widget.connManager.prefs.setString(_lastConnectionKey, conn.id);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SessionListScreen(
          connection: conn,
          prefs: widget.connManager.prefs,
        ),
      ),
    );
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (_) => _AddDialog(
        onSave:
            (
              label,
              host,
              port,
              apiKey, {
              gatewayPrefix,
              dashboardPrefix,
              dashboardProxied = false,
              dashboardPort,
              dashboardHost,
              dashboardUsername,
              dashboardPassword,
              cfAccessClientId,
              cfAccessClientSecret,
            }) {
              widget.connManager.saveConnection(
                label,
                host,
                port,
                apiKey,
                gatewayPrefix: gatewayPrefix,
                dashboardPrefix: dashboardPrefix,
                dashboardProxied: dashboardProxied,
                dashboardPort: dashboardPort,
                dashboardHost: dashboardHost,
                dashboardUsername: dashboardUsername,
                dashboardPassword: dashboardPassword,
                cfAccessClientId: cfAccessClientId,
                cfAccessClientSecret: cfAccessClientSecret,
              ).then((_) => _refresh());
            },
      ),
    );
  }

  void _showApiKeyDialog(SavedConnection conn) {
    final ctrl = TextEditingController(text: conn.apiKey);
    bool validating = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Update API Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: 'API_SERVER_KEY from ~/.hermes/.env',
                ),
                obscureText: true,
                enabled: !validating,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: validating ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: validating
                  ? null
                  : () async {
                      final key = ctrl.text.trim();
                      if (key.isEmpty) return;

                      setDialogState(() {
                        validating = true;
                        error = null;
                      });

                      try {
                        final baseUrl = conn.baseUrl;
                        final client = ApiClient(
                          baseUrl: baseUrl,
                          apiKey: key,
                          pathPrefix: conn.gatewayPrefix ?? '',
                          cfAccessClientId: conn.cfAccessClientId,
                          cfAccessClientSecret: conn.cfAccessClientSecret,
                        );
                        final result = await client.healthCheckDetail();
                        client.close();

                        if (!ctx.mounted) return;

                        if (result.ok) {
                          await widget.connManager.updateApiKey(conn.id, key);
                          _refresh();
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                        } else {
                          setDialogState(() {
                            error = result.message ?? 'Validation failed.';
                            validating = false;
                          });
                        }
                      } catch (e) {
                        if (!ctx.mounted) return;
                        setDialogState(() {
                          error = 'Cannot reach ${conn.host}:${conn.port}.';
                          validating = false;
                        });
                      }
                    },
              child: validating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ctrl.dispose();
      });
    });
  }

  void _showDashboardAuthDialog(SavedConnection conn) {
    final gatewayPrefixCtrl = TextEditingController(
      text: conn.gatewayPrefix ?? '',
    );
    final dashboardPrefixCtrl = TextEditingController(
      text: conn.dashboardPrefix ?? '',
    );
    final portCtrl = TextEditingController(
      text: conn.dashboardPortOverride?.toString() ?? '',
    );
    final dashHostCtrl = TextEditingController(
      text: conn.dashboardHostOverride ?? '',
    );
    final userCtrl = TextEditingController(text: conn.dashboardUsername ?? '');
    final passCtrl = TextEditingController(text: conn.dashboardPassword ?? '');
    final cfIdCtrl = TextEditingController(text: conn.cfAccessClientId ?? '');
    final cfSecretCtrl = TextEditingController(text: conn.cfAccessClientSecret ?? '');
    var proxied = conn.dashboardProxied;
    bool validating = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Dashboard / Proxy Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Used for hosted path prefixes and for the Settings, '
                    'Memory, Skills and Cron tabs. Leave username/password '
                    'blank for an open dashboard, or enable proxied mode when '
                    'your reverse proxy injects dashboard auth.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ),
                if (error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            error!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                TextField(
                  controller: gatewayPrefixCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Gateway path prefix',
                    hintText: 'e.g. /profile/peter',
                  ),
                  autocorrect: false,
                  enabled: !validating,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dashboardPrefixCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Dashboard path prefix',
                    hintText: 'e.g. /dashboard',
                  ),
                  autocorrect: false,
                  enabled: !validating,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: proxied,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dashboard behind proxy'),
                  subtitle: const Text(
                    'Proxy injects auth; app sends clean requests',
                  ),
                  onChanged: validating
                      ? null
                      : (v) => setDialogState(() => proxied = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: portCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Dashboard Port',
                    hintText: 'Leave blank for default (9119)',
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !validating,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dashHostCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Dashboard Host (optional)',
                    hintText: 'e.g. hermes.example.com (defaults to gateway host)',
                  ),
                  autocorrect: false,
                  enabled: !validating,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username (optional)',
                  ),
                  autocorrect: false,
                  enabled: !validating,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Password (optional)',
                  ),
                  obscureText: true,
                  enabled: !validating,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cfIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'CF Access Client ID (optional)',
                    hintText: 'Cloudflare Access service token Client ID',
                  ),
                  autocorrect: false,
                  enabled: !validating,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cfSecretCtrl,
                  decoration: const InputDecoration(
                    labelText: 'CF Access Client Secret (optional)',
                    hintText: 'Cloudflare Access service token Client Secret',
                  ),
                  obscureText: true,
                  autocorrect: false,
                  enabled: !validating,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: validating ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: validating
                  ? null
                  : () async {
                      final portText = portCtrl.text.trim();
                      final port = portText.isEmpty
                          ? null
                          : int.tryParse(portText);
                      if (portText.isNotEmpty && (port == null || port <= 0)) {
                        setDialogState(() => error = 'Invalid port number.');
                        return;
                      }
                      final user = userCtrl.text.trim();
                      final pass = passCtrl.text.trim();
                      final gatewayPrefix = gatewayPrefixCtrl.text.trim();
                      final dashboardPrefix = dashboardPrefixCtrl.text.trim();
                      final dashHost = dashHostCtrl.text.trim();

                      setDialogState(() {
                        validating = true;
                        error = null;
                      });

                      if (gatewayPrefix != (conn.gatewayPrefix ?? '')) {
                        final apiClient = ApiClient(
                          baseUrl: conn.baseUrl,
                          apiKey: conn.apiKey,
                          pathPrefix: gatewayPrefix,
                          cfAccessClientId: cfIdCtrl.text.trim().isEmpty
                              ? null
                              : cfIdCtrl.text.trim(),
                          cfAccessClientSecret: cfSecretCtrl.text.trim().isEmpty
                              ? null
                              : cfSecretCtrl.text.trim(),
                        );
                        final result = await apiClient.healthCheckDetail();
                        apiClient.close();
                        if (!ctx.mounted) return;
                        if (!result.ok) {
                          setDialogState(() {
                            error = result.message ??
                                'Could not reach/authenticate the Gateway API at '
                                '${conn.host}:${conn.port}$gatewayPrefix.';
                            validating = false;
                          });
                          return;
                        }
                      }

                      final client = DashboardClient(
                        host: dashHost.isEmpty ? conn.host : dashHost,
                        port: port ?? conn.dashboardPort,
                        useHttps: conn.useHttps,
                        pathPrefix: dashboardPrefix,
                        proxied: proxied,
                        username: user.isEmpty ? null : user,
                        password: pass.isEmpty ? null : pass,
                        cfAccessClientId: cfIdCtrl.text.trim().isEmpty
                            ? null
                            : cfIdCtrl.text.trim(),
                        cfAccessClientSecret: cfSecretCtrl.text.trim().isEmpty
                            ? null
                            : cfSecretCtrl.text.trim(),
                      );
                      try {
                        await client.getModelInfo();
                        client.close();
                        if (!ctx.mounted) return;
                        await widget.connManager.updateDashboardAuth(
                          conn.id,
                          dashboardPort: port,
                          dashboardHost: dashHost,
                          username: user,
                          password: pass,
                          gatewayPrefix: gatewayPrefix,
                          dashboardPrefix: dashboardPrefix,
                          dashboardProxied: proxied,
                          cfAccessClientId: cfIdCtrl.text.trim(),
                          cfAccessClientSecret: cfSecretCtrl.text.trim(),
                        );
                        _refresh();
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                      } catch (e) {
                        client.close();
                        if (!ctx.mounted) return;
                        setDialogState(() {
                          error =
                              'Could not reach/authenticate the dashboard at '
                              '${dashHost.isEmpty ? conn.host : dashHost}:${port ?? conn.dashboardPort}. '
                              'Check the host, port and credentials.';
                          validating = false;
                        });
                      }
                    },
              child: validating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        gatewayPrefixCtrl.dispose();
        dashboardPrefixCtrl.dispose();
        portCtrl.dispose();
        dashHostCtrl.dispose();
        userCtrl.dispose();
        passCtrl.dispose();
        cfIdCtrl.dispose();
        cfSecretCtrl.dispose();
      });
    });
  }

  Widget _buildConnectionCard(SavedConnection conn) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.router, color: Color(0xFFD4AF37)),
        title: Text(conn.label),
        subtitle: Text(
          '${conn.host}:${conn.port}${conn.gatewayPrefix != null && conn.gatewayPrefix!.isNotEmpty ? conn.gatewayPrefix! : ''}'
          '  \u2022  Key: ${conn.apiKey.isNotEmpty ? "\u2713" : "\u2717"}',
          style: TextStyle(color: Colors.grey[600]),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'delete') {
              widget.connManager.deleteConnection(conn.id).then((_) => _refresh());
            } else if (v == 'apikey') {
              _showApiKeyDialog(conn);
            } else if (v == 'dashboard') {
              _showDashboardAuthDialog(conn);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'apikey', child: Text('Update API Key')),
            const PopupMenuItem(
              value: 'dashboard',
              child: Text('Dashboard / Proxy Settings'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
        onTap: () => _navigateToSessions(conn),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'HERMES',
          style: GoogleFonts.cinzel(
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
        actions: [
          if (widget.biometricAvailable)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'biometric') {
                  widget.onToggleBiometric(!widget.biometricEnabled);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'biometric',
                  child: Row(
                    children: [
                      Icon(
                        widget.biometricEnabled
                            ? Icons.lock
                            : Icons.lock_open,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(widget.biometricEnabled
                          ? 'Disable App Lock'
                          : 'Enable App Lock'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _connections.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_outlined, size: 64, color: Colors.grey[800]),
                  const SizedBox(height: 16),
                  Text(
                    'No connections',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to add a remote Hermes Gateway\n(API Server, port 8642)',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                if (Responsive.isTablet(context)) {
                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: Responsive.gridColumns(context),
                      childAspectRatio: 2.5,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _connections.length,
                    itemBuilder: (_, i) =>
                        _buildConnectionCard(_connections[i]),
                  );
                }
                return ListView.builder(
                  itemCount: _connections.length,
                  itemBuilder: (_, i) => _buildConnectionCard(_connections[i]),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add Connection',
        onPressed: _showAddDialog,
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }
}

class _AddDialog extends StatefulWidget {
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
  const _AddDialog({required this.onSave});

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final _label = TextEditingController(text: 'Home');
  final _host = TextEditingController();
  final _port = TextEditingController(text: '8642');
  final _apiKey = TextEditingController();
  final _gatewayPrefix = TextEditingController();
  final _dashboardPrefix = TextEditingController();
  final _dashPort = TextEditingController();
  final _dashHost = TextEditingController();
  final _dashUser = TextEditingController();
  final _dashPass = TextEditingController();
  final _cfAccessClientId = TextEditingController();
  final _cfAccessClientSecret = TextEditingController();
  bool _showDashboard = false;
  bool _dashboardProxied = false;
  bool _validating = false;
  String? _error;

  Future<void> _validateAndSave() async {
    final label = _label.text.trim();
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 8642;
    final apiKey = _apiKey.text.trim();
    final gatewayPrefix = _gatewayPrefix.text.trim();
    final dashboardPrefix = _dashboardPrefix.text.trim();

    if (label.isEmpty || host.isEmpty || port <= 0) return;

    setState(() {
      _validating = true;
      _error = null;
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
        cfAccessClientId: _cfAccessClientId.text.trim().isEmpty
            ? null
            : _cfAccessClientId.text.trim(),
        cfAccessClientSecret: _cfAccessClientSecret.text.trim().isEmpty
            ? null
            : _cfAccessClientSecret.text.trim(),
      );
      final result = await client.healthCheckDetail();
      client.close();

      if (!mounted) return;

      if (!result.ok) {
        setState(() {
          _error = result.message ?? 'Validation failed.';
          _validating = false;
        });
        return;
      }

      final dashPortText = _dashPort.text.trim();
      final dashHostText = _dashHost.text.trim();
      final dashUser = _dashUser.text.trim();
      final dashPass = _dashPass.text.trim();
      final dashPort = dashPortText.isEmpty ? null : int.tryParse(dashPortText);
      final dashHost = dashHostText.isEmpty ? null : dashHostText;

      // If the user supplied any dashboard details, validate them before saving
      // (parity with the Dashboard Login dialog). The gateway is already known
      // good at this point.
      if (dashPortText.isNotEmpty ||
          dashHostText.isNotEmpty ||
          dashUser.isNotEmpty ||
          dashPass.isNotEmpty ||
          dashboardPrefix.isNotEmpty ||
          _dashboardProxied) {
        final dashHostForValidation = dashHost ?? normalized.host;
        final dashClient = DashboardClient(
          host: dashHostForValidation,
          port: SavedConnection(
            id: '',
            label: '',
            host: normalized.host,
            port: normalized.port,
            apiKey: '',
            useHttps: normalized.useHttps,
            dashboardPortOverride: dashPort,
          ).dashboardPort,
          useHttps: normalized.useHttps,
          pathPrefix: dashboardPrefix,
          proxied: _dashboardProxied,
          username: dashUser.isEmpty ? null : dashUser,
          password: dashPass.isEmpty ? null : dashPass,
          cfAccessClientId: _cfAccessClientId.text.trim().isEmpty
              ? null
              : _cfAccessClientId.text.trim(),
          cfAccessClientSecret: _cfAccessClientSecret.text.trim().isEmpty
              ? null
              : _cfAccessClientSecret.text.trim(),
        );
        try {
          await dashClient.getModelInfo();
        } catch (_) {
          dashClient.close();
          if (!mounted) return;
          setState(() {
            _error =
                'Gateway connected, but the dashboard could not be reached or '
                'authenticated. Check the dashboard details, or clear them to skip.';
            _validating = false;
            _showDashboard = true;
          });
          return;
        }
        dashClient.close();
        if (!mounted) return;
      }

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
        cfAccessClientId: _cfAccessClientId.text.trim().isEmpty
            ? null
            : _cfAccessClientId.text.trim(),
        cfAccessClientSecret: _cfAccessClientSecret.text.trim().isEmpty
            ? null
            : _cfAccessClientSecret.text.trim(),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Cannot reach $host:$port. Check the host and port.';
        _validating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Gateway Connection'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
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
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 18,
                    ),
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
            TextField(
              controller: _label,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: 'Host',
                hintText:
                    '192.168.1.50, 100.x.y.z, or hermes-machine.tailnet.ts.net',
              ),
              keyboardType: TextInputType.text,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _port,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '8642 (API Server)',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKey,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: 'API_SERVER_KEY from ~/.hermes/.env',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cfAccessClientId,
              decoration: const InputDecoration(
                labelText: 'CF Access Client ID (optional)',
                hintText: 'Cloudflare Access service token Client ID',
              ),
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cfAccessClientSecret,
              decoration: const InputDecoration(
                labelText: 'CF Access Client Secret (optional)',
                hintText: 'Cloudflare Access service token Client Secret',
              ),
              obscureText: true,
              autocorrect: false,
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: _validating
                  ? null
                  : () => setState(() => _showDashboard = !_showDashboard),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _showDashboard ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: Colors.grey[500],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Custom proxy and dashboard details',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            if (_showDashboard) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _gatewayPrefix,
                decoration: const InputDecoration(
                  labelText: 'Gateway path prefix',
                  hintText:
                      'e.g. /profile/peter (proxy path before /api/ and /v1/)',
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
                subtitle: const Text(
                  'Nginx injects auth — app sends clean requests',
                ),
                onChanged: (v) => setState(() => _dashboardProxied = v),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Optional. For the Memory/Cron/Skills/Settings tabs. Leave '
                  'blank to use the default dashboard port (9119) with no login.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
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
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _validating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _validating ? null : _validateAndSave,
          child: _validating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Connect'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _label.dispose();
    _host.dispose();
    _port.dispose();
    _apiKey.dispose();
    _gatewayPrefix.dispose();
    _dashboardPrefix.dispose();
    _dashPort.dispose();
    _dashHost.dispose();
    _dashUser.dispose();
    _dashPass.dispose();
    _cfAccessClientId.dispose();
    _cfAccessClientSecret.dispose();
    super.dispose();
  }
}
