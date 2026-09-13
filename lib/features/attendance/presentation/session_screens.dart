import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../security/application/security_controller.dart';
import '../../security/data/security_models.dart';
import '../../security/presentation/blocked_student_view.dart';
import '../application/attendance_controller.dart';
import '../ble/beacon_engines.dart';
import '../ble/beacon_radio.dart';
import '../ble/keep_alive.dart';
import '../data/attendance_models.dart';
import '../domain/beacon_codec.dart';
import '../domain/relay_policy.dart';

/// Opens the right screen for this person and session.
Future<void> openSessionScreen(
  BuildContext context, {
  required AttendanceSession session,
  required bool canManage,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => canManage
          ? TeacherSessionScreen(initial: session)
          : StudentSessionScreen(initial: session),
    ),
  );
}

// ---------------------------------------------------------------------------
// Starting a session
// ---------------------------------------------------------------------------

Future<void> showStartSessionSheet(
  BuildContext context, {
  required String classroomId,
}) async {
  final session = await showModalBottomSheet<AttendanceSession>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _StartSessionSheet(classroomId: classroomId),
  );
  if (session != null && context.mounted) {
    await openSessionScreen(context, session: session, canManage: true);
  }
}

class _StartSessionSheet extends ConsumerStatefulWidget {
  const _StartSessionSheet({required this.classroomId});

  final String classroomId;

  @override
  ConsumerState<_StartSessionSheet> createState() => _StartSessionSheetState();
}

class _StartSessionSheetState extends ConsumerState<_StartSessionSheet> {
  int _threshold = 5;
  int _rssi = -80;
  int _hops = Beacon.maxHopDepth;
  final int _radius = 15;
  bool _withLocation = true;
  bool _busy = false;
  String? _error;

  Future<(double?, double?)> _location() async {
    if (!_withLocation) return (null, null);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return (null, null);
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return (position.latitude, position.longitude);
    } on Exception {
      // Location is recorded for reference only; Bluetooth is the proof. A
      // cold GPS indoors must not stop a lecture from starting.
      return (null, null);
    }
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final radio = ref.read(beaconRadioProvider);
    try {
      // Check the radio *before* creating the session. A session whose
      // teacher cannot broadcast would sit open with nobody able to mark.
      final problem = await radio.prepare(advertise: true);
      if (problem != null) {
        setState(() => _error = problem.message);
        return;
      }
      if (!await radio.canAdvertise()) {
        setState(() => _error =
            'This phone cannot broadcast a Bluetooth beacon. Start attendance from another phone.');
        return;
      }

      final (latitude, longitude) = await _location();
      final session = await ref.read(attendanceRepositoryProvider).start(
            widget.classroomId,
            localDate: DateTime.now(),
            settings: SessionSettings(
              thresholdMinutes: _threshold,
              radiusMeters: _radius,
              rssiThreshold: _rssi,
              hopDepth: _hops,
            ),
            latitude: latitude,
            longitude: longitude,
          );
      if (mounted) Navigator.of(context).pop(session);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strength =
        SignalStrength.of(_rssi + Beacon.signalBandDb, threshold: _rssi);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Take attendance', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Keep this phone in the room. It broadcasts a beacon that students’ phones detect and relay.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            _SliderRow(
              label: 'Verification opens after',
              value: '$_threshold min',
              slider: Slider(
                value: _threshold.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _threshold = v.round()),
              ),
            ),
            _SliderRow(
              label: 'Minimum signal',
              value: '$_rssi dBm',
              help: 'Lower reaches further but lets in students further away. '
                  '${strength.label} starts at ${_rssi + Beacon.signalBandDb} dBm.',
              slider: Slider(
                value: _rssi.toDouble(),
                min: -95,
                max: -60,
                divisions: 7,
                onChanged:
                    _busy ? null : (v) => setState(() => _rssi = v.round()),
              ),
            ),
            const SizedBox(height: 8),
            Text('Relays between phones', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('None')),
                ButtonSegment(value: 1, label: Text('1 hop')),
                ButtonSegment(value: 2, label: Text('2 hops')),
              ],
              selected: {_hops},
              onSelectionChanged:
                  _busy ? null : (s) => setState(() => _hops = s.first),
            ),
            const SizedBox(height: 4),
            Text(
              'Relays let students at the back be detected through classmates’ phones.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Record classroom location'),
              subtitle: Text('Radius $_radius m · for reference only'),
              value: _withLocation,
              onChanged:
                  _busy ? null : (v) => setState(() => _withLocation = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _start,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.bluetooth_audio),
              label: const Text('Start session'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.slider,
    this.help,
  });

  final String label;
  final String value;
  final Widget slider;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
            Text(value, style: theme.textTheme.labelLarge),
          ],
        ),
        slider,
        if (help != null) Text(help!, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------

String _clockTime(DateTime t) {
  final local = t.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    this.action,
    this.error = false,
  });

  final IconData icon;
  final String text;
  final Widget? action;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background =
        error ? scheme.errorContainer : scheme.secondaryContainer;
    final foreground =
        error ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return Card(
      color: background,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: foreground),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: TextStyle(color: foreground))),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}

