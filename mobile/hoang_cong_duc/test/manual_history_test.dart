import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hoang_cong_duc/state/session.dart';
import 'package:hoang_cong_duc/models/models.dart';
import 'package:hoang_cong_duc/features/employee/records_screens.dart';

void main() {
  testWidgets(
    'Manual checkout history displays admin source without GPS or crash',
    (tester) async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'manual-test',
                'action': 'CheckOut',
                'employeeName': 'Nhân viên thử',
                'shiftName': 'Ca thử',
                'workDate': '2026-10-29',
                'effectiveAtUtc': '2026-10-29T10:00:00Z',
                'source': 'AdminCorrection',
                'distanceMeters': null,
                'accuracyMeters': null,
              },
            ],
            'page': 1,
            'pageSize': 20,
            'totalCount': 1,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final session = Session(client: client)
        ..token = 'test-only'
        ..user = UserProfile.fromJson({
          'id': 'test-only',
          'username': 'test',
          'fullName': 'Test',
          'email': 'test@example.invalid',
          'role': 'Employee',
          'approvalStatus': 'Approved',
          'emailConfirmed': true,
          'phoneNumberConfirmed': false,
        });
      await tester.pumpWidget(MaterialApp(home: HistoryScreen(session)));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Admin bổ sung theo giải trình'),
        findsOneWidget,
      );
      expect(find.textContaining('Không có GPS'), findsOneWidget);
      expect(tester.takeException(), isNull);
      client.close();
    },
  );
}
