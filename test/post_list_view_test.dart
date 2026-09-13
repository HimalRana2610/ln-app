import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/features/post/application/post_controller.dart';
import 'package:ln_app/features/post/data/post_models.dart';
import 'package:ln_app/features/post/presentation/post_widgets.dart';

const _classroomId = '82ad84fc-0f66-4357-a982-d46a23d592ee';

Post _assignment({DateTime? mySubmittedAt, int? submissionCount}) => Post(
      id: '11111111-2222-3333-4444-555555555555',
      classroomId: _classroomId,
      kind: PostKind.assignment,
      title: 'Implement a scheduler',
      dueDate: DateTime.utc(2099),
      authorId: '66666666-7777-8888-9999-000000000000',
      authorName: 'Grace Hopper',
      createdAt: DateTime.utc(2026, 9, 13),
      updatedAt: DateTime.utc(2026, 9, 13),
      submissionCount: submissionCount,
      mySubmittedAt: mySubmittedAt,
    );

Future<void> _pump(WidgetTester tester, Post post, {required bool canManage}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        postListProvider.overrideWith((ref, key) async => [post]),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PostListView(
            classroomId: _classroomId,
            kind: PostKind.assignment,
            canManage: canManage,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
      'a student sees their status and a submit button, no teacher controls',
      (tester) async {
    await _pump(tester, _assignment(), canManage: false);
    await tester.pumpAndSettle();

    expect(find.text('Implement a scheduler'), findsOneWidget);
    expect(find.text('Not submitted'), findsOneWidget);
    expect(find.text('Submit work'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsNothing);
    expect(find.text('View submissions'), findsNothing);
  });

  testWidgets('after submitting, a student is offered resubmission',
      (tester) async {
    await _pump(
      tester,
      _assignment(mySubmittedAt: DateTime.utc(2026, 9, 14)),
      canManage: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('Submitted'), findsOneWidget);
    expect(find.text('View or resubmit'), findsOneWidget);
  });

  testWidgets('a teacher sees the count, submissions and delete',
      (tester) async {
    await _pump(tester, _assignment(submissionCount: 3), canManage: true);
    await tester.pumpAndSettle();

    expect(find.text('3 submitted'), findsOneWidget);
    expect(find.text('View submissions'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);
    expect(find.text('Submit work'), findsNothing);
  });
}
