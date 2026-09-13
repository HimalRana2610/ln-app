import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/local_store.dart';

/// The person's theme choice, applied to `MaterialApp.themeMode`.
///
/// Starts at [ThemeMode.system] and switches once the stored choice has been
/// read. That read takes a few milliseconds at launch, so a saved "dark" can
/// show one light frame first — accepted rather than delaying the first frame.
final themeModeProvider =
    NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);

class ThemeController extends Notifier<ThemeMode> {
  static const storageKey = 'theme_mode';

  /// Set when the person picks a theme before the stored one has loaded, so a
  /// slow read cannot overwrite a choice they just made.
  bool _chosen = false;

  @override
  ThemeMode build() {
    Future.microtask(_load);
    return ThemeMode.system;
  }

  LocalStore get _store => ref.read(localStoreProvider);

  Future<void> _load() async {
    final stored = await _store.read(storageKey);
    if (!ref.mounted || _chosen) return;
    state = parse(stored);
  }

  Future<void> set(ThemeMode mode) async {
    _chosen = true;
    state = mode;
    await _store.write(storageKey, mode.name);
  }

  /// Unknown or missing values fall back to following the system.
  static ThemeMode parse(Object? value) => ThemeMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => ThemeMode.system,
      );
}
