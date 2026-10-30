import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hoang_cong_duc/services/device_service.dart';
import 'package:hoang_cong_duc/services/api_service.dart';
import 'package:hoang_cong_duc/services/attendance_service.dart';

Position fix(
  DateTime time, {
  double lat = 10,
  double accuracy = 10,
  bool mocked = false,
}) => Position(
  latitude: lat,
  longitude: 106,
  timestamp: time,
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
  isMocked: mocked,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Ignore cached fix; use two fresh agreeing fixes', () async {
    final now = DateTime.now();
    final latest = fix(now.add(const Duration(milliseconds: 1)), lat: 10.00001);
    final selected = await DeviceService.selectPosition(
      Stream.fromIterable([
        fix(now.subtract(const Duration(minutes: 5)), lat: 20),
        fix(now),
        latest,
      ]),
      settlingTime: Duration.zero,
    );
    expect(selected, same(latest));
  });
  test('A single cached timestamp cannot count as stable GPS', () async {
    final p = fix(DateTime.now());
    await expectLater(
      DeviceService.selectPosition(
        Stream.fromIterable([p, p]),
        settlingTime: Duration.zero,
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<ApiException>()),
    );
  });
  test('Large GPS jumps do not become a stable position', () async {
    final now = DateTime.now();
    await expectLater(
      DeviceService.selectPosition(
        Stream.fromIterable([
          fix(now),
          fix(now.add(const Duration(milliseconds: 1)), lat: 11),
        ]),
        settlingTime: Duration.zero,
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<ApiException>()),
    );
  });
  test(
    'Poor GPS is review evidence, never accepted for setting company center',
    () async {
      final now = DateTime.now();
      final samples = [
        fix(now, accuracy: 100),
        fix(now.add(const Duration(milliseconds: 1)), accuracy: 90),
      ];
      final p = await DeviceService.selectPosition(
        Stream.fromIterable(samples),
        settlingTime: Duration.zero,
        timeout: const Duration(milliseconds: 20),
      );
      expect(p.accuracy, 90);
      await expectLater(
        DeviceService.selectPosition(
          Stream.fromIterable(samples),
          requireAccuracy: true,
          settlingTime: Duration.zero,
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test('Mock GPS fails and GPS subscription is canceled', () async {
    var canceled = false;
    final stream = StreamController<Position>(
      onCancel: () {
        canceled = true;
      },
    );
    final future = DeviceService.selectPosition(stream.stream);
    final check = expectLater(future, throwsA(isA<ApiException>()));
    stream.add(fix(DateTime.now(), mocked: true));
    await check;
    expect(canceled, isTrue);
    await stream.close();
  });
  test(
    'Timeout releases provider and nonfinite positions are rejected',
    () async {
      var canceled = false;
      final stream = StreamController<Position>(
        onCancel: () {
          canceled = true;
        },
      );
      await expectLater(
        DeviceService.selectPosition(
          stream.stream,
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(canceled, isTrue);
      await stream.close();
      expect(
        DeviceService.isFresh(fix(DateTime.now(), accuracy: double.nan)),
        isFalse,
      );
    },
  );
  test(
    'Retry preserves GPS acquisition time and exact request payload',
    () async {
      final bodies = <String>[];
      final keys = <String?>[];
      final api = ApiService(
        () => null,
        () {},
        client: MockClient((r) async {
          bodies.add(r.body);
          keys.add(r.headers['Idempotency-Key']);
          return http.Response('{"status":"Accepted"}', 201);
        }),
      );
      final p = fix(DateTime.now());
      final service = AttendanceService(api);
      for (var i = 0; i < 2; i++) {
        await service.submit(
          action: 'CheckIn',
          assignmentId: 'a',
          qrToken: 'qr',
          position: p,
          idempotencyKey: 'same-operation',
        );
      }
      expect(bodies[0], bodies[1]);
      expect(
        jsonDecode(bodies[0])['capturedAtUtc'],
        p.timestamp.toUtc().toIso8601String(),
      );
      expect(keys, ['same-operation', 'same-operation']);
    },
  );
}
