import 'package:flutter/foundation.dart';

/// Type of active run.
enum ActiveRunType {
  chat,
  service,
  question,
  reconnecting,
}

/// Status of an active run.
enum ActiveRunStatus {
  running,
  pending,
  reconnecting,
  awaitingConfirmation,
  cancellationRequested,
  completed,
  failed,
  cancelled,
}

/// A unified representation of any background work the user might want to track.
class ActiveRun {
  final String id;
  final ActiveRunType type;
  final ActiveRunStatus status;
  final String connectionId;
  final String connectionLabel;
  final String sessionId;
  final String? sessionTitle;
  final String title;
  final String? lastAction;
  final DateTime startedAt;
  final DateTime? completedAt;

  const ActiveRun({
    required this.id,
    required this.type,
    required this.status,
    required this.connectionId,
    required this.connectionLabel,
    required this.sessionId,
    this.sessionTitle,
    required this.title,
    this.lastAction,
    required this.startedAt,
    this.completedAt,
  });

  bool get isActive =>
      status == ActiveRunStatus.running ||
      status == ActiveRunStatus.pending ||
      status == ActiveRunStatus.reconnecting ||
      status == ActiveRunStatus.awaitingConfirmation ||
      status == ActiveRunStatus.cancellationRequested;

  Duration get elapsed {
    final end = completedAt ?? DateTime.now();
    return end.difference(startedAt);
  }

