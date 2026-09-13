import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/features/attendance/domain/beacon_codec.dart';

void main() {
  group('beaconToken', () {
    // Pinned in ln-backend/tests/test_attendance.py too. If either side
    // changes how tokens are made, both tests fail rather than every student
    // being silently rejected.
    const secret =
        '0000000000000000000000000000000000000000000000000000000000000001';
    const sessionId = '12345678-1234-5678-1234-567812345678';

    test('matches the backend byte for byte', () {
      String token(int w) => bytesToHex(
          beaconToken(secretHex: secret, sessionId: sessionId, window: w));
      expect(token(0), '04eeaa24a6b04171');
      expect(token(7), '3af1fe0d4a84178e');
      expect(token(123456), 'af534f2474c390fe');
    });

    test('session tag is the first four bytes of the id', () {
      expect(bytesToHex(sessionTagBytes(sessionId)), '12345678');
    });
  });

  group('BeaconPayload', () {
    const payload = BeaconPayload(
      sessionTag: 'deadbeef',
      window: 70000,
      hop: 1,
      token: '0123456789abcdef',
    );

    test('fits the 17-byte layout and round-trips', () {
      final bytes = payload.encode();
      expect(bytes, hasLength(17));
      expect(bytesToHex(bytes), 'deadbeef' '00011170' '01' '0123456789abcdef');
      expect(BeaconPayload.decode(bytes), payload);
    });

    test('ignores advertisements that are not ours', () {
      expect(BeaconPayload.decode(const []), isNull);
      expect(BeaconPayload.decode(List.filled(16, 0)), isNull);
      expect(BeaconPayload.decode(List.filled(24, 0)), isNull);
    });

    test('relaying adds one hop and changes nothing else', () {
      final relayed = payload.relayed();
      expect(relayed.hop, 2);
      expect((relayed.sessionTag, relayed.window, relayed.token),
          (payload.sessionTag, payload.window, payload.token));
    });
  });

  group('SignalStrength', () {
    test('bands are 10 dB either side of the threshold', () {
      SignalStrength of(int rssi) => SignalStrength.of(rssi, threshold: -80);
      expect(of(-60), SignalStrength.strong);
      expect(of(-70), SignalStrength.strong);
      expect(of(-71), SignalStrength.medium);
      expect(of(-80), SignalStrength.medium);
      expect(of(-81), SignalStrength.weak);
      expect(of(-90), SignalStrength.weak);
      expect(of(-91), SignalStrength.outOfRange);
    });

    test('only strong and medium count', () {
      expect(
        SignalStrength.values.where((s) => s.counts),
        [SignalStrength.strong, SignalStrength.medium],
      );
    });
  });

  group('windows', () {
    final start = DateTime.utc(2026, 9, 14, 9);

    test('are 30 seconds long', () {
      expect(windowIndex(startedAt: start, at: start), 0);
      expect(
        windowIndex(
            startedAt: start,
            at: start.add(const Duration(milliseconds: 29999))),
        0,
      );
      expect(
          windowIndex(
              startedAt: start, at: start.add(const Duration(seconds: 30))),
          1);
      expect(
          windowIndex(
              startedAt: start, at: start.subtract(const Duration(seconds: 1))),
          -1);
      expect(windowStart(start, 3), start.add(const Duration(seconds: 90)));
    });

    test('seventy percent rounds up, exactly like the backend', () {
      const cases = {1: 1, 2: 2, 3: 3, 10: 7, 11: 8, 20: 14, 100: 70};
      cases.forEach((elapsed, required) {
        expect(requiredWindows(elapsed), required, reason: 'elapsed=$elapsed');
      });
    });
  });
}
