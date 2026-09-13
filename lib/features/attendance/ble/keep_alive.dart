import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps Bluetooth work alive while the screen is locked or the app is in the
/// background.
///
/// Without a foreground service Android suspends the process within seconds
/// of the screen turning off, and scanning and advertising stop with it. The
/// service does no work of its own — the beacon engines keep running in the
/// app — it only holds a persistent notification so Android leaves them alone.
abstract final class AttendanceKeepAlive {
  static bool _initialised = false;

  static void _init() {
    if (_initialised) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'attendance',
        channelName: 'Attendance',
        channelDescription: 'Shown while attendance is being taken',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
      ),
    );
    _initialised = true;
  }

  /// Starts (or retitles) the service. Returns false if Android refused it,
  /// in which case attendance still works while the app stays open.
  static Future<bool> start(
      {required String title, required String text}) async {
    if (!Platform.isAndroid) return true;
    _init();
    try {
      final permission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
        );
        return true;
      }
      final result = await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.connectedDevice],
        notificationTitle: title,
        notificationText: text,
      );
      return result is ServiceRequestSuccess;
    } on Exception catch (error) {
      debugPrint('Attendance keep-alive failed: $error');
      return false;
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid || !_initialised) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } on Exception catch (error) {
      debugPrint('Attendance keep-alive stop failed: $error');
    }
  }

  /// Manufacturers' battery savers kill even foreground services. Detected so
  /// the screen can explain it instead of attendance silently stopping.
  static Future<bool> isBatteryOptimised() async {
    if (!Platform.isAndroid) return false;
    try {
      return !await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } on Exception {
      return false;
    }
  }

  static Future<void> requestBatteryExemption() async {
    if (!Platform.isAndroid) return;
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }
}
