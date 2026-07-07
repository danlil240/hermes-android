# Choice Questions

The LLM can pause mid-session and ask a **structured** question rendered as
buttons — not fragile free text (plan §14–§18).

## Message block model

```text
Message
  ├── TextBlock
  ├── ChoiceQuestionBlock
  ├── ConfirmationQuestionBlock
  ├── ServiceProgressBlock
  ├── ServiceResultBlock
  └── ErrorBlock
```

## Single choice

```json
{
  "type": "choice_question",
  "question_id": "q_001",
  "session_id": "s_123",
  "title": "What should I update?",
  "mode": "single",
  "required": true,
  "options": [
    { "id": "hermes", "label": "Hermes only" },
    { "id": "cloudflared", "label": "Cloudflare Tunnel only" },
    { "id": "ollama", "label": "Model server only" },
    { "id": "everything", "label": "Everything" }
  ]
}
```

## Multiple choice

```json
{
  "type": "choice_question",
  "question_id": "q_002",
  "session_id": "s_123",
  "title": "Which components should I restart?",
  "mode": "multiple",
  "min_selected": 1,
  "max_selected": 4,
  "options": [
    { "id": "gateway", "label": "Gateway" },
    { "id": "agent", "label": "Agent" },
    { "id": "cloudflared", "label": "Cloudflare Tunnel" },
    { "id": "ollama", "label": "Ollama" }
  ],
  "submit_label": "Restart selected",
  "cancel_label": "Cancel"
}
```

## Confirmation

```json
{
  "type": "confirmation_question",
  "question_id": "q_003",
  "session_id": "s_123",
  "title": "Confirm restart",
  "description": "Hermes will restart and the app may disconnect for a few seconds.",
  "confirm_label": "Restart Hermes",
  "cancel_label": "Cancel",
  "risk_level": "high"
}
```

## Android renderers (`lib/features/questions/`)

```text
choice_question mode=single    → radio / large choice buttons
choice_question mode=multiple  → checkboxes + submit
confirmation_question          → confirm/cancel card (typed phrase for critical)
```

## Flow

```text
user message → agent needs info → question engine creates question block
→ gateway sends block → app renders buttons → user answers
→ POST /questions/{id}/answer → agent run resumes
```
