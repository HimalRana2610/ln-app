import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/features/quiz/data/quiz_models.dart';
import 'package:ln_app/features/quiz/presentation/quiz_tab.dart';

QuizQuestion _question({
  QuestionStatus status = QuestionStatus.active,
  String? correctOption,
  String? myOption,
}) =>
    QuizQuestion(
      id: 'q1',
      classroomId: 'c1',
      prompt: 'Which scheduler is preemptive?',
      options: const ['FCFS', 'Round robin', 'SJF', 'None'],
      status: status,
      startedAt: DateTime.utc(2026, 9, 14, 9),
      correctOption: correctOption,
      answerCount: 3,
      myOption: myOption,
    );

Future<List<String>> _pump(
  WidgetTester tester,
  QuizState state, {
  required bool canManage,
}) async {
  final answers = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: QuizView(
          state: state,
          canManage: canManage,
          onAnswer: (question, option) async {
            answers.add(option);
            return true;
          },
          onEnd: (_) async => true,
          onAsk: (_, __, ___) async => true,
        ),
      ),
    ),
  );
  return answers;
}

bool _enabled(WidgetTester tester, String letter) => tester
    .widget<OutlinedButton>(find.byKey(ValueKey('option-$letter')))
    .enabled;

void main() {
  testWidgets('a student can answer a live question they have not answered',
      (tester) async {
    final answers =
        await _pump(tester, QuizState(active: _question()), canManage: false);

    for (final letter in quizOptionLetters) {
      expect(_enabled(tester, letter), isTrue);
    }
    // The server withholds the answer from students while live.
    expect(find.bySemanticsLabel('Correct'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('option-B')));
    expect(answers, ['B']);
  });

  testWidgets('answer buttons are disabled after answering, answer hidden',
      (tester) async {
    await _pump(
      tester,
      QuizState(active: _question(myOption: 'C')),
      canManage: false,
    );

    for (final letter in quizOptionLetters) {
      expect(_enabled(tester, letter), isFalse);
    }
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.textContaining('You answered C'), findsOneWidget);
    expect(find.text('End question'), findsNothing);
  });

  testWidgets('a teacher sees the correct option and can end the question',
      (tester) async {
    await _pump(
      tester,
      QuizState(active: _question(correctOption: 'B')),
      canManage: true,
    );

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('End question'), findsOneWidget);
    expect(_enabled(tester, 'A'), isFalse);
  });

  testWidgets('a teacher with no live question sees the composer',
      (tester) async {
    await _pump(tester, const QuizState(), canManage: true);
    expect(find.text('Ask a question'), findsOneWidget);
    expect(find.text('Option D'), findsOneWidget);
  });

  testWidgets('the leaderboard keeps the server order', (tester) async {
    // Deliberately not sorted by anything the client could recompute: equal
    // scores, the server broke the tie on penalty.
    const entries = [
      LeaderboardEntry(
          rank: 1,
          studentId: 'z',
          studentName: 'Zed',
          correct: 2,
          answered: 2,
          penaltySeconds: 4.5),
      LeaderboardEntry(
          rank: 2,
          studentId: 'a',
          studentName: 'Ada',
          correct: 2,
          answered: 2,
          penaltySeconds: 9),
      LeaderboardEntry(
          rank: 3,
          studentId: 'm',
          studentName: 'Mia',
          correct: 3,
          answered: 5,
          penaltySeconds: 1),
    ];
    await _pump(tester, const QuizState(leaderboard: entries),
        canManage: false);

    final names = tester
        .widgetList<ListTile>(find.byWidgetPredicate((widget) =>
            widget is ListTile &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('leader-')))
        .map((tile) => ((tile.title! as Text).data))
        .toList();
    expect(names, ['Zed', 'Ada', 'Mia']);
  });
}
