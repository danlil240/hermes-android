import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/session.dart';

/// Small stale-while-revalidate cache for the data users expect immediately.
///
/// The cache is scoped by connection id so switching Hermes servers can never
/// show data from another server. SharedPreferences is used deliberately here:
/// cached data is convenience data, while the server remains authoritative.
class SessionCache {
  final SharedPreferences _prefs;
  final String _connectionId;

  SessionCache(this._prefs, this._connectionId);

  String get _sessionsKey => 'session_cache_${_connectionId}_sessions';
  String _messagesKey(String sessionId) =>
      'session_cache_${_connectionId}_messages_$sessionId';

  List<Session> loadSessions() {
    final raw = _prefs.getString(_sessionsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Session.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSessions(List<Session> sessions) async {
    await _prefs.setString(
      _sessionsKey,
      jsonEncode(sessions.map(_sessionToJson).toList()),
    );
  }

  List<Map<String, dynamic>> loadMessages(String sessionId) {
    final raw = _prefs.getString(_messagesKey(sessionId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveMessages(
    String sessionId,
    List<Map<String, dynamic>> messages,
  ) async {
    await _prefs.setString(_messagesKey(sessionId), jsonEncode(messages));
  }

  Map<String, dynamic> _sessionToJson(Session session) => {
        'id': session.id,
        'title': session.title,
        'model': session.model,
        'source': session.source,
        'message_count': session.messageCount,
        'preview': session.preview,
        'started_at': session.startedAt,
        'ended_at': session.endedAt,
      };
}
