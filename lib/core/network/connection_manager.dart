// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'background_chat_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/connection.dart';
import '../models/service.dart';
import '../models/session.dart';
import '../storage/secure_storage.dart';

// Re-export for convenience
export '../models/connection.dart';
export '../models/service.dart';
export '../models/session.dart';

/// Result of a health check with detailed error info.
class HealthCheckResult {
  final bool ok;
  final int? statusCode;
  final String? message;

  const HealthCheckResult({
    required this.ok,
    this.statusCode,
    this.message,
  });
}

/// Manages saved remote connections using SharedPreferences for metadata
/// and [SecureStorage] for secrets (API keys, dashboard credentials).
///
/// When [secureStorage] is null (e.g. in unit tests), secrets are stored
/// alongside metadata in SharedPreferences for backward compatibility.
class ConnectionManager {
  static const String _key = 'saved_connections';
  static const Uuid _uuid = Uuid();
  final SharedPreferences prefs;
  final SecureStorage? secureStorage;

  ConnectionManager(this.prefs, [this.secureStorage]);

  bool get _useSecureStorage => secureStorage != null;

  /// One-time migration: moves secrets (API key, dashboard credentials,
  /// Cloudflare Access credentials) from SharedPreferences to SecureStorage
  /// for connections that were saved before the secure-storage change.
  ///
  /// After migration, the secrets are stripped from the prefs JSON so that
  /// only [SecureStorage] holds them going forward.
  Future<void> migrateSecretsToSecureStorage() async {
    if (!_useSecureStorage) return;
    final jsonList = prefs.getStringList(_key) ?? [];
    if (jsonList.isEmpty) return;

    final migrated = <SavedConnection>[];
    var changed = false;

    for (final j in jsonList) {
      final map = jsonDecode(j) as Map<String, dynamic>;
      final connId = map['id'] as String? ?? '';
      if (connId.isEmpty) {
        migrated.add(SavedConnection.fromMap(map));
        continue;
      }

      final apiKey = map['api_key'] as String?;
      final dashUser = map['dashboard_username'] as String?;
      final dashPass = map['dashboard_password'] as String?;
      final cfClientId = map['cf_access_client_id'] as String?;
      final cfClientSecret = map['cf_access_client_secret'] as String?;

      final hasSecretsInPrefs = (apiKey != null && apiKey.isNotEmpty) ||
          (dashUser != null && dashUser.isNotEmpty) ||
          (dashPass != null && dashPass.isNotEmpty) ||
          (cfClientId != null && cfClientId.isNotEmpty) ||
          (cfClientSecret != null && cfClientSecret.isNotEmpty);

      if (hasSecretsInPrefs) {
        final existingApiKey = await secureStorage!.readApiKey(connId);
        final existingDash =
            await secureStorage!.readDashboardCredentials(connId);
        final existingCf =
            await secureStorage!.readCfAccessCredentials(connId);

        await secureStorage!.writeConnectionSecrets(
          connectionId: connId,
          apiKey: existingApiKey?.isNotEmpty == true
              ? existingApiKey
              : apiKey,
          dashboardUsername: existingDash.username?.isNotEmpty == true
              ? existingDash.username
              : dashUser,
          dashboardPassword: existingDash.password?.isNotEmpty == true
              ? existingDash.password
              : dashPass,
          cfAccessClientId: existingCf.clientId?.isNotEmpty == true
              ? existingCf.clientId
              : cfClientId,
          cfAccessClientSecret: existingCf.clientSecret?.isNotEmpty == true
              ? existingCf.clientSecret
              : cfClientSecret,
        );
        changed = true;
      }

      map.remove('api_key');
      map.remove('dashboard_username');
      map.remove('dashboard_password');
      map.remove('cf_access_client_id');
      map.remove('cf_access_client_secret');
      migrated.add(SavedConnection.fromMap(map));
    }

    if (changed) {
      _saveAll(migrated);
    }
  }

  /// Returns connections from prefs. When [secureStorage] is active,
  /// secrets (API key, dashboard username/password) are stripped from the
  /// prefs map and must be loaded via [getConnectionsWithSecrets].
  List<SavedConnection> getConnections() {
    final jsonList = prefs.getStringList(_key) ?? [];
    return jsonList.map((j) {
      final map = jsonDecode(j) as Map<String, dynamic>;
      if (_useSecureStorage) {
        map.remove('api_key');
        map.remove('dashboard_username');
        map.remove('dashboard_password');
        map.remove('cf_access_client_id');
        map.remove('cf_access_client_secret');
      }
      return SavedConnection.fromMap(map);
    }).toList();
  }

