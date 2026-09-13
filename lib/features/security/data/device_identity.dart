import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:android_id/android_id.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// This phone's attendance key pair and a hashed hardware identifier.
///
/// **One key per installation, not per account.** If a friend signs in on
/// your phone, the same public key reaches the server under a second account,
/// which is exactly what the backend refuses as a shared device.
///
/// The private seed lives in `flutter_secure_storage` (Android Keystore-backed
/// encryption) and never leaves the phone. It is not hardware-bound: a rooted
/// phone could extract it. Device binding, the biometric claim and the beacon
/// together make cheating costly; none of them alone is proof.
class DeviceIdentity {
  DeviceIdentity(
      {FlutterSecureStorage? storage, Future<String?> Function()? androidId})
      : _storage = storage ?? const FlutterSecureStorage(),
        _androidId = androidId ?? const AndroidId().getId;

  static const _seedKey = 'ln_attendance_key_seed';
  static const _installKey = 'ln_install_id';

  final FlutterSecureStorage _storage;
  final Future<String?> Function() _androidId;

  SimpleKeyPair? _cached;

  Future<SimpleKeyPair> keyPair() async {
    if (_cached != null) return _cached!;
    var seedB64 = await _storage.read(key: _seedKey);
    if (seedB64 == null) {
      final random = Random.secure();
      seedB64 =
          base64Encode(List<int>.generate(32, (_) => random.nextInt(256)));
      await _storage.write(key: _seedKey, value: seedB64);
    }
    return _cached = await Ed25519().newKeyPairFromSeed(base64Decode(seedB64));
  }

  Future<String> publicKeyBase64() async {
    final publicKey = await (await keyPair()).extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  /// SHA-256 of ANDROID_ID, which survives reinstalling the app — so a fresh
  /// install (and fresh key) is still recognised as the same handset. Falls
  /// back to a random per-install id where there is none.
  Future<String> fingerprintHash() async {
    String? raw;
    if (Platform.isAndroid) {
      try {
        raw = await _androidId();
      } on Exception {
        raw = null;
      }
    }
    if (raw == null || raw.isEmpty) {
      raw = await _storage.read(key: _installKey);
      if (raw == null) {
        final random = Random.secure();
        raw = List<int>.generate(16, (_) => random.nextInt(256))
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        await _storage.write(key: _installKey, value: raw);
      }
      raw = 'install:$raw';
    } else {
      raw = 'android:$raw';
    }
    return crypto.sha256.convert(utf8.encode(raw)).toString();
  }

  static String platformName() => Platform.isIOS ? 'ios' : 'android';
}
