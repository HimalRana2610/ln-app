import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../note/application/note_controller.dart';
import '../data/post_models.dart';
import '../data/post_repository.dart';

final postRepositoryProvider = Provider<PostRepository>((ref) {
  return PostRepository(apiClient: ref.watch(apiClientProvider));
});

/// A classroom's posts of one kind, keyed by `(classroomId, kind)`.
final postListProvider =
    FutureProvider.family<List<Post>, (String, PostKind)>((ref, key) {
  final (classroomId, kind) = key;
  return ref.read(postRepositoryProvider).list(classroomId, kind);
});

/// Every submission for an assignment. Teachers only.
final submissionsProvider =
    FutureProvider.family<List<Submission>, String>((ref, postId) {
  return ref.read(postRepositoryProvider).listSubmissions(postId);
});

/// The signed-in student's submission, or null.
final mySubmissionProvider =
    FutureProvider.family<Submission?, String>((ref, postId) {
  return ref.read(postRepositoryProvider).mySubmission(postId);
});

/// Actions on a classroom's posts.
///
/// Like `NoteActions`, each refreshes from the server afterwards instead of
/// patching lists in memory, so a screen cannot drift from what is stored.
class PostActions {
  const PostActions(this._ref, this.classroomId);

  final Ref _ref;
  final String classroomId;

  PostRepository get _repository => _ref.read(postRepositoryProvider);

  void _refresh(PostKind kind) =>
      _ref.invalidate(postListProvider((classroomId, kind)));

  /// Presign and PUT straight to storage; only the asset id reaches the API.
  Future<String> _upload(
    File file, {
    required String filename,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final notes = _ref.read(noteRepositoryProvider);
    final slot = await notes.presignUpload(
      filename: filename,
      contentType: contentType,
      sizeBytes: await file.length(),
      purpose: 'attachment',
    );
    await notes.uploadFile(slot: slot, file: file, onProgress: onProgress);
    return slot.assetId;
  }

  Future<void> create({
    required PostKind kind,
    required String title,
    String? description,
    DateTime? dueDate,
    File? file,
    String? filename,
    String? contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    String? assetId;
    if (file != null) {
      assetId = await _upload(
        file,
        filename: filename!,
        contentType: contentType!,
        onProgress: onProgress,
      );
    }

    await _repository.create(
      classroomId,
      kind: kind,
      title: title,
      description: description,
      dueDate: dueDate,
      assetId: assetId,
    );
    _refresh(kind);
  }

  Future<void> delete(Post post) async {
    await _repository.delete(post.id);
    _refresh(post.kind);
  }

  Future<void> submit(
    Post post,
    File file, {
    required String filename,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final assetId = await _upload(
      file,
      filename: filename,
      contentType: contentType,
      onProgress: onProgress,
    );
    await _repository.submit(post.id, assetId: assetId);

    _ref.invalidate(mySubmissionProvider(post.id));
    _refresh(PostKind.assignment);
  }
}

final postActionsProvider =
    Provider.family<PostActions, String>((ref, classroomId) {
  return PostActions(ref, classroomId);
});
