import 'package:geolocator/geolocator.dart';

import '../models/models.dart';
import 'api_service.dart';

class AttendanceService {
  final ApiService api;
  AttendanceService(this.api);
  Future<Json> submit({
    required String action,
    required String assignmentId,
    required String qrToken,
    required Position position,
    required String idempotencyKey,
  }) => api.post(
    '/attendance/${action == 'CheckIn' ? 'check-in' : 'check-out'}',
    {
      'employeeShiftId': assignmentId,
      'qrToken': qrToken,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracyMeters': position.accuracy,
      'capturedAtUtc': position.timestamp.toUtc().toIso8601String(),
    },
    idempotencyKey: idempotencyKey,
  );
}
