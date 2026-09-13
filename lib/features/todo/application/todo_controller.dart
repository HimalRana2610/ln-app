import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/todo_models.dart';
import '../data/todo_repository.dart';

final toDoRepositoryProvider = Provider<ToDoRepository>((ref) {
  return ToDoRepository(apiClient: ref.watch(apiClientProvider));
});

final toDoListProvider = FutureProvider<List<ToDoItem>>((ref) {
  return ref.read(toDoRepositoryProvider).list();
});