  /// Async version that loads secrets from [SecureStorage] and merges them
  /// into the returned connections. Use this when you need the full
  /// connection with API keys (e.g. before navigating to chat).
  Future<List<SavedConnection>> getConnectionsWithSecrets() async {
    final connections = getConnections();
    if (!_useSecureStorage) return connections;
    final result = <SavedConnection>[];
    for (final conn in connections) {
      final apiKey = await secureStorage!.readApiKey(conn.id);
      final creds = await secureStorage!.readDashboardCredentials(conn.id);
      final cfCreds = await secureStorage!.readCfAccessCredentials(conn.id);
      result.add(conn.copyWith(
        apiKey: apiKey ?? '',
        dashboardUsername: creds.username,
        dashboardPassword: creds.password,
        cfAccessClientId: cfCreds.clientId,
        cfAccessClientSecret: cfCreds.clientSecret,
      ));
    }
    return result;
  }

  Future<void> saveConnection(
    String label,
    String host,
    int port,
    String apiKey, {
    String? gatewayPrefix,
    String? dashboardPrefix,
    bool dashboardProxied = false,
    int? dashboardPort,
    String? dashboardHost,
    String? dashboardUsername,
    String? dashboardPassword,
    String? cfAccessClientId,
    String? cfAccessClientSecret,
  }) async {
    final normalized = SavedConnection.normalizeHostAndPort(host, port);
    final id = _uuid.v4();
    final conn = SavedConnection(
      id: id,
      label: label,
      host: normalized.host,
      port: normalized.port,
      apiKey: apiKey,
      useHttps: normalized.useHttps,
      gatewayPrefix: gatewayPrefix,
      dashboardPrefix: dashboardPrefix,
      dashboardProxied: dashboardProxied,
      dashboardPortOverride: dashboardPort,
      dashboardHostOverride: dashboardHost,
      dashboardUsername: dashboardUsername,
      dashboardPassword: dashboardPassword,
      cfAccessClientId: cfAccessClientId,
      cfAccessClientSecret: cfAccessClientSecret,
    );
    if (_useSecureStorage) {
      await secureStorage!.writeConnectionSecrets(
        connectionId: id,
        apiKey: apiKey,
        dashboardUsername: dashboardUsername,
        dashboardPassword: dashboardPassword,
        cfAccessClientId: cfAccessClientId,
        cfAccessClientSecret: cfAccessClientSecret,
      );
    }
    final current = getConnections();
    current.insert(0, conn);
    _saveAll(current);
  }

  /// Updates the dashboard port + basic-auth credentials on an existing
  /// connection. Empty strings clear the corresponding field.
  Future<void> updateDashboardAuth(
    String connId, {
    int? dashboardPort,
    String? dashboardHost,
    required String username,
    required String password,
    String? gatewayPrefix,
    String? dashboardPrefix,
    bool? dashboardProxied,
    String? cfAccessClientId,
    String? cfAccessClientSecret,
  }) async {
    final current = getConnections();
    final idx = current.indexWhere((c) => c.id == connId);
    if (idx < 0) return;
    final u = username.trim();
    final p = password.trim();
    final gateway = gatewayPrefix?.trim();
    final dashboard = dashboardPrefix?.trim();
    final dashHost = dashboardHost?.trim();
    final cfId = cfAccessClientId?.trim();
    final cfSecret = cfAccessClientSecret?.trim();
    current[idx] = current[idx].copyWith(
      gatewayPrefix: gateway == null || gateway.isEmpty ? null : gateway,
      clearGatewayPrefix: gateway != null && gateway.isEmpty,
      dashboardPrefix: dashboard == null || dashboard.isEmpty
          ? null
          : dashboard,
      clearDashboardPrefix: dashboard != null && dashboard.isEmpty,
      dashboardProxied: dashboardProxied,
      dashboardPortOverride: dashboardPort,
      clearDashboardPort: dashboardPort == null,
      dashboardHostOverride: dashHost == null || dashHost.isEmpty ? null : dashHost,
      clearDashboardHost: dashHost != null && dashHost.isEmpty,
      dashboardUsername: u.isEmpty ? null : u,
      clearDashboardUsername: u.isEmpty,
      dashboardPassword: p.isEmpty ? null : p,
      clearDashboardPassword: p.isEmpty,
      cfAccessClientId: cfId == null || cfId.isEmpty ? null : cfId,
      clearCfAccessClientId: cfId != null && cfId.isEmpty,
      cfAccessClientSecret: cfSecret == null || cfSecret.isEmpty ? null : cfSecret,
      clearCfAccessClientSecret: cfSecret != null && cfSecret.isEmpty,
    );
    if (_useSecureStorage) {
      await secureStorage!.writeConnectionSecrets(
        connectionId: connId,
        dashboardUsername: u.isEmpty ? null : u,
        dashboardPassword: p.isEmpty ? null : p,
        cfAccessClientId: cfId == null || cfId.isEmpty ? null : cfId,
        cfAccessClientSecret: cfSecret == null || cfSecret.isEmpty ? null : cfSecret,
      );
    }
    _saveAll(current);
  }

