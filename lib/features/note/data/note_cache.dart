import '../../../core/network/api_exception.dart';
import '../../../core/storage/local_store.dart';
import 'note_models.dart';

/// A value, and whether it came from the offline copy rather than the server.
class Cached<T> {
  const Cached(this.value, {this.isOffline = false});

  final T value;
  final bool isOffline;
}

/// The last notes list and note bodies the phone saw, so notes stay readable
/// without a connection.
///
/// Read-only offline support on purpose: writes made offline are not queued
/// (phase 6, "Do not gold-plate offline support").
class NoteCache {
  NoteCache(this._store);

  final LocalStore _store;

  static String _listKey(String classroomId) => 'notes_list_$classroomId';
  static String _noteKey(String noteId) => 'note_$noteId';

  Future<void> saveList(String classroomId, List<NoteSummary> notes) =>
      _store.write(
          _listKey(classroomId), [for (final note in notes) note.toJson()]);

  Future<List<NoteSummary>?> readList(String classroomId) async {
    final json = await _store.read(_listKey(classroomId));
    if (json is! List) return null;
    try {
      return [
        for (final item in json)
          NoteSummary.fromJson(item as Map<String, dynamic>)
      ];
    } on Object {
      // A copy written by an older build that no longer parses.
      return null;
    }
  }

  Future<void> saveNote(Note note) async {
    // Only a finished note is worth reading offline.
    if (note.status != NoteStatus.ready) return;
    await _store.write(_noteKey(note.id), note.toJson());
  }

  Future<Note?> readNote(String noteId) async {
    final json = await _store.read(_noteKey(noteId));
    if (json is! Map<String, dynamic>) return null;
    try {
      return Note.fromJson(json);
    } on Object {
      return null;
    }
  }
}

/// Fetches from the server and refreshes the saved copy; on a network failure,
/// falls back to that copy.
///
/// Only a network failure falls back. A 403 or 404 means the server answered
/// and the note is gone or forbidden — showing a stale copy then would be wrong.
Future<Cached<T>> fetchWithOfflineCopy<T>({
  required Future<T> Function() fetch,
  required Future<void> Function(T value) save,
  required Future<T?> Function() read,
}) async {
  try {
    final value = await fetch();
    await save(value);
    return Cached(value);
  } on ApiException catch (error) {
    if (!error.isNetworkFailure) rethrow;
    final saved = await read();
    if (saved == null) rethrow;
    return Cached(saved, isOffline: true);
  }
}
