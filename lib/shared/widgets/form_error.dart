import 'package:flutter/material.dart';

/// Inline error banner for form-level failures.
class FormError extends StatelessWidget {
  const FormError({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: TextStyle(color: scheme.onErrorContainer, fontSize: 14),
      ),
    );
  }
}
