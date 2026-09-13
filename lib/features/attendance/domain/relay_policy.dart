import 'beacon_codec.dart';

/// Why a received beacon was or was not relayed.
enum RelayDecision {
  relay,
  maxDepthReached,
  signalTooWeak,
  sessionNotRunning,
  alreadyRelayedThisWindow,
  alreadyRelaying,
  deviceCannotAdvertise,
  alreadyMarked;

  bool get allowed => this == relay;
}

/// Decides whether a student's phone should rebroadcast a beacon it heard.
///
/// Relaying only extends *reach*. It grants nothing — the relaying phone's own
/// attendance and the receiving phone's are both judged by the server on the
/// same rules. So every limit here exists to stop propagation getting out of
/// hand, not to protect attendance:
///
/// | Rule                     | Limit                              |
/// | ------------------------ | ---------------------------------- |
/// | Hop depth                | 2, or the session's own lower limit|
/// | Duration                 | 30 seconds, then stop              |
/// | Deduplication            | once per window                    |
/// | Signal                   | Strong or Medium only              |
/// | Session                  | monitoring or active only          |
class RelayPolicy {
  RelayPolicy({required this.sessionHopDepth, required this.rssiThreshold});

  /// The most relays the session allows; never above [Beacon.maxHopDepth].
  final int sessionHopDepth;
  final int rssiThreshold;

  int? _lastRelayedWindow;
  DateTime? _relayingUntil;

  int get _maxHop => sessionHopDepth < Beacon.maxHopDepth
      ? sessionHopDepth
      : Beacon.maxHopDepth;

  bool isRelaying(DateTime now) =>
      _relayingUntil != null && now.isBefore(_relayingUntil!);

  RelayDecision evaluate(
    BeaconPayload payload, {
    required int rssi,
    required DateTime now,
    required bool sessionRunning,
    required bool canAdvertise,
    bool markedPresent = false,
  }) {
    if (!sessionRunning) return RelayDecision.sessionNotRunning;
    // Once marked, the phone has nothing left to do in this session; relaying
    // stops like it did in the old app.
    if (markedPresent) return RelayDecision.alreadyMarked;
    if (!canAdvertise) return RelayDecision.deviceCannotAdvertise;
    // The relayed copy would carry hop + 1, which must stay within limits.
    if (payload.hop + 1 > _maxHop) return RelayDecision.maxDepthReached;
    if (!SignalStrength.of(rssi, threshold: rssiThreshold).counts) {
      return RelayDecision.signalTooWeak;
    }
    if (isRelaying(now)) return RelayDecision.alreadyRelaying;
    if (_lastRelayedWindow == payload.window) {
      return RelayDecision.alreadyRelayedThisWindow;
    }
    return RelayDecision.relay;
  }

  /// Call when a relay actually starts. Returns when it must stop.
  DateTime begin(BeaconPayload payload, DateTime now) {
    _lastRelayedWindow = payload.window;
    final until = now.add(const Duration(seconds: Beacon.rebroadcastSeconds));
    _relayingUntil = until;
    return until;
  }

  /// Call when a relay stops early (session ended, marked present).
  void stop() => _relayingUntil = null;
}
