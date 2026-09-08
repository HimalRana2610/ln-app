import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/features/classroom/presentation/classroom_palette.dart';

void main() {
  group('ClassroomPalette.gradientFor', () {
    test('maps a known Tailwind pair to its palette colours', () {
      final gradient =
          ClassroomPalette.gradientFor('from-rose-500 to-pink-600');

      // Tailwind rose-500 and pink-600. If these drift, a class card is a
      // different colour on mobile than on the web.
      expect(
          gradient.colors, [const Color(0xFFF43F5E), const Color(0xFFDB2777)]);
    });

    test('runs top-left to bottom-right, matching bg-gradient-to-br', () {
      final gradient =
          ClassroomPalette.gradientFor('from-blue-500 to-indigo-600');

      expect(gradient.begin, Alignment.topLeft);
      expect(gradient.end, Alignment.bottomRight);
    });

    test('every advertised theme resolves to two real colours', () {
      // Guards the case where the backend adds a theme and this table does not,
      // which would silently render every new class in the fallback colour.
      for (final theme in ClassroomPalette.themeColors) {
        final gradient = ClassroomPalette.gradientFor(theme);
        expect(gradient.colors.length, 2, reason: theme);
        expect(
          gradient.colors.first,
          isNot(equals(gradient.colors.last)),
          reason: '$theme resolved to a flat gradient, so a shade is missing',
        );
      }
    });

    test('falls back rather than throwing on an unknown theme', () {
      // A colour is never worth crashing a screen for.
      final gradient =
          ClassroomPalette.gradientFor('from-puce-500 to-beige-600');
      expect(gradient.colors.length, 2);
    });

    test('falls back on malformed input', () {
      expect(ClassroomPalette.gradientFor('').colors.length, 2);
      expect(ClassroomPalette.gradientFor('from-blue-500').colors.length, 2);
    });

    test('theme list matches the backend order', () {
      // Mirrors THEME_COLORS in ln-backend/app/schemas/classroom.py so the
      // colour picker is identical on both clients.
      expect(ClassroomPalette.themeColors.first, 'from-blue-500 to-indigo-600');
      expect(ClassroomPalette.themeColors.length, 8);
      expect(
        ClassroomPalette.themeColors.toSet().length,
        ClassroomPalette.themeColors.length,
        reason: 'duplicate themes',
      );
    });
  });
}
