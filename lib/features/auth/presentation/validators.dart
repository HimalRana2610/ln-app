/// Form validators mirroring `app/schemas/auth.py` and `ln-web`'s Zod schemas.
///
/// Client-side validation is a courtesy that saves a round trip; the backend
/// validates independently and is the only thing that actually enforces these.
abstract final class Validators {
  static const passwordMinLength = 10;

  // Deliberately permissive. Strict email regexes reject valid addresses far
  // more often than they catch typos; the backend uses a real parser.
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Enter your email';
    if (!_emailPattern.hasMatch(input)) {
      return 'That does not look like an email';
    }
    return null;
  }

  static String? Function(String?) required(String message) {
    return (value) => (value?.trim().isEmpty ?? true) ? message : null;
  }

  static String? password(String? value) {
    final input = value ?? '';
    if (input.isEmpty) return 'Choose a password';
    if (input.length < passwordMinLength) {
      return 'Use at least $passwordMinLength characters';
    }
    if (input.trim() != input) return 'Cannot start or end with a space';
    if (input.split('').toSet().length < 4) {
      return 'Too repetitive to be a good password';
    }
    return null;
  }

  static String? Function(String?) matches(
    String Function() other,
    String message,
  ) {
    return (value) => value == other() ? null : message;
  }

  static String? name(String? value) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) return 'Enter your name';
    if (input.length > 200) return 'That name is too long';
    return null;
  }
}
