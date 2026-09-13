import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/beacon_codec.dart';
import 'beacon_radio.dart';

/// [BeaconRadio] on real hardware: `flutter_blue_plus` receives,
/// `flutter_ble_peripheral` transmits.
///
/// Only verified on a physical phone — there is no Bluetooth on the emulator.
class PluginBeaconRadio implements BeaconRadio {
  PluginBeaconRadio({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamController<BeaconSighting>? _sightings;

  @override
  Future<RadioProblem?> prepare({required bool advertise}) async {
    if (!await FlutterBluePlus.isSupported) return RadioProblem.unsupported;

    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        if (advertise) Permission.bluetoothAdvertise,
        // Required for scanning on Android 11 and below, and still needed on
        // some manufacturers' builds above that.
        Permission.locationWhenInUse,
      ].request();
      if (statuses.values.any((s) => !s.isGranted)) {
        return RadioProblem.permissionDenied;
      }

      // Granted is not enough: with Location switched off in quick settings,
      // Android silently returns no scan results at all.
      if (!await Permission.locationWhenInUse.serviceStatus.isEnabled) {
        return RadioProblem.locationOff;
      }
    }

    final adapter = await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown)
        .first
        .timeout(const Duration(seconds: 3),
            onTimeout: () => BluetoothAdapterState.unknown);
    if (adapter != BluetoothAdapterState.on) {
      if (Platform.isAndroid) {
        try {
          // Shows the system "turn on Bluetooth?" prompt.
          await FlutterBluePlus.turnOn(timeout: 30);
          return null;
        } on Exception {
          return RadioProblem.bluetoothOff;
        }
      }
      return RadioProblem.bluetoothOff;
    }
    return null;
  }

  @override
  Future<bool> canAdvertise() async {
    try {
      return await _peripheral.isSupported;
    } on PlatformException {
      return false;
    }
  }

  @override
  Stream<BeaconSighting> scan() {
    final controller =
        _sightings = StreamController<BeaconSighting>.broadcast();

    _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final data =
            result.advertisementData.manufacturerData[Beacon.manufacturerId];
        if (data == null) continue;
        final payload = BeaconPayload.decode(data);
        if (payload == null) continue;
        controller.add(BeaconSighting(
          payload: payload,
          rssi: result.rssi,
          at: _clock(),
        ));
      }
    });

    unawaited(
      FlutterBluePlus.startScan(
        // Filtering by manufacturer id in the controller is what lets Android
        // keep scanning with the screen off; an unfiltered background scan is
        // throttled to nothing.
        withMsd: [MsdFilter(Beacon.manufacturerId)],
        // Report every advertisement, not just the first per device, so the
        // RSSI keeps updating and window changes are noticed.
        continuousUpdates: true,
        androidScanMode: AndroidScanMode.lowLatency,
      ).catchError((Object error) {
        controller.addError(error);
      }),
    );

    return controller.stream;
  }

  @override
  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _sightings?.close();
    _sightings = null;
    await FlutterBluePlus.stopScan();
  }

  @override
  Future<void> advertise(Uint8List payload) async {
    // Android cannot change a running advertisement's data; restart it.
    if (await _peripheral.isAdvertising) await _peripheral.stop();
    try {
      await _peripheral.start(
        advertiseData: AndroidAdvertiseData(
          manufacturerId: Beacon.manufacturerId,
          manufacturerData: payload,
        ),
        androidSettings: const AndroidAdvertiseSettings(
          advertiseSettings: AdvertiseSettings(
            advertiseMode: AdvertiseMode.advertiseModeLowLatency,
            txPowerLevel: AdvertiseTxPower.advertiseTxPowerMedium,
          ),
        ),
      );
    } on PlatformException catch (error) {
      debugPrint('Beacon advertise failed: ${error.code} ${error.message}');
      rethrow;
    }
  }

  @override
  Future<void> stopAdvertising() async {
    if (await _peripheral.isAdvertising) await _peripheral.stop();
  }
}
