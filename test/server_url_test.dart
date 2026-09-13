import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/core/config/server_url.dart';

void main() {
  group('ServerUrl.normalize', () {
    test('fills in the scheme, the port and the API prefix', () {
      expect(
        ServerUrl.normalize('192.168.1.3'),
        'http://192.168.1.3:8000/api/v1',
      );
    });

    test('keeps a port that was given', () {
      expect(
        ServerUrl.normalize('192.168.1.3:9000'),
        'http://192.168.1.3:9000/api/v1',
      );
    });

    test('leaves an address that is already complete alone', () {
      const url = 'http://192.168.1.3:8000/api/v1';
      expect(ServerUrl.normalize(url), url);
    });

    test('strips a trailing slash rather than doubling the prefix', () {
      expect(
        ServerUrl.normalize('http://192.168.1.3:8000/api/v1/'),
        'http://192.168.1.3:8000/api/v1',
      );
      expect(
        ServerUrl.normalize('http://192.168.1.3:8000/'),
        'http://192.168.1.3:8000/api/v1',
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        ServerUrl.normalize('  192.168.1.3:8000  '),
        'http://192.168.1.3:8000/api/v1',
      );
    });

    test('does not invent a port for a deployed host', () {
      // Adding :8000 to an HTTPS host would break it - that address is
      // reached over 443.
      expect(
        ServerUrl.normalize('https://api.example.com'),
        'https://api.example.com/api/v1',
      );
    });

    test('adds the backend port for localhost and .local names', () {
      expect(ServerUrl.normalize('localhost'), 'http://localhost:8000/api/v1');
      expect(
        ServerUrl.normalize('victus.local'),
        'http://victus.local:8000/api/v1',
      );
    });

    test('rejects what cannot be a server address', () {
      expect(ServerUrl.normalize(''), isNull);
      expect(ServerUrl.normalize('   '), isNull);
      expect(ServerUrl.normalize('ftp://192.168.1.3'), isNull);
      expect(ServerUrl.normalize('http://'), isNull);
    });
  });

  group('ServerUrl', () {
    test('display shows host and port without scheme or path', () {
      expect(
        ServerUrl.display('http://192.168.1.3:8000/api/v1'),
        '192.168.1.3:8000',
      );
      expect(ServerUrl.display('https://api.example.com/api/v1'),
          'api.example.com');
    });

    test('healthUrl points at the liveness endpoint', () {
      expect(
        ServerUrl.healthUrl('http://192.168.1.3:8000/api/v1'),
        'http://192.168.1.3:8000/api/v1/health',
      );
    });

    test('forHost builds a base URL for a discovered address', () {
      expect(
        ServerUrl.forHost('192.168.1.3'),
        'http://192.168.1.3:8000/api/v1',
      );
    });
  });
}
