import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_store.dart';
import '../../auth/application/auth_controller.dart';
import '../data/note_cache.dart';
import '../data/note_models.dart';
import '../data/note_repository.dart';

/// How often to re-check while something is still generating.
const notePollInterval = Duration(seconds: 3);

final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  return NoteRepository(apiClient: ref.watch(apiClientProvider));
});

final noteCacheProvider = Provider<NoteCache>((ref) {
  return NoteCache(ref.watch(localStoreProvider));
});

/// One classroom's notes, keyed by classroom id.
///
/// A plain [FutureProvider.family] rather than a family notifier: Riverpod 3
/// removed `FamilyAsyncNotifier`, and this needs no long-lived state anyway.
/// Refreshing is `ref.invalidate`, which is also exactly what polling wants.
///
/// Falls back to the saved copy when offline; [Cached.isOffline] says so.
final noteListProvider = FutureProvider.family<Cached<List<NoteSummary>>,
    String>((ref, classroomId) {
  final cache = ref.read(noteCacheProvider);
  return fetchWithOfflineCopy(
    fetch: () => ref.read(noteRepositoryProvider).list(classroomId),
    save: (notes) => cache.saveList(classroomId, notes),
    read: () => cache.readList(classroomId),
  );
});

/// A single note, including its Markdown body. Offline fallback as above.
final noteProvider =
    FutureProvider.family<Cached<Note>, String>((ref, noteId) {
  final cache = ref.read(noteCacheProvider);
  return fetchWithOfflineCopy(
    fetch: () => ref.read(noteRepositoryProvider).get(noteId),
    save: cache.saveNote,
    read: () => cache.readNote(noteId),
  );
});

/// Actions on a classroom's notes.
///
/// Each one refreshes the list afterwards rather than patching it in memory, so
/// the screen can never drift from what the server actually holds.
class NoteActions {
  const NoteActions(this._ref, this.classroomId);

  final Ref _ref;
  final String classroomId;

  NoteRepository get _repository => _ref.read(noteRepositoryProvider);

  void _refreshList() => _ref.invalidate(noteListProvider(classroomId));

  Future<void> createFromText(String text, {DateTime? date}) async {
    await _repository.createFromText(classroomId, text: text, date: date);
    _refreshList();
  }

  Future<void> createFromYoutube(String url, {DateTime? date}) async {
    await _repository.createFromYoutube(classroomId, url: url, date: date);
    _refreshList();
  }

  /// Upload a recording or PDF, then queue a note from it.
  ///
  /// The file goes straight to object storage; only the resulting asset id
  /// reaches the API.
  Future<void> createFromFile(
    File file, {
    required String filename,
    required String contentType,
    DateTime? date,
    void Function(int sent, int total)? onProgress,
  }) async {
    final slot = await _repository.presignUpload(
      filename: filename,
      contentType: contentType,
      sizeBytes: await file.length(),
    );
    await _repository.uploadFile(
        slot: slot, file: file, onProgress: onProgress);
    await _repository.createFromAsset(classroomId,
        assetId: slot.assetId, date: date);

    _refreshList();
  }

  Future<void> delete(String noteId) async {
    await _repository.delete(noteId);
    _refreshList();
  }
}

final noteActionsProvider =
    Provider.family<NoteActions, String>((ref, classroomId) {
  return NoteActions(ref, classroomId);
});
