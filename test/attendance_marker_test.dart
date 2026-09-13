import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/core/network/api_exception.dart';
import 'package:ln_app/features/attendance/data/attendance_models.dart';
import 'package:ln_app/features/attendance/data/attendance_repository.dart';
import 'package:ln_app/features/attendance/domain/evidence_log.dart';
import 'package:ln_app/features/security/application/security_controller.dart';
import 'package:ln_app/features/security/data/biometric_gate.dart';
import 'package:ln_app/features/security/data/device_identity.dart';
import 'package:ln_app/features/security/data/security_models.dart';
import 'package:ln_app/features/security/data/security_repository.dart';
import 'package:ln_app/features/security/domain/attendance_signer.dart';
import 'package:ln_app/features/security/presentation/blocked_student_view.dart';
import 'package:ln_app/features/security/presentation/verify_email_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockSecurity extends Mock implements SecurityRepository {}

class MockAttendance extends Mock implements AttendanceRepository {}

class FakeIdentity implements DeviceIdentity {
  SimpleKeyPair? _pair;

  @override
  Future<SimpleKeyPair> keyPair() async =>
      _pair ??= await Ed25519().newKeyPairFromSeed(List<int>.filled(32, 7));

  @override
  Future<String> publicKeyBase64() async =>
      base64Encode((await (await keyPair()).extractPublicKey()).bytes);

  @override
  Future<String> fingerprintHash() async => 'f' * 64;
}

class FakeGate implements BiometricGate {
  FakeGate(this.result);

  BiometricFailure? result;
  int calls = 0;

  @override
  Future<BiometricFailure?> confirm(String reason) async {
    calls++;
    return result;
  }
}

final _session = AttendanceSession(
  id: '12345678-1234-5678-1234-567812345678',
  classroomId: 'c',
  startedBy: 't',
  startedByName: 'Grace Hopper',
  date: '2026-09-14',
  status: SessionStatus.active,
  startedAt: DateTime.utc(2026, 9, 14, 9),
  verificationOpensAt: DateTime.utc(2026, 9, 14, 9),
  radiusMeters: 15,
  thresholdMinutes: 5,
  rssiThreshold: -80,
  hopDepth: 2,
  sessionTag: '12345678',
  windowSeconds: 30,
  serverTime: DateTime.utc(2026, 9, 14, 9, 2),
  presentCount: 0,
  recordCount: 1,
);

const _observations = [
  Observation(window: 3, token: '0011223344556677', rssi: -70, hop: 0),
];

final _device = DeviceInfo(
  id: '11111111-2222-3333-4444-555555555555',
  platform: 'android',
  model: null,
  boundAt: DateTime.utc(2026),
  lastSeenAt: DateTime.utc(2026),
);

const _accepted = VerifyResult(
  accepted: true,
  message: 'You are marked present.',
  validWindows: 5,
  elapsedWindows: 5,
  requiredWindows: 4,
);

