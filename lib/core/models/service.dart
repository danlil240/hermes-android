// Service models for the Hermes Services Runner.
//
// Represents service manifests, service runs, and risk levels per the plan.

enum ServiceRiskLevel { low, medium, high, critical, unknown }

enum ServiceRunStatus {
  pending,
  awaitingConfirmation,
  running,
  cancellationRequested,
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

  // ── Operational metadata (from backend manifest) ──
  final List<String> systemsAffected;
  final String? expectedDuration;
  final String? riskExplanation;
  final String? prerequisites;
  final String? recoveryGuidance;
  final String? verificationServiceId;

  const ServiceDefinition({
    required this.id,
    required this.name,
    required this.category,
    this.description = '',
    this.riskLevel = ServiceRiskLevel.unknown,
    this.requiresConfirmation = false,
    this.timeoutSeconds,
    this.systemsAffected = const [],
    this.expectedDuration,
    this.riskExplanation,
    this.prerequisites,
    this.recoveryGuidance,
    this.verificationServiceId,
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

    final systemsAffected = <String>[];
    final sa = json['systems_affected'];
    if (sa is List) {
      systemsAffected.addAll(sa.map((e) => e.toString()));
    } else if (sa is String) {
      systemsAffected.add(sa);
    }

    return ServiceDefinition(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      riskLevel: risk,
      requiresConfirmation: json['requires_confirmation'] as bool? ?? false,
      timeoutSeconds: json['timeout_seconds'] as int?,
      systemsAffected: systemsAffected,
      expectedDuration: json['expected_duration']?.toString(),
      riskExplanation: json['risk_explanation']?.toString(),
      prerequisites: json['prerequisites']?.toString(),
      recoveryGuidance: json['recovery_guidance']?.toString(),
      verificationServiceId: json['verification_service_id']?.toString(),
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
      case 'cancellation_requested':
        status = ServiceRunStatus.cancellationRequested;
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
  bool get isCancellationRequested =>
      status == ServiceRunStatus.cancellationRequested;
  bool get isCancelled => status == ServiceRunStatus.cancelled;
  bool get isDone =>
      isCompleted || isFailed || isCancelled;

  Duration? get duration {
    if (startedAt == null) return null;
    final end = completedAt ?? DateTime.now();
    return end.difference(startedAt!);
  }
}

/// A single step in a multi-phase service run (e.g. "pulling code",
/// "rebuilding", "restarting").
class ServiceRunStep {
  final String id;
  final String label;
  final String? status;
  final String? detail;
  final DateTime? startedAt;
  final DateTime? completedAt;

  const ServiceRunStep({
    required this.id,
    required this.label,
    this.status,
    this.detail,
    this.startedAt,
    this.completedAt,
  });

  factory ServiceRunStep.fromJson(Map<String, dynamic> json) {
    DateTime? parseTs(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }
    return ServiceRunStep(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      status: json['status']?.toString(),
      detail: json['detail']?.toString(),
      startedAt: parseTs(json['started_at']),
      completedAt: parseTs(json['completed_at']),
    );
  }

  bool get isCompleted => status == 'completed';
  bool get isRunning => status == 'running';
  bool get isPending => status == null || status == 'pending';
  bool get isFailed => status == 'failed';
}

/// Progress event received via SSE during a service run.
class ServiceRunProgress {
  final String runId;
  final String? logLine;
  final ServiceRunStep? step;
  final ServiceRunStatus? status;
  final String? resultSummary;
  final String? error;

  const ServiceRunProgress({
    required this.runId,
    this.logLine,
    this.step,
    this.status,
    this.resultSummary,
    this.error,
  });

  factory ServiceRunProgress.fromSseEvent(
    String eventType,
    Map<String, dynamic> data,
  ) {
    ServiceRunStatus? parseStatus(String? s) {
      switch (s) {
        case 'pending':
          return ServiceRunStatus.pending;
        case 'awaiting_confirmation':
          return ServiceRunStatus.awaitingConfirmation;
        case 'running':
          return ServiceRunStatus.running;
        case 'completed':
          return ServiceRunStatus.completed;
        case 'failed':
          return ServiceRunStatus.failed;
        case 'cancellation_requested':
          return ServiceRunStatus.cancellationRequested;
        case 'cancelled':
          return ServiceRunStatus.cancelled;
        default:
          return null;
      }
    }

    final stepJson = data['step'];
    return ServiceRunProgress(
      runId: data['run_id']?.toString() ?? data['id']?.toString() ?? '',
      logLine: data['log']?.toString() ?? data['line']?.toString(),
      step: stepJson is Map<String, dynamic>
          ? ServiceRunStep.fromJson(stepJson)
          : null,
      status: parseStatus(data['status']?.toString()),
      resultSummary: data['result_summary']?.toString(),
      error: data['error']?.toString(),
    );
  }

  bool get isLogEvent => logLine != null && logLine!.isNotEmpty;
  bool get isStepEvent => step != null;
  bool get isStatusEvent => status != null;
  bool get isDone =>
      status == ServiceRunStatus.completed ||
      status == ServiceRunStatus.failed ||
      status == ServiceRunStatus.cancelled;

  bool get isCancellationRequested =>
      status == ServiceRunStatus.cancellationRequested;
}
