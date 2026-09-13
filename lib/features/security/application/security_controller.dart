import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../attendance/data/attendance_models.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/domain/evidence_log.dart';
import '../../auth/application/auth_controller.dart';
import '../data/biometric_gate.dart';
import '../data/device_identity.dart';
import '../data/security_models.dart';
import '../data/security_repository.dart';
import '../domain/attendance_signer.dart';

final securityRepositoryProvider = Provider<SecurityRepository>((ref) {
  return SecurityRepository(apiClient: ref.watch(apiClientProvider));
});

final deviceIdentityProvider =
    Provider<DeviceIdentity>((ref) => DeviceIdentity());

final biometricGateProvider = Provider<BiometricGate>((ref) => LocalAuthGate());

final mySecurityProvider = FutureProvider<MySecurityStatus>((ref) {
  return ref.read(securityRepositoryProvider).myStatus();
});

final faceStatusProvider = FutureProvider<FaceStatus>((ref) {
  return ref.read(securityRepositoryProvider).faceStatus();
});

final studentSecurityProvider =
    FutureProvider.family<List<StudentSecurity>, String>((ref, classroomId) {
  return ref.read(securityRepositoryProvider).students(classroomId);
});

final securityAlertsProvider =
    FutureProvider.family<List<SecurityAlert>, String>((ref, classroomId) {
  return ref.read(securityRepositoryProvider).alerts(classroomId);
});

/// Why marking did not reach the server.
class MarkingBlocked implements Exception {
  const MarkingBlocked(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Binds this phone, confirms the owner, signs, and submits attendance.
///
/// The order matters: the biometric check happens *after* the evidence is
/// gathered and immediately before signing, so the claim in the signed
/// message describes the moment of marking, not some earlier unlock.
class AttendanceMarker {
  AttendanceMarker({
    required this.security,
    required this.attendance,
    required this.identity,
    required this.biometrics,
    required this.userId,
    Random? random,
  }) : _random = random ?? Random.secure();

  final SecurityRepository security;
  final AttendanceRepository attendance;
  final DeviceIdentity identity;
  final BiometricGate biometrics;
  final String userId;
  final Random _random;

  DeviceInfo? _device;

  /// Registers (or checks in) this phone. Throws [MarkingBlocked] when the
  /// account is bound elsewhere or the phone belongs to someone else.
  Future<DeviceInfo> ensureBound() async {
    if (_device != null) return _device!;
    try {
      return _device = await security.registerDevice(
        publicKey: await identity.publicKeyBase64(),
        fingerprintHash: await identity.fingerprintHash(),
        platform: DeviceIdentity.platformName(),
      );
    } on ApiException catch (error) {
      if (error.statusCode == 409) throw MarkingBlocked(error.message);
      rethrow;
    }
  }

  String _nonce() => base64Url
      .encode(List<int>.generate(18, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  Future<VerifyResult> mark({
    required AttendanceSession session,
    required List<Observation> observations,
    required DateTime serverNow,
  }) async {
    final device = await ensureBound();

    final failure =
        await biometrics.confirm('Confirm it is you to mark attendance');
    if (failure != null) throw MarkingBlocked(failure.message);

    final body = await AttendanceSigner.signedBody(
      keyPair: await identity.keyPair(),
      sessionId: session.id,
      userId: userId,
      deviceId: device.id,
      nonce: _nonce(),
      // Server time, not the phone's: a phone a few minutes out would
      // otherwise be refused as a stale request.
      issuedAt: serverNow.millisecondsSinceEpoch ~/ 1000,
      biometric: true,
      observations: observations,
    );
    return attendance.verifySigned(session.id, body);
  }
}

final attendanceMarkerProvider = Provider<AttendanceMarker?>((ref) {
  final auth = ref.watch(authControllerProvider);
  if (auth is! AuthAuthenticated) return null;
  return AttendanceMarker(
    security: ref.watch(securityRepositoryProvider),
    attendance: AttendanceRepository(apiClient: ref.watch(apiClientProvider)),
    identity: ref.watch(deviceIdentityProvider),
    biometrics: ref.watch(biometricGateProvider),
    userId: auth.user.id,
  );
});
