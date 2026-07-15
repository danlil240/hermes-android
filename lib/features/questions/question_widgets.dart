// Question renderer widgets for LLM-driven structured questions.
//
// Supports:
//   - choice_question mode=single   → large tap-to-answer choice buttons
//   - choice_question mode=multiple  → checkboxes + submit button
//   - confirmation_question          → confirm/cancel card
//   - text_input_question            → text field + submit button
//   - number_question                → numeric input
//   - date_time_question             → date/time picker
//
// These are reusable widgets designed to be embedded in chat message lists.
import 'package:flutter/material.dart';
import '../../core/models/question.dart';

/// Callback when a question is answered.
/// [answer] contains the answer payload to POST to /questions/{id}/answer.
typedef QuestionAnswerCallback = void Function(
  String questionId,
  Map<String, dynamic> answer,
);

/// Main question renderer — picks the right widget based on [Question.type].
class QuestionCard extends StatefulWidget {
  final Question question;
  final QuestionAnswerCallback onAnswer;
  final bool enabled;

  const QuestionCard({
    required this.question,
    required this.onAnswer,
    this.enabled = true,
    super.key,
  });

  @override
  State<QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<QuestionCard> {
  @override
  Widget build(BuildContext context) {
    final q = widget.question;

    if (q.isSingleChoice) {
      return _SingleChoiceCard(
        question: q,
        onAnswer: widget.onAnswer,
        enabled: widget.enabled && q.isPending,
      );
    }
    if (q.isMultipleChoice) {
      return _MultipleChoiceCard(
        question: q,
        onAnswer: widget.onAnswer,
        enabled: widget.enabled && q.isPending,
      );
    }
    if (q.isConfirmation) {
      return _ConfirmationCard(
        question: q,
        onAnswer: widget.onAnswer,
        enabled: widget.enabled && q.isPending,
      );
    }
    if (q.type == QuestionType.textInputQuestion) {
      return _TextInputCard(
        question: q,
        onAnswer: widget.onAnswer,
        enabled: widget.enabled && q.isPending,
      );
    }
    if (q.type == QuestionType.numberQuestion) {
      return _NumberInputCard(
        question: q,
        onAnswer: widget.onAnswer,
        enabled: widget.enabled && q.isPending,
      );
    }
    if (q.type == QuestionType.dateTimeQuestion) {
      return _DateTimeCard(
        question: q,
        onAnswer: widget.onAnswer,
        enabled: widget.enabled && q.isPending,
      );
    }

    // Fallback: show raw title
    return _QuestionContainer(
      title: q.title,
      description: q.description,
      child: Text(
        'Unsupported question type: ${q.type.name}',
        style: TextStyle(color: Colors.grey[600], fontSize: 13),
      ),
    );
  }
}

/// Shared container for all question types.
class _QuestionContainer extends StatelessWidget {
  final String title;
  final String description;
  final Widget child;
  final Color? accentColor;

  const _QuestionContainer({
    required this.title,
    required this.child,
    this.description = '',
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = accentColor ?? const Color(0xFFD4AF37);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width - 80,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.3), width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline, size: 18, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Single-choice question — large choice buttons.
class _SingleChoiceCard extends StatefulWidget {
  final Question question;
  final QuestionAnswerCallback onAnswer;
  final bool enabled;

  const _SingleChoiceCard({
    required this.question,
    required this.onAnswer,
    required this.enabled,
  });

  @override
  State<_SingleChoiceCard> createState() => _SingleChoiceCardState();
}

class _SingleChoiceCardState extends State<_SingleChoiceCard> {
  // The option the user just tapped (before the server confirms). Lets us
  // highlight the choice immediately even while the answer is in flight.
  String? _pending;

  void _answer(String optionId) {
    if (!widget.enabled) return;
    setState(() => _pending = optionId);
    widget.onAnswer(widget.question.id, {
      'selected_option_id': optionId,
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final answered = q.isAnswered;
    final selectedId = answered ? q.selectedOptionId : _pending;
    // Once answered (or an answer is in flight) the options become read-only.
    final locked = answered || _pending != null || !widget.enabled;

    return _QuestionContainer(
      title: q.title,
      description: q.description,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...q.options.map((option) {
            final isSelected = selectedId == option.id;
            // Dim unpicked options after a choice is locked in.
            final dimmed = locked && !isSelected;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  // Single press = submit immediately. Disabled once locked.
                  onPressed: locked ? null : () => _answer(option.id),
                  style: FilledButton.styleFrom(
                    backgroundColor: isSelected
                        ? const Color(0xFFD4AF37).withValues(alpha: 0.25)
                        : null,
                    foregroundColor: isSelected
                        ? const Color(0xFFD4AF37)
                        : dimmed
                            ? Colors.grey
                            : null,
                    disabledBackgroundColor: isSelected
                        ? const Color(0xFFD4AF37).withValues(alpha: 0.25)
                        : Colors.transparent,
                    disabledForegroundColor: isSelected
                        ? const Color(0xFFD4AF37)
                        : Colors.grey,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        size: 18,
                        color: isSelected
                            ? const Color(0xFFD4AF37)
                            : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(option.label)),
                    ],
                  ),
                ),
              ),
            );
          }),
          if (!answered && widget.enabled && _pending == null && q.cancelLabel != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => widget.onAnswer(q.id, {'cancelled': true}),
                child: Text(q.cancelLabel!),
              ),
            ),
          ],
          if (selectedId != null && selectedId.isNotEmpty)
            _AnswerSummary(labels: [q.labelForOption(selectedId)]),
        ],
      ),
    );
  }
}

