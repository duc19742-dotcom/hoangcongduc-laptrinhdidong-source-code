import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppPreferences extends ChangeNotifier {
  final FlutterSecureStorage storage;
  AppPreferences(this.storage);
  ThemeMode mode = ThemeMode.system;
  double fontScale = 1;
  int color = 0xff16a34a;
  static const colors = [
    0xff16a34a,
    0xff155eef,
    0xff137547,
    0xff7950b5,
    0xffa64b17,
  ];
  Future<void> load() async {
    try {
      final raw = await storage.read(key: 'app_preferences');
      if (raw == null) return;
      final j = jsonDecode(raw) as Map;
      mode = ThemeMode.values.firstWhere(
        (v) => v.name == j['mode'],
        orElse: () => ThemeMode.system,
      );
      fontScale = (j['scale'] as num?)?.toDouble() ?? 1;
      if (![1.0, 1.15, 1.3, 1.5].contains(fontScale)) fontScale = 1;
      color = colors.contains(j['color']) ? j['color'] : colors.first;
    } catch (_) {
      mode = ThemeMode.system;
      fontScale = 1;
      color = colors.first;
    }
    notifyListeners();
  }

  Future<void> update({ThemeMode? theme, double? scale, int? seed}) async {
    if (scale != null && ![1.0, 1.15, 1.3, 1.5].contains(scale)) {
      throw ArgumentError('Invalid font size');
    }
    if (seed != null && !colors.contains(seed)) {
      throw ArgumentError('Invalid color');
    }
    final nextMode = theme ?? mode;
    final nextScale = scale ?? fontScale;
    final nextColor = seed ?? color;
    await storage.write(
      key: 'app_preferences',
      value: jsonEncode({
        'mode': nextMode.name,
        'scale': nextScale,
        'color': nextColor,
      }),
    );
    mode = nextMode;
    fontScale = nextScale;
    color = nextColor;
    notifyListeners();
  }
}

class AccessibleTextScaler extends TextScaler {
  final TextScaler system;
  final double multiplier;
  const AccessibleTextScaler(this.system, this.multiplier);
  @override
  double scale(double fontSize) => system.scale(fontSize) * multiplier;
  @override
  double get textScaleFactor => scale(14) / 14;
}