class _BatteryBanner extends StatefulWidget {
  const _BatteryBanner();

  @override
  State<_BatteryBanner> createState() => _BatteryBannerState();
}

class _BatteryBannerState extends State<_BatteryBanner> {
  bool _optimised = false;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    final optimised = await AttendanceKeepAlive.isBatteryOptimised();
    if (mounted) setState(() => _optimised = optimised);
  }

  @override
  Widget build(BuildContext context) {
    if (!_optimised) return const SizedBox.shrink();
    return _Banner(
      icon: Icons.battery_alert,
      text: 'Battery saving may stop attendance when the screen locks.',
      action: TextButton(
        onPressed: () async {
          await AttendanceKeepAlive.requestBatteryExemption();
          await _check();
        },
        child: const Text('Allow'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Teacher
// ---------------------------------------------------------------------------

class TeacherSessionScreen extends ConsumerStatefulWidget {
  const TeacherSessionScreen({required this.initial, super.key});

  final AttendanceSession initial;

  @override
  ConsumerState<TeacherSessionScreen> createState() =>
      _TeacherSessionScreenState();
}

class _TeacherSessionScreenState extends ConsumerState<TeacherSessionScreen> {
  late AttendanceSession _session = widget.initial;
  List<AttendanceRecord>? _records;
  TeacherBeacon? _beacon;
  Timer? _poll;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    if (_session.status.isRunning) {
      unawaited(_startBeacon());
      _poll = Timer.periodic(attendancePollInterval, (_) => _refresh());
    }
  }

  Future<void> _startBeacon() async {
    if (_session.beaconSecret == null) return;
    final radio = ref.read(beaconRadioProvider);
    final problem = await radio.prepare(advertise: true);
    if (!mounted) return;
    if (problem != null) {
      setState(() => _error = problem.message);
      return;
    }
    final beacon = TeacherBeacon(
      session: _session,
      radio: radio,
      clock: ServerClock(serverTime: _session.serverTime),
    );
    setState(() => _beacon = beacon);
    await beacon.start();
    await AttendanceKeepAlive.start(
      title: 'Taking attendance',
      text: 'Broadcasting the classroom beacon',
    );
  }

  Future<void> _stopBeacon() async {
    _poll?.cancel();
    _poll = null;
    await _beacon?.stop();
    await AttendanceKeepAlive.stop();
  }

  Future<void> _refresh() async {
    final repository = ref.read(attendanceRepositoryProvider);
    try {
      final session = await repository.get(_session.id);
      final records = await repository.records(_session.id);
      if (!mounted) return;
      setState(() {
        _session = session;
        _records = records;
        _error = null;
      });
      if (!session.status.isRunning) await _stopBeacon();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  void dispose() {
    unawaited(_stopBeacon());
    super.dispose();
  }

  Future<void> _run(Future<AttendanceSession> Function() action) async {
    setState(() => _busy = true);
    try {
      final updated = await action();
      if (mounted) setState(() => _session = updated);
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End session?'),
        content: const Text(
            'Everyone not yet marked will be recorded absent, and students can no longer mark themselves.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('End session')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() => ref.read(attendanceRepositoryProvider).end(_session.id));
  }

  Future<void> _correct(AttendanceRecord record, RecordStatus status) async {
    try {
      await ref.read(attendanceRepositoryProvider).correct(record.id, status);
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_session.status.isRunning) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop broadcasting?'),
        content: const Text(
            'The beacon stops when you leave this screen, so students cannot be detected. The session stays open — come back to resume.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Stay')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Leave')),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final records = _records;
    final present =
        records?.where((r) => r.status == RecordStatus.present).length ??
            _session.presentCount;
    final total = records?.length ?? _session.recordCount;

    return PopScope(
      canPop: !_session.status.isRunning,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text('Attendance · ${_session.date}')),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (_error != null)
                _Banner(icon: Icons.error_outline, text: _error!, error: true),
              if (_session.status.isRunning) ...[
                const _BatteryBanner(),
                if (_beacon != null)
                  ValueListenableBuilder<int?>(
                    valueListenable: _beacon!.window,
                    builder: (_, window, __) => _Banner(
                      icon: Icons.bluetooth_audio,
                      text: window == null
                          ? 'Starting the beacon…'
                          : 'Broadcasting · window ${window + 1}. Keep this screen open.',
                    ),
                  ),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_session.status.label,
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        switch (_session.status) {
                          SessionStatus.monitoring =>
                            'Students can mark themselves from ${_clockTime(_session.verificationOpensAt)}.',
                          SessionStatus.active =>
                            'Students in range for 70% of the lecture can mark themselves.',
                          SessionStatus.ended =>
                            'Ended ${_session.endedAt == null ? '' : _clockTime(_session.endedAt!)}.',
                        },
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Text('$present of $total present',
                          style: theme.textTheme.headlineSmall),
                      Text(
                        'Signal ≥ ${_session.rssiThreshold} dBm · up to ${_session.hopDepth} relay${_session.hopDepth == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (_session.status.isRunning) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            if (_session.status == SessionStatus.monitoring)
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _run(() => ref
                                          .read(attendanceRepositoryProvider)
                                          .openVerification(_session.id)),
                                  child: const Text('Open now'),
                                ),
                              ),
                            if (_session.status == SessionStatus.monitoring)
                              const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: _busy ? null : _end,
                                child: const Text('End session'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (records == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (records.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No students in this class yet.',
                      textAlign: TextAlign.center),
                )
              else
                for (final record in records)
                  RecordTile(
                    record: record,
                    onCorrect: (status) => _correct(record, status),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class RecordTile extends StatelessWidget {
  const RecordTile({required this.record, this.onCorrect, super.key});

  final AttendanceRecord record;
  final void Function(RecordStatus status)? onCorrect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (record.status) {
      RecordStatus.present => (Icons.check_circle, Colors.green),
      RecordStatus.absent => (Icons.cancel, scheme.error),
      RecordStatus.pending => (Icons.schedule, scheme.onSurfaceVariant),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(record.studentName),
        subtitle: Text([
          record.status.label,
          if (record.markedAt != null) _clockTime(record.markedAt!),
          if (record.corrected) 'set by teacher',
        ].join(' · ')),
        trailing: onCorrect == null
            ? null
            : PopupMenuButton<RecordStatus>(
                tooltip: 'Correct',
                onSelected: onCorrect,
                itemBuilder: (_) => [
                  if (record.status != RecordStatus.present)
                    const PopupMenuItem(
                        value: RecordStatus.present,
                        child: Text('Mark present')),
                  if (record.status != RecordStatus.absent)
                    const PopupMenuItem(
                        value: RecordStatus.absent, child: Text('Mark absent')),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Student
// ---------------------------------------------------------------------------

class StudentSessionScreen extends ConsumerStatefulWidget {
  const StudentSessionScreen({required this.initial, super.key});

  final AttendanceSession initial;

  @override
  ConsumerState<StudentSessionScreen> createState() =>
      _StudentSessionScreenState();
}

class _StudentSessionScreenState extends ConsumerState<StudentSessionScreen> {
  late AttendanceSession _session = widget.initial;
  StudentTracker? _tracker;
  Timer? _poll;
  RadioProblem? _problem;
  VerifyResult? _result;
  String? _error;
  bool _submitting = false;

  /// Checked before listening: there is no point gathering evidence for a
  /// student who cannot submit it.
  MySecurityStatus? _security;
  String? _bindingProblem;

  bool get _done =>
      !_session.status.isRunning || _session.myStatus == RecordStatus.present;

  BlockInfo? get _block => _security?.blockFor(_session.classroomId);

  @override
  void initState() {
    super.initState();
    if (!_done) unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      final security = await ref.read(securityRepositoryProvider).myStatus();
      if (!mounted) return;
      setState(() => _security = security);
      if (security.blockFor(_session.classroomId) != null) return;

      // Bind now rather than at the moment of marking, so "this account is
      // bound to another phone" is known before the lecture, not after it.
      await ref.read(attendanceMarkerProvider)?.ensureBound();
    } on MarkingBlocked catch (error) {
      if (mounted) setState(() => _bindingProblem = error.message);
      return;
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
    if (!mounted) return;
    unawaited(_startTracking());
    _poll = Timer.periodic(attendancePollInterval, (_) => _refresh());
  }

  Future<void> _startTracking() async {
    final radio = ref.read(beaconRadioProvider);
    var problem = await radio.prepare(advertise: true);
    var canRelay = problem == null && await radio.canAdvertise();
    if (problem == RadioProblem.permissionDenied) {
      // Advertising permission refused: still take part as a listener.
      problem = await radio.prepare(advertise: false);
      canRelay = false;
    }
    if (!mounted) return;
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }

    final tracker = StudentTracker(
      session: _session,
      radio: radio,
      clock: ServerClock(serverTime: _session.serverTime),
      canAdvertise: canRelay,
    )..start();
    setState(() {
      _tracker = tracker;
      _problem = null;
    });
    await AttendanceKeepAlive.start(
      title: 'Attendance in progress',
      text: 'Listening for the classroom beacon',
    );
  }

  Future<void> _stopTracking() async {
    _poll?.cancel();
    _poll = null;
    await _tracker?.stop();
    await AttendanceKeepAlive.stop();
  }

  Future<void> _refresh() async {
    try {
      final session =
          await ref.read(attendanceRepositoryProvider).get(_session.id);
      if (!mounted) return;
      setState(() => _session = session);
      await _tracker?.updateSession(session);
      if (_done) await _stopTracking();
    } on ApiException {
      // A missed poll is harmless; the next one will catch up.
    }
  }

  Future<void> _mark() async {
    final tracker = _tracker;
    final marker = ref.read(attendanceMarkerProvider);
    if (tracker == null || marker == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await marker.mark(
        session: _session,
        observations: tracker.log.observations,
        serverNow: tracker.clock.now(),
      );
      if (!mounted) return;
      setState(() => _result = result);
      if (result.accepted) {
        await tracker.markedPresent();
        await _refresh();
      }
    } on MarkingBlocked catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    unawaited(_stopTracking());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('Attendance · ${_session.date}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_session.myStatus == RecordStatus.present)
            const _Banner(
                icon: Icons.check_circle, text: 'You are marked present.')
          else if (!_session.status.isRunning)
            _Banner(
              icon: Icons.event_busy,
              text:
                  'This session has ended. You were recorded ${(_session.myStatus ?? RecordStatus.absent).label.toLowerCase()}.',
            )
          else if (_block != null)
            BlockedStudentView(block: _block!)
          else if (_bindingProblem != null)
            _Banner(
              icon: Icons.phonelink_lock,
              text: _bindingProblem!,
              error: true,
            )
          else ...[
            if (_security != null && !_security!.emailVerified)
              _Banner(
                icon: Icons.mark_email_unread_outlined,
                text: 'Verify your email before you can mark attendance.',
                error: true,
                action: TextButton(
                  onPressed: () async {
                    await context.push(Routes.verifyEmail);
                    if (!mounted) return;
                    final security =
                        await ref.read(securityRepositoryProvider).myStatus();
                    if (mounted) setState(() => _security = security);
                  },
                  child: const Text('Verify'),
                ),
              ),
            if (_problem != null)
              _Banner(
                icon: Icons.bluetooth_disabled,
                text: _problem!.message,
                error: true,
                action: TextButton(
                    onPressed: _startTracking, child: const Text('Retry')),
              ),
            const _BatteryBanner(),
            if (_tracker != null)
              ValueListenableBuilder<TrackerState>(
                valueListenable: _tracker!.state,
                builder: (_, state, __) => _StudentProgress(
                  session: _session,
                  state: state,
                  canRelay: _tracker!.canAdvertise,
                ),
              ),
            if (_result != null && !_result!.accepted)
              _Banner(
                icon: Icons.info_outline,
                text:
                    '${_result!.message} (${_result!.validWindows} of ${_result!.requiredWindows} needed)',
                error: true,
              ),
            if (_error != null)
              _Banner(icon: Icons.error_outline, text: _error!, error: true),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _session.status == SessionStatus.active &&
                      _tracker != null &&
                      (_security?.emailVerified ?? false) &&
                      !_submitting
                  ? _mark
                  : null,
              icon: const Icon(Icons.fingerprint),
              label: Text(_session.status == SessionStatus.active
                  ? 'Mark me present'
                  : 'Opens at ${_clockTime(_session.verificationOpensAt)}'),
            ),
            const SizedBox(height: 8),
            Text(
              'Keep the app open or the phone locked with the notification showing. Leaving this screen stops listening.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _StudentProgress extends StatelessWidget {
  const _StudentProgress({
    required this.session,
    required this.state,
    required this.canRelay,
  });

  final AttendanceSession session;
  final TrackerState state;
  final bool canRelay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = state.progress;
    final signal = progress.lastSignal;
    final heard = signal != null && progress.fresh;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  heard ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                  color: heard && signal.counts
                      ? Colors.green
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    !heard
                        ? 'Looking for the classroom beacon…'
                        : 'Signal: ${signal.label}${state.lastHop != null && state.lastHop! > 0 ? ' · via ${state.lastHop} relay${state.lastHop == 1 ? '' : 's'}' : ''}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: progress.fraction),
            const SizedBox(height: 6),
            Text(
              'In range ${progress.validWindows} of ${progress.elapsedWindows} '
              'half-minutes · ${progress.requiredWindows} needed',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              state.relaying
                  ? 'Relaying the beacon to classmates nearby.'
                  : !canRelay
                      ? 'This phone can only listen, not relay. That does not affect your attendance.'
                      : state.lastRelayDecision == RelayDecision.maxDepthReached
                          ? 'Too far down the relay chain to pass the beacon on.'
                          : 'Your phone relays the beacon briefly when it hears it clearly.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
