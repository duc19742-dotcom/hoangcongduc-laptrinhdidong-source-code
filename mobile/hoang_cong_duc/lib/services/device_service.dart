import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'api_service.dart';

class DeviceService {
  static Future<Position> position({
    double targetAccuracyMeters = 50,
    bool requireAccuracy = false,
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const ApiException(
        'GPS đang tắt. Hãy bật Vị trí trên điện thoại rồi thử lại.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const ApiException(
        'Quyền vị trí đã bị từ chối vĩnh viễn. Hãy mở cài đặt ứng dụng để cấp lại.',
      );
    }
    if (permission == LocationPermission.denied) {
      throw const ApiException(
        'Cần quyền vị trí để chia sẻ GPS khi chấm công.',
      );
    }
    if ((defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS) &&
        await Geolocator.getLocationAccuracy() ==
            LocationAccuracyStatus.reduced) {
      throw const ApiException(
        'Hãy bật “Vị trí chính xác” trong quyền Vị trí của ứng dụng. Vị trí gần đúng không đủ để chấm công.',
      );
    }
    return selectPosition(
      Geolocator.getPositionStream(
        locationSettings: defaultTargetPlatform == TargetPlatform.android
            ? AndroidSettings(
                accuracy: LocationAccuracy.best,
                distanceFilter: 0,
                intervalDuration: const Duration(seconds: 1),
                maxUpdateAge: Duration.zero,
              )
            : const LocationSettings(
                accuracy: LocationAccuracy.best,
                distanceFilter: 0,
              ),
      ),
      targetAccuracyMeters: targetAccuracyMeters,
      requireAccuracy: requireAccuracy,
    );
  }

  static bool isFresh(
    Position p, {
    DateTime? now,
    Duration maxAge = const Duration(seconds: 15),
  }) {
    final age = (now ?? DateTime.now()).difference(p.timestamp);
    return age >= const Duration(seconds: -5) &&
        age <= maxAge &&
        p.latitude.isFinite &&
        p.longitude.isFinite &&
        p.accuracy.isFinite &&
        p.latitude.abs() <= 90 &&
        p.longitude.abs() <= 180 &&
        p.accuracy > 0;
  }

  // Never average coordinates or prefer samples closer to the company.
  static Future<Position> selectPosition(
    Stream<Position> stream, {
    double targetAccuracyMeters = 50,
    bool requireAccuracy = false,
    Duration timeout = const Duration(seconds: 25),
    Duration settlingTime = const Duration(seconds: 2),
  }) async {
    final started = DateTime.now();
    final elapsed = Stopwatch()..start();
    final result = Completer<Position>();
    Position? previous, stable;
    var stableAccurate = false;
    final subscription = stream.listen(
      (p) {
        if (result.isCompleted) return;
        if (p.isMocked) {
          result.completeError(
            const ApiException(
              'Phát hiện vị trí giả lập. Hãy tắt ứng dụng giả GPS rồi lấy lại vị trí thật.',
            ),
          );
          return;
        }
        if (!isFresh(p) ||
            p.timestamp.isBefore(
              started.subtract(const Duration(seconds: 2)),
            )) {
          return;
        }
        final last = previous;
        if (last != null && !p.timestamp.isAfter(last.timestamp)) return;
        previous = p;
        if (last == null) return;
        final agree =
            Geolocator.distanceBetween(
              last.latitude,
              last.longitude,
              p.latitude,
              p.longitude,
            ) <=
            last.accuracy + p.accuracy;
        if (!agree) {
          stable = null;
          return;
        }
        stable = p;
        stableAccurate =
            p.accuracy <= targetAccuracyMeters &&
            last.accuracy <= targetAccuracyMeters;
        if (elapsed.elapsed >= settlingTime && stableAccurate) {
          result.complete(p);
        }
      },
      onError: (Object e, StackTrace stack) {
        if (!result.isCompleted) result.completeError(e, stack);
      },
    );
    final timer = Timer(timeout, () {
      if (result.isCompleted) return;
      final p = stable;
      if (p != null && isFresh(p) && (!requireAccuracy || stableAccurate)) {
        result.complete(p);
      } else {
        result.completeError(
          ApiException(
            requireAccuracy
                ? 'GPS chưa ổn định hoặc sai số lớn hơn ${targetAccuracyMeters.toStringAsFixed(0)} m. Ra chỗ thoáng rồi lấy lại, chưa thay đổi tâm công ty.'
                : 'Chưa lấy được GPS mới và ổn định. Ra chỗ thoáng, đứng yên rồi thử lại.',
          ),
        );
      }
    });
    try {
      return await result.future;
    } finally {
      timer.cancel();
      elapsed.stop();
      await subscription.cancel();
    }
  }
}
