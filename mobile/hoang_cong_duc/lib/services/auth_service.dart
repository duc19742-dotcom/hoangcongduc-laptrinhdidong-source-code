import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';
import 'api_service.dart';

class AuthService {
  final ApiService api;
  final FlutterSecureStorage storage;
  AuthService(this.api, {FlutterSecureStorage? storage})
    : storage = storage ?? const FlutterSecureStorage();
  Future<OtpFlow> login(String username, String password) async =>
      OtpFlow.fromJson(
        await api.post('/auth/login', {
          'username': username.trim(),
          'password': password,
        }),
      );
  Future<OtpFlow> register(Json body) async =>
      OtpFlow.fromJson(await api.post('/auth/register', body));
  Future<OtpFlow> forgot(String email) async => OtpFlow.fromJson(
    await api.post('/auth/forgot-password', {'email': email.trim()}),
  );
  Future<Json> send(OtpFlow flow, String channel) =>
      api.post('/auth/otp/send', {...flow.toJson(), 'channel': channel});
  Future<Json> startFirebase(OtpFlow flow) =>
      api.post('/auth/sms/firebase/start', flow.toJson());
  Future<Json> verifyFirebase(OtpFlow flow, String challenge, String idToken) =>
      api.post('/auth/sms/firebase/verify', {
        ...flow.toJson(),
        'challengeId': challenge,
        'idToken': idToken,
      });
  Future<Json> verify(
    OtpFlow flow,
    String challenge,
    String code, {
    String? password,
  }) {
    final endpoint = switch (flow.purpose) {
      'VerifyEmail' => '/auth/email-verification/verify',
      'VerifyPhone' => '/auth/phone-verification/verify',
      'ResetPassword' => '/auth/reset-password',
      _ => '/auth/login/otp/verify',
    };
    return api.post(endpoint, {
      ...flow.toJson(),
      'challengeId': challenge,
      'code': code.trim(),
      'newPassword': ?password,
      'confirmPassword': ?password,
    });
  }

  Future<OtpFlow> phone(OtpFlow flow) async => OtpFlow.fromJson(
    await api.post('/auth/phone-verification/start', flow.toJson()),
  );
}
