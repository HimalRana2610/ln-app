import 'package:freezed_annotation/freezed_annotation.dart';

part 'todo_models.freezed.dart';
part 'todo_models.g.dart';

/// Computed by the server. The phone never works it out itself: the old app
/// did, and a phone with a wrong clock showed the wrong status.
enum ToDoStatus {
  @JsonValue('assigned')
  assigned,
  @JsonValue('missing')
  missing,
  @JsonValue('done')
  done;

  String get label => switch (this) {
        ToDoStatus.assigned => 'Assigned',
        ToDoStatus.missing => 'Missing',
        ToDoStatus.done => 'Done',
      };
}

/// Mirrors the backend's `ToDoItem`: one assignment from one of my classes.
@freezed
abstract class ToDoItem with _$ToDoItem {
  const factory ToDoItem({
    @JsonKey(name: 'post_id') required String postId,
    @JsonKey(name: 'classroom_id') required String classroomId,
    @JsonKey(name: 'classroom_name') required String classroomName,
    required String title,
    String? description,
    @JsonKey(name: 'due_date') DateTime? dueDate,
    @JsonKey(name: 'author_name') required String authorName,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'submitted_at') DateTime? submittedAt,
    @JsonKey(name: 'is_late') @Default(false) bool isLate,
    required ToDoStatus status,
  }) = _ToDoItem;

  factory ToDoItem.fromJson(Map<String, dynamic> json) =>
      _$ToDoItemFromJson(json);
}
