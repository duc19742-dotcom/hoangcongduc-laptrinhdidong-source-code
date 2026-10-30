import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hoang_cong_duc/main.dart';
import 'package:hoang_cong_duc/services/api_service.dart';
import 'package:hoang_cong_duc/state/session.dart';

void main() {
  testWidgets(
    'Small Android screen shows login and validates without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = Session()..initializing = false;
      await tester.pumpWidget(AttendanceApp(session));
      await tester.pump();
      expect(find.text('Đức Attendance'), findsOneWidget);
      await tester.ensureVisible(find.text('Tiếp tục đăng nhập'));
      await tester.tap(find.text('Tiếp tục đăng nhập'));
      await tester.pumpAndSettle();
      expect(find.text('Vui lòng nhập mật khẩu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('401 informs session and returns an understandable error', () async {
    var expired = false;
    final api = ApiService(
      () => 'expired',
      () => expired = true,
      client: MockClient((r) async => http.Response('', 401)),
    );
    await expectLater(
      api.get('/auth/me'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
    );
    expect(expired, isTrue);
  });
  test('403 keeps session and preserves server rejection detail', () async {
    var expired = false;
    final api = ApiService(
      () => 'token',
      () => expired = true,
      client: MockClient(
        (r) async => http.Response(
          '{"detail":"Không có quyền quản trị","code":"Forbidden"}',
          403,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    await expectLater(
      api.get('/employees'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Không có quyền quản trị',
        ),
      ),
    );
    expect(expired, isFalse);
  });
  test(
    'HTML error page becomes an API error rather than JSON parsing crash',
    () async {
      final api = ApiService(
        () => null,
        () {},
        client: MockClient(
          (r) async => http.Response('<html>server error</html>', 500),
        ),
      );
      await expectLater(
        api.get('/attendance/me'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 500)),
      );
    },
  );
  test(
    'Retry forwards the same idempotency key and uses public HTTPS',
    () async {
      final received = <String?>[];
      final api = ApiService(
        () => 'token',
        () {},
        client: MockClient((r) async {
          expect(r.url.scheme, 'https');
          expect(r.url.host, isNot('localhost'));
          expect(r.headers['Authorization'], 'Bearer token');
          received.add(r.headers['Idempotency-Key']);
          return http.Response('{"status":"Accepted"}', 201);
        }),
      );
      for (var i = 0; i < 2; i++) {
        await api.post('/attendance/check-in', {
          'employeeShiftId': 'test',
        }, idempotencyKey: 'one-intent');
      }
      expect(received, ['one-intent', 'one-intent']);
    },
  );
}
