import 'beacon_codec.dart';

/// One beacon heard, as the backend's `Observation` expects it.
class Observation {
  const Observation({
    required this.window,
    required this.token,
    required this.rssi,
    required this.hop,
  });

  final int window;
  final String token;
  final int rssi;
  final int hop;

  Map<String, Object> toJson() =>
      {'window': window, 'token': token, 'rssi': rssi, 'hop': hop};
}

/// Where a student stands, as far as this phone can tell.
class PresenceProgress {
  const PresenceProgress({
    required this.validWindows,
    required this.elapsedWindows,
    required this.requiredWindows,
    required this.lastSignal,
    required this.fresh,
  });

  final int validWindows;
  final int elapsedWindows;
  final int requiredWindows;

  /// Strength of the newest reading, or null before anything was heard.
  final SignalStrength? lastSignal;

  /// Heard in this window or the previous one.
  final bool fresh;

  double get fraction =>
      elapsedWindows == 0 ? 0 : (validWindows / elapsedWindows).clamp(0, 1);

  /// Whether submitting now is likely to succeed. The backend decides; this
  /// only avoids offering a button that would certainly be refused.
  bool get looksEligible =>
      fresh && (lastSignal?.counts ?? false) && validWindows >= requiredWindows;
}

/// The beacons one phone has heard during one session.
///
/// Keeps the best reading per (window, hop) — a phone hears the same
/// advertisement many times a second, and sending all of them would only
/// inflate the request. Mirrors the backend's rules so the student sees
/// progress, but it proves nothing: the server re-checks every token.
class EvidenceLog {
  EvidenceLog({
    required this.sessionTag,
    required this.startedAt,
    required this.rssiThreshold,
    required this.hopDepth,
  });

  final String sessionTag;
  final DateTime startedAt;
  final int rssiThreshold;
  final int hopDepth;

  final Map<(int, int), Observation> _best = {};
  Observation? _newest;

  /// Records a sighting. Returns false when it is not for this session or
  /// could not have been heard yet.
  bool add(BeaconPayload payload, {required int rssi, required DateTime at}) {
    if (payload.sessionTag != sessionTag) return false;
    // A window from the future is either clock skew or a forgery; the server
    // ignores it, so there is no point keeping it.
    if (payload.window > windowIndex(startedAt: startedAt, at: at)) {
      return false;
    }

    final key = (payload.window, payload.hop);
    final existing = _best[key];
    final observation = Observation(
      window: payload.window,
      token: payload.token,
      rssi: rssi,
      hop: payload.hop,
    );
    if (existing == null || rssi > existing.rssi) _best[key] = observation;

    final newest = _newest;
    if (newest == null ||
        payload.window > newest.window ||
        (payload.window == newest.window && rssi > newest.rssi)) {
      _newest = observation;
    }
    return true;
  }

  List<Observation> get observations => _best.values.toList(growable: false);

  PresenceProgress progress(DateTime now) {
    final current = windowIndex(startedAt: startedAt, at: now);
    final elapsed = current + 1 < 1 ? 1 : current + 1;

    final counted = <int>{
      for (final o in _best.values)
        if (o.hop <= hopDepth &&
            SignalStrength.of(o.rssi, threshold: rssiThreshold).counts)
          o.window,
    };

    final newest = _newest;
    return PresenceProgress(
      validWindows: counted.length,
      elapsedWindows: elapsed,
      requiredWindows: requiredWindows(elapsed),
      lastSignal: newest == null
          ? null
          : SignalStrength.of(newest.rssi, threshold: rssiThreshold),
      fresh: newest != null && newest.window >= current - 1,
    );
  }
}
