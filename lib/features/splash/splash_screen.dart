import 'package:flutter/material.dart';

/// Shown while the session is restored from secure storage.
///
/// Exists so a returning user never sees the login screen flash before their
/// stored session is checked.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
