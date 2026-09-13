import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/attendance_models.dart';
import '../domain/beacon_codec.dart';
import '../domain/evidence_log.dart';
import '../domain/relay_policy.dart';
import 'beacon_radio.dart';

/// Server time on this phone's clock.
///
/// Windows are counted from the server's `started_at`. A phone whose clock is
/// a minute out would otherwise advertise the wrong window's token and every
/// student would be rejected for a stale signal.
class ServerClock {
  ServerClock({required DateTime serverTime, DateTime Function()? device})
      : _device = device ?? DateTime.now {
    _offset = serverTime.difference(_device());
  }

  final DateTime Function() _device;
  late final Duration _offset;

  DateTime now() => _device().add(_offset);
}

/// The teacher's phone: advertises the session's token, switching at every
/// 30-second window boundary.
class TeacherBeacon {
  TeacherBeacon({
    required this.session,
    required this.radio,
    required this.clock,
  }) : assert(session.beaconSecret != null, 'Only teachers get the secret');

  final AttendanceSession session;
  final BeaconRadio radio;
  final ServerClock clock;

  Timer? _timer;
  final ValueNotifier<int?> window = ValueNotifier(null);
  final ValueNotifier<Object?> error = ValueNotifier(null);

  BeaconPayload payloadFor(int w) => BeaconPayload(
        sessionTag: session.sessionTag,
        window: w,
        hop: 0,
        token: bytesToHex(beaconToken(
          secretHex: session.beaconSecret!,
          sessionId: session.id,
          window: w,
        )),
      );

  Future<void> start() => _tick();

  Future<void> _tick() async {
    final now = clock.now();
    final w = windowIndex(startedAt: session.startedAt, at: now);
    try {
      if (w >= 0) {
        await radio.advertise(payloadFor(w).encode());
        window.value = w;
        error.value = null;
      }
    } on Object catch (e) {
      error.value = e;
    }

    // Wake just after the next boundary rather than on a fixed period, so
    // drift from slow advertise calls never accumulates.
    final next = windowStart(session.startedAt, w + 1)
        .add(const Duration(milliseconds: 150));
    _timer = Timer(next.difference(clock.now()), _tick);
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await radio.stopAdvertising();
    window.value = null;
  }
}

/// What a student's phone is doing, for the screen to show.
@immutable
class TrackerState {
  const TrackerState({
    required this.progress,
    this.lastHop,
    this.relaying = false,
    this.lastRelayDecision,
  });

  final PresenceProgress progress;
  final int? lastHop;
  final bool relaying;
  final RelayDecision? lastRelayDecision;
}

/// The student's phone: listens for the beacon, records evidence, and relays
/// within the rules.
class StudentTracker {
  StudentTracker({
    required AttendanceSession session,
    required this.radio,
    required this.clock,
    required this.canAdvertise,
  })  : log = EvidenceLog(
          sessionTag: session.sessionTag,
          startedAt: session.startedAt,
          rssiThreshold: session.rssiThreshold,
          hopDepth: session.hopDepth,
        ),
        policy = RelayPolicy(
          sessionHopDepth: session.hopDepth,
          rssiThreshold: session.rssiThreshold,
        ),
        _sessionRunning = session.status.isRunning {
    state = ValueNotifier(TrackerState(progress: log.progress(clock.now())));
  }

  final BeaconRadio radio;
  final ServerClock clock;
  final bool canAdvertise;
  final EvidenceLog log;
  final RelayPolicy policy;
  late final ValueNotifier<TrackerState> state;

  bool _sessionRunning;
  bool _markedPresent = false;
  StreamSubscription<BeaconSighting>? _subscription;
  Timer? _relayTimer;
  Timer? _progressTimer;

  void start() {
    _subscription = radio.scan().listen(onSighting);
    // Progress changes as windows pass even when nothing is heard — that is
    // precisely when a student needs to see it fall.
    _progressTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _publish());
  }

  /// Handles one sighting. Public so tests can drive it without a stream.
  Future<void> onSighting(BeaconSighting sighting) async {
    // Scan callbacks carry the phone's clock; windows are judged on the
    // server's.
    final at = clock.now();
    if (!log.add(sighting.payload, rssi: sighting.rssi, at: at)) return;

    final decision = policy.evaluate(
      sighting.payload,
      rssi: sighting.rssi,
      now: at,
      sessionRunning: _sessionRunning,
      canAdvertise: canAdvertise,
      markedPresent: _markedPresent,
    );

    if (decision.allowed) {
      final until = policy.begin(sighting.payload, at);
      try {
        await radio.advertise(sighting.payload.relayed().encode());
        _relayTimer?.cancel();
        _relayTimer = Timer(until.difference(clock.now()), _stopRelay);
      } on Object {
        policy.stop();
      }
    }

    _publish(lastHop: sighting.payload.hop, decision: decision);
  }

  void _publish({int? lastHop, RelayDecision? decision}) {
    final now = clock.now();
    state.value = TrackerState(
      progress: log.progress(now),
      lastHop: lastHop ?? state.value.lastHop,
      relaying: policy.isRelaying(now),
      lastRelayDecision: decision ?? state.value.lastRelayDecision,
    );
  }

  Future<void> _stopRelay() async {
    _relayTimer?.cancel();
    _relayTimer = null;
    policy.stop();
    await radio.stopAdvertising();
    _publish();
  }

  /// Called when polling sees the session change. Ending stops any relay at once.
  Future<void> updateSession(AttendanceSession session) async {
    _sessionRunning = session.status.isRunning;
    if (!_sessionRunning) await _stopRelay();
  }

  Future<void> markedPresent() async {
    _markedPresent = true;
    await _stopRelay();
  }

  Future<void> stop() async {
    _progressTimer?.cancel();
    await _subscription?.cancel();
    await radio.stopScan();
    await _stopRelay();
  }
}