  String get elapsedLabel {
    final d = elapsed;
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    }
    return '${d.inSeconds}s';
  }

  String get typeLabel {
    switch (type) {
      case ActiveRunType.chat:
        return 'Chat';
      case ActiveRunType.service:
        return 'Service';
      case ActiveRunType.question:
        return 'Question';
      case ActiveRunType.reconnecting:
        return 'Reconnecting';
    }
  }

  String get statusLabel {
    switch (status) {
      case ActiveRunStatus.running:
        return 'Running';
      case ActiveRunStatus.pending:
        return 'Pending';
      case ActiveRunStatus.reconnecting:
        return 'Reconnecting';
      case ActiveRunStatus.awaitingConfirmation:
        return 'Awaiting confirmation';
      case ActiveRunStatus.cancellationRequested:
        return 'Cancellation requested';
      case ActiveRunStatus.completed:
        return 'Completed';
      case ActiveRunStatus.failed:
        return 'Failed';
      case ActiveRunStatus.cancelled:
        return 'Cancelled';
    }
  }

  ActiveRun copyWith({
    ActiveRunStatus? status,
    String? title,
    String? lastAction,
    DateTime? completedAt,
    String? sessionTitle,
  }) {
    return ActiveRun(
      id: id,
      type: type,
      status: status ?? this.status,
      connectionId: connectionId,
      connectionLabel: connectionLabel,
      sessionId: sessionId,
      sessionTitle: sessionTitle ?? this.sessionTitle,
      title: title ?? this.title,
      lastAction: lastAction ?? this.lastAction,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

/// Singleton manager that tracks all active background work across the app.
///
/// Chat screens, service screens, and connection managers report state here
/// so that a unified "Active Runs" surface can show everything in one place.
class ActiveRunsManager extends ChangeNotifier {
  ActiveRunsManager._();
  static final ActiveRunsManager instance = ActiveRunsManager._();

  final Map<String, ActiveRun> _runs = {};

  List<ActiveRun> get runs => _runs.values.toList()
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  List<ActiveRun> get activeRuns =>
      runs.where((r) => r.isActive).toList();

  bool get hasActiveRuns => activeRuns.isNotEmpty;

  /// Register or update a chat run.
  void updateChatRun({
    required String sessionId,
    required String connectionId,
    required String connectionLabel,
    String? sessionTitle,
    ActiveRunStatus status = ActiveRunStatus.running,
    String? lastAction,
  }) {
    final id = 'chat:$connectionId:$sessionId';
    final existing = _runs[id];
    if (existing != null && !existing.isActive) return;

    _runs[id] = ActiveRun(
      id: id,
      type: ActiveRunType.chat,
      status: status,
      connectionId: connectionId,
      connectionLabel: connectionLabel,
      sessionId: sessionId,
      sessionTitle: sessionTitle,
      title: sessionTitle ?? 'Chat',
      lastAction: lastAction ?? existing?.lastAction,
      startedAt: existing?.startedAt ?? DateTime.now(),
      completedAt: status == ActiveRunStatus.completed ||
              status == ActiveRunStatus.failed ||
              status == ActiveRunStatus.cancelled
          ? DateTime.now()
          : null,
    );
    notifyListeners();
  }

  /// Register or update a service run.
  void updateServiceRun({
    required String runId,
    required String serviceId,
    required String connectionId,
    required String connectionLabel,
    String? sessionId,
    ActiveRunStatus status = ActiveRunStatus.running,
    String? lastAction,
  }) {
    final id = 'service:$runId';
    final existing = _runs[id];

    _runs[id] = ActiveRun(
      id: id,
      type: ActiveRunType.service,
      status: status,
      connectionId: connectionId,
      connectionLabel: connectionLabel,
      sessionId: sessionId ?? existing?.sessionId ?? '',
      title: serviceId,
      lastAction: lastAction ?? existing?.lastAction,
      startedAt: existing?.startedAt ?? DateTime.now(),
      completedAt: status == ActiveRunStatus.completed ||
              status == ActiveRunStatus.failed ||
              status == ActiveRunStatus.cancelled
          ? DateTime.now()
          : null,
    );
    notifyListeners();
  }

  /// Register or update a pending question.
  void updateQuestion({
    required String questionId,
    required String sessionId,
    required String connectionId,
    required String connectionLabel,
    String? sessionTitle,
    String? questionText,
    bool resolved = false,
  }) {
    final id = 'question:$questionId';
    if (resolved) {
      _runs.remove(id);
      notifyListeners();
      return;
    }

    final existing = _runs[id];
    _runs[id] = ActiveRun(
      id: id,
      type: ActiveRunType.question,
      status: ActiveRunStatus.awaitingConfirmation,
      connectionId: connectionId,
      connectionLabel: connectionLabel,
      sessionId: sessionId,
      sessionTitle: sessionTitle,
      title: questionText ?? 'Pending question',
      lastAction: 'Awaiting your answer',
      startedAt: existing?.startedAt ?? DateTime.now(),
    );
    notifyListeners();
  }

  /// Register a reconnecting job.
  void updateReconnecting({
    required String connectionId,
    required String connectionLabel,
    bool resolved = false,
  }) {
    final id = 'reconnect:$connectionId';
    if (resolved) {
      _runs.remove(id);
      notifyListeners();
      return;
    }

    final existing = _runs[id];
    if (existing != null && !existing.isActive) return;

    _runs[id] = ActiveRun(
      id: id,
      type: ActiveRunType.reconnecting,
      status: ActiveRunStatus.reconnecting,
      connectionId: connectionId,
      connectionLabel: connectionLabel,
      sessionId: '',
      title: 'Reconnecting to $connectionLabel',
      lastAction: 'Retrying connection',
      startedAt: existing?.startedAt ?? DateTime.now(),
    );
    notifyListeners();
  }

  /// Remove a run by id.
  void remove(String id) {
    if (_runs.remove(id) != null) notifyListeners();
  }

  /// Clear all completed/failed/cancelled runs.
  void clearFinished() {
    final before = _runs.length;
    _runs.removeWhere((_, r) => !r.isActive);
    if (_runs.length != before) notifyListeners();
  }

  /// Get the active chat run for a session, if any.
  ActiveRun? chatRunFor(String connectionId, String sessionId) {
    final id = 'chat:$connectionId:$sessionId';
    return _runs[id];
  }
}
