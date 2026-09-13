import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../ble/beacon_radio.dart';
import '../ble/plugin_beacon_radio.dart';
import '../data/attendance_models.dart';
import '../data/attendance_repository.dart';

/// How often an open session's screens refresh from the server.
const attendancePollInterval = Duration(seconds: 5);

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(apiClient: ref.watch(apiClientProvider));
});

/// Overridden in tests with a fake; the emulator has no Bluetooth either.
final beaconRadioProvider = Provider<BeaconRadio>((ref) => PluginBeaconRadio());

final attendanceSessionsProvider =
    FutureProvider.family<List<AttendanceSession>, String>((ref, classroomId) {
  return ref.read(attendanceRepositoryProvider).list(classroomId);
});

final attendanceRecordsProvider =
    FutureProvider.family<List<AttendanceRecord>, String>((ref, sessionId) {
  return ref.read(attendanceRepositoryProvider).records(sessionId);
});
