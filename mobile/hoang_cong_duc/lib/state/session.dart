import 'package:flutter/foundation.dart';

import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import 'app_preferences.dart';

class Session extends ChangeNotifier {
  final http.Client? client;
  Session({this.client});
  String? token;
  UserProfile? user;
  bool initializing = true;
  void updateUser(Json data) {
    user = UserProfile.fromJson(data);
    notifyListeners();
  }

  bool authenticationInProgress = false;
  Json biometricAccount = {};
  final fingerprint = FingerprintService();
  final face = FaceService();
  late final preferences = AppPreferences(auth.storage);
  bool get hasBiometrics =>
      biometricAccount['fingerprintId'] != null ||
      biometricAccount['faceToken'] != null;
  bool get currentBiometrics =>
      hasBiometrics && biometricAccount['userId'] == user?.id;
  Future<void> readBiometrics() async {
    final raw = await auth.storage.read(key: 'biometric_account');
    biometricAccount = raw == null
        ? {}
        : Map<String, dynamic>.from(jsonDecode(raw));
  }

  Future<void> saveBiometrics() async => auth.storage.write(
    key: 'biometric_account',
    value: jsonEncode(biometricAccount),
  );
  Future<void> refreshUser() async {
    user = UserProfile.fromJson(await api.get('/auth/me'));
    notifyListeners();
  }

  Future<void> enrollBiometric(String method) async {
    if (user == null || authenticationInProgress) return;
    authenticationInProgress = true;
    try {
      if (method == 'Fingerprint') {
        if (!await fingerprint.available()) {
          throw const ApiException(
            'Máy chưa có vân tay được đăng ký. Hãy thiết lập trong Cài đặt điện thoại.',
          );
        }
        final challenge = await api.post(
          '/auth/biometric/fingerprint/enroll/challenge',
          {},
        );
        final alias = 'duc_bio_${const Uuid().v4()}';
        try {
          final key = await fingerprint.createKey(alias);
          final signature = await fingerprint.sign(alias, challenge['nonce']);
          final enrolled = await api.post(
            '/auth/biometric/fingerprint/enroll',
            {
              'challengeId': challenge['id'],
              'publicKey': key,
              'signature': signature,
            },
          );
          if (biometricAccount['userId'] != user!.id) biometricAccount = {};
          biometricAccount.addAll({
            'userId': user!.id,
            'username': user!.username,
            'fingerprintId': enrolled['id'],
            'alias': alias,
          });
        } catch (_) {
          try {
            await fingerprint.remove(alias);
          } catch (_) {}
          rethrow;
        }
      } else {
        // Require a recent password/OTP session before collecting enrollment photos.
        await api.post('/auth/biometric/enroll/check', {});
        final first = await face.capture();
        if (first == null) return;
        final second = await face.capture();
        if (second == null) return;
        final enrolled = await api.post('/auth/biometric/face/enroll', {
          'first': first,
          'second': second,
          'acceptDemoRisk': true,
        });
        if (biometricAccount['userId'] != user!.id) biometricAccount = {};
        biometricAccount.addAll({
          'userId': user!.id,
          'username': user!.username,
          'faceId': enrolled['id'],
          'faceToken': enrolled['token'],
        });
      }
      await saveBiometrics();
      await forgetRemembered();
      notifyListeners();
    } finally {
      authenticationInProgress = false;
    }
  }

