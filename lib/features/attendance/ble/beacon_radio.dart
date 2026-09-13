import 'dart:typed_data';

import '../domain/beacon_codec.dart';

/// A beacon this phone heard.
class BeaconSighting {
  const BeaconSighting({
    required this.payload,
    required this.rssi,
    required this.at,
  });

  final BeaconPayload payload;
  final int rssi;
  final DateTime at;
}

/// What stands between the phone and taking part in attendance.
enum RadioProblem {
  unsupported('This phone has no Bluetooth LE.'),
  bluetoothOff('Turn on Bluetooth to take part in attendance.'),
  permissionDenied(
      'Allow Nearby devices and Location so the app can find the classroom beacon.'),
  locationOff(
      'Turn on Location. Android needs it switched on to scan for Bluetooth beacons.'),
  notificationsDenied(
      'Allow notifications so attendance keeps running when the screen locks.');

  const RadioProblem(this.message);

  final String message;
}

/// The Bluetooth operations attendance needs, and nothing else.
///
/// An interface so the beacon engines can be tested without a radio — the
/// emulator has none, and neither does a test runner.
abstract interface class BeaconRadio {
  /// Requests permissions and checks the adapter. Null means ready.
  Future<RadioProblem?> prepare({required bool advertise});

  /// Whether this phone can transmit. Many cheaper phones can only receive;
  /// they still take part, they just cannot relay.
  Future<bool> canAdvertise();

  /// Starts scanning. Sightings arrive until [stopScan].
  Stream<BeaconSighting> scan();

  Future<void> stopScan();

  /// Replaces whatever is being advertised with [payload].
  Future<void> advertise(Uint8List payload);

  Future<void> stopAdvertising();
}
