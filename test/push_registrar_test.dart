import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/core/storage/local_store.dart';
import 'package:ln_app/features/push/push_repository.dart';
import 'package:ln_app/features/push/push_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements PushRepository {}

class _FakePush implements PushService {
  final refresh = StreamController<String>.broadcast();
  String token = 'token-1';

  @override
  bool get isAvailable => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => refresh.stream;

  @override
  Stream<Map<String, dynamic>> get onOpened => const Stream.empty();
}

void main() {
  late Directory dir;
  late _MockRepository repository;
  late _FakePush push;
  late PushRegistrar registrar;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ln_push_test');
    repository = _MockRepository();
    push = _FakePush();
    when(() => repository.registerToken(any(), platform: any(named: 'platform')))
        .thenAnswer((_) async {});
    when(() => repository.removeToken(any())).thenAnswer((_) async {});
    registrar = PushRegistrar(
      service: push,
      repository: repository,
      store: LocalStore(directory: () async => dir),
    );
  });

  tearDown(() => dir.delete(recursive: true));

  test('registers on sign-in and on refresh, removes on sign-out', () async {
    await registrar.onSignedIn();
    verify(() => repository.registerToken('token-1',
        platform: any(named: 'platform'))).called(1);

    push.refresh.add('token-2');
    await Future<void>.delayed(Duration.zero);
    verify(() => repository.registerToken('token-2',
        platform: any(named: 'platform'))).called(1);

    await registrar.onSigningOut();
    verify(() => repository.removeToken('token-2')).called(1);
  });

  test('does nothing when the no-op service is in use', () async {
    final noop = PushRegistrar(
      service: const NoopPushService(),
      repository: repository,
      store: LocalStore(directory: () async => dir),
    );
    await noop.onSignedIn();
    await noop.onSigningOut();
    verifyNever(() =>
        repository.registerToken(any(), platform: any(named: 'platform')));
    verifyNever(() => repository.removeToken(any()));
  });

  test('switched off in Settings, sign-in does not register', () async {
    await registrar.setEnabled(false);
    await registrar.onSignedIn();
    verifyNever(() =>
        repository.registerToken(any(), platform: any(named: 'platform')));
  });
}
