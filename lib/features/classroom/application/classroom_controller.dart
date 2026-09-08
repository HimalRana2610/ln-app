import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/classroom_models.dart';
import '../data/classroom_repository.dart';

final classroomRepositoryProvider = Provider<ClassroomRepository>((ref) {
  return ClassroomRepository(apiClient: ref.watch(apiClientProvider));
});

/// The signed-in user's classrooms.
///
/// An [AsyncNotifier] rather than a plain [Notifier] so loading and error
/// states are represented in the type, and the UI cannot forget to handle them.
final classroomListProvider =
    AsyncNotifierProvider<ClassroomListController, List<Classroom>>(
  ClassroomListController.new,
);

class ClassroomListController extends AsyncNotifier<List<Classroom>> {
  @override
  Future<List<Classroom>> build() async {
    // Re-fetch whenever the session changes, so signing in as someone else
    // never shows the previous user's classes.
    ref.watch(authControllerProvider);
    return ref.read(classroomRepositoryProvider).listMine();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(classroomRepositoryProvider).listMine(),
    );
  }

  /// Creates a classroom and prepends it, matching the backend's newest-first
  /// ordering without a second round trip.
  Future<Classroom> create({
    required String name,
    String? section,
    required ClassroomType type,
    required String themeColor,
  }) async {
    final classroom = await ref.read(classroomRepositoryProvider).create(
          name: name,
          section: section,
          type: type,
          themeColor: themeColor,
        );
    state = AsyncValue.data([classroom, ...state.value ?? const []]);
    return classroom;
  }

  Future<Classroom> join(String code) async {
    final classroom =
        await ref.read(classroomRepositoryProvider).joinByCode(code);
    state = AsyncValue.data([classroom, ...state.value ?? const []]);
    return classroom;
  }

  Future<void> leave(Classroom classroom) async {
    await ref.read(classroomRepositoryProvider).leave(classroom.id);
    _removeLocally(classroom.id);
  }

  Future<void> delete(Classroom classroom) async {
    await ref.read(classroomRepositoryProvider).delete(classroom.id);
    _removeLocally(classroom.id);
  }

  void _removeLocally(String classroomId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(
      current
          .where((Classroom classroom) => classroom.id != classroomId)
          .toList(),
    );
  }
}

/// Members of one classroom, keyed by classroom id.
final classroomMembersProvider =
    FutureProvider.family<List<ClassroomMember>, String>((ref, classroomId) {
  return ref.read(classroomRepositoryProvider).members(classroomId);
});
