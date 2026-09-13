import 'package:local_auth/local_auth.dart';

/// Why a biometric check did not pass.
enum BiometricFailure {
  unavailable(
      'This phone has no fingerprint or face unlock set up. Set one up in Settings to mark attendance.'),
  cancelled('Confirmation was cancelled.'),
  lockedOut('Too many attempts. Unlock your phone, then try again.'),
  failed('Could not confirm it is you. Try again.');

  const BiometricFailure(this.message);

  final String message;
}

/// Asks the platform to confirm the phone's owner is holding it.
abstract interface class BiometricGate {
  /// Null when confirmed.
  Future<BiometricFailure?> confirm(String reason);
}

class LocalAuthGate implements BiometricGate {
  LocalAuthGate({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<BiometricFailure?> confirm(String reason) async {
    try {
      if (!await _auth.isDeviceSupported() ||
          (await _auth.getAvailableBiometrics()).isEmpty) {
        return BiometricFailure.unavailable;
      }
      // biometricOnly: a PIN is exactly what a friend holding your unlocked
      // phone could be told. Only a fingerprint or face stops a handover.
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return ok ? null : BiometricFailure.failed;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback =>
          BiometricFailure.cancelled,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout =>
          BiometricFailure.lockedOut,
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.noCredentialsSet =>
          BiometricFailure.unavailable,
        _ => BiometricFailure.failed,
      };
    }
  }
}
