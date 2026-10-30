import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../core/firebase_config.dart';

class FirebaseSmsException implements Exception {
  final String message;
  const FirebaseSmsException(this.message);
  @override
  String toString() => message;
}

class FirebaseSmsService {
  Future<FirebaseAuth> ready() async {
    if (!FirebaseConfig.configured) {
      throw const FirebaseSmsException(
        'SMS chưa được cấu hình cho bản ứng dụng này. Bạn có thể dùng Email OTP.',
      );
    }
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: FirebaseConfig.options);
    }
    return FirebaseAuth.instance;
  }

  Future<void> send({
    required String phone,
    required void Function(String, int?) onCodeSent,
    required void Function(PhoneAuthCredential) onAutomatic,
    required void Function(FirebaseSmsException) onError,
    int? resendToken,
  }) async {
    try {
      final auth = await ready();
      // A fresh phone sign-in is needed for this password-authenticated API flow.
      await auth.signOut();
      await auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        forceResendingToken: resendToken,
        verificationCompleted: onAutomatic,
        verificationFailed: (e) => onError(explain(e)),
        codeSent: onCodeSent,
        codeAutoRetrievalTimeout: (_) {},
      );
    } on FirebaseAuthException catch (e) {
      throw explain(e);
    }
  }

  Future<String> confirm(String verificationId, String code) => tokenFor(
    PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code),
  );

  Future<String> tokenFor(PhoneAuthCredential credential) async {
    final auth = await ready();
    try {
      final result = await auth.signInWithCredential(credential);
      final token = await result.user?.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw const FirebaseSmsException(
          'Chưa nhận được kết quả xác minh SMS. Hãy thử lại.',
        );
      }
      return token;
    } on FirebaseAuthException catch (e) {
      throw explain(e);
    } finally {
      // The application uses the API's own JWT, not a persistent Firebase login.
      await auth.signOut();
    }
  }

  static FirebaseSmsException explain(FirebaseAuthException e) =>
      FirebaseSmsException(switch (e.code) {
        'invalid-verification-code' =>
          'Mã SMS không đúng. Hãy kiểm tra tin nhắn và nhập lại.',
        'session-expired' => 'Mã SMS đã hết hạn. Hãy yêu cầu mã mới.',
        'invalid-phone-number' =>
          'Số điện thoại chưa hợp lệ. Hãy liên hệ quản trị viên để kiểm tra.',
        'too-many-requests' || 'quota-exceeded' =>
          'Đã đạt giới hạn gửi SMS. Hãy chờ hoặc dùng Email OTP.',
        'billing-not-enabled' => 'Dự án Firebase chưa bật thanh toán để gửi SMS thật. Hãy dùng Email OTP trong lúc cấu hình.',
        'operation-not-allowed' => 'Dự án chưa bật xác thực số điện thoại hoặc chưa cho phép gửi SMS đến Việt Nam.',
        'app-not-authorized' ||
        'invalid-app-credential' ||
        'missing-client-identifier' => 'Chưa xác minh được ứng dụng. Cần kiểm tra cấu hình Android và chữ ký ứng dụng trên Firebase.',
        'captcha-check-failed' || 'app-verification-failed' => 'Chưa hoàn tất xác minh ứng dụng. Hãy thử lại và làm bước xác minh trên màn hình nếu được yêu cầu.',
        'network-request-failed' =>
          'Chưa kết nối được dịch vụ SMS. Hãy kiểm tra Internet.',
        _ =>
          'Chưa gửi hoặc xác minh được SMS. Hãy thử lại hoặc dùng Email OTP.',
      });
}
