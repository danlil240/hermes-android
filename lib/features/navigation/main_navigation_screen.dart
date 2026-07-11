import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/active_runs_manager.dart';
import '../../core/network/connection_manager.dart';
import '../active_runs/active_runs_screen.dart';
import '../cron/cron_screen.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../memory/memory_screen.dart';
import '../services/services_screen.dart';
import '../sessions/session_list_screen.dart';
import '../settings/settings_screen.dart';
import '../skills/skills_screen.dart';

/// Goal-based top-level navigation with four tabs:
///   0 — Chats        (session list)
///   1 — Automations  (Cron + Services)
///   2 — Agent        (Memory + Skills)
///   3 — More         (Diagnostics, Settings, Active Runs, Security, Connection)
///
/// A drawer holds infrequent account/connection controls.
class MainNavigationScreen extends StatefulWidget {
  final SavedConnection connection;
  final SharedPreferences prefs;
  final ConnectionManager connManager;
  final bool biometricAvailable;
  final bool biometricEnabled;
  final ValueChanged<bool> onToggleBiometric;
  final VoidCallback onSwitchConnection;
  final VoidCallback onConfigureDashboard;
  final VoidCallback onConnectionChanged;

  const MainNavigationScreen({
    required this.connection,
    required this.prefs,
    required this.connManager,
    required this.biometricAvailable,
    required this.biometricEnabled,
    required this.onToggleBiometric,
    required this.onSwitchConnection,
    required this.onConfigureDashboard,
    required this.onConnectionChanged,
    super.key,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          SessionListScreen(
            connection: widget.connection,
            prefs: widget.prefs,
            onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          _AutomationsTab(
            connection: widget.connection,
            onConfigureDashboard: widget.onConfigureDashboard,
          ),
          _AgentTab(
            connection: widget.connection,
            onConfigureDashboard: widget.onConfigureDashboard,
          ),
          _MoreTab(
            connection: widget.connection,
            connManager: widget.connManager,
            biometricAvailable: widget.biometricAvailable,
            biometricEnabled: widget.biometricEnabled,
            onToggleBiometric: widget.onToggleBiometric,
            onSwitchConnection: widget.onSwitchConnection,
            onConnectionChanged: widget.onConnectionChanged,
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── Bottom navigation with live badges ──────────────────────────────

  Widget _buildBottomNav() {
    return ListenableBuilder(
      listenable: ActiveRunsManager.instance,
      builder: (context, _) {
        final active = ActiveRunsManager.instance.activeRuns;
        final chatCount = active
            .where(
              (r) =>
                  r.type == ActiveRunType.chat ||
                  r.type == ActiveRunType.question,
            )
            .length;
        final serviceCount = active
            .where((r) => r.type == ActiveRunType.service)
            .length;
        final moreCount = active.length;

        return NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: [
            NavigationDestination(
              icon: _badgeIcon(Icons.chat_bubble_outline, chatCount),
              selectedIcon: _badgeIcon(Icons.chat, chatCount),
              label: 'Chats',
            ),
            NavigationDestination(
              icon: _badgeIcon(Icons.sync_outlined, serviceCount),
              selectedIcon: _badgeIcon(Icons.sync, serviceCount),
              label: 'Automations',
            ),
            const NavigationDestination(
              icon: Icon(Icons.psychology_outlined),
              selectedIcon: Icon(Icons.psychology),
              label: 'Agent',
            ),
            NavigationDestination(
              icon: _badgeIcon(Icons.more_horiz, moreCount),
              selectedIcon: _badgeIcon(Icons.more_horiz, moreCount),
              label: 'More',
            ),
          ],
        );
      },
    );
  }

  Widget _badgeIcon(IconData icon, int count) {
    if (count == 0) return Icon(icon);
    return Badge(label: Text('$count'), child: Icon(icon));
  }

  // ── Drawer for infrequent controls ──────────────────────────────────

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              color: Colors.black,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'HERMES',
                    style: GoogleFonts.cinzel(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFD4AF37),
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.connection.label,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Switch Connection'),
              onTap: widget.onSwitchConnection,
            ),
            const Divider(),
            ListenableBuilder(
              listenable: ActiveRunsManager.instance,
              builder: (context, _) {
                final count = ActiveRunsManager.instance.activeRuns.length;
                return ListTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: const Text('Active Runs'),
                  trailing: count > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4AF37),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ActiveRunsScreen(connection: widget.connection),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Automations tab: Cron + Services ──────────────────────────────────

class _AutomationsTab extends StatelessWidget {
  final SavedConnection connection;
  final VoidCallback onConfigureDashboard;
  const _AutomationsTab({
    required this.connection,
    required this.onConfigureDashboard,
  });

  @override
  Widget build(BuildContext context) {
    if (!connection.isDashboardConfigured) {
      return _DashboardSetupCard(
        title: 'Automations',
        connection: connection,
        features: const ['Cron Jobs', 'Services'],
        onConfigureDashboard: onConfigureDashboard,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Automations')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _FeatureCard(
            icon: Icons.schedule,
            title: 'Cron Jobs',
            subtitle: 'Scheduled tasks and recurring jobs',
            onTap: () => _push(context, CronScreen(connection: connection)),
          ),
          _FeatureCard(
            icon: Icons.build,
            title: 'Services',
            subtitle: 'Background services and integrations',
            onTap: () => _push(context, ServicesScreen(connection: connection)),
          ),
        ],
      ),
    );
  }
}

// ── Agent tab: Memory + Skills ────────────────────────────────────────

class _AgentTab extends StatelessWidget {
  final SavedConnection connection;
  final VoidCallback onConfigureDashboard;
  const _AgentTab({
    required this.connection,
    required this.onConfigureDashboard,
  });

  @override
  Widget build(BuildContext context) {
    if (!connection.isDashboardConfigured) {
      return _DashboardSetupCard(
        title: 'Agent',
        connection: connection,
        features: const ['Memory', 'Skills'],
        onConfigureDashboard: onConfigureDashboard,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Agent')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _FeatureCard(
            icon: Icons.memory,
            title: 'Memory',
            subtitle: 'Agent memory and persistent context',
            onTap: () => _push(context, MemoryScreen(connection: connection)),
          ),
          _FeatureCard(
            icon: Icons.auto_awesome,
            title: 'Skills',
            subtitle: 'Agent capabilities and tools',
            onTap: () => _push(context, SkillsScreen(connection: connection)),
          ),
        ],
      ),
    );
  }
}

