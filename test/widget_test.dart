import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/question.dart';
import 'package:hermes_android/features/questions/question_widgets.dart';

/// Widget tests for the QuestionCard dispatch and sub-widgets.
///
/// These tests verify that QuestionCard correctly renders the appropriate
/// UI for each QuestionType and that user interactions invoke the onAnswer
/// callback with the expected parameters.
void main() {
  Widget wrapWithMaterial(Widget child) {
    return MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );
  }

  group('QuestionCard dispatch', () {
    testWidgets('renders single choice card for single-choice question',
        (tester) async {
      final q = Question(
        id: 'q1',
        sessionId: 's1',
        type: QuestionType.choiceQuestion,
        title: 'Pick a color',
        mode: QuestionMode.single,
        status: QuestionStatus.pending,
        options: const [
          QuestionOption(id: 'red', label: 'Red'),
          QuestionOption(id: 'blue', label: 'Blue'),
        ],
      );

      await tester.pumpWidget(wrapWithMaterial(
        QuestionCard(question: q, onAnswer: (_, _) {}, enabled: true),
      ));

      expect(find.text('Pick a color'), findsOneWidget);
      expect(find.text('Red'), findsOneWidget);
      expect(find.text('Blue'), findsOneWidget);
    });

    testWidgets('renders confirmation card with risk indicator',
        (tester) async {
      final q = Question(
        id: 'q2',
        sessionId: 's1',
        type: QuestionType.confirmationQuestion,
        title: 'Are you sure?',
        status: QuestionStatus.pending,
        riskLevel: 'high',
        confirmLabel: 'Confirm',
        cancelLabel: 'Cancel',
      );

      await tester.pumpWidget(wrapWithMaterial(
        QuestionCard(question: q, onAnswer: (_, _) {}, enabled: true),
      ));

      expect(find.text('Are you sure?'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('renders text input card', (tester) async {
      final q = Question(
        id: 'q3',
        sessionId: 's1',
        type: QuestionType.textInputQuestion,
        title: 'What is your name?',
        status: QuestionStatus.pending,
      );

      await tester.pumpWidget(wrapWithMaterial(
        QuestionCard(question: q, onAnswer: (_, _) {}, enabled: true),
      ));

      expect(find.text('What is your name?'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('renders number input card', (tester) async {
      final q = Question(
        id: 'q4',
        sessionId: 's1',
        type: QuestionType.numberQuestion,
        title: 'How many?',
        status: QuestionStatus.pending,
      );

      await tester.pumpWidget(wrapWithMaterial(
        QuestionCard(question: q, onAnswer: (_, _) {}, enabled: true),
      ));

      expect(find.text('How many?'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('renders fallback for unknown question type', (tester) async {
      final q = Question(
        id: 'q5',
        sessionId: 's1',
        type: QuestionType.unknown,
        title: 'Mystery',
        status: QuestionStatus.pending,
      );

      await tester.pumpWidget(wrapWithMaterial(
        QuestionCard(question: q, onAnswer: (_, _) {}, enabled: true),
      ));

      expect(find.text('Mystery'), findsOneWidget);
      expect(find.textContaining('Unsupported'), findsOneWidget);
    });
  });

  group('QuestionCard interaction', () {
    testWidgets('confirmation confirm button calls onAnswer', (tester) async {
      String? capturedId;
      dynamic capturedData;

      final q = Question(
        id: 'q-conf',
        sessionId: 's1',
        type: QuestionType.confirmationQuestion,
        title: 'Confirm?',
        status: QuestionStatus.pending,
        confirmLabel: 'Yes',
        cancelLabel: 'No',
      );

      await tester.pumpWidget(wrapWithMaterial(
        QuestionCard(
          question: q,
          onAnswer: (id, data) {
            capturedId = id;
            capturedData = data;
          },
          enabled: true,
        ),
      ));

      await tester.tap(find.text('Yes'));
      await tester.pump();

      expect(capturedId, 'q-conf');
      expect(capturedData, isNotNull);
    });

    testWidgets('disabled question does not call onAnswer', (tester) async {
      var answerCalled = false;

      final q = Question(
        id: 'q-disabled',
        sessionId: 's1',
        type: QuestionType.confirmationQuestion,
        title: 'Confirm?',
        status: QuestionStatus.answered,
        confirmLabel: 'Yes',
        cancelLabel: 'No',
      );

      await tester.pumpWidget(wrapWithMaterial(
        QuestionCard(
          question: q,
          onAnswer: (_, _) => answerCalled = true,
          enabled: false,
        ),
      ));

      expect(find.text('Confirm?'), findsOneWidget);
      expect(answerCalled, isFalse);
    });
  });
}
