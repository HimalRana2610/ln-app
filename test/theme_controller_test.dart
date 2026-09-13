import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/core/storage/local_store.dart';
import 'package:ln_app/core/theme/theme_controller.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ln_theme_test');
  });

  tearDown(() => dir.delete(recursive: true));

  ProviderContainer container() => ProviderContainer(overrides: [
        localStoreProvider
            .overrideWithValue(LocalStore(directory: () async => dir)),
      ]);

  test('defaults to following the system', () async {
    final c = container();
    addTearDown(c.dispose);
    expect(c.read(themeModeProvider), ThemeMode.system);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(themeModeProvider), ThemeMode.system);
  });

  test('a chosen theme survives a restart', () async {
    final first = container();
    await first.read(themeModeProvider.notifier).set(ThemeMode.dark);
    expect(first.read(themeModeProvider), ThemeMode.dark);
    first.dispose();

    // A fresh container stands in for the next launch.
    final second = container();
    addTearDown(second.dispose);
    second.read(themeModeProvider);
    // Let the stored value load.
    for (var i = 0; i < 20 && second.read(themeModeProvider) != ThemeMode.dark;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(second.read(themeModeProvider), ThemeMode.dark);
  });

  test('unknown stored values fall back to system', () {
    expect(ThemeController.parse('sepia'), ThemeMode.system);
    expect(ThemeController.parse(null), ThemeMode.system);
    expect(ThemeController.parse('light'), ThemeMode.light);
  });
}
