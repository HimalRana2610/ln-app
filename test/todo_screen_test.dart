import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/features/todo/application/todo_controller.dart';
import 'package:ln_app/features/todo/data/todo_models.dart';
import 'package:ln_app/features/todo/presentation/todo_screen.dart';

ToDoItem _item(String title, ToDoStatus status, {DateTime? due}) => ToDoItem(
      postId: title,
      classroomId: 'c1',
      classroomName: 'Operating Systems',
      title: title,
      dueDate: due,
      authorName: 'Grace Hopper',
      createdAt: DateTime.utc(2026, 9, 1),
      status: status,
    );

void main() {
  test('parses the server status verbatim', () {
    final item = ToDoItem.fromJson({
      'post_id': 'p',
      'classroom_id': 'c',
      'classroom_name': 'OS',
      'title': 'Essay',
      'description': null,
      // Due long ago and not submitted, yet the server says "assigned" (say,
      // an extension). The phone must not second-guess it.
      'due_date': '2000-01-01T00:00:00Z',
      'author_name': 'Grace',
      'created_at': '2026-09-01T00:00:00Z',
      'submitted_at': null,
      'is_late': false,
      'status': 'assigned',
    });
    expect(item.status, ToDoStatus.assigned);
  });

  testWidgets('groups by the status the server sent, in server order',
      (tester) async {
    final items = [
      // A past due date on an "assigned" item: shown as assigned regardless.
      _item('Past due but assigned', ToDoStatus.assigned,
          due: DateTime.utc(2000)),
      _item('Missing one', ToDoStatus.missing, due: DateTime.utc(2099)),
      _item('Second assigned', ToDoStatus.assigned),
      _item('Handed in', ToDoStatus.done),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [toDoListProvider.overrideWith((ref) async => items)],
        child: const MaterialApp(home: ToDoScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Assigned (2)'), findsOneWidget);
    expect(find.text('Missing (1)'), findsOneWidget);
    expect(find.text('Done (1)'), findsOneWidget);

    final titles = tester
        .widgetList<ToDoTile>(find.byType(ToDoTile))
        .map((tile) => tile.item.title)
        .toList();
    expect(titles, ['Past due but assigned', 'Second assigned']);
    expect(find.text('Missing one'), findsNothing);

    await tester.tap(find.text('Missing (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Missing one'), findsOneWidget);
    expect(find.text('Missing'), findsOneWidget); // the status chip
  });
}
