/// Question models for LLM-driven structured questions during sessions.
///
/// Supports choice questions (single/multiple), confirmation questions,
/// text input, number, and date-time questions per the Hermes plan.
enum QuestionType {
  choiceQuestion,
  confirmationQuestion,
  textInputQuestion,
  numberQuestion,
  dateTimeQuestion,
  unknown;

  static QuestionType fromString(String? s) {
    switch (s) {
      case 'choice_question':
        return QuestionType.choiceQuestion;
      case 'confirmation_question':
        return QuestionType.confirmationQuestion;
      case 'text_input_question':
        return QuestionType.textInputQuestion;
      case 'number_question':
        return QuestionType.numberQuestion;
      case 'date_time_question':
        return QuestionType.dateTimeQuestion;
      default:
        return QuestionType.unknown;
    }
  }
}

enum QuestionMode { single, multiple, unknown }

enum QuestionStatus { pending, answered, expired, cancelled, unknown }

class QuestionOption {
  final String id;
  final String label;

  const QuestionOption({required this.id, required this.label});

  factory QuestionOption.fromJson(Map<String, dynamic> json) {
    return QuestionOption(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
    );
  }
}

class Question {
  final String id;
  final String sessionId;
  final QuestionType type;
  final String title;
  final String description;
  final QuestionMode mode;
  final QuestionStatus status;
  final List<QuestionOption> options;
  final int? minSelected;
  final int? maxSelected;
  final bool required;
  final String? submitLabel;
  final String? cancelLabel;
  final String? confirmLabel;
  final String? riskLevel;
  final String? selectedOptionId;
  final List<String> selectedOptionIds;

  const Question({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.title,
    this.description = '',
    this.mode = QuestionMode.unknown,
    this.status = QuestionStatus.pending,
    this.options = const [],
    this.minSelected,
    this.maxSelected,
    this.required = false,
    this.submitLabel,
    this.cancelLabel,
    this.confirmLabel,
    this.riskLevel,
    this.selectedOptionId,
    this.selectedOptionIds = const [],
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    final type = QuestionType.fromString(json['type'] as String?);
    final modeStr = json['mode'] as String?;
    final statusStr = json['status'] as String?;

    final optionsRaw = json['options'] as List? ?? [];
    final options = optionsRaw
        .whereType<Map<String, dynamic>>()
        .map((o) => QuestionOption.fromJson(o))
        .toList();

    final selected = json['selected_option_id']?.toString();
    final selectedList = (json['selected_option_ids'] as List?)
            ?.whereType<String>()
            .toList() ??
        const <String>[];

    return Question(
      id: json['question_id']?.toString() ?? json['id']?.toString() ?? '',
      sessionId: json['session_id']?.toString() ?? '',
      type: type,
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      mode: modeStr == 'single'
          ? QuestionMode.single
          : modeStr == 'multiple'
              ? QuestionMode.multiple
              : QuestionMode.unknown,
      status: statusStr == 'answered'
          ? QuestionStatus.answered
          : statusStr == 'expired'
              ? QuestionStatus.expired
              : statusStr == 'cancelled'
                  ? QuestionStatus.cancelled
                  : statusStr == 'pending'
                      ? QuestionStatus.pending
                      : QuestionStatus.unknown,
      options: options,
      minSelected: json['min_selected'] as int?,
      maxSelected: json['max_selected'] as int?,
      required: json['required'] as bool? ?? false,
      submitLabel: json['submit_label']?.toString(),
      cancelLabel: json['cancel_label']?.toString(),
      confirmLabel: json['confirm_label']?.toString(),
      riskLevel: json['risk_level']?.toString(),
      selectedOptionId: selected,
      selectedOptionIds: selectedList,
    );
  }

  bool get isPending => status == QuestionStatus.pending;
  bool get isAnswered => status == QuestionStatus.answered;
  bool get isSingleChoice =>
      type == QuestionType.choiceQuestion && mode == QuestionMode.single;
  bool get isMultipleChoice =>
      type == QuestionType.choiceQuestion && mode == QuestionMode.multiple;
  bool get isConfirmation => type == QuestionType.confirmationQuestion;
}
