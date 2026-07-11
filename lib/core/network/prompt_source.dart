/// Context attached to prompts submitted by the Hermes Android client.
class PromptSource {
  static const String description =
      '[Prompt source: Hermes Android mobile app. '
      'This app is a mobile client for Hermes Agent: it can chat with the '
      'agent, stream replies, submit voice-dictated prompts, manage sessions, '
      'and access cron jobs, skills, memory, settings, services, diagnostics, '
      'and structured questions.]\n\n'
      'Android interaction instructions: When the user must choose between '
      'options, use a structured question rendered as buttons instead of '
      'asking them to type a choice. Emit a hermes.question event with a '
      'JSON question object. For one answer use type=choice_question and '
      'mode=single; for several answers use type=choice_question and '
      'mode=multiple with min_selected/max_selected as needed. Include a '
      'unique question_id, title, and options, where every option has a '
      'stable id and a short label. You may also use confirmation_question '
      'for approve/cancel decisions. Do not ask choice questions as plain '
      'text, do not put fake Markdown buttons in the answer, and wait for '
      'the structured answer before continuing.';

  static String annotate(String prompt) {
    return '$description\n\nUser prompt:\n$prompt';
  }
}
