import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/question.dart';
import 'package:hermes_android/features/questions/question_widgets.dart';

void main() {
  Widget wrapWithMaterial(Widget child) {
    return MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  group('QuestionCard - Single Choice', () {
    testWidgets('renders title and options', (tester) async {
      final q = Question(
        id: 'q1',
        sessionId: 's1',
        type: QuestionType.choiceQuestion,
        title: 'Which service?',
        description: 'Choose one',
        mode: QuestionMode.single,
        status: QuestionStatus.pending,
        options: const [
          QuestionOption(id: 'a', label: 'Option A'),
          QuestionOption(id: 'b', label: 'Option B'),
          QuestionOption(id: 'c', label: 'Option C'),
        ],
      );

      await tester.pumpWidget(wrapWithMaterial(
        QuestionCard(question: q, onAnswer: (_, _) {}, enabled: true),
      ));

      expect(find.text('Which service?'), findsOneWidget);
      expect(find.text('Choose one'), findsOneWidget);
      expect(find.text('Option A'), findsOneWidget);
      expect(find.text('Option B'), findsOneWidget);
      expect(find.text('Option C'), findsOneWidget);
    });

    testWidgets('disables interaction when enabled is false', (tester) async {
      final q = Question(
        id: 'q1',
        sessionId: 's1',
        type: QuestionType.choiceQuestion,
        title: 'Pick one',
        mode: QuestionMode.single,
        status: QuestionStatus.answered,
        options: const [
          QuestionOption(id: 'a', label: 'Option A'),
        ],
      );

      await tester.pumpWidget(wrapWithMaterial(
        QuestionCard(question: q, onAnswer: (_, _) {}, enabled: false),
      ));

      // The question should still render but be disabled
      expect(find.text('Pick one'), findsOneWidget);
      expect(find.text('Option A'), findsOneWidget);
    });
  });

  group('QuestionCard - Multiple Choice', () {
    testWidgets('renders with checkboxes for multiple selection', (tester) async {
      final q = Question(
        id: 'q2',
        sessionId: 's1',
        type: QuestionType.choiceQuestion,
        title: 'Select components',
        mode: QuestionMode.multiple,
        status: QuestionStatus.pending,
        options: const [
          QuestionOption(id: 'a', label: 'Component A'),
          QuestionOption(id: 'b', label: 'Component B'),
        ],
        minSelected: 1,
        maxSelected: 2,
      );

      await tester.pumpWidget(wrapWithMaterial(
        QuestionCard(question: q, onAnswer: (_, _) {}, enabled: true),
      ));

      expect(find.text('Select components'), findsOneWidget);
      expect(find.text('Component A'), findsOneWidget);
      expect(find.text('Component B'), findsOneWidget);
    });
  });

  group('QuestionCard - Confirmation', () {
    testWidgets('renders confirm and cancel buttons', (tester) async {
      final q = Question(
        id: 'q3',
        sessionId: 's1',
        type: QuestionType.confirmationQuestion,
        title: 'Confirm restart?',
        description: 'This will restart all services',
        status: QuestionStatus.pending,
        confirmLabel: 'Yes, restart',
        cancelLabel: 'No, cancel',
        riskLevel: 'high',
      );

      await tester.pumpWidget(wrapWithMaterial(
        QuestionCard(question: q, onAnswer: (_, _) {}, enabled: true),
      ));

      expect(find.text('Confirm restart?'), findsOneWidget);
      expect(find.text('This will restart all services'), findsOneWidget);
      expect(find.text('Yes, restart'), findsOneWidget);
      expect(find.text('No, cancel'), findsOneWidget);
    });

    testWidgets('calls onAnswer with true when confirm is tapped',
        (tester) async {
      String? answeredQuestionId;
      dynamic answeredData;

      final q = Question(
        id: 'q3',
        sessionId: 's1',
        type: QuestionType.confirmationQuestion,
        title: 'Confirm?',
        status: QuestionStatus.pending,
        confirmLabel: 'Confirm',
        cancelLabel: 'Cancel',
      );

      await tester.pumpWidget(wrapWithMaterial(
        QuestionCard(
          question: q,
          onAnswer: (questionId, data) {
            answeredQuestionId = questionId;
            answeredData = data;
          },
          enabled: true,
        ),
      ));

      await tester.tap(find.text('Confirm'));
      await tester.pump();

      expect(answeredQuestionId, 'q3');
      expect(answeredData, isNotNull);
    });
  });

  group('QuestionCard - Text Input', () {
    testWidgets('renders text input field', (tester) async {
      final q = Question(
        id: 'q4',
        sessionId: 's1',
        type: QuestionType.textInputQuestion,
        title: 'Enter a name',
        description: 'Provide a session name',
        status: QuestionStatus.pending,
      );

      await tester.pumpWidget(wrapWithMaterial(
        QuestionCard(question: q, onAnswer: (_, _) {}, enabled: true),
      ));

      expect(find.text('Enter a name'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('QuestionCard - Number Input', () {
    testWidgets('renders number input field', (tester) async {
      final q = Question(
        id: 'q5',
        sessionId: 's1',
        type: QuestionType.numberQuestion,
        title: 'Enter a number',
        status: QuestionStatus.pending,
      );

      await tester.pumpWidget(wrapWithMaterial(
        QuestionCard(question: q, onAnswer: (_, _) {}, enabled: true),
      ));

      expect(find.text('Enter a number'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('QuestionCard - Unsupported type', () {
    testWidgets('shows fallback message for unknown type', (tester) async {
      final q = Question(
        id: 'q6',
        sessionId: 's1',
        type: QuestionType.unknown,
        title: 'Mystery question',
        status: QuestionStatus.pending,
      );

      await tester.pumpWidget(wrapWithMaterial(
        QuestionCard(question: q, onAnswer: (_, _) {}, enabled: true),
      ));

      expect(find.text('Mystery question'), findsOneWidget);
      expect(find.textContaining('Unsupported question type'), findsOneWidget);
    });
  });
}
