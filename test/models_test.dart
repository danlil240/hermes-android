import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/service.dart';
import 'package:hermes_android/core/models/question.dart';
import 'package:hermes_android/core/models/session.dart';

void main() {
  group('ServiceDefinition', () {
    test('fromJson parses all fields correctly', () {
      final svc = ServiceDefinition.fromJson({
        'id': 'restart_hermes',
        'name': 'Restart Hermes',
        'category': 'maintenance',
        'description': 'Restarts the Hermes stack',
        'risk_level': 'high',
        'requires_confirmation': true,
        'timeout_seconds': 120,
      });

      expect(svc.id, 'restart_hermes');
      expect(svc.name, 'Restart Hermes');
      expect(svc.category, 'maintenance');
      expect(svc.description, 'Restarts the Hermes stack');
      expect(svc.riskLevel, ServiceRiskLevel.high);
      expect(svc.requiresConfirmation, isTrue);
      expect(svc.timeoutSeconds, 120);
    });

    test('fromJson handles missing fields with defaults', () {
      final svc = ServiceDefinition.fromJson({});

      expect(svc.id, '');
      expect(svc.name, '');
      expect(svc.riskLevel, ServiceRiskLevel.unknown);
      expect(svc.requiresConfirmation, isFalse);
      expect(svc.timeoutSeconds, isNull);
    });

    test('needsConfirmation is true for high risk even without flag', () {
      final svc = ServiceDefinition(
        id: 'restart',
        name: 'Restart',
        category: 'maintenance',
        riskLevel: ServiceRiskLevel.high,
      );
      expect(svc.needsConfirmation, isTrue);
    });

    test('needsConfirmation is true for critical risk', () {
      final svc = ServiceDefinition(
        id: 'wipe',
        name: 'Wipe',
        category: 'danger',
        riskLevel: ServiceRiskLevel.critical,
      );
      expect(svc.needsConfirmation, isTrue);
      expect(svc.needsTypedConfirmation, isTrue);
    });

    test('needsConfirmation is false for low risk without flag', () {
      final svc = ServiceDefinition(
        id: 'status',
        name: 'Status',
        category: 'info',
        riskLevel: ServiceRiskLevel.low,
      );
      expect(svc.needsConfirmation, isFalse);
      expect(svc.needsTypedConfirmation, isFalse);
    });

    test('all risk levels parse correctly', () {
      for (final entry in {
        'low': ServiceRiskLevel.low,
        'medium': ServiceRiskLevel.medium,
        'high': ServiceRiskLevel.high,
        'critical': ServiceRiskLevel.critical,
        'unknown_val': ServiceRiskLevel.unknown,
        null: ServiceRiskLevel.unknown,
      }.entries) {
        final svc = ServiceDefinition.fromJson({
          'id': 'x',
          'name': 'x',
          'category': 'x',
          'risk_level': entry.key,
        });
        expect(svc.riskLevel, entry.value);
      }
    });
  });

  group('ServiceRun', () {
    test('fromJson parses a completed run', () {
      final run = ServiceRun.fromJson({
        'run_id': 'run-123',
        'service_id': 'restart_hermes',
        'session_id': 'sess-456',
        'status': 'completed',
        'risk_level': 'high',
        'confirmation_required': true,
        'result_summary': 'Hermes restarted successfully',
        'logs_tail': 'All services up',
        'started_at': '2024-01-15T10:00:00Z',
        'completed_at': '2024-01-15T10:01:30Z',
        'created_at': '2024-01-15T09:59:00Z',
      });

      expect(run.runId, 'run-123');
      expect(run.serviceId, 'restart_hermes');
      expect(run.sessionId, 'sess-456');
      expect(run.status, ServiceRunStatus.completed);
      expect(run.riskLevel, ServiceRiskLevel.high);
      expect(run.confirmationRequired, isTrue);
      expect(run.resultSummary, 'Hermes restarted successfully');
      expect(run.logsTail, 'All services up');
      expect(run.startedAt, isNotNull);
      expect(run.completedAt, isNotNull);
      expect(run.isCompleted, isTrue);
      expect(run.isDone, isTrue);
      expect(run.isRunning, isFalse);
    });

    test('fromJson falls back to id field when run_id is absent', () {
      final run = ServiceRun.fromJson({
        'id': 'fallback-id',
        'service_id': 'svc',
        'status': 'running',
      });
      expect(run.runId, 'fallback-id');
    });

    test('all statuses parse correctly', () {
      final cases = {
        'pending': ServiceRunStatus.pending,
        'awaiting_confirmation': ServiceRunStatus.awaitingConfirmation,
        'running': ServiceRunStatus.running,
        'completed': ServiceRunStatus.completed,
        'failed': ServiceRunStatus.failed,
        'cancelled': ServiceRunStatus.cancelled,
        'weird': ServiceRunStatus.unknown,
        null: ServiceRunStatus.unknown,
      };
      for (final entry in cases.entries) {
        final run = ServiceRun.fromJson({
          'run_id': 'r',
          'service_id': 's',
          'status': entry.key,
        });
        expect(run.status, entry.value, reason: 'status: ${entry.key}');
      }
    });

    test('isDone covers completed, failed, and cancelled', () {
      for (final status in [
        ServiceRunStatus.completed,
        ServiceRunStatus.failed,
        ServiceRunStatus.cancelled,
      ]) {
        final run = ServiceRun(
          runId: 'r',
          serviceId: 's',
          status: status,
        );
        expect(run.isDone, isTrue, reason: 'status: $status');
      }
      for (final status in [
        ServiceRunStatus.pending,
        ServiceRunStatus.running,
        ServiceRunStatus.awaitingConfirmation,
      ]) {
        final run = ServiceRun(
          runId: 'r',
          serviceId: 's',
          status: status,
        );
        expect(run.isDone, isFalse, reason: 'status: $status');
      }
    });

    test('duration is null when startedAt is null', () {
      final run = ServiceRun(
        runId: 'r',
        serviceId: 's',
        status: ServiceRunStatus.completed,
      );
      expect(run.duration, isNull);
    });

    test('duration computes from startedAt and completedAt', () {
      final start = DateTime(2024, 1, 15, 10, 0, 0);
      final end = DateTime(2024, 1, 15, 10, 1, 30);
      final run = ServiceRun(
        runId: 'r',
        serviceId: 's',
        status: ServiceRunStatus.completed,
        startedAt: start,
        completedAt: end,
      );
      expect(run.duration, const Duration(minutes: 1, seconds: 30));
    });
  });

  group('Question', () {
    test('fromJson parses a single-choice question', () {
      final q = Question.fromJson({
        'question_id': 'q-1',
        'session_id': 'sess-1',
        'type': 'choice_question',
        'title': 'Which service?',
        'description': 'Choose a service to restart',
        'mode': 'single',
        'status': 'pending',
        'options': [
          {'id': 'hermes', 'label': 'Hermes only'},
          {'id': 'agent', 'label': 'Agent only'},
          {'id': 'all', 'label': 'Everything'},
        ],
        'min_selected': 1,
        'max_selected': 1,
        'required': true,
        'submit_label': 'Confirm',
        'cancel_label': 'Cancel',
      });

      expect(q.id, 'q-1');
      expect(q.sessionId, 'sess-1');
      expect(q.type, QuestionType.choiceQuestion);
      expect(q.title, 'Which service?');
      expect(q.mode, QuestionMode.single);
      expect(q.status, QuestionStatus.pending);
      expect(q.options.length, 3);
      expect(q.options[0].id, 'hermes');
      expect(q.options[0].label, 'Hermes only');
      expect(q.minSelected, 1);
      expect(q.maxSelected, 1);
      expect(q.required, isTrue);
      expect(q.submitLabel, 'Confirm');
      expect(q.cancelLabel, 'Cancel');
      expect(q.isPending, isTrue);
      expect(q.isSingleChoice, isTrue);
      expect(q.isMultipleChoice, isFalse);
    });

    test('fromJson parses a multiple-choice question', () {
      final q = Question.fromJson({
        'id': 'q-2',
        'session_id': 'sess-1',
        'type': 'choice_question',
        'title': 'Select components',
        'mode': 'multiple',
        'status': 'pending',
        'options': [
          {'id': 'a', 'label': 'A'},
          {'id': 'b', 'label': 'B'},
        ],
        'min_selected': 1,
        'max_selected': 3,
      });

      expect(q.mode, QuestionMode.multiple);
      expect(q.isMultipleChoice, isTrue);
      expect(q.isSingleChoice, isFalse);
    });

    test('fromJson parses a confirmation question', () {
      final q = Question.fromJson({
        'id': 'q-3',
        'session_id': 'sess-1',
        'type': 'confirmation_question',
        'title': 'Confirm update?',
        'status': 'pending',
        'confirm_label': 'Yes, update',
        'cancel_label': 'No',
        'risk_level': 'high',
      });

      expect(q.type, QuestionType.confirmationQuestion);
      expect(q.isConfirmation, isTrue);
      expect(q.confirmLabel, 'Yes, update');
      expect(q.riskLevel, 'high');
    });

    test('fromJson parses an answered question with selected option', () {
      final q = Question.fromJson({
        'id': 'q-4',
        'session_id': 'sess-1',
        'type': 'choice_question',
        'title': 'Done',
        'mode': 'single',
        'status': 'answered',
        'selected_option_id': 'hermes',
        'selected_option_ids': ['hermes'],
      });

      expect(q.status, QuestionStatus.answered);
      expect(q.isAnswered, isTrue);
      expect(q.isPending, isFalse);
      expect(q.selectedOptionId, 'hermes');
      expect(q.selectedOptionIds, ['hermes']);
    });

    test('fromJson falls back to id when question_id is absent', () {
      final q = Question.fromJson({
        'id': 'fallback',
        'type': 'text_input_question',
        'title': 'Enter text',
      });
      expect(q.id, 'fallback');
      expect(q.type, QuestionType.textInputQuestion);
    });

    test('fromJson handles unknown type gracefully', () {
      final q = Question.fromJson({
        'id': 'q',
        'type': 'unknown_type',
        'title': 'x',
      });
      expect(q.type, QuestionType.unknown);
    });

    test('fromJson handles all status values', () {
      final cases = {
        'answered': QuestionStatus.answered,
        'expired': QuestionStatus.expired,
        'cancelled': QuestionStatus.cancelled,
        'pending': QuestionStatus.pending,
        'weird': QuestionStatus.unknown,
        null: QuestionStatus.unknown,
      };
      for (final entry in cases.entries) {
        final q = Question.fromJson({
          'id': 'q',
          'type': 'choice_question',
          'title': 'x',
          'status': entry.key,
        });
        expect(q.status, entry.value, reason: 'status: ${entry.key}');
      }
    });
  });

  group('Session', () {
    test('fromJson parses an active session', () {
      final s = Session.fromJson({
        'id': 'sess-1',
        'title': 'My Session',
        'model': 'llama3',
        'source': 'android',
        'message_count': 42,
        'preview': 'Hello Hermes',
        'started_at': 1705000000.0,
      });

      expect(s.id, 'sess-1');
      expect(s.title, 'My Session');
      expect(s.model, 'llama3');
      expect(s.source, 'android');
      expect(s.messageCount, 42);
      expect(s.isActive, isTrue);
      expect(s.preview, 'Hello Hermes');
      expect(s.startedAt, 1705000000.0);
      expect(s.endedAt, isNull);
    });

    test('fromJson parses an ended session', () {
      final s = Session.fromJson({
        'id': 'sess-2',
        'title': 'Old Session',
        'model': 'mistral',
        'source': 'telegram',
        'message_count': 10,
        'preview': 'Bye',
        'started_at': 1704000000.0,
        'ended_at': 1704100000.0,
      });

      expect(s.isActive, isFalse);
      expect(s.endedAt, 1704100000.0);
    });

    test('fromJson uses defaults for missing fields', () {
      final s = Session.fromJson({});

      expect(s.id, '');
      expect(s.title, 'Untitled');
      expect(s.model, 'Default');
      expect(s.source, '');
      expect(s.messageCount, 0);
      expect(s.isActive, isTrue);
      expect(s.preview, '');
      expect(s.startedAt, 0.0);
    });
  });

  group('ServiceRunStep', () {
    test('fromJson parses all fields correctly', () {
      final step = ServiceRunStep.fromJson({
        'id': 'pull',
        'label': 'Pulling code',
        'status': 'completed',
        'detail': 'Pulled 42 files',
        'started_at': '2024-01-01T10:00:00Z',
        'completed_at': '2024-01-01T10:01:00Z',
      });

      expect(step.id, 'pull');
      expect(step.label, 'Pulling code');
      expect(step.status, 'completed');
      expect(step.detail, 'Pulled 42 files');
      expect(step.startedAt, isNotNull);
      expect(step.completedAt, isNotNull);
      expect(step.isCompleted, isTrue);
      expect(step.isRunning, isFalse);
      expect(step.isPending, isFalse);
    });

    test('fromJson handles missing fields with defaults', () {
      final step = ServiceRunStep.fromJson({});

      expect(step.id, '');
      expect(step.label, '');
      expect(step.status, isNull);
      expect(step.detail, isNull);
      expect(step.isPending, isTrue);
    });

    test('status getters work correctly', () {
      expect(ServiceRunStep.fromJson({'status': 'running'}).isRunning, isTrue);
      expect(ServiceRunStep.fromJson({'status': 'failed'}).isFailed, isTrue);
      expect(ServiceRunStep.fromJson({'status': 'completed'}).isCompleted, isTrue);
      expect(ServiceRunStep.fromJson({}).isPending, isTrue);
    });
  });

  group('ServiceRunProgress', () {
    test('fromSseEvent parses log event', () {
      final progress = ServiceRunProgress.fromSseEvent(
        'hermes.service.log',
        {'run_id': 'run-123', 'log': '[INFO] Starting service...'},
      );

      expect(progress.runId, 'run-123');
      expect(progress.logLine, '[INFO] Starting service...');
      expect(progress.isLogEvent, isTrue);
      expect(progress.isStepEvent, isFalse);
      expect(progress.isStatusEvent, isFalse);
      expect(progress.isDone, isFalse);
    });

    test('fromSseEvent parses step event', () {
      final progress = ServiceRunProgress.fromSseEvent(
        'hermes.service.step',
        {
          'run_id': 'run-456',
          'step': {'id': 'build', 'label': 'Rebuilding', 'status': 'running'},
        },
      );

      expect(progress.runId, 'run-456');
      expect(progress.isStepEvent, isTrue);
      expect(progress.step, isNotNull);
      expect(progress.step!.id, 'build');
      expect(progress.step!.label, 'Rebuilding');
      expect(progress.step!.isRunning, isTrue);
      expect(progress.isLogEvent, isFalse);
    });

    test('fromSseEvent parses status event - completed', () {
      final progress = ServiceRunProgress.fromSseEvent(
        'hermes.service.status',
        {
          'run_id': 'run-789',
          'status': 'completed',
          'result_summary': 'Service finished successfully',
        },
      );

      expect(progress.runId, 'run-789');
      expect(progress.isStatusEvent, isTrue);
      expect(progress.status, ServiceRunStatus.completed);
      expect(progress.resultSummary, 'Service finished successfully');
      expect(progress.isDone, isTrue);
    });

    test('fromSseEvent parses status event - failed with error', () {
      final progress = ServiceRunProgress.fromSseEvent(
        'hermes.service.status',
        {
          'run_id': 'run-fail',
          'status': 'failed',
          'error': 'Build failed: exit code 1',
        },
      );

      expect(progress.status, ServiceRunStatus.failed);
      expect(progress.error, 'Build failed: exit code 1');
      expect(progress.isDone, isTrue);
    });

    test('fromSseEvent parses status event - cancelled', () {
      final progress = ServiceRunProgress.fromSseEvent(
        'hermes.service.status',
        {'run_id': 'run-cancel', 'status': 'cancelled'},
      );

      expect(progress.status, ServiceRunStatus.cancelled);
      expect(progress.isDone, isTrue);
    });

    test('fromSseEvent handles log via "line" key as fallback', () {
      final progress = ServiceRunProgress.fromSseEvent(
        'hermes.service.log',
        {'run_id': 'run-1', 'line': 'Alternative log key'},
      );

      expect(progress.logLine, 'Alternative log key');
      expect(progress.isLogEvent, isTrue);
    });

    test('fromSseEvent handles unknown status gracefully', () {
      final progress = ServiceRunProgress.fromSseEvent(
        'hermes.service.status',
        {'run_id': 'run-1', 'status': 'unknown_status'},
      );

      expect(progress.status, isNull);
      expect(progress.isStatusEvent, isFalse);
      expect(progress.isDone, isFalse);
    });

    test('fromSseEvent handles missing run_id gracefully', () {
      final progress = ServiceRunProgress.fromSseEvent(
        'hermes.service.log',
        {'log': 'No run ID'},
      );

      expect(progress.runId, '');
      expect(progress.logLine, 'No run ID');
    });
  });
}
