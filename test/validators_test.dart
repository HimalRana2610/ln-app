import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/features/auth/presentation/validators.dart';

void main() {
  group('Validators.email', () {
    test('accepts a normal address', () {
      expect(Validators.email('ada@example.edu'), isNull);
    });

    test('trims surrounding whitespace before judging', () {
      expect(Validators.email('  ada@example.edu  '), isNull);
    });

    test('rejects empty input', () {
      expect(Validators.email(''), 'Enter your email');
      expect(Validators.email(null), 'Enter your email');
    });

    test('rejects input with no domain', () {
      expect(Validators.email('ada@'), isNotNull);
      expect(Validators.email('ada'), isNotNull);
    });
  });

  group('Validators.password', () {
    test('accepts a passphrase', () {
      expect(Validators.password('correct-horse-battery'), isNull);
    });

    test('rejects anything under the minimum length', () {
      // Must stay in step with the backend's PASSWORD_MIN_LENGTH of 10.
      expect(Validators.password('abcdefghi'), isNotNull);
      expect(Validators.password('abcdefghij'), isNull);
    });

    test('rejects a repetitive password', () {
      expect(Validators.password('aaaaaaaaaaaa'), isNotNull);
    });

    test('rejects leading or trailing whitespace', () {
      expect(Validators.password(' correct-horse '), isNotNull);
    });
  });

  group('Validators.matches', () {
    test('passes when the two agree', () {
      final validate =
          Validators.matches(() => 'secret', 'Passwords do not match');
      expect(validate('secret'), isNull);
    });

    test('fails when they differ', () {
      final validate =
          Validators.matches(() => 'secret', 'Passwords do not match');
      expect(validate('different'), 'Passwords do not match');
    });
  });

  group('Validators.name', () {
    test('rejects blank input', () {
      expect(Validators.name('   '), 'Enter your name');
    });

    test('accepts a normal name', () {
      expect(Validators.name('Ada Lovelace'), isNull);
    });
  });
}