void main() {
  late MockSecurity security;
  late MockAttendance attendance;
  late FakeIdentity identity;

  setUpAll(() => registerFallbackValue(<String, Object>{}));

  setUp(() {
    security = MockSecurity();
    attendance = MockAttendance();
    identity = FakeIdentity();
    when(() => security.registerDevice(
          publicKey: any(named: 'publicKey'),
          fingerprintHash: any(named: 'fingerprintHash'),
          platform: any(named: 'platform'),
        )).thenAnswer((_) async => _device);
    when(() => attendance.verifySigned(any(), any()))
        .thenAnswer((_) async => _accepted);
  });

  AttendanceMarker marker(FakeGate gate) => AttendanceMarker(
        security: security,
        attendance: attendance,
        identity: identity,
        biometrics: gate,
        userId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      );

  test('binds, confirms, signs with server time, and submits', () async {
    final gate = FakeGate(null);
    final result = await marker(gate).mark(
      session: _session,
      observations: _observations,
      serverNow: DateTime.utc(2026, 9, 14, 9, 2, 15),
    );
    expect(result.accepted, isTrue);
    expect(gate.calls, 1);

    final body =
        verify(() => attendance.verifySigned(_session.id, captureAny()))
            .captured
            .single as Map<String, Object>;
    expect(body['device_id'], _device.id);
    expect(body['biometric_verified'], isTrue);
    expect(body['issued_at'],
        DateTime.utc(2026, 9, 14, 9, 2, 15).millisecondsSinceEpoch ~/ 1000);
    expect((body['nonce']! as String).length, greaterThanOrEqualTo(16));

    // The signature verifies against this phone's key over the exact message
    // the backend rebuilds.
    final message = AttendanceSigner.message(
      sessionId: _session.id,
      userId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      deviceId: _device.id,
      nonce: body['nonce']! as String,
      issuedAt: body['issued_at']! as int,
      biometric: true,
      observations: _observations,
    );
    final publicKey = await (await identity.keyPair()).extractPublicKey();
    final ok = await Ed25519().verify(
      message,
      signature: Signature(base64Decode(body['signature']! as String),
          publicKey: publicKey),
    );
    expect(ok, isTrue);
  });

  test('nothing is sent when the biometric check fails', () async {
    final gate = FakeGate(BiometricFailure.cancelled);
    await expectLater(
      marker(gate).mark(
          session: _session,
          observations: _observations,
          serverNow: DateTime.utc(2026)),
      throwsA(isA<MarkingBlocked>().having(
          (e) => e.message, 'message', BiometricFailure.cancelled.message)),
    );
    verifyNever(() => attendance.verifySigned(any(), any()));
  });

  test('an account bound to another phone is explained, not retried', () async {
    when(() => security.registerDevice(
              publicKey: any(named: 'publicKey'),
              fingerprintHash: any(named: 'fingerprintHash'),
              platform: any(named: 'platform'),
            ))
        .thenThrow(const ApiException(
            statusCode: 409,
            code: 'conflict',
            message: 'Your account is already bound to another phone.'));
    final gate = FakeGate(null);
    await expectLater(
      marker(gate).mark(
          session: _session,
          observations: _observations,
          serverNow: DateTime.utc(2026)),
      throwsA(isA<MarkingBlocked>()),
    );
    expect(gate.calls, 0,
        reason: 'no biometric prompt for a request that cannot succeed');
  });

  test('each attempt uses a fresh nonce', () async {
    final m = marker(FakeGate(null));
    for (var i = 0; i < 2; i++) {
      await m.mark(
          session: _session,
          observations: _observations,
          serverNow: DateTime.utc(2026));
    }
    final nonces = verify(() => attendance.verifySigned(any(), captureAny()))
        .captured
        .map((b) => (b as Map<String, Object>)['nonce'])
        .toSet();
    expect(nonces, hasLength(2));
  });

  group('email code input', () {
    test('accepts pasted and spaced codes', () {
      expect(normaliseOtp('123 456'), '123456');
      expect(normaliseOtp('123-456\n'), '123456');
      expect(normaliseOtp('12345'), isNull);
      expect(normaliseOtp('abcdef'), isNull);
    });
  });

  group('security models', () {
    test('parse the status and find a class block', () {
      final status = MySecurityStatus.fromJson({
        'email_verified': true,
        'device': null,
        'face_enrolled': false,
        'blocks': [
          {
            'classroom_id': 'c1',
            'classroom_name': 'Networks',
            'reason': 'Marked from home',
            'blocked_at': '2026-09-14T09:00:00Z',
          },
        ],
      });
      expect(status.blockFor('c1')?.reason, 'Marked from home');
      expect(status.blockFor('c2'), isNull);
    });
  });

  testWidgets('the blocked view says why and who can clear it', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: BlockedStudentView(
          block: BlockInfo(
              classroomId: 'c1',
              classroomName: 'Networks',
              reason: 'Marked from home'),
        ),
      ),
    ));
    expect(find.text('Attendance blocked'), findsOneWidget);
    expect(find.text('Reason: Marked from home'), findsOneWidget);
    expect(find.textContaining('speak to your teacher'), findsOneWidget);
  });
}
