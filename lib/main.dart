import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/push/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase is optional: without a google-services.json this returns a no-op
  // service and the rest of the app works exactly as before.
  final push = await createPushService();

  runApp(ProviderScope(
    overrides: [pushServiceProvider.overrideWithValue(push)],
    child: const LectureNoteApp(),
  ));
}

class LectureNoteApp extends ConsumerWidget {
  const LectureNoteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    // Opens the classroom a tapped notification points at.
    ref.watch(pushNavigationProvider);

    return MaterialApp.router(
      title: 'LectureNote AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
    );
  }
}
