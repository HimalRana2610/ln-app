import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/core/network/api_exception.dart';
import 'package:ln_app/core/storage/local_store.dart';
import 'package:ln_app/features/note/data/note_cache.dart';
import 'package:ln_app/features/note/data/note_models.dart';

const _network = ApiException(
    statusCode: 0, code: 'network_error', message: 'Could not reach');

Note _note() => Note(
      id: 'n1',
      classroomId: 'c1',
      date: DateTime.utc(2026, 9, 14),
      title: 'Scheduling',
      status: NoteStatus.ready,
      sourceType: NoteSourceType.text,
      authorId: 'u1',
      authorName: 'Grace Hopper',
      createdAt: DateTime.utc(2026, 9, 14, 10),
      markdown: '# Round robin\n\nEach process gets a quantum.',
    );

void main() {
  late Directory dir;
  late NoteCache cache;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ln_cache_test');
    cache = NoteCache(LocalStore(directory: () async => dir));
  });

  tearDown(() => dir.delete(recursive: true));

  test('reads back the saved copy when the network fails', () async {
    final online = await fetchWithOfflineCopy<Note>(
      fetch: () async => _note(),
      save: cache.saveNote,
      read: () => cache.readNote('n1'),
    );
    expect(online.isOffline, isFalse);

    final offline = await fetchWithOfflineCopy<Note>(
      fetch: () async => throw _network,
      save: cache.saveNote,
      read: () => cache.readNote('n1'),
    );
    expect(offline.isOffline, isTrue);
    expect(offline.value, _note());
    expect(offline.value.markdown, contains('Round robin'));
  });

  test('the notes list round-trips too', () async {
    final summary = NoteSummary.fromJson(
      (_note().toJson()..remove('markdown')),
    );
    await cache.saveList('c1', [summary]);

    final offline = await fetchWithOfflineCopy<List<NoteSummary>>(
      fetch: () async => throw _network,
      save: (notes) => cache.saveList('c1', notes),
      read: () => cache.readList('c1'),
    );
    expect(offline.isOffline, isTrue);
    expect(offline.value, [summary]);
  });

  test('with nothing saved, the network error still surfaces', () async {
    expect(
      fetchWithOfflineCopy<Note>(
        fetch: () async => throw _network,
        save: cache.saveNote,
        read: () => cache.readNote('unknown'),
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('a server answer such as 404 does not fall back to the copy', () async {
    await cache.saveNote(_note());
    expect(
      fetchWithOfflineCopy<Note>(
        fetch: () async => throw const ApiException(
            statusCode: 404, code: 'not_found', message: 'Gone'),
        save: cache.saveNote,
        read: () => cache.readNote('n1'),
      ),
      throwsA(isA<ApiException>()),
    );
  });
}
