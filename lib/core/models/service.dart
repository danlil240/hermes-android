/// Service models for the Hermes Services Runner.
///
/// Represents service manifests, service runs, and risk levels per the plan.

enum ServiceRiskLevel { low, medium, high, critical, unknown }

enum ServiceRunStatus {
  pending,
  awaitingConfirmation,
  running,
  completed,
  failed,
  cancelled,
  unknown,
}

/// A service definition (manifest) returned by `GET /services`.
class ServiceDefinition {
  final String id;
  final String name;
  final String category;
  final String description;
  final ServiceRiskLevel riskLevel;
  final bool requiresConfirmation;
  final int? timeoutSeconds;

  const ServiceDefinition({
    required this.id,
    required this.name,
    required this.category,
    this.description = '',
    this.riskLevel = ServiceRiskLevel.unknown,
    this.requiresConfirmation = false,
    this.timeoutSeconds,
  });

  factory ServiceDefinition.fromJson(Map<String, dynamic> json) {
    final riskStr = json['risk_level'] as String?;
    ServiceRiskLevel risk;
    switch (riskStr) {
      case 'low':
        risk = ServiceRiskLevel.low;
        break;
      case 'medium':
        risk = ServiceRiskLevel.medium;
        break;
      case 'high':
        risk = ServiceRiskLevel.high;
        break;
      case 'critical':
        risk = ServiceRiskLevel.critical;
        break;
      default:
        risk = ServiceRiskLevel.unknown;
    }

    return ServiceDefinition(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      riskLevel: risk,
      requiresConfirmation: json['requires_confirmation'] as bool? ?? false,
      timeoutSeconds: json['timeout_seconds'] as int?,
    );
  }

  /// Whether this service needs a confirmation dialog before running.
  bool get needsConfirmation =>
      requiresConfirmation || riskLevel == ServiceRiskLevel.high ||
      riskLevel == ServiceRiskLevel.critical;

  /// Whether this service requires a typed confirmation phrase.
  bool get needsTypedConfirmation =>
      riskLevel == ServiceRiskLevel.critical;
}

/// A service run returned by `POST /services/{id}/run` or `GET /service-runs/{id}`.
class ServiceRun {
  final String runId;
  final String serviceId;
  final String? sessionId;
  final ServiceRunStatus status;
  final ServiceRiskLevel riskLevel;
  final bool confirmationRequired;
  final String? resultSummary;
  final String? logsTail;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? confirmedAt;
  final DateTime? createdAt;

  const ServiceRun({
    required this.runId,
    required this.serviceId,
    this.sessionId,
    required this.status,
    this.riskLevel = ServiceRiskLevel.unknown,
    this.confirmationRequired = false,
    this.resultSummary,
    this.logsTail,
    this.startedAt,
    this.completedAt,
    this.confirmedAt,
    this.createdAt,
  });

  factory ServiceRun.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String?;
    ServiceRunStatus status;
    switch (statusStr) {
      case 'pending':
        status = ServiceRunStatus.pending;
        break;
      case 'awaiting_confirmation':
        status = ServiceRunStatus.awaitingConfirmation;
        break;
      case 'running':
        status = ServiceRunStatus.running;
        break;
      case 'completed':
        status = ServiceRunStatus.completed;
        break;
      case 'failed':
        status = ServiceRunStatus.failed;
        break;
      case 'cancelled':
        status = ServiceRunStatus.cancelled;
        break;
      default:
        status = ServiceRunStatus.unknown;
    }

    final riskStr = json['risk_level'] as String?;
    ServiceRiskLevel risk;
    switch (riskStr) {
      case 'low':
        risk = ServiceRiskLevel.low;
        break;
      case 'medium':
        risk = ServiceRiskLevel.medium;
        break;
      case 'high':
        risk = ServiceRiskLevel.high;
        break;
      case 'critical':
        risk = ServiceRiskLevel.critical;
        break;
      default:
        risk = ServiceRiskLevel.unknown;
    }

    DateTime? parseTs(dynamic v) {
      if (v == null) return null;
      final s = v.toString();
      return DateTime.tryParse(s);
    }

    return ServiceRun(
      runId: json['run_id']?.toString() ?? json['id']?.toString() ?? '',
      serviceId: json['service_id']?.toString() ?? '',
      sessionId: json['session_id']?.toString(),
      status: status,
      riskLevel: risk,
      confirmationRequired: json['confirmation_required'] as bool? ?? false,
      resultSummary: json['result_summary']?.toString(),
      logsTail: json['logs_tail']?.toString(),
      startedAt: parseTs(json['started_at']),
      completedAt: parseTs(json['completed_at']),
      confirmedAt: parseTs(json['confirmed_at']),
      createdAt: parseTs(json['created_at']),
    );
  }

  bool get isRunning => status == ServiceRunStatus.running;
  bool get isCompleted => status == ServiceRunStatus.completed;
  bool get isFailed => status == ServiceRunStatus.failed;
  bool get isAwaitingConfirmation =>
      status == ServiceRunStatus.awaitingConfirmation;
  bool get isCancelled => status == ServiceRunStatus.cancelled;
  bool get isDone =>
      isCompleted || isFailed || isCancelled;

  Duration? get duration {
    if (startedAt == null) return null;
    final end = completedAt ?? DateTime.now();
    return end.difference(startedAt!);
  }
}
