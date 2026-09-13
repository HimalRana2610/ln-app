import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Small JSON documents kept in the app's documents directory.
///
/// Used for things that must survive a restart but are not secrets: the theme
/// choice and the offline copy of notes. Plain files rather than a new
/// preferences plugin — `path_provider` is already a dependency, and a note's
/// Markdown is too large to sit comfortably in key-value storage anyway.
///
/// Every failure is swallowed and reads as "nothing stored". A cache or a
/// preference that cannot be read must never stop the app working.
class LocalStore {
  LocalStore({Future<Directory> Function()? directory})
      : _directory = directory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file(String key) async {
    final root = await _directory();
    // Keys are ids and fixed names; anything else is flattened so a key can
    // never climb out of the store's folder.
    final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return File('${root.path}${Platform.pathSeparator}ln_store'
        '${Platform.pathSeparator}$safe.json');
  }

  Future<Object?> read(String key) async {
    try {
      final file = await _file(key);
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } on Exception {
      return null;
    }
  }

  Future<void> write(String key, Object? value) async {
    try {
      final file = await _file(key);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(value));
    } on Exception {
      // Best-effort; see the class comment.
    }
  }

  Future<void> delete(String key) async {
    try {
      final file = await _file(key);
      if (await file.exists()) await file.delete();
    } on Exception {
      // Best-effort.
    }
  }
}

final localStoreProvider = Provider<LocalStore>((ref) => LocalStore());
