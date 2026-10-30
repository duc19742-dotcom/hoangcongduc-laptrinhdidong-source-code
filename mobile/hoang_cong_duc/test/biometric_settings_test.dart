import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hoang_cong_duc/state/session.dart';
import 'package:hoang_cong_duc/state/app_preferences.dart';
import 'package:hoang_cong_duc/services/biometric_service.dart';
import 'package:hoang_cong_duc/features/settings_screen.dart';
import 'package:hoang_cong_duc/models/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final binding =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => binding.setMockMethodCallHandler(FingerprintService.channel, null),
  );
  test('Biometric restart locks stored JWT and blocks quick login', () async {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'old',
      'biometric_account': jsonEncode({
        'fingerprintId': 'device',
        'userId': 'u',
        'username': 'saved',
        'alias': 'key',
      }),
    });
    final s = Session(
      client: MockClient(
        (_) async => throw StateError('No automatic HTTP login'),
      ),
    );
    await s.restore();
    expect(s.token, isNull);
    expect(s.hasBiometrics, isTrue);
    expect(await s.auth.storage.read(key: 'access_token'), isNull);
    await expectLater(s.resumeRemembered(), throwsException);
  });
  test(
    'Fingerprint authenticates by signed challenge without password or OTP',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'biometric_account': jsonEncode({
          'fingerprintId': 'device',
          'userId': 'u',
          'username': 'saved',
          'alias': 'key',
        }),
      });
      final requests = <String>[];
      binding.setMockMethodCallHandler(FingerprintService.channel, (
        call,
      ) async {
        expect(call.method, 'sign');
        expect(call.arguments, {'alias': 'key', 'nonce': 'single-use'});
        return 'signed';
      });
      final s = Session(
        client: MockClient((r) async {
          requests.add(r.url.path);
          final body = r.url.path.endsWith('/challenge')
              ? {'id': 'challenge', 'nonce': 'single-use'}
              : {
                  'accessToken': 'new',
                  'user': {
                    'id': 'u',
                    'username': 'saved',
                    'fullName': 'Staff',
                    'email': 'a@example.invalid',
                    'role': 'Employee',
                    'approvalStatus': 'Approved',
                    'emailConfirmed': true,
                    'phoneNumberConfirmed': false,
                  },
                };
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await s.restore();
      await s.loginBiometric('Fingerprint');
      expect(s.token, 'new');
      expect(requests, [
        '/api/v1/auth/biometric/fingerprint/challenge',
        '/api/v1/auth/biometric/fingerprint/verify',
      ]);
    },
  );
  test('Canceled fingerprint never requests a login token', () async {
    FlutterSecureStorage.setMockInitialValues({
      'biometric_account': jsonEncode({
        'fingerprintId': 'device',
        'userId': 'u',
        'alias': 'key',
      }),
    });
    binding.setMockMethodCallHandler(
      FingerprintService.channel,
      (_) async =>
          throw PlatformException(code: 'CANCELED', message: 'Canceled'),
    );
    final s = Session(
      client: MockClient((r) async {
        expect(r.url.path.endsWith('/challenge'), isTrue);
        return http.Response('{"id":"c","nonce":"n"}', 200);
      }),
    );
    await s.restore();
    await expectLater(s.loginBiometric('Fingerprint'), throwsException);
    expect(s.user, isNull);
    expect(s.authenticationInProgress, isFalse);
  });
  test('Appearance persists and respects system text scaling', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const storage = FlutterSecureStorage();
    final p = AppPreferences(storage);
    await p.update(
      theme: ThemeMode.dark,
      scale: 1.5,
      seed: AppPreferences.colors[1],
    );
    final restored = AppPreferences(storage);
    await restored.load();
    expect(restored.mode, ThemeMode.dark);
    expect(restored.fontScale, 1.5);
    expect(restored.color, AppPreferences.colors[1]);
    expect(
      const AccessibleTextScaler(TextScaler.linear(1.2), 1.5).scale(20),
      36,
    );
  });
  testWidgets('Settings supports large text on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FlutterSecureStorage.setMockInitialValues({});
    final s = Session();
    s.user = const UserProfile(
      id: 'u',
      fullName: 'Staff',
      username: 'staff',
      email: 'a@example.invalid',
      role: 'Employee',
      approvalStatus: 'Approved',
      emailConfirmed: true,
      phoneNumberConfirmed: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: SettingsScreen(s),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