/// Multiple-choice question — checkboxes + submit.
class _MultipleChoiceCard extends StatefulWidget {
  final Question question;
  final QuestionAnswerCallback onAnswer;
  final bool enabled;

  const _MultipleChoiceCard({
    required this.question,
    required this.onAnswer,
    required this.enabled,
  });

  @override
  State<_MultipleChoiceCard> createState() => _MultipleChoiceCardState();
}

class _MultipleChoiceCardState extends State<_MultipleChoiceCard> {
  final Set<String> _selected = {};

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        final max = widget.question.maxSelected;
        if (max != null && _selected.length >= max) return;
        _selected.add(id);
      }
    });
  }

  void _submit() {
    if (_selected.isEmpty) return;
    final min = widget.question.minSelected ?? 0;
    if (_selected.length < min) return;
    widget.onAnswer(widget.question.id, {
      'selected_option_ids': _selected.toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final answered = q.isAnswered;
    final selectedIds = answered ? q.selectedOptionIds.toSet() : _selected;

    return _QuestionContainer(
      title: q.title,
      description: q.description,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...q.options.map((option) {
            final isSelected = selectedIds.contains(option.id);
            return Material(
              color: Colors.transparent,
              child: CheckboxListTile(
                value: isSelected,
                onChanged: widget.enabled ? (_) => _toggle(option.id) : null,
                title: Text(option.label),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: const Color(0xFFD4AF37),
              ),
            );
          }),
          if (q.minSelected != null || q.maxSelected != null) ...[
            const SizedBox(height: 4),
            Text(
              _buildRangeLabel(),
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
          if (!answered && widget.enabled) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (q.cancelLabel != null)
                  TextButton(
                    onPressed: () => widget.onAnswer(q.id, {'cancelled': true}),
                    child: Text(q.cancelLabel!),
                  ),
                if (q.submitLabel != null || q.cancelLabel == null)
                  FilledButton(
                    onPressed: _canSubmit() ? _submit : null,
                    child: Text(q.submitLabel ?? 'Submit'),
                  ),
              ],
            ),
          ],
          if (answered && q.selectedLabels.isNotEmpty)
            _AnswerSummary(labels: q.selectedLabels),
        ],
      ),
    );
  }

  String _buildRangeLabel() {
    final min = widget.question.minSelected;
    final max = widget.question.maxSelected;
    if (min != null && max != null) {
      return 'Select $min–$max options';
    }
    if (min != null) return 'Select at least $min';
    if (max != null) return 'Select up to $max';
    return '';
  }

  bool _canSubmit() {
    if (_selected.isEmpty) return false;
    final min = widget.question.minSelected ?? 0;
    return _selected.length >= min;
  }
}

/// Confirmation question — confirm/cancel card.
class _ConfirmationCard extends StatelessWidget {
  final Question question;
  final QuestionAnswerCallback onAnswer;
  final bool enabled;

