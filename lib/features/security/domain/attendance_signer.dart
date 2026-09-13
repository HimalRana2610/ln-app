import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import '../../attendance/domain/evidence_log.dart';

/// Builds and signs the attendance message the backend verifies.
///
/// Mirrors `ln-backend/app/services/signing.py` exactly. The pinned vector in
/// `test/attendance_signer_test.dart` is the same one the backend test pins, so
/// a change to the format on either side fails both suites.
abstract final class AttendanceSigner {
  static const version = 'ln-attendance-v1';

  static String observationsDigest(List<Observation> observations) {
    final lines = observations
        .map((o) => '${o.window}:${o.token.toLowerCase()}:${o.rssi}:${o.hop}')
        .join('\n');
    return crypto.sha256.convert(utf8.encode(lines)).toString();
  }

  static List<int> message({
    required String sessionId,
    required String userId,
    required String deviceId,
    required String nonce,
    required int issuedAt,
    required bool biometric,
    required List<Observation> observations,
  }) {
    return utf8.encode([
      version,
      'session:$sessionId',
      'user:$userId',
      'device:$deviceId',
      'nonce:$nonce',
      'issued_at:$issuedAt',
      'biometric:${biometric ? 1 : 0}',
      'observations:${observationsDigest(observations)}',
    ].join('\n'));
  }

  /// The complete verify request body, signed with [keyPair].
  static Future<Map<String, Object>> signedBody({
    required SimpleKeyPair keyPair,
    required String sessionId,
    required String userId,
    required String deviceId,
    required String nonce,
    required int issuedAt,
    required bool biometric,
    required List<Observation> observations,
  }) async {
    final signature = await Ed25519().sign(
      message(
        sessionId: sessionId,
        userId: userId,
        deviceId: deviceId,
        nonce: nonce,
        issuedAt: issuedAt,
        biometric: biometric,
        observations: observations,
      ),
      keyPair: keyPair,
    );
    return {
      'observations': [for (final o in observations) o.toJson()],
      'device_id': deviceId,
      'nonce': nonce,
      'issued_at': issuedAt,
      'signature': base64Encode(signature.bytes),
      'biometric_verified': biometric,
    };
  }
}
