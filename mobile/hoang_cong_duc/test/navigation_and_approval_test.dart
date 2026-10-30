import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoang_cong_duc/features/admin/operations_screens.dart';
import 'package:hoang_cong_duc/main.dart';
import 'package:hoang_cong_duc/models/models.dart';
import 'package:hoang_cong_duc/state/session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Json page(List<Json> items) => {
  'items': items,
  'page': 1,
  'pageSize': 20,
  'totalCount': items.length,
};
http.Response response(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Session session(String role, http.Client client) => Session(client: client)
  ..initializing = false
  ..token = 'widget-test-only'
  ..user = UserProfile.fromJson({
    'id': 'user-test',
    'fullName': 'Người dùng kiểm thử',
    'username': 'tester',
    'email': 'test@example.invalid',
    'role': role,
    'approvalStatus': 'Approved',
    'emailConfirmed': true,
    'phoneNumberConfirmed': false,
  });

void main() {
  testWidgets(
    'Employee sees the attendance action first and tools open on demand',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = MockClient((request) async {
        expect(request.url.scheme, 'https');
        return response({
          ...page([]),
          'serverTimeUtc': DateTime.now().toUtc().toIso8601String(),
          'status': 'Draft',
        });
      });
      await tester.pumpWidget(AttendanceApp(session('Employee', client)));
      await tester.pumpAndSettle();
      expect(find.text('Trang chủ'), findsOneWidget);
      expect(find.text('Bảng công'), findsOneWidget);
      expect(find.text('Lịch làm'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Chấm công vào / ra').hitTestable(),
        100,
      );
      expect(find.text('Chấm công vào / ra').hitTestable(), findsOneWidget);
      expect(find.text('GPS hiện tại'), findsNothing);
      await tester.scrollUntilVisible(find.text('Tiện ích').hitTestable(), 140);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tiện ích'));
      await tester.pumpAndSettle();
      expect(find.text('GPS hiện tại'), findsOneWidget);
      expect(find.text('Chuyển động'), findsOneWidget);
      expect(tester.takeException(), isNull);
      client.close();
    },
  );

  testWidgets('Admin separates pending work from staff management', (
    tester,
  ) async {
    final client = MockClient(
      (request) async => response({
        'checkIns': 0,
        'checkOuts': 0,
        'lateCheckIns': 0,
        'openShifts': 0,
        'items': [],
        'date': '2026-10-30',
      }),
    );
    await tester.pumpWidget(AttendanceApp(session('Admin', client)));
    await tester.pumpAndSettle();
    expect(find.text('Báo cáo'), findsOneWidget);
    expect(find.text('Nhân sự'), findsOneWidget);
    expect(find.text('Chấm công vào / ra'), findsNothing);
    await tester.scrollUntilVisible(find.text('Cần xử lý'), 120);
    await tester.scrollUntilVisible(
      find.text('Duyệt tài khoản').hitTestable(),
      120,
    );
    expect(find.text('Duyệt tài khoản'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Duyệt giải trình').hitTestable(),
      120,
    );
    expect(find.text('Duyệt giải trình'), findsOneWidget);
    expect(tester.takeException(), isNull);
    client.close();
  });

  testWidgets('A single assigned shift is selected without another tap', (
    tester,
  ) async {
    final today = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 7))
        .toIso8601String()
        .substring(0, 10);
    final client = MockClient(
      (request) async => response(
        request.url.path.endsWith('/attendance/options')
            ? page([
                {
                  'id': 'assignment-test',
                  'shiftName': 'Ca kiểm thử',
                  'workDate': today,
                },
              ])
            : {
                ...page([]),
                'serverTimeUtc': DateTime.now().toUtc().toIso8601String(),
                'status': 'Draft',
              },
      ),
    );
    await tester.pumpWidget(AttendanceApp(session('Employee', client)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Chấm công vào / ra'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chấm công vào / ra'));
    await tester.pumpAndSettle();
    final field = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(field.initialValue, 'assignment-test');
    await tester.scrollUntilVisible(
      find.text('Chấm công vào').hitTestable(),
      100,
    );
    expect(find.text('Chấm công vào'), findsOneWidget);
    expect(find.text('Quét QR của ca làm'), findsNothing);
    expect(tester.takeException(), isNull);
    client.close();
  });

  testWidgets(
    'Registered staff are approved with one request and no repeated profile entry',
    (tester) async {
      const pending = {
        'id': 'pending-test',
        'username': 'user1',
        'fullName': 'Nhân viên kiểm thử',
        'email': 'new@example.invalid',
        'phoneNumber': '+84901234567',
        'emailConfirmed': true,
      };
      var approved = false;
      var approvalCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/users/pending')) {
          return response(page(approved ? [] : [pending]));
        }
        if (request.url.path.endsWith('/departments')) {
          return response(
            page([
              {'id': 'department-test', 'name': 'Phòng kiểm thử'},
            ]),
          );
        }
        if (request.url.path.endsWith('/employees') &&
            request.method == 'GET') {
          return response({
            ...page([]),
            'serverTimeUtc': DateTime.now().toUtc().toIso8601String(),
            'status': 'Draft',
          });
        }
        if (request.url.path.endsWith(
          '/users/pending-test/approve-registration',
        )) {
          final body = jsonDecode(request.body) as Json;
          expect(body['departmentId'], 'department-test');
          expect(body.containsKey('fullName'), isFalse);
          expect(body.containsKey('email'), isFalse);
          expect(body.containsKey('phone'), isFalse);
          approvalCalls++;
          approved = true;
          return response({
            'approvalStatus': 'Approved',
            'employeeId': 'employee-test',
          });
        }
        throw StateError(
          'Unexpected test route ${request.method} ${request.url.path}',
        );
      });
      await tester.pumpWidget(
        MaterialApp(home: PendingUsersScreen(session('Admin', client))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhân viên kiểm thử'));
      await tester.pumpAndSettle();
      expect(find.text('Duyệt nhân viên'), findsNWidgets(2));
      expect(find.text('Nhân viên kiểm thử'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Họ và tên'), findsNothing);
      expect(approved, isFalse);
      final approveButton = find.widgetWithText(
        FilledButton,
        'Duyệt nhân viên',
      );
      await tester.ensureVisible(approveButton);
      await tester.pumpAndSettle();
      await tester.tap(approveButton);
      await tester.pumpAndSettle();
      expect(approved, isTrue);
      expect(approvalCalls, 1);
      expect(tester.takeException(), isNull);
      client.close();
    },
  );
}