  const _ConfirmationCard({
    required this.question,
    required this.onAnswer,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final q = question;
    final answered = q.isAnswered;
    final riskColor = _riskColor(q.riskLevel);

    return _QuestionContainer(
      title: q.title,
      description: q.description,
      accentColor: riskColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (q.riskLevel != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: riskColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: riskColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                q.riskLevel!.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  color: riskColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (!answered && enabled)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        onAnswer(q.id, {'cancelled': true}),
                    child: Text(q.cancelLabel ?? 'Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        onAnswer(q.id, {'confirmed': true}),
                    style: FilledButton.styleFrom(backgroundColor: riskColor),
                    child: Text(q.confirmLabel ?? 'Confirm'),
                  ),
                ),
              ],
            ),
          if (answered)
            Text(
              'Answered',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  Color _riskColor(String? risk) {
    switch (risk) {
      case 'low':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'high':
        return Colors.deepOrange;
      case 'critical':
        return Colors.red;
      default:
        return const Color(0xFFD4AF37);
    }
  }
}

/// Text input question — text field + submit.
class _TextInputCard extends StatefulWidget {
  final Question question;
  final QuestionAnswerCallback onAnswer;
  final bool enabled;

  const _TextInputCard({
    required this.question,
    required this.onAnswer,
    required this.enabled,
  });

  @override
  State<_TextInputCard> createState() => _TextInputCardState();
}

class _TextInputCardState extends State<_TextInputCard> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onAnswer(widget.question.id, {'text': text});
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final answered = q.isAnswered;

    return _QuestionContainer(
      title: q.title,
      description: q.description,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!answered && widget.enabled) ...[
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (q.cancelLabel != null)
                  TextButton(
                    onPressed: () =>
                        widget.onAnswer(q.id, {'cancelled': true}),
                    child: Text(q.cancelLabel!),
                  ),
                FilledButton(
                  onPressed: _submit,
                  child: Text(q.submitLabel ?? 'Submit'),
                ),
              ],
            ),
          ],
          if (answered)
            const _AnswerSummary(labels: ['Answered']),
        ],
      ),
    );
  }
}

/// Number input question — numeric input + submit.
class _NumberInputCard extends StatefulWidget {
  final Question question;
  final QuestionAnswerCallback onAnswer;
  final bool enabled;

  const _NumberInputCard({
    required this.question,
    required this.onAnswer,
    required this.enabled,
  });

  @override
  State<_NumberInputCard> createState() => _NumberInputCardState();
}

class _NumberInputCardState extends State<_NumberInputCard> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    final num = double.tryParse(text);
    if (num == null) return;
    widget.onAnswer(widget.question.id, {'number': num});
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final answered = q.isAnswered;

    return _QuestionContainer(
      title: q.title,
      description: q.description,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!answered && widget.enabled) ...[
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (q.cancelLabel != null)
                  TextButton(
                    onPressed: () =>
                        widget.onAnswer(q.id, {'cancelled': true}),
                    child: Text(q.cancelLabel!),
                  ),
                FilledButton(
                  onPressed: _submit,
                  child: Text(q.submitLabel ?? 'Submit'),
                ),
              ],
            ),
          ],
          if (answered)
            const _AnswerSummary(labels: ['Confirmed']),
        ],
      ),
    );
  }
}

/// Date/time question — date/time picker + submit.
class _DateTimeCard extends StatefulWidget {
  final Question question;
  final QuestionAnswerCallback onAnswer;
  final bool enabled;

  const _DateTimeCard({
    required this.question,
    required this.onAnswer,
    required this.enabled,
  });

  @override
  State<_DateTimeCard> createState() => _DateTimeCardState();
}

class _DateTimeCardState extends State<_DateTimeCard> {
  DateTime? _selected;

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selected ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    setState(() => _selected = date);
  }

  Future<void> _pickTime() async {
    if (_selected == null) {
      setState(() => _selected = DateTime.now());
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selected ?? DateTime.now()),
    );
    if (time == null || !mounted) return;
    setState(() {
      _selected = DateTime(
        _selected!.year,
        _selected!.month,
        _selected!.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _submit() {
    if (_selected == null) return;
    widget.onAnswer(widget.question.id, {
      'datetime': _selected!.toIso8601String(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final answered = q.isAnswered;

    return _QuestionContainer(
      title: q.title,
      description: q.description,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!answered && widget.enabled) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      _selected != null
                          ? '${_selected!.day}/${_selected!.month}/${_selected!.year}'
                          : 'Pick date',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time, size: 18),
                    label: Text(
                      _selected != null
                          ? '${_selected!.hour.toString().padLeft(2, '0')}:${_selected!.minute.toString().padLeft(2, '0')}'
                          : 'Pick time',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (q.cancelLabel != null)
                  TextButton(
                    onPressed: () =>
                        widget.onAnswer(q.id, {'cancelled': true}),
                    child: Text(q.cancelLabel!),
                  ),
                FilledButton(
                  onPressed: _selected == null ? null : _submit,
                  child: Text(q.submitLabel ?? 'Submit'),
                ),
              ],
            ),
          ],
          if (answered)
            const _AnswerSummary(labels: ['Answered']),
        ],
      ),
    );
  }
}

/// Compact "your answer" banner shown once a question is answered.
///
/// Makes the user's choice clearly visible in the chat history instead of a
/// faint "Answered" id line.
class _AnswerSummary extends StatelessWidget {
  final List<String> labels;

  const _AnswerSummary({required this.labels});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFD4AF37);
    final text = labels.where((l) => l.isNotEmpty).join(', ');
    if (text.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 16, color: accent),
          const SizedBox(width: 6),
          Text(
            'Your answer: ',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
