import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hoang_cong_duc/main.dart';
import 'package:hoang_cong_duc/models/models.dart';
import 'package:hoang_cong_duc/state/session.dart';
import 'package:hoang_cong_duc/widgets/workforce_ui.dart';

// Presentation fixtures only: production screens continue to use the real API.
Json page(List<Json> rows) => {
  'items': rows,
  'totalCount': rows.length,
  'page': 1,
  'pageSize': 20,
};
final lines = <Json>[
  {
    'date': '2026-10-30',
    'shift': 'Ca hành chính',
    'location': 'hutech',
    'startUtc': '2026-10-30T01:00:00Z',
    'endUtc': '2026-10-30T10:00:00Z',
    'checkInUtc': '2026-10-30T01:02:00Z',
    'checkOutUtc': null,
    'status': 'Working',
    'lateMinutes': 0,
    'earlyMinutes': 0,
    'leaveMinutes': 0,
    'graceMinutes': 5,
  },
  {
    'date': '2026-10-31',
    'shift': 'Ca sáng',
    'location': 'hutech',
    'startUtc': '2026-10-31T01:00:00Z',
    'endUtc': '2026-10-31T05:00:00Z',
    'checkInUtc': null,
    'checkOutUtc': null,
    'status': 'Scheduled',
    'lateMinutes': 0,
    'earlyMinutes': 0,
    'leaveMinutes': 0,
    'graceMinutes': 5,
  },
];
Json sheet() => {
  'employeeId': 'e',
  'employeeName': 'Hoàng Công Đức',
  'employeeCode': 'NV01',
  'department': 'Kỹ thuật',
  'attendedDays': 18,
  'confirmedHours': 136,
  'lateShifts': 1,
  'earlyShifts': 0,
  'missingShifts': 0,
  'scheduledShifts': 22,
  'scheduledDays': 22,
  'leaveHours': 4,
  'lines': lines,
};
Session account(String role) {
  final client = MockClient((r) async {
    final Object result;
    if (r.url.path.endsWith('/dashboard')) {
      result = {
        'date': '2026-10-30',
        'employees': 24,
        'scheduled': 24,
        'checkIns': 20,
        'checkOuts': 4,
        'late': 2,
        'missingIn': 2,
        'missingOut': 1,
        'onLeave': 2,
        'pendingLeave': 3,
        'pendingAttendance': 2,
        'pendingSupport': 1,
        'items': [],
      };
    } else if (r.url.path.contains('/timesheets/')) {
      result = {
        ...page([
          {'data': sheet(), 'responseStatus': 'NotPublished'},
        ]),
        'status': 'Draft',
        'revision': 0,
        'serverTimeUtc': '2026-10-30T04:00:00Z',
      };
    } else {
      result = page([]);
    }
    return http.Response(
      jsonEncode(result),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  return Session(client: client)
    ..initializing = false
    ..token = 'test-only'
    ..user = UserProfile.fromJson({
      'id': 'u',
      'fullName': 'Hoàng Công Đức',
      'username': 'duc',
      'email': 'test@example.invalid',
      'role': role,
      'approvalStatus': 'Approved',
    });
}

Future<void> capture(WidgetTester tester, String name) async {
  final dir = Platform.environment['DUC_UI_CAPTURE'];
  if (dir == null) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  setUpAll(() async {
    if (Platform.environment['DUC_UI_CAPTURE'] == null) return;
    for (final entry in {
      'Roboto': r'D:\duc_attendance\.toolchains\flutter\bin\cache\artifacts\material_fonts\roboto-regular.ttf',
      'MaterialIcons': r'D:\duc_attendance\.toolchains\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
    }.entries) {
      final file = File(entry.value);
      if (await file.exists()) {
        final loader = FontLoader(entry.key)
          ..addFont(
            Future.value(ByteData.sublistView(await file.readAsBytes())),
          );
        await loader.load();
      }
    }
  });
  Future<void> render(
    WidgetTester tester,
    Session s, {
    bool large = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    s.preferences.fontScale = large ? 1.5 : 1;
    await tester.pumpWidget(RepaintBoundary(child: AttendanceApp(s)));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Employee redesign keeps five destinations and real summary fields',
    (tester) async {
      final s = account('Employee');
      await render(tester, s);
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      expect(find.byType(GreenHero), findsOneWidget);
      expect(find.text('Chấm công vào / ra'), findsOneWidget);
      await capture(tester, 'employee-home');
      await tester.tap(find.text('Bảng công'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarStrip), findsOneWidget);
      await capture(tester, 'employee-timesheet');
      final day = find.text('T7\n31');
      await tester.ensureVisible(day);
      await tester.tap(day);
      await tester.pumpAndSettle();
      expect(find.text('31/10/2026'), findsOneWidget);
      expect(find.text('30/10/2026'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      s.client!.close();
    },
  );
  testWidgets('Admin shell exposes staff shifts location reports and profile', (
    tester,
  ) async {
    final s = account('Admin');
    await render(tester, s);
    await capture(tester, 'admin-dashboard');
    for (final label in ['Nhân sự', 'Lịch ca', 'QR/GPS', 'Báo cáo']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Bảng công'), findsOneWidget);
    await tester.tap(find.text('Tổng quan'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hồ sơ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    s.client!.close();
  });
  testWidgets(
    'Green login remains scrollable and validates on a small device',
    (tester) async {
      final s = Session()..initializing = false;
      await render(tester, s, large: true);
      await capture(tester, 'login');
      await tester.ensureVisible(find.text('Tiếp tục đăng nhập'));
      await tester.tap(find.text('Tiếp tục đăng nhập'));
      await tester.pumpAndSettle();
      expect(find.text('Vui lòng nhập mật khẩu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Large dark employee home and navigation have no overflow', (
    tester,
  ) async {
    final s = account('Employee');
    s.preferences.mode = ThemeMode.dark;
    await render(tester, s, large: true);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Lịch làm'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    s.client!.close();
  });
}