  Future<void> updateApiKey(String connId, String apiKey) async {
    final current = getConnections();
    final idx = current.indexWhere((c) => c.id == connId);
    if (idx < 0) return;
    current[idx] = current[idx].copyWith(apiKey: apiKey);
    if (_useSecureStorage) {
      await secureStorage!.write(
        SecureStorage.apiKeyKey(connId),
        apiKey,
      );
    }
    _saveAll(current);
  }

  Future<void> deleteConnection(String id) async {
    if (_useSecureStorage) {
      await secureStorage!.deleteConnectionSecrets(id);
    }
    final current = getConnections();
    current.removeWhere((c) => c.id == id);
    _saveAll(current);
  }

  void _saveAll(List<SavedConnection> list) {
    final maps = list.map((c) {
      final map = c.toMap();
      if (_useSecureStorage) {
        map.remove('api_key');
        map.remove('dashboard_username');
        map.remove('dashboard_password');
        map.remove('cf_access_client_id');
        map.remove('cf_access_client_secret');
      }
      return jsonEncode(map);
    }).toList();
    prefs.setStringList(_key, maps);
  }
}

/// HTTP client for the Hermes Gateway API Server (port 8642).
///
/// Uses Bearer token auth. Same pattern as hermes-desktop.
class ApiClient {
  final http.Client _http;
  final String baseUrl;
  final String _apiKey;
  final String? _cfAccessClientId;
  final String? _cfAccessClientSecret;

