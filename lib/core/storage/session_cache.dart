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
  String get _sessionsSyncedKey =>
      'session_cache_${_connectionId}_sessions_synced_at';
  String get _pinnedKey => 'session_cache_${_connectionId}_pinned';
  String get _archivedKey => 'session_cache_${_connectionId}_archived';
  String _messagesKey(String sessionId) =>
      'session_cache_${_connectionId}_messages_$sessionId';
  String _messagesSyncedKey(String sessionId) =>
      'session_cache_${_connectionId}_messages_${sessionId}_synced_at';

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

  /// Returns the timestamp of the last successful sessions fetch, or null
  /// if sessions have never been cached.
  DateTime? sessionsSyncedAt() {
    final ms = _prefs.getInt(_sessionsSyncedKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> saveSessions(List<Session> sessions) async {
    await _prefs.setString(
      _sessionsKey,
      jsonEncode(sessions.map(_sessionToJson).toList()),
    );
    await _prefs.setInt(
      _sessionsSyncedKey,
      DateTime.now().millisecondsSinceEpoch,
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

  /// Returns the timestamp of the last successful messages fetch for the
  /// given session, or null if messages have never been cached.
  DateTime? messagesSyncedAt(String sessionId) {
    final ms = _prefs.getInt(_messagesSyncedKey(sessionId));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> saveMessages(
    String sessionId,
    List<Map<String, dynamic>> messages,
  ) async {
    await _prefs.setString(_messagesKey(sessionId), jsonEncode(messages));
    await _prefs.setInt(
      _messagesSyncedKey(sessionId),
      DateTime.now().millisecondsSinceEpoch,
    );
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

  // ── Pin / Archive (local-only state) ────────────────────────────────

  Set<String> _loadIdSet(String key) {
    final raw = _prefs.getStringList(key);
    return raw?.toSet() ?? {};
  }

  Future<void> _saveIdSet(String key, Set<String> ids) async {
    await _prefs.setStringList(key, ids.toList());
  }

  Set<String> pinnedSessionIds() => _loadIdSet(_pinnedKey);

  bool isPinned(String sessionId) => pinnedSessionIds().contains(sessionId);

  Future<void> togglePinned(String sessionId) async {
    final ids = pinnedSessionIds();
    if (ids.contains(sessionId)) {
      ids.remove(sessionId);
    } else {
      ids.add(sessionId);
    }
    await _saveIdSet(_pinnedKey, ids);
  }

  Set<String> archivedSessionIds() => _loadIdSet(_archivedKey);

  bool isArchived(String sessionId) =>
      archivedSessionIds().contains(sessionId);

  Future<void> toggleArchived(String sessionId) async {
    final ids = archivedSessionIds();
    if (ids.contains(sessionId)) {
      ids.remove(sessionId);
    } else {
      ids.add(sessionId);
    }
    await _saveIdSet(_archivedKey, ids);
  }

  Future<void> removeFromArchive(String sessionId) async {
    final ids = archivedSessionIds();
    ids.remove(sessionId);
    await _saveIdSet(_archivedKey, ids);
  }

  // ── Full-text search over cached messages ───────────────────────────

  /// Searches cached message content for [query] across all cached sessions.
  /// Returns the set of session IDs whose messages contain the query.
  Set<String> searchMessages(String query) {
    if (query.isEmpty) return {};
    final q = query.toLowerCase();
    final results = <String>{};
    final sessions = loadSessions();
    for (final session in sessions) {
      final messages = loadMessages(session.id);
      for (final msg in messages) {
        final content = (msg['content'] as String?) ?? '';
        if (content.toLowerCase().contains(q)) {
          results.add(session.id);
          break;
        }
      }
    }
    return results;
  }

  /// Returns true if the session has any tool messages in the cache.
  bool hasToolActivity(String sessionId) {
    final messages = loadMessages(sessionId);
    return messages.any((m) => (m['role'] as String?) == 'tool');
  }

  /// Returns true if the session has any pending (unanswered) questions.
  bool hasPendingQuestion(String sessionId) {
    final messages = loadMessages(sessionId);
    for (final msg in messages) {
      final type = (msg['type'] as String?) ?? '';
      if (_isQuestionType(type)) return true;
      final questionField = msg['question'];
      if (questionField is Map<String, dynamic>) return true;
      final blocks = msg['blocks'];
      if (blocks is List) {
        for (final block in blocks) {
          if (block is Map<String, dynamic>) {
            final blockType = (block['type'] as String?) ?? '';
            if (_isQuestionType(blockType)) return true;
          }
        }
      }
    }
    return false;
  }

  bool _isQuestionType(String type) {
    return type == 'choice_question' ||
        type == 'confirmation_question' ||
        type == 'text_input_question' ||
        type == 'number_question' ||
        type == 'date_time_question';
  }
}
