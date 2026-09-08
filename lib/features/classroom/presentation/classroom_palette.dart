import 'package:flutter/material.dart';

/// Maps the backend's Tailwind gradient strings onto Flutter colours.
///
/// The web client applies `theme_color` as a CSS class directly. Flutter has no
/// Tailwind, so this table is the bridge that keeps a class card the same colour
/// on both clients. Values are Tailwind's own palette hex codes.
///
/// Keys must stay in step with `THEME_COLORS` in
/// `ln-backend/app/schemas/classroom.py`. An unknown key falls back to the
/// default rather than throwing — a colour is never worth crashing a screen for.
abstract final class ClassroomPalette {
  static const _tailwind = <String, Color>{
    'blue-500': Color(0xFF3B82F6),
    'blue-600': Color(0xFF2563EB),
    'indigo-600': Color(0xFF4F46E5),
    'sky-500': Color(0xFF0EA5E9),
    'cyan-600': Color(0xFF0891B2),
    'green-500': Color(0xFF22C55E),
    'emerald-600': Color(0xFF059669),
    'rose-500': Color(0xFFF43F5E),
    'pink-600': Color(0xFFDB2777),
    'amber-500': Color(0xFFF59E0B),
    'orange-600': Color(0xFFEA580C),
    'violet-500': Color(0xFF8B5CF6),
    'purple-600': Color(0xFF9333EA),
    'slate-600': Color(0xFF475569),
    'slate-800': Color(0xFF1E293B),
  };

  /// Same order as the backend's `THEME_COLORS`, so the picker matches the web.
  static const themeColors = <String>[
    'from-blue-500 to-indigo-600',
    'from-blue-500 to-sky-500',
    'from-blue-600 to-cyan-600',
    'from-green-500 to-emerald-600',
    'from-rose-500 to-pink-600',
    'from-amber-500 to-orange-600',
    'from-violet-500 to-purple-600',
    'from-slate-600 to-slate-800',
  ];

  static const _fallback = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3B82F6), Color(0xFF4F46E5)],
  );

  /// Parses `"from-<shade> to-<shade>"` into a top-left to bottom-right
  /// gradient, matching the web's `bg-gradient-to-br`.
  static LinearGradient gradientFor(String themeColor) {
    final parts = themeColor.split(RegExp(r'\s+'));
    if (parts.length != 2) return _fallback;

    final from = _tailwind[parts[0].replaceFirst('from-', '')];
    final to = _tailwind[parts[1].replaceFirst('to-', '')];
    if (from == null || to == null) return _fallback;

    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [from, to],
    );
  }
}
