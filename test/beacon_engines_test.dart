import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/features/attendance/ble/beacon_engines.dart';
import 'package:ln_app/features/attendance/ble/beacon_radio.dart';
import 'package:ln_app/features/attendance/data/attendance_models.dart';
import 'package:ln_app/features/attendance/domain/beacon_codec.dart';
import 'package:ln_app/features/attendance/domain/relay_policy.dart';

const _secret =
    '0000000000000000000000000000000000000000000000000000000000000001';
const _sessionId = '12345678-1234-5678-1234-567812345678';
final _start = DateTime.utc(2026, 9, 14, 9);

AttendanceSession _session({
  String? secret,
  SessionStatus status = SessionStatus.active,
  int hopDepth = 2,
}) =>
    AttendanceSession(
      id: _sessionId,
      classroomId: 'c',
      startedBy: 't',
      startedByName: 'Grace Hopper',
      date: '2026-09-14',
      status: status,
      startedAt: _start,
      verificationOpensAt: _start,
      radiusMeters: 15,
      thresholdMinutes: 5,
      rssiThreshold: -80,
      hopDepth: hopDepth,
      sessionTag: '12345678',
      windowSeconds: 30,
      serverTime: _start,
      beaconSecret: secret,
      presentCount: 0,
      recordCount: 0,
    );

class FakeRadio implements BeaconRadio {
  final advertised = <BeaconPayload>[];
  final stops = <DateTime>[];
  bool advertising = false;
  final controller = StreamController<BeaconSighting>.broadcast();
  DateTime Function() now = DateTime.now;

  @override
  Future<RadioProblem?> prepare({required bool advertise}) async => null;

  @override
  Future<bool> canAdvertise() async => true;

  @override
  Stream<BeaconSighting> scan() => controller.stream;

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> advertise(Uint8List payload) async {
    advertised.add(BeaconPayload.decode(payload)!);
    advertising = true;
  }

  @override
  Future<void> stopAdvertising() async {
    if (advertising) stops.add(now());
    advertising = false;
  }
}

String _token(int w) => bytesToHex(
    beaconToken(secretHex: _secret, sessionId: _sessionId, window: w));

BeaconSighting _heard(int window, {int hop = 0, int rssi = -65}) =>
    BeaconSighting(
      payload: BeaconPayload(
        sessionTag: '12345678',
        window: window,
        hop: hop,
        token: _token(window),
      ),
      rssi: rssi,
      at: _start,
    );

void main() {
  test('ServerClock corrects a phone whose clock is wrong', () {
    var device = DateTime.utc(2026, 9, 14, 8, 58); // two minutes slow
    final clock = ServerClock(serverTime: _start, device: () => device);
    expect(clock.now(), _start);
    device = device.add(const Duration(seconds: 45));
    expect(clock.now(), _start.add(const Duration(seconds: 45)));
  });

  group('TeacherBeacon', () {
    test('advertises the current window and rotates at each boundary', () {
      fakeAsync((async) {
        final radio = FakeRadio();
        // 10 seconds into window 2.
        final base = DateTime.utc(2026, 9, 14, 9, 1, 10);
        final clock = ServerClock(
          serverTime: base,
          device: () => base.add(async.elapsed),
        );
        final beacon = TeacherBeacon(
          session: _session(secret: _secret),
          radio: radio,
          clock: clock,
        );

        beacon.start();
        async.flushMicrotasks();
        expect(radio.advertised.single.window, 2);
        expect(radio.advertised.single.hop, 0);
        expect(radio.advertised.single.token, _token(2));

        async.elapse(const Duration(seconds: 21));
        expect(radio.advertised.map((p) => p.window), [2, 3]);

        async.elapse(const Duration(seconds: 60));
        expect(radio.advertised.map((p) => p.window), [2, 3, 4, 5]);
        expect(radio.advertised.last.token, _token(5));

        beacon.stop();
        async.flushMicrotasks();
        expect(radio.advertising, isFalse);
        async.elapse(const Duration(minutes: 5));
        expect(radio.advertised, hasLength(4));
      });
    });
  });

  group('StudentTracker', () {
    StudentTracker tracker(
      FakeRadio radio,
      FakeAsync async, {
      AttendanceSession? session,
      bool canAdvertise = true,
    }) {
      final base = _start.add(const Duration(seconds: 65)); // window 2
      radio.now = () => base.add(async.elapsed);
      return StudentTracker(
        session: session ?? _session(),
        radio: radio,
        clock: ServerClock(
            serverTime: base, device: () => base.add(async.elapsed)),
        canAdvertise: canAdvertise,
      );
    }

    test('relays a strong teacher beacon as hop 1 for 30 seconds', () {
      fakeAsync((async) {
        final radio = FakeRadio();
        final t = tracker(radio, async);

        t.onSighting(_heard(2));
        async.flushMicrotasks();
        expect(radio.advertised.single.hop, 1);
        expect(radio.advertised.single.token, _token(2));
        expect(t.state.value.relaying, isTrue);

        async.elapse(const Duration(seconds: 29));
        expect(radio.advertising, isTrue);
        async.elapse(const Duration(seconds: 2));
        expect(radio.advertising, isFalse);
        expect(t.state.value.relaying, isFalse);
      });
    });

    test('does not relay a hop-2 beacon, a weak one, or twice a window', () {
      fakeAsync((async) {
        final radio = FakeRadio();
        final t = tracker(radio, async);

        t.onSighting(_heard(2, hop: 2));
        async.flushMicrotasks();
        expect(t.state.value.lastRelayDecision, RelayDecision.maxDepthReached);

        t.onSighting(_heard(2, rssi: -85));
        async.flushMicrotasks();
        expect(t.state.value.lastRelayDecision, RelayDecision.signalTooWeak);
        expect(radio.advertised, isEmpty);

        t.onSighting(_heard(2));
        async.elapse(const Duration(seconds: 31));
        t.onSighting(_heard(2));
        async.flushMicrotasks();
        expect(radio.advertised, hasLength(1));
        expect(t.state.value.lastRelayDecision,
            RelayDecision.alreadyRelayedThisWindow);
      });
    });

    test('a phone that cannot advertise still records evidence', () {
      fakeAsync((async) {
        final radio = FakeRadio();
        final t = tracker(radio, async, canAdvertise: false);
        t.onSighting(_heard(2));
        async.flushMicrotasks();
        expect(radio.advertised, isEmpty);
        expect(t.log.observations, hasLength(1));
        expect(t.state.value.progress.validWindows, 1);
      });
    });

    test('ending the session stops a relay immediately', () {
      fakeAsync((async) {
        final radio = FakeRadio();
        final t = tracker(radio, async);
        t.onSighting(_heard(2));
        async.flushMicrotasks();
        expect(radio.advertising, isTrue);

        t.updateSession(_session(status: SessionStatus.ended));
        async.flushMicrotasks();
        expect(radio.advertising, isFalse);

        t.onSighting(_heard(2));
        async.flushMicrotasks();
        expect(radio.advertised, hasLength(1));
        expect(
            t.state.value.lastRelayDecision, RelayDecision.sessionNotRunning);
      });
    });

    test('being marked present stops relaying', () {
      fakeAsync((async) {
        final radio = FakeRadio();
        final t = tracker(radio, async);
        t.onSighting(_heard(2));
        async.flushMicrotasks();
        t.markedPresent();
        async.flushMicrotasks();
        expect(radio.advertising, isFalse);
      });
    });
  });
}