// ── More tab: Diagnostics, Settings, Active Runs, Security, Connection ─

class _MoreTab extends StatelessWidget {
  final SavedConnection connection;
  final ConnectionManager connManager;
  final bool biometricAvailable;
  final bool biometricEnabled;
  final ValueChanged<bool> onToggleBiometric;
  final VoidCallback onSwitchConnection;
  final VoidCallback onConnectionChanged;

  const _MoreTab({
    required this.connection,
    required this.connManager,
    required this.biometricAvailable,
    required this.biometricEnabled,
    required this.onToggleBiometric,
    required this.onSwitchConnection,
    required this.onConnectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _FeatureCard(
            icon: Icons.dns,
            title: 'Diagnostics',
            subtitle: 'System health, logs, and debug info',
            onTap: () =>
                _push(context, DiagnosticsScreen(connection: connection)),
          ),
          _FeatureCard(
            icon: Icons.settings,
            title: 'Settings',
            subtitle: 'Model selection, theme, and app preferences',
            onTap: () => _push(context, SettingsScreen(connection: connection)),
          ),
          ListenableBuilder(
            listenable: ActiveRunsManager.instance,
            builder: (context, _) {
              final count = ActiveRunsManager.instance.activeRuns.length;
              return _FeatureCard(
                icon: Icons.play_circle_outline,
                title: 'Active Runs',
                subtitle: 'Background tasks and pending questions',
                badge: count,
                onTap: () =>
                    _push(context, ActiveRunsScreen(connection: connection)),
              );
            },
          ),
          const Divider(),
          if (biometricAvailable)
            Card(
              child: SwitchListTile(
                secondary: Icon(
                  biometricEnabled ? Icons.lock : Icons.lock_open,
                  color: const Color(0xFFD4AF37),
                ),
                title: const Text('App Lock'),
                subtitle: const Text('Require biometric authentication'),
                value: biometricEnabled,
                onChanged: onToggleBiometric,
              ),
            ),
          _FeatureCard(
            icon: Icons.swap_horiz,
            title: 'Switch Connection',
            subtitle: 'Connect to a different Hermes server',
            onTap: onSwitchConnection,
          ),
        ],
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int? badge;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFD4AF37)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: badge != null && badge! > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              )
            : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Shown when dashboard features are not configured.
class _DashboardSetupCard extends StatelessWidget {
  final String title;
  final SavedConnection connection;
  final List<String> features;
  final VoidCallback onConfigureDashboard;

  const _DashboardSetupCard({
    required this.title,
    required this.connection,
    required this.features,
    required this.onConfigureDashboard,
  });

  @override
  Widget build(BuildContext context) {
    final featureLabel = _joinFeatures(features);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 24),
          Icon(Icons.dns_outlined, size: 52, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '$title needs dashboard access',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Chat is available through the Gateway API, but $featureLabel '
            'use the Hermes dashboard API.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CapabilityRow(
                    icon: Icons.check_circle,
                    color: Colors.green,
                    label: 'Chat',
                    value: 'Ready via ${connection.host}:${connection.port}',
                  ),
                  const Divider(height: 24),
                  _CapabilityRow(
                    icon: Icons.radio_button_unchecked,
                    color: Colors.orange,
                    label: featureLabel,
                    value:
                        'Configure dashboard at ${connection.dashboardHost}:${connection.dashboardPort}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onConfigureDashboard,
            icon: const Icon(Icons.settings_ethernet),
            label: const Text('Open Connection Settings'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () =>
                _push(context, DiagnosticsScreen(connection: connection)),
            icon: const Icon(Icons.dns),
            label: const Text('Run Diagnostics'),
          ),
          const SizedBox(height: 12),
          Text(
            'From Connection Settings, choose Dashboard / Proxy Settings and '
            'set dashboard host, port, proxy prefix, or credentials.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  String _joinFeatures(List<String> values) {
    if (values.isEmpty) return 'these features';
    if (values.length == 1) return values.first;
    return '${values.take(values.length - 1).join(', ')} and ${values.last}';
  }
}

class _CapabilityRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _CapabilityRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

void _push(BuildContext context, Widget screen) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
}
