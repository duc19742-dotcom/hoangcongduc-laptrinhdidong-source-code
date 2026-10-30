import 'package:hoang_cong_duc/widgets/workforce_ui.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoang_cong_duc/features/timesheets_screen.dart';
import 'package:hoang_cong_duc/features/leave_screen.dart';
import 'package:hoang_cong_duc/features/admin/dashboard_screen.dart';
import 'package:hoang_cong_duc/models/models.dart';
import 'package:hoang_cong_duc/state/session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Session account(String role, http.Client client) => Session(client: client)
  ..initializing = false
  ..token = 'test-only'
  ..user = UserProfile.fromJson({
    'id': 'u',
    'fullName': 'Đức',
    'username': 'duc',
    'email': 'test@example.invalid',
    'role': role,
    'approvalStatus': 'Approved',
  });
http.Response reply(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Json sheet() => {
  'employeeId': 'e',
  'employeeCode': 'NV01',
  'employeeName': 'Đức',
  'department': 'Kỹ thuật',
  'scheduledShifts': 1,
  'scheduledDays': 1,
  'attendedDays': 1,
  'confirmedHours': 0,
  'leaveHours': 0,
  'lateShifts': 0,
  'earlyShifts': 0,
  'missingShifts': 1,
  'lines': [
    {
      'date': '2026-10-01',
      'shift': 'Ca ngày',
      'location': 'hutech',
      'status': 'MissingCheckOut',
      'startUtc': '2026-10-01T01:00:00Z',
      'endUtc': '2026-10-01T10:00:00Z',
      'checkInUtc': '2026-10-01T01:00:00Z',
      'checkOutUtc': null,
      'workedMinutes': null,
      'leaveMinutes': 0,
      'lateMinutes': 0,
      'earlyMinutes': 0,
      'graceMinutes': 5,
      'inSource': 'Automatic',
    },
  ],
};
Future<void> render(
  WidgetTester tester,
  Widget screen, {
  bool large = false,
}) async {
  tester.view.physicalSize = const Size(360, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(large ? 1.5 : 1)),
        child: child!,
      ),
      home: screen,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Monthly sheet preserves unknown hours and supports large dark text',
    (tester) async {
      final client = MockClient(
        (_) async => reply({
          'status': 'Draft',
          'revision': 0,
          'items': [
            {'data': sheet(), 'responseStatus': 'NotPublished'},
          ],
          'totalCount': 1,
        }),
      );
      await render(
        tester,
        TimesheetsScreen(account('Employee', client)),
        large: true,
      );
      await tester.scrollUntilVisible(
        find.text('Giờ làm xác nhận').hitTestable(),
        160,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      expect(find.text('Giờ làm xác nhận'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('01/10/2026').hitTestable(),
        150,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('01/10/2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('01/10/2026'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Chưa đủ vào/ra'), findsOneWidget);
      expect(tester.takeException(), isNull);
      client.close();
    },
  );
  testWidgets('Employee confirmation sends snapshot ID and status once', (
    tester,
  ) async {
    var calls = 0;
    final client = MockClient((r) async {
      if (r.method == 'POST') {
        expect(r.url.path.endsWith('/snapshots/snap1/respond'), isTrue);
        expect(jsonDecode(r.body)['status'], 'Confirmed');
        calls++;
        return reply({'responseStatus': 'Confirmed'});
      }
      return reply({
        'status': 'Published',
        'revision': 2,
        'items': [
          {
            'data': sheet(),
            'snapshotId': 'snap1',
            'responseStatus': calls == 0 ? 'Pending' : 'Confirmed',
          },
        ],
        'totalCount': 1,
      });
    });
    await render(tester, TimesheetsScreen(account('Employee', client)));
    await tester.scrollUntilVisible(
      find.text('Xác nhận công').hitTestable(),
      160,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận công'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Đã xác nhận'), findsOneWidget);
    expect(tester.takeException(), isNull);
    client.close();
  });
  testWidgets('Leave form validates reason and keeps server error visible', (
    tester,
  ) async {
    final client = MockClient(
      (_) async => reply({'detail': 'Khoảng nghỉ chưa có lịch làm việc.'}, 409),
    );
    await render(tester, LeaveEditor(account('Employee', client)), large: true);
    await tester.ensureVisible(find.text('Gửi đơn nghỉ phép'));
    await tester.tap(find.text('Gửi đơn nghỉ phép'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập ít nhất 5 ký tự.'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField),
      'Xin nghỉ việc gia đình',
    );
    await tester.ensureVisible(find.text('Gửi đơn nghỉ phép'));
    await tester.tap(find.text('Gửi đơn nghỉ phép'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận'));
    await tester.pumpAndSettle();
    expect(find.text('Khoảng nghỉ chưa có lịch làm việc.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    client.close();
  });
  testWidgets('Dashboard metrics open the matching shift list', (tester) async {
    final client = MockClient((_) async => reply({}));
    final data = <String, dynamic>{
      'date': '2026-10-01',
      'employees': 1,
      'scheduled': 1,
      'checkIns': 1,
      'checkOuts': 0,
      'late': 0,
      'missingIn': 0,
      'missingOut': 1,
      'onLeave': 0,
      'pendingLeave': 0,
      'pendingAttendance': 0,
      'pendingSupport': 0,
      'items': [
        {
          'employeeId': 'e',
          'employeeCode': 'NV01',
          'employeeName': 'Đức',
          'line': (sheet()['lines'] as List).first,
        },
      ],
    };
    await render(
      tester,
      Scaffold(
        body: ListView(
          children: [DashboardPanel(account('Admin', client), data)],
        ),
      ),
      large: true,
    );
    final missingMetric = find.descendant(
      of: find.byType(MetricTile),
      matching: find.text('Thiếu lượt ra'),
    );
    await tester.scrollUntilVisible(missingMetric.hitTestable(), 160);
    await tester.pumpAndSettle();
    await tester.tap(missingMetric);
    await tester.pumpAndSettle();
    expect(find.text('Đức · NV01'), findsOneWidget);
    expect(tester.takeException(), isNull);
    client.close();
  });
}
