import 'package:flutter/material.dart';

/// Light and dark themes built from one seed colour.
///
/// Material 3 derives a full, contrast-checked palette from the seed, so there
/// is no hand-maintained colour list to drift between the two modes.
abstract final class AppTheme {
  static const _seed = Color(0xFF1E293B); // slate-800, matching ln-web

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      inputDecorationTheme: const InputDecorationTheme(filled: true),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
    );
  }
}
