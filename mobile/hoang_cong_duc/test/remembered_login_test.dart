import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hoang_cong_duc/state/session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Remembered account resumes without password or OTP; logout keeps only device credential; forget removes it', () async {
    FlutterSecureStorage.setMockInitialValues({
      'remembered_username': 'saved_employee',
      'device_token': 'device-old-test',
    });
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add(request.url.path);
      if (request.url.path.endsWith('/devices/resume')) {
        expect(jsonDecode(request.body)['token'], 'device-old-test');
        return http.Response(
          jsonEncode({
            'deviceToken': 'device-rotated-test',
            'session': {
              'accessToken': 'access-test',
              'user': {
                'id': 'employee-test',
                'username': 'saved_employee',
                'fullName': 'Nhân viên đã lưu',
                'email': 'test@example.invalid',
                'role': 'Employee',
                'approvalStatus': 'Approved',
                'emailConfirmed': true,
                'phoneNumberConfirmed': false,
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.url.path.endsWith('/auth/logout') ||
          request.url.path.endsWith('/devices/forget')) {
        return http.Response('', 204);
      }
      throw StateError('Unexpected authentication request ${request.url.path}');
    });
    final session = Session(client: client);
    await session.readRemembered();
    expect(session.rememberedUsername, 'saved_employee');
    await session.resumeRemembered();
    expect(session.user!.username, 'saved_employee');
    expect(session.token, 'access-test');
    expect(
      await session.auth.storage.read(key: 'device_token'),
      'device-rotated-test',
    );
    await session.logout();
    expect(session.user, isNull);
    expect(await session.auth.storage.read(key: 'access_token'), isNull);
    expect(
      await session.auth.storage.read(key: 'device_token'),
      'device-rotated-test',
    );
    await session.forgetRemembered();
    expect(await session.auth.storage.read(key: 'device_token'), isNull);
    expect(session.rememberedUsername, isNull);
    expect(requests, [
      '/api/v1/auth/devices/resume',
      '/api/v1/auth/logout',
      '/api/v1/auth/devices/forget',
    ]);
    client.close();
  });
}
