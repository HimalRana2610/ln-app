import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/quiz_models.dart';

/// Keeps a quiz fresh by polling — the rebuild's stand-in for the old app's
/// Firestore listeners (see phase 6, "Polling instead of realtime").
///
/// Runs only while the tab is on screen *and* the app is in the foreground, so
/// a phone in a pocket or on another tab makes no requests. The next poll is
/// armed after the previous one finishes, never on a fixed beat, so a slow
/// network cannot stack requests; its delay is whatever
/// `poll_interval_seconds` the server last sent.
///
/// A plain class with no Flutter bindings, so tests drive it with `fakeAsync`.
class QuizPoller {
  QuizPoller({
    required Future<QuizState> Function() fetch,
    Duration initialInterval = const Duration(seconds: 3),
  })  : _fetch = fetch,
        _interval = initialInterval;

  final Future<QuizState> Function() _fetch;

  /// The latest state, or null before the first successful poll.
  final state = ValueNotifier<QuizState?>(null);

  /// The last poll's failure; cleared by the next success.
  final error = ValueNotifier<Object?>(null);

  Duration _interval;
  Timer? _timer;
  bool _visible = false;
  bool _resumed = true;
  bool _inFlight = false;
  bool _disposed = false;

  /// Increments whenever polling stops, so a request that was already in flight
  /// does not re-arm a timer after the tab was hidden.
  int _generation = 0;

  Duration get interval => _interval;

  bool get isRunning => _visible && _resumed && !_disposed;

  /// The tab became visible or hidden.
  void setVisible(bool visible) {
    _visible = visible;
    _sync();
  }

  /// The app was resumed or paused.
  void setResumed(bool resumed) {
    _resumed = resumed;
    _sync();
  }

  /// Poll now, e.g. straight after answering, without waiting for the timer.
  Future<void> refresh() => _poll(_generation);

  void _sync() {
    if (isRunning) {
      // Coming back into view: fetch at once rather than showing a stale
      // question for a whole interval.
      if (_timer == null && !_inFlight) _poll(_generation);
    } else {
      _generation++;
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _poll(int generation) async {
    _timer?.cancel();
    _timer = null;
    _inFlight = true;

    try {
      final next = await _fetch();
      if (_disposed) return;
      state.value = next;
      error.value = null;
      if (next.pollIntervalSeconds > 0) {
        _interval = Duration(seconds: next.pollIntervalSeconds);
      }
    } on Object catch (e) {
      if (_disposed) return;
      // Keep showing the last good state; the next poll may well succeed.
      error.value = e;
    } finally {
      _inFlight = false;
    }

    if (isRunning && generation == _generation && _timer == null) {
      _timer = Timer(_interval, () => _poll(generation));
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _timer = null;
    state.dispose();
    error.dispose();
  }
}
