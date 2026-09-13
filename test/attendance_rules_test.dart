import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/features/attendance/domain/beacon_codec.dart';
import 'package:ln_app/features/attendance/domain/evidence_log.dart';
import 'package:ln_app/features/attendance/domain/relay_policy.dart';

final _start = DateTime.utc(2026, 9, 14, 9);

DateTime _at(int seconds) => _start.add(Duration(seconds: seconds));

BeaconPayload _beacon({int window = 0, int hop = 0, String tag = 'aabbccdd'}) =>
    BeaconPayload(
      sessionTag: tag,
      window: window,
      hop: hop,
      token: '00112233445566' '${window.toRadixString(16).padLeft(2, '0')}',
    );

void main() {
  group('RelayPolicy', () {
    RelayPolicy policy({int depth = 2}) =>
        RelayPolicy(sessionHopDepth: depth, rssiThreshold: -80);

    RelayDecision decide(
      RelayPolicy p,
      BeaconPayload b, {
      int rssi = -65,
      int at = 0,
      bool running = true,
      bool canAdvertise = true,
      bool marked = false,
    }) =>
        p.evaluate(
          b,
          rssi: rssi,
          now: _at(at),
          sessionRunning: running,
          canAdvertise: canAdvertise,
          markedPresent: marked,
        );

    test('relays a strong teacher beacon', () {
      expect(decide(policy(), _beacon()), RelayDecision.relay);
    });

    test('never exceeds two hops', () {
      final p = policy();
      expect(decide(p, _beacon(hop: 1)), RelayDecision.relay);
      expect(decide(p, _beacon(hop: 2)), RelayDecision.maxDepthReached);
      expect(decide(p, _beacon(hop: 9)), RelayDecision.maxDepthReached);
    });

    test('a session can allow fewer hops, but never more', () {
      expect(decide(policy(depth: 1), _beacon(hop: 1)),
          RelayDecision.maxDepthReached);
      expect(
          decide(policy(depth: 0), _beacon()), RelayDecision.maxDepthReached);
      expect(decide(policy(depth: 5), _beacon(hop: 2)),
          RelayDecision.maxDepthReached);
    });

    test('weak signals do not propagate', () {
      final p = policy();
      expect(decide(p, _beacon(), rssi: -81), RelayDecision.signalTooWeak);
      expect(decide(p, _beacon(), rssi: -80), RelayDecision.relay);
    });

    test('no relaying once the session has ended', () {
      expect(decide(policy(), _beacon(), running: false),
          RelayDecision.sessionNotRunning);
    });

    test('lasts 30 seconds and happens once per window', () {
      final p = policy();
      final beacon = _beacon(window: 4);
      final until = p.begin(beacon, _at(120));
      expect(until, _at(150));

      expect(p.isRelaying(_at(149)), isTrue);
      expect(decide(p, _beacon(window: 5), at: 149),
          RelayDecision.alreadyRelaying);

      expect(p.isRelaying(_at(150)), isFalse);
      expect(
          decide(p, beacon, at: 151), RelayDecision.alreadyRelayedThisWindow);
      expect(decide(p, _beacon(window: 5), at: 151), RelayDecision.relay);
    });

    test('a device that cannot advertise still just listens', () {
      expect(decide(policy(), _beacon(), canAdvertise: false),
          RelayDecision.deviceCannotAdvertise);
    });

    test('stops once the student is marked present', () {
      expect(decide(policy(), _beacon(), marked: true),
          RelayDecision.alreadyMarked);
    });
  });

  group('EvidenceLog', () {
    EvidenceLog log({int depth = 2}) => EvidenceLog(
          sessionTag: 'aabbccdd',
          startedAt: _start,
          rssiThreshold: -80,
          hopDepth: depth,
        );

    test('keeps one reading per window and hop, the strongest', () {
      final l = log();
      for (final rssi in [-75, -62, -70]) {
        l.add(_beacon(window: 1), rssi: rssi, at: _at(45));
      }
      l.add(_beacon(window: 1, hop: 1), rssi: -72, at: _at(45));

      final obs = l.observations;
      expect(obs, hasLength(2));
      expect(obs.firstWhere((o) => o.hop == 0).rssi, -62);
    });

    test('ignores other sessions and future windows', () {
      final l = log();
      expect(l.add(_beacon(tag: '11111111'), rssi: -60, at: _at(0)), isFalse);
      expect(l.add(_beacon(window: 3), rssi: -60, at: _at(60)), isFalse);
      expect(l.observations, isEmpty);
    });

    test('shows seventy percent progress the way the server counts it', () {
      final l = log();
      // At 4:45 (window 9): heard 7 of the 10 windows.
      for (final w in [0, 1, 2, 6, 7, 8, 9]) {
        l.add(_beacon(window: w), rssi: -70, at: _at(285));
      }
      final progress = l.progress(_at(285));
      expect(progress.validWindows, 7);
      expect(progress.elapsedWindows, 10);
      expect(progress.requiredWindows, 7);
      expect(progress.looksEligible, isTrue);
    });

    test('is not eligible when the newest reading is weak or old', () {
      final weakNow = log();
      for (var w = 0; w < 10; w++) {
        weakNow.add(_beacon(window: w), rssi: -70, at: _at(300));
      }
      weakNow.add(_beacon(window: 10), rssi: -95, at: _at(300));
      expect(weakNow.progress(_at(300)).lastSignal, SignalStrength.outOfRange);
      expect(weakNow.progress(_at(300)).looksEligible, isFalse);

      final left = log();
      for (var w = 0; w < 18; w++) {
        left.add(_beacon(window: w), rssi: -70, at: _at(540));
      }
      expect(left.progress(_at(600)).fresh, isFalse);
      expect(left.progress(_at(600)).looksEligible, isFalse);
    });

    test('does not count relays beyond the session depth', () {
      final l = log(depth: 0);
      for (var w = 0; w < 5; w++) {
        l.add(_beacon(window: w, hop: 1), rssi: -65, at: _at(120));
      }
      expect(l.progress(_at(120)).validWindows, 0);
    });

    test('serialises observations for the verify request', () {
      final l = log()..add(_beacon(window: 2, hop: 1), rssi: -71, at: _at(75));
      expect(l.observations.single.toJson(), {
        'window': 2,
        'token': '0011223344556602',
        'rssi': -71,
        'hop': 1,
      });
    });
  });
}
