import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_service.dart';

/// [PushService] backed by Firebase Cloud Messaging.
///
/// Only constructed through [initialize], which throws when the platform has no
/// Firebase configuration; `createPushService` turns that into the no-op.
class FirebasePushService implements PushService {
  FirebasePushService._(this._messaging);

  final FirebaseMessaging _messaging;
  final _opened = StreamController<Map<String, dynamic>>.broadcast();

  static Future<FirebasePushService> initialize() async {
    // Reads android/app/google-services.json via the Gradle plugin's generated
    // resources. Without that file this throws, which is the intended signal.
    await Firebase.initializeApp();
    final service = FirebasePushService._(FirebaseMessaging.instance);
    service._listen();
    return service;
  }

  void _listen() {
    FirebaseMessaging.onMessageOpenedApp
        .listen((message) => _opened.add(message.data));

    // A tap that cold-started the app. Delivered after a microtask so the
    // navigation listener, set up while the first frame builds, receives it.
    _messaging.getInitialMessage().then((message) {
      if (message != null) _opened.add(message.data);
    });
  }

  @override
  bool get isAvailable => true;

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<Map<String, dynamic>> get onOpened => _opened.stream;
}
