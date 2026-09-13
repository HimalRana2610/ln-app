import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/features/attendance/domain/evidence_log.dart';
import 'package:ln_app/features/security/domain/attendance_signer.dart';

// The same key, message and signature as
// ln-backend/tests/test_security.py::test_signing_vector_is_pinned_...
// Ed25519 is deterministic, so one vector pins field order, newlines and the
// observation digest. If this fails, every student's attendance would be
// rejected with invalid_signature.
const _observations = [
  Observation(window: 3, token: '0011223344556677', rssi: -70, hop: 1),
  Observation(window: 4, token: '8899aabbccddeeff', rssi: -65, hop: 0),
];

void main() {
  test('observation digest matches the backend', () {
    expect(
      AttendanceSigner.observationsDigest(_observations),
      '5abcc723b65a0ca97a8a4e622c96cb428c59101a7c579c7e6da2b984f40f663d',
    );
  });

  test('signature matches the backend byte for byte', () async {
    final keyPair =
        await Ed25519().newKeyPairFromSeed(List<int>.generate(32, (i) => i));
    final publicKey = await keyPair.extractPublicKey();
    expect(base64Encode(publicKey.bytes),
        'A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=');

    final body = await AttendanceSigner.signedBody(
      keyPair: keyPair,
      sessionId: '12345678-1234-5678-1234-567812345678',
      userId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      deviceId: '11111111-2222-3333-4444-555555555555',
      nonce: 'nonce-0123456789abcdef',
      issuedAt: 1789376400,
      biometric: true,
      observations: _observations,
    );

    expect(
      body['signature'],
      'iBVK7P/zGI07qjZbKElKnNW7t16LbH87vnriZFnyJsh7mPzPWkOtZ4k8ayQ8BeLIwNXWm2Zwl21a1DvvcRzFBA==',
    );
    expect(body['biometric_verified'], isTrue);
    expect(body['observations'], hasLength(2));
  });

  test('the biometric claim is part of what is signed', () {
    List<int> build({required bool biometric}) => AttendanceSigner.message(
          sessionId: 's',
          userId: 'u',
          deviceId: 'd',
          nonce: 'n',
          issuedAt: 1,
          biometric: biometric,
          observations: _observations,
        );
    expect(build(biometric: true), isNot(build(biometric: false)));
  });
}
