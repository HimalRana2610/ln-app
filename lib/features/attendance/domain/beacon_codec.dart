import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The attendance beacon's constants and byte format.
///
/// Mirrors `ln-backend/app/services/beacon.py`, which is the authority. The
/// token values in `test/beacon_codec_test.dart` are the same ones the backend
/// test pins, so the two cannot drift apart silently.
abstract final class Beacon {
  static const windowSeconds = 30;
  static const maxHopDepth = 2;
  static const rebroadcastSeconds = 30;
  static const tokenBytes = 8;
  static const requiredPresence = 0.70;

  /// Bluetooth SIG company id reserved for testing.
  static const manufacturerId = 0xFFFF;

  /// Strong is this many dB above the session's threshold.
  static const signalBandDb = 10;

  /// session tag (4) + window (4) + hop (1) + token (8).
  static const payloadLength = 17;
}

/// How strong a received beacon is, relative to the session's threshold.
enum SignalStrength {
  strong('Strong'),
  medium('Medium'),
  weak('Weak'),
  outOfRange('Out of range');

  const SignalStrength(this.label);

  final String label;

  /// Strong and Medium count for attendance and may be relayed. Nothing else.
  bool get counts => this == strong || this == medium;

  static SignalStrength of(int rssi, {required int threshold}) {
    if (rssi >= threshold + Beacon.signalBandDb) return strong;
    if (rssi >= threshold) return medium;
    if (rssi >= threshold - Beacon.signalBandDb) return weak;
    return outOfRange;
  }
}

/// The window a moment falls in. Negative before the session began.
int windowIndex({required DateTime startedAt, required DateTime at}) {
  final elapsedMs = at.difference(startedAt).inMilliseconds;
  return (elapsedMs / (Beacon.windowSeconds * 1000)).floor();
}

/// When a window begins — the moment the teacher's phone must switch tokens.
DateTime windowStart(DateTime startedAt, int window) =>
    startedAt.add(Duration(seconds: window * Beacon.windowSeconds));

/// Windows needed in range out of [elapsed], rounded in the strict direction.
int requiredWindows(int elapsed) {
  // Rounded to 9 places first: 0.7 * 10 is 7.000000000000001 in floating
  // point, and a bare ceil would demand 8 of 10 — as the backend guards too.
  final exact =
      double.parse((Beacon.requiredPresence * elapsed).toStringAsFixed(9));
  return exact.ceil();
}

/// The window's token: `HMAC-SHA256(secret, "<sessionId>:<window>")`, first 8 bytes.
Uint8List beaconToken({
  required String secretHex,
  required String sessionId,
  required int window,
}) {
  final hmac = Hmac(sha256, hexToBytes(secretHex));
  final digest = hmac.convert(utf8.encode('$sessionId:$window'));
  return Uint8List.fromList(digest.bytes.sublist(0, Beacon.tokenBytes));
}

/// The first 4 bytes of a session UUID, which identify it on air.
Uint8List sessionTagBytes(String sessionId) =>
    hexToBytes(sessionId.replaceAll('-', '').substring(0, 8));

/// One advertisement's contents.
class BeaconPayload {
  const BeaconPayload({
    required this.sessionTag,
    required this.window,
    required this.hop,
    required this.token,
  });

  /// 8 lowercase hex characters.
  final String sessionTag;
  final int window;
  final int hop;

  /// 16 lowercase hex characters.
  final String token;

  Uint8List encode() {
    final bytes = ByteData(Beacon.payloadLength);
    final tag = hexToBytes(sessionTag);
    final tokenBytes = hexToBytes(token);
    for (var i = 0; i < 4; i++) {
      bytes.setUint8(i, tag[i]);
    }
    bytes.setUint32(4, window, Endian.big);
    bytes.setUint8(8, hop);
    for (var i = 0; i < Beacon.tokenBytes; i++) {
      bytes.setUint8(9 + i, tokenBytes[i]);
    }
    return bytes.buffer.asUint8List();
  }

  /// Parses manufacturer data, or returns null for anything that is not ours.
  ///
  /// Scanning a lecture hall picks up headphones, watches and TVs; malformed
  /// data from any of them must be ignored rather than crash the scan.
  static BeaconPayload? decode(List<int> data) {
    if (data.length != Beacon.payloadLength) return null;
    final bytes = ByteData.sublistView(Uint8List.fromList(data));
    return BeaconPayload(
      sessionTag: bytesToHex(data.sublist(0, 4)),
      window: bytes.getUint32(4, Endian.big),
      hop: bytes.getUint8(8),
      token: bytesToHex(data.sublist(9, 17)),
    );
  }

  /// The same beacon, one relay further from the teacher.
  BeaconPayload relayed() => BeaconPayload(
        sessionTag: sessionTag,
        window: window,
        hop: hop + 1,
        token: token,
      );

  @override
  bool operator ==(Object other) =>
      other is BeaconPayload &&
      other.sessionTag == sessionTag &&
      other.window == window &&
      other.hop == hop &&
      other.token == token;

  @override
  int get hashCode => Object.hash(sessionTag, window, hop, token);

  @override
  String toString() => 'BeaconPayload($sessionTag, w=$window, h=$hop)';
}

Uint8List hexToBytes(String hex) {
  if (hex.length.isOdd) throw FormatException('Odd-length hex', hex);
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
