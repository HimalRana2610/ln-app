import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/core/network/api_exception.dart';

void main() {
  group('ApiException.fromResponse', () {
    test('parses the backend error envelope', () {
      final exception = ApiException.fromResponse(409, {
        'error': {
          'code': 'conflict',
          'message': 'An account with that email already exists',
        },
      });

      expect(exception.statusCode, 409);
      expect(exception.code, 'conflict');
      expect(exception.message, 'An account with that email already exists');
      expect(exception.fieldErrors, isEmpty);
    });

    test('collects per-field validation details', () {
      final exception = ApiException.fromResponse(422, {
        'error': {
          'code': 'validation_error',
          'message': 'Request payload failed validation',
          'details': [
            {'field': 'email', 'message': 'not a valid email address'},
            {'field': 'password', 'message': 'too short'},
          ],
        },
      });

      expect(exception.fieldErrors['email'], 'not a valid email address');
      expect(exception.fieldErrors['password'], 'too short');
    });

    test('survives a body that is not the expected shape', () {
      // A proxy or gateway can return HTML; this must not crash the app.
      final exception =
          ApiException.fromResponse(502, '<html>Bad Gateway</html>');

      expect(exception.code, 'unexpected_response');
      expect(exception.message, isNotEmpty);
    });

    test('ignores malformed entries in details', () {
      final exception = ApiException.fromResponse(422, {
        'error': {
          'code': 'validation_error',
          'message': 'nope',
          'details': [
            {'field': 'email'},
            'not-an-object',
            {'field': 'password', 'message': 'too short'},
          ],
        },
      });

      expect(exception.fieldErrors, {'password': 'too short'});
    });

    test('flags 401 as unauthorized', () {
      final exception = ApiException.fromResponse(401, {
        'error': {'code': 'authentication_failed', 'message': 'nope'},
      });

      expect(exception.isUnauthorized, isTrue);
    });
  });
}