  // Keep the public parameter name `apiKey` while storing it privately.
  ApiClient({
    required String baseUrl,
    required String apiKey,
    String pathPrefix = '',
    String? cfAccessClientId,
    String? cfAccessClientSecret,
    http.Client? httpClient,
  }) : _apiKey = apiKey,
       _cfAccessClientId = cfAccessClientId,
       _cfAccessClientSecret = cfAccessClientSecret,
       baseUrl = SavedConnection.joinBaseUrl(baseUrl, pathPrefix),
       _http = httpClient ?? http.Client();

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $_apiKey',
    'Content-Type': 'application/json',
    if (_cfAccessClientId != null && _cfAccessClientId.isNotEmpty)
      'CF-Access-Client-Id': _cfAccessClientId,
    if (_cfAccessClientSecret != null && _cfAccessClientSecret.isNotEmpty)
      'CF-Access-Client-Secret': _cfAccessClientSecret,
  };

  // ── Session listing ──────────────────────────────────────────────────

  Future<List<Session>> getSessions() async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/sessions'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['data'] as List? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((s) => Session.fromJson(s))
        .toList();
  }

  // ── Session management ───────────────────────────────────────────────

  Future<void> deleteSession(String sessionId) async {
    final res = await _http.delete(
      Uri.parse('$baseUrl/api/sessions/$sessionId'),
      headers: _headers,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  Future<void> updateSession(
    String sessionId, {
    String? title,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    final res = await _http.patch(
      Uri.parse('$baseUrl/api/sessions/$sessionId'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
  }

  // ── Messages ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMessages(String sessionId) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/sessions/$sessionId/messages'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['data'] as List? ?? [];
    return list.whereType<Map<String, dynamic>>().toList();
  }

  // ── Models ───────────────────────────────────────────────────────────

  Future<List<String>> getModels() async {
    final res = await _http.get(
      Uri.parse('$baseUrl/v1/models'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      return ['hermes-agent'];
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['data'] as List? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((m) => (m['id'] as String?) ?? 'hermes-agent')
        .toList();
  }

  // ── Health check ─────────────────────────────────────────────────────

  Future<bool> healthCheck() async {
    final result = await healthCheckDetail();
    return result.ok;
  }

  /// Like [healthCheck] but returns detailed error info for better UX.
  Future<HealthCheckResult> healthCheckDetail() async {
    try {
      final health = await _http
          .get(Uri.parse('$baseUrl/health'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (health.statusCode == 401 || health.statusCode == 403) {
        return HealthCheckResult(
          ok: false,
          statusCode: health.statusCode,
          message: 'Authentication failed (HTTP ${health.statusCode}). '
              'Check that the API key matches API_SERVER_KEY on the server.',
        );
      }
      if (health.statusCode != 200) {
        return HealthCheckResult(
          ok: false,
          statusCode: health.statusCode,
          message: 'Server returned HTTP ${health.statusCode} on /health.',
        );
      }

      final sessions = await _http
          .get(Uri.parse('$baseUrl/api/sessions'), headers: _headers)
          .timeout(const Duration(seconds: 5));
      if (sessions.statusCode == 401 || sessions.statusCode == 403) {
        return HealthCheckResult(
          ok: false,
          statusCode: sessions.statusCode,
          message: 'Authentication failed (HTTP ${sessions.statusCode}). '
              'Check that the API key matches API_SERVER_KEY on the server.',
        );
      }
      if (sessions.statusCode != 200) {
        return HealthCheckResult(
          ok: false,
          statusCode: sessions.statusCode,
          message: 'Server returned HTTP ${sessions.statusCode} on /api/sessions.',
        );
      }
      return const HealthCheckResult(ok: true);
    } on TimeoutException {
      return HealthCheckResult(
        ok: false,
        message: 'Connection timed out. Check host/port and network reachability.',
      );
    } on SocketException catch (e) {
      return HealthCheckResult(
        ok: false,
        message: 'Network error: ${e.message}. '
            'Check host/port and that the server is running.',
      );
    } catch (e) {
      return HealthCheckResult(
        ok: false,
        message: 'Connection failed: $e',
      );
    }
  }

  // ── Generic HTTP helpers (for Dashboard API compatibility) ────────────

  Future<Map<String, dynamic>> apiGet(String endpoint) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/$endpoint'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> apiGetList(String endpoint) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/$endpoint'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> apiPost(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/$endpoint'),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> apiDelete(String endpoint) async {
    final res = await _http.delete(
      Uri.parse('$baseUrl/$endpoint'),
      headers: _headers,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }

  Future<Map<String, dynamic>> apiPatch(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final res = await _http.patch(
      Uri.parse('$baseUrl/$endpoint'),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Diagnostics ──────────────────────────────────────────────────────

  /// Fetches `/status` from the Gateway API for diagnostics.
  Future<Map<String, dynamic>> getStatus() async {
    final res = await _http.get(
      Uri.parse('$baseUrl/status'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Services ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getServices() async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/services'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final data = jsonDecode(res.body);
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    if (data is Map<String, dynamic>) {
      final list = data['data'] as List? ?? [];
      return list.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> runService(String serviceId) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/services/$serviceId/run'),
      headers: _headers,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getServiceRun(String runId) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/service-runs/$runId'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> confirmServiceRun(String runId) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/service-runs/$runId/confirm'),
      headers: _headers,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> cancelServiceRun(String runId) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/service-runs/$runId/cancel'),
      headers: _headers,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Fetches past service runs for the audit log.
  /// Calls `GET /api/service-runs` with optional pagination.
  Future<List<ServiceRun>> getServiceRuns({
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _http.get(
      Uri.parse(
        '$baseUrl/api/service-runs?limit=$limit&offset=$offset',
      ),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final data = jsonDecode(res.body);
    List<dynamic> list;
    if (data is List) {
      list = data;
    } else if (data is Map<String, dynamic>) {
      list = data['data'] as List? ?? [];
    } else {
      list = [];
    }
    return list
        .whereType<Map<String, dynamic>>()
        .map((r) => ServiceRun.fromJson(r))
        .toList();
  }

  // ── Service run SSE log streaming ────────────────────────────────────

  /// Stream real-time logs and progress for a service run via Server-Sent
  /// Events. The endpoint is `GET /api/service-runs/{runId}/logs` and returns
  /// SSE frames with event types:
  ///   - `hermes.service.log`     — a single log line
  ///   - `hermes.service.step`    — a progress step update
  ///   - `hermes.service.status`  — a status change (running → completed, etc.)
  ///
  /// The stream completes when the service run reaches a terminal state
  /// (completed, failed, cancelled) or the server closes the connection.
  ///
  /// Returns a `ServiceRunStreamController` that can be listened to and
  /// cancelled.
  ServiceRunStreamController streamServiceRunLogs(
    String runId, {
    required void Function(ServiceRunProgress progress) onProgress,
    required void Function() onDone,
    required void Function(String error) onError,
  }) {
    return ServiceRunStreamController(
      ApiClient(
        baseUrl: baseUrl,
        apiKey: _apiKey,
        cfAccessClientId: _cfAccessClientId,
        cfAccessClientSecret: _cfAccessClientSecret,
        httpClient: _http,
      ),
      runId,
      onProgress: onProgress,
      onDone: onDone,
      onError: onError,
    );
  }

  // ── Questions ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getSessionQuestions(
    String sessionId,
  ) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/sessions/$sessionId/questions'),
      headers: _headers,
    );
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body);
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    if (data is Map<String, dynamic>) {
      final list = data['data'] as List? ?? [];
      return list.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> getQuestion(String questionId) async {
    final res = await _http.get(
      Uri.parse('$baseUrl/api/questions/$questionId'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> answerQuestion(
    String questionId,
    Map<String, dynamic> answer,
  ) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/api/questions/$questionId/answer'),
      headers: _headers,
      body: jsonEncode(answer),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Dashboard-compatible helpers (port 9119 endpoints, may not work on API server) ──

  Future<Map<String, dynamic>> getModelInfo() => apiGet('api/model/info');
  Future<Map<String, dynamic>> getModelOptions() => apiGet('api/model/options');
  Future<List<Map<String, dynamic>>> getSkills() async {
    final data = await apiGetList('api/skills');
    return data.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> setModel(
    String scope,
    String provider,
    String model,
  ) => apiPost(
    'api/model/set',
    body: {'scope': scope, 'provider': provider, 'model': model},
  );

  void close() => _http.close();
}

typedef ToolProgressCallback = void Function(Map<String, dynamic> progress);

typedef QuestionCallback = void Function(Map<String, dynamic> question);

/// SSE streaming chat client for the Gateway API Server.
class GatewayChatClient {
  final ApiClient _api;
  final String _baseUrl;
  final http.Client Function() _streamClientFactory;
  http.Client? _activeStreamClient;

  GatewayChatClient(
    this._api, {
    http.Client Function()? streamClientFactory,
  })  : _baseUrl = _api.baseUrl,
        _streamClientFactory = streamClientFactory ?? http.Client.new;

  /// Generate a client-side session ID: `mob-<timestamp>-<uuid>`.
  static String generateSessionId() {
    return 'mob-${DateTime.now().millisecondsSinceEpoch}-${const Uuid().v4()}';
  }

  /// Build OpenAI chat-completions messages, preserving prior history and
  /// ensuring the newly typed user message is present exactly once at the end.
  static List<Map<String, dynamic>> buildChatCompletionMessages({
    required String message,
    List<Map<String, dynamic>>? history,
  }) {
    final messages = <Map<String, dynamic>>[];
    if (history != null && history.isNotEmpty) {
      for (final msg in history) {
        final role = (msg['role'] == 'agent' || msg['role'] == 'assistant')
            ? 'assistant'
            : 'user';
        final content = msg['content']?.toString() ?? '';
        if (content.isEmpty) continue;
        messages.add({'role': role, 'content': content});
      }
    }

    final latest = message.trim();
    final alreadyLast =
        messages.isNotEmpty &&
        messages.last['role'] == 'user' &&
        messages.last['content'] == latest;
    if (latest.isNotEmpty && !alreadyLast) {
      messages.add({'role': 'user', 'content': latest});
    }
    return messages;
  }

  /// Parse one SSE frame. Returns streamed text token, or null for non-token
  /// frames. Hermes tool progress frames are delivered via [onToolProgress].
  static String? parseSseFrame(
    String frame, {
    ToolProgressCallback? onToolProgress,
    QuestionCallback? onQuestion,
  }) {
    String eventType = '';
    final dataLines = <String>[];

    for (final rawLine in frame.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty || line.startsWith(':')) continue;
      if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }

    if (dataLines.isEmpty) return null;
    final data = dataLines.join('\n').trim();
    if (data.isEmpty || data == '[DONE]') return null;

    try {
      final parsed = jsonDecode(data);
      if (eventType == 'hermes.tool.progress') {
        if (parsed is Map<String, dynamic>) onToolProgress?.call(parsed);
        return null;
      }
      if (eventType == 'hermes.question') {
        if (parsed is Map<String, dynamic>) onQuestion?.call(parsed);
        return null;
      }

      if (parsed is Map<String, dynamic>) {
        final choices = parsed['choices'] as List?;
        if (choices != null && choices.isNotEmpty && choices.first is Map) {
          final first = choices.first as Map;
          final delta = first['delta'];
          if (delta is Map) {
            final content = delta['content'];
            if (content != null && content.toString().isNotEmpty) {
              return content.toString();
            }
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Submits a server-owned run and asks Android to synchronize its status.
  ///
  /// The Android service never owns the model/tool request. POST /v1/runs
  /// returns immediately and Hermes continues the run on the server even if
  /// the phone process and its network connection disappear.
  Future<bool> startMessageInBackground({
    required String message,
    required String sessionId,
    String? model,
    List<Map<String, dynamic>>? history,
  }) {
    return BackgroundChatService.start(
      endpoint: '$_baseUrl/v1/runs',
      headers: _api._headers,
      body: jsonEncode({
        'model': model ?? 'hermes-agent',
        'input': message,
        'session_id': sessionId,
        'conversation_history': history ?? const <Map<String, dynamic>>[],
      }),
      sessionId: sessionId,
    );
  }

  /// Send a message and stream the assistant response token-by-token.
  Future<void> sendMessageStreaming({
    required String message,
    required String sessionId,
    String? model,
    List<Map<String, dynamic>>? history,
    required void Function(String token) onToken,
    ToolProgressCallback? onToolProgress,
    QuestionCallback? onQuestion,
    required void Function() onDone,
    required void Function(String error) onError,
  }) async {
    final messages = buildChatCompletionMessages(
      message: message,
      history: history,
    );

    final body = {
      'model': model ?? 'hermes-agent',
      'messages': messages,
      'stream': true,
    };

    final headers = {..._api._headers, 'X-Hermes-Session-Id': sessionId};

    final streamClient = _streamClientFactory();
    _activeStreamClient = streamClient;

    try {
      final request = http.Request(
        'POST',
        Uri.parse('$_baseUrl/v1/chat/completions'),
      );
      request.headers.addAll(headers);
      request.body = jsonEncode(body);

      final response = await streamClient.send(request);

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        String errorMsg;
        try {
          final err = jsonDecode(errorBody);
          errorMsg =
              err['error']?['message'] ??
              err['message'] ??
              'HTTP ${response.statusCode}';
        } catch (_) {
          errorMsg = 'HTTP ${response.statusCode}';
        }
        onError(errorMsg);
        return;
      }

      String buffer = '';
      await response.stream.transform(utf8.decoder).forEach((chunk) {
        buffer += chunk;
        while (buffer.contains('\n\n')) {
          final eventEnd = buffer.indexOf('\n\n');
          final frame = buffer.substring(0, eventEnd);
          buffer = buffer.substring(eventEnd + 2);

          final token = parseSseFrame(
            frame,
            onToolProgress: onToolProgress,
            onQuestion: onQuestion,
          );
          if (token != null && token.isNotEmpty) onToken(token);
        }
      });

      onDone();
    } catch (e) {
      onError(e.toString());
    } finally {
      if (identical(_activeStreamClient, streamClient)) {
        _activeStreamClient = null;
      }
      streamClient.close();
    }
  }

  void abort() {
    _activeStreamClient?.close();
    _activeStreamClient = null;
    _api.close();
  }
}

/// Client for the Hermes Dashboard REST API.
///
/// Three auth modes, picked by proxy configuration and supplied credentials:
///
///  * **Proxied dashboard** — when [proxied] is true, upstream infrastructure
///    injects auth and the app sends clean JSON requests with no dashboard
///    session token or cookie.
///  * **Password (gated) dashboard** — when [username] and [password] are set,
///    performs the `/auth/password-login` flow (provider `basic`) and
///    authenticates subsequent `/api/` calls with the returned
///    `hermes_session_at` session cookie. This is what hermes-desktop does and
///    is required when the dashboard runs with basic-auth.
///  * **Insecure (open) dashboard** — when no credentials are given, falls back
///    to scraping the ephemeral SPA session token from the homepage. Only works
///    on a dashboard started with `--insecure`.
///
/// Used for Dashboard-only features: cron, memory, skills, settings.
class DashboardClient {
  final http.Client _http;
  final String _baseUrl;
  final bool _proxied;
  final String? _username;
  final String? _password;
  final String? _cfAccessClientId;
  final String? _cfAccessClientSecret;
  String? _token;
  String? _cookie;
  // In-flight auth requests, shared so concurrent /api calls trigger a single
  // login / token fetch instead of a thundering herd (the dashboard
  // rate-limits password logins).
  Future<String>? _cookieInFlight;
  Future<String>? _tokenInFlight;

  String get baseUrl => _baseUrl;

  bool get _usesPasswordAuth =>
      (_username?.isNotEmpty ?? false) && (_password?.isNotEmpty ?? false);

  DashboardClient({
    required String host,
    int port = 9119,
    bool useHttps = false,
    String pathPrefix = '',
    bool proxied = false,
    String? username,
    String? password,
    String? cfAccessClientId,
    String? cfAccessClientSecret,
    http.Client? httpClient,
  }) : _proxied = proxied,
       _username = username,
       _password = password,
       _cfAccessClientId = cfAccessClientId,
       _cfAccessClientSecret = cfAccessClientSecret,
       _baseUrl = SavedConnection.joinBaseUrl(
         '${useHttps ? 'https' : 'http'}://$host:$port',
         pathPrefix,
       ),
       _http = httpClient ?? http.Client();

  /// Clears any cached auth state so the next request re-authenticates.
  void _resetAuth() {
    _token = null;
    _cookie = null;
    _cookieInFlight = null;
    _tokenInFlight = null;
  }

  /// Returns the session cookie, reusing a cached value or an in-flight login.
  Future<String> _getCookie() {
    final cached = _cookie;
    if (cached != null) return Future.value(cached);
    return _cookieInFlight ??= _login();
  }

  /// Logs in against the `basic` password provider and caches the session
  /// cookie. Throws on failure (bad credentials → 401, etc.).
  Map<String, String> get _cfAccessHeaders => {
    if (_cfAccessClientId != null && _cfAccessClientId.isNotEmpty)
      'CF-Access-Client-Id': _cfAccessClientId,
    if (_cfAccessClientSecret != null && _cfAccessClientSecret.isNotEmpty)
      'CF-Access-Client-Secret': _cfAccessClientSecret,
  };

  Future<String> _login() async {
    try {
      final res = await _http.post(
        Uri.parse('$_baseUrl/auth/password-login'),
        headers: {
          'Content-Type': 'application/json',
          ..._cfAccessHeaders,
        },
        body: jsonEncode({
          'provider': 'basic',
          'username': _username,
          'password': _password,
        }),
      );
      if (res.statusCode == 401) {
        throw Exception('Dashboard login failed: invalid username or password');
      }
      if (res.statusCode != 200) {
        throw Exception('Dashboard login failed: HTTP ${res.statusCode}');
      }
      final setCookie = res.headers['set-cookie'] ?? '';
      // The `http` package folds multiple Set-Cookie headers into one
      // comma-joined string; cookie expiry dates also contain commas, so match
      // the access-token cookie by name and take its value up to the first
      // delimiter. Handles the bare name plus the __Host-/__Secure- prefixes
      // Hermes uses on HTTPS binds.
      final match = RegExp(
        r'((?:__Host-|__Secure-)?hermes_session_at)=([^;,\s]+)',
      ).firstMatch(setCookie);
      if (match == null) {
        throw Exception(
          'Dashboard login succeeded but no session cookie found',
        );
      }
      _cookie = '${match.group(1)}=${match.group(2)}';
      return _cookie!;
    } finally {
      _cookieInFlight = null;
    }
  }

  /// Returns the SPA session token, reusing a cached value or an in-flight fetch.
  Future<String> _getToken() {
    final cached = _token;
    if (cached != null) return Future.value(cached);
    return _tokenInFlight ??= _fetchToken();
  }

  Future<String> _fetchToken() async {
    try {
      final res = await _http.get(
        Uri.parse('$_baseUrl/'),
        headers: _cfAccessHeaders,
      );
      if (res.statusCode != 200) throw Exception('Dashboard not reachable');
      final match = RegExp(
        r'window\.__HERMES_SESSION_TOKEN__="([^"]+)";',
      ).firstMatch(res.body);
      if (match == null) throw Exception('Session token not found');
      _token = match.group(1)!;
      return _token!;
    } finally {
      _tokenInFlight = null;
    }
  }

  Future<Map<String, String>> _authHeaders() async {
    if (_proxied) {
      return {'Content-Type': 'application/json', ..._cfAccessHeaders};
    }
    if (_usesPasswordAuth) {
      return {
        'Cookie': await _getCookie(),
        'Content-Type': 'application/json',
        ..._cfAccessHeaders,
      };
    }
    return {
      'X-Hermes-Session-Token': await _getToken(),
      'Content-Type': 'application/json',
      ..._cfAccessHeaders,
    };
  }

  Map<String, dynamic> _decodeMapResponse(http.Response res) {
    final trimmed = res.body.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }

  Future<Map<String, dynamic>> apiGet(
    String endpoint, {
    bool retried = false,
  }) async {
    final headers = await _authHeaders();
    final res = await _http.get(
      Uri.parse('$_baseUrl/api/$endpoint'),
      headers: headers,
    );
    if (res.statusCode == 401 && !retried) {
      _resetAuth();
      return apiGet(endpoint, retried: true);
    }
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return _decodeMapResponse(res);
  }

  Future<List<dynamic>> apiGetList(
    String endpoint, {
    bool retried = false,
  }) async {
    final headers = await _authHeaders();
    final res = await _http.get(
      Uri.parse('$_baseUrl/api/$endpoint'),
      headers: headers,
    );
    if (res.statusCode == 401 && !retried) {
      _resetAuth();
      return apiGetList(endpoint, retried: true);
    }
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final decoded = jsonDecode(res.body);
    if (decoded is List<dynamic>) return decoded;
    if (decoded is Map<String, dynamic> && decoded['data'] is List<dynamic>) {
      return decoded['data'] as List<dynamic>;
    }
    throw Exception('Expected list response');
  }

  Future<Map<String, dynamic>> apiPost(
    String endpoint, {
    Map<String, dynamic>? body,
    bool retried = false,
  }) async {
    final headers = await _authHeaders();
    final res = await _http.post(
      Uri.parse('$_baseUrl/api/$endpoint'),
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    );
    if (res.statusCode == 401 && !retried) {
      _resetAuth();
      return apiPost(endpoint, body: body, retried: true);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return _decodeMapResponse(res);
  }

  Future<void> apiDelete(String endpoint, {bool retried = false}) async {
    final headers = await _authHeaders();
    final res = await _http.delete(
      Uri.parse('$_baseUrl/api/$endpoint'),
      headers: headers,
    );
    if (res.statusCode == 401 && !retried) {
      _resetAuth();
      return apiDelete(endpoint, retried: true);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }

  Future<Map<String, dynamic>> apiPut(
    String endpoint, {
    Map<String, dynamic>? body,
    bool retried = false,
  }) async {
    final headers = await _authHeaders();
    final res = await _http.put(
      Uri.parse('$_baseUrl/api/$endpoint'),
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    );
    if (res.statusCode == 401 && !retried) {
      _resetAuth();
      return apiPut(endpoint, body: body, retried: true);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return _decodeMapResponse(res);
  }

  Future<Map<String, dynamic>> getModelInfo() => apiGet('model/info');
  Future<Map<String, dynamic>> getModelOptions() => apiGet('model/options');
  Future<List<Map<String, dynamic>>> getSkills() async {
    final data = await apiGetList('skills');
    return data.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> setModel(
    String scope,
    String provider,
    String model,
  ) => apiPost(
    'model/set',
    body: {'scope': scope, 'provider': provider, 'model': model},
  );

  // ── Cron job management ──────────────────────────────────────────────

  Future<Map<String, dynamic>> createJob({
    required String prompt,
    required String schedule,
    String name = '',
    String deliver = 'local',
  }) => apiPost(
    'cron/jobs',
    body: {
      'prompt': prompt,
      'schedule': schedule,
      'name': name,
      'deliver': deliver,
    },
  );

  static Map<String, dynamic> buildCronUpdateBody(
    Map<String, dynamic> updates,
  ) => {'updates': updates};

  Future<Map<String, dynamic>> updateJob(
    String jobId,
    Map<String, dynamic> updates, {
    bool retried = false,
  }) async {
    final headers = await _authHeaders();
    final res = await _http.put(
      Uri.parse('$_baseUrl/api/cron/jobs/$jobId'),
      headers: headers,
      body: jsonEncode(buildCronUpdateBody(updates)),
    );
    if (res.statusCode == 401 && !retried) {
      _resetAuth();
      return updateJob(jobId, updates, retried: true);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  void close() => _http.close();
}

/// SSE stream controller for service run logs and progress.
///
/// Connects to `GET /api/service-runs/{runId}/logs` and parses SSE frames
/// into [ServiceRunProgress] events. Automatically closes when the run
/// reaches a terminal status or the server closes the connection.
class ServiceRunStreamController {
  final ApiClient _client;
  final String _runId;
  final void Function(ServiceRunProgress progress) _onProgress;
  final void Function() _onDone;
  final void Function(String error) _onError;
  http.StreamedResponse? _response;
  StreamSubscription? _subscription;
  bool _cancelled = false;

  ServiceRunStreamController(
    this._client,
    this._runId, {
    required void Function(ServiceRunProgress progress) onProgress,
    required void Function() onDone,
    required void Function(String error) onError,
  })  : _onProgress = onProgress,
        _onDone = onDone,
        _onError = onError {
    _connect();
  }

  Future<void> _connect() async {
    if (_cancelled) return;
    try {
      final request = http.Request(
        'GET',
        Uri.parse('${_client.baseUrl}/api/service-runs/$_runId/logs'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer ${_client._apiKey}',
        'Accept': 'text/event-stream',
      });

      _response = await _client._http.send(request);

      if (_response!.statusCode != 200) {
        final errorBody = await _response!.stream.bytesToString();
        _onError('HTTP ${_response!.statusCode}: $errorBody');
        _client.close();
        return;
      }

      String buffer = '';
      _subscription = _response!.stream.transform(utf8.decoder).listen(
        (chunk) {
          buffer += chunk;
          while (buffer.contains('\n\n')) {
            final eventEnd = buffer.indexOf('\n\n');
            final frame = buffer.substring(0, eventEnd);
            buffer = buffer.substring(eventEnd + 2);
            _parseSseFrame(frame);
          }
        },
        onDone: () {
          if (!_cancelled) {
            _onDone();
          }
          _client.close();
        },
        onError: (e) {
          if (!_cancelled) {
            _onError(e.toString());
          }
          _client.close();
        },
      );
    } catch (e) {
      if (!_cancelled) {
        _onError(e.toString());
      }
      _client.close();
    }
  }

  void _parseSseFrame(String frame) {
    String eventType = '';
    final dataLines = <String>[];

    for (final rawLine in frame.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty || line.startsWith(':')) continue;
      if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }

    if (dataLines.isEmpty) return;
    final data = dataLines.join('\n').trim();
    if (data.isEmpty || data == '[DONE]') return;

    try {
      final parsed = jsonDecode(data);
      if (parsed is Map<String, dynamic>) {
        final progress = ServiceRunProgress.fromSseEvent(eventType, parsed);
        _onProgress(progress);
        if (progress.isDone) {
          _cancelled = true;
          _subscription?.cancel();
          _onDone();
          _client.close();
        }
      }
    } catch (_) {
      // Ignore malformed frames
    }
  }

  /// Cancel the stream and clean up resources.
  void cancel() {
    _cancelled = true;
    _subscription?.cancel();
    _client.close();
  }
}