  Future<void> loginBiometric(String method) async {
    if (authenticationInProgress) return;
    authenticationInProgress = true;
    try {
      Json response;
      if (method == 'Fingerprint') {
        if (biometricAccount['fingerprintId'] == null) {
          throw const ApiException(
            'Đăng nhập bằng mật khẩu + OTP rồi bật vân tay trong Cài đặt.',
          );
        }
        final challenge = await api.post(
          '/auth/biometric/fingerprint/challenge',
          {'deviceId': biometricAccount['fingerprintId']},
        );
        final signature = await fingerprint.sign(
          biometricAccount['alias'],
          challenge['nonce'],
        );
        response = await api.post('/auth/biometric/fingerprint/verify', {
          'challengeId': challenge['id'],
          'signature': signature,
        });
      } else {
        if (biometricAccount['faceToken'] == null) {
          throw const ApiException(
            'Đăng nhập bằng mật khẩu + OTP rồi đăng ký khuôn mặt trong Cài đặt.',
          );
        }
        final values = await face.capture();
        if (values == null) return;
        final result = await api.post('/auth/biometric/face/verify', {
          'token': biometricAccount['faceToken'],
          'embedding': values,
        });
        biometricAccount['faceToken'] = result['deviceToken'];
        await saveBiometrics();
        response = Map<String, dynamic>.from(result['session']);
      }
      rememberLogin = false;
      await accept(response);
    } finally {
      authenticationInProgress = false;
    }
  }

  Future<void> removeBiometric(String method) async {
    final key = method == 'Fingerprint' ? 'fingerprintId' : 'faceId';
    if (biometricAccount[key] != null) {
      await api.delete('/auth/biometric/${biometricAccount[key]}');
    }
    if (method == 'Fingerprint') {
      if (biometricAccount['alias'] != null) {
        await fingerprint.remove(biometricAccount['alias']);
      }
      biometricAccount.remove('fingerprintId');
      biometricAccount.remove('alias');
    } else {
      biometricAccount.remove('faceId');
      biometricAccount.remove('faceToken');
    }
    await saveBiometrics();
    notifyListeners();
  }

  bool rememberLogin = false;
  String? rememberedUsername;
  Future<void> readRemembered() async {
    rememberedUsername = await auth.storage.read(key: 'remembered_username');
  }

  Future<void> resumeRemembered() async {
    if (hasBiometrics) {
      throw const ApiException(
        'Chọn Khuôn mặt hoặc Vân tay để mở tài khoản đã lưu.',
      );
    }
    final device = await auth.storage.read(key: 'device_token');
    if (device == null) throw const ApiException('Hãy đăng nhập lại.');
    try {
      final r = await api.post('/auth/devices/resume', {'token': device});
      await auth.storage.write(key: 'device_token', value: r['deviceToken']);
      rememberLogin = false;
      await accept(Map<String, dynamic>.from(r['session']));
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) await forgetRemembered();
      rethrow;
    }
  }

  Future<void> forgetRemembered() async {
    final device = await auth.storage.read(key: 'device_token');
    if (device != null) {
      await api.post('/auth/devices/forget', {'token': device});
    }
    await auth.storage.delete(key: 'device_token');
    await auth.storage.delete(key: 'remembered_username');
    rememberedUsername = null;
    notifyListeners();
  }

  late final ApiService api = ApiService(
    () => token,
    () => clear(),
    client: client,
  );
  late final AuthService auth = AuthService(api);
  Future<void> restore() async {
    try {
      await preferences.load();
      await readBiometrics();
      await readRemembered();
      if (hasBiometrics) {
        await auth.storage.delete(key: 'access_token');
        return;
      }
      token = await auth.storage.read(key: 'access_token');
      if (token != null) user = UserProfile.fromJson(await api.get('/auth/me'));
    } catch (_) {
      token = null;
      user = null;
    } finally {
      initializing = false;
      notifyListeners();
    }
  }

  Future<void> accept(Json response) async {
    token = response['accessToken'];
    user = UserProfile.fromJson(Map<String, dynamic>.from(response['user']));
    await auth.storage.write(key: 'access_token', value: token);
    if (rememberLogin && !currentBiometrics) {
      final saved = await api.post('/auth/devices', {});
      await auth.storage.write(key: 'device_token', value: saved['token']);
      await auth.storage.write(
        key: 'remembered_username',
        value: saved['username'],
      );
      rememberedUsername = saved['username'];
      rememberLogin = false;
    }
    rememberLogin = false;
    notifyListeners();
  }

  Future<void> clear() async {
    token = null;
    user = null;
    await auth.storage.delete(key: 'access_token');
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout', {});
    } finally {
      await clear();
    }
  }
}
