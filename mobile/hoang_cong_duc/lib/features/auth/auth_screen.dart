import '../../widgets/workforce_ui.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/firebase_sms_service.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';

enum AuthMode { login, register, forgot }

class AuthScreen extends StatefulWidget {
  final Session session;
  final AuthMode mode;
  const AuthScreen(this.session, {super.key, this.mode = AuthMode.login});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  bool busy = false;
  bool obscure = true;
  @override
  void initState() {
    super.initState();
    widget.session.readRemembered().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> remembered() async {
    setState(() => busy = true);
    try {
      await widget.session.resumeRemembered();
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> biometric(String method) async {
    setState(() => busy = true);
    try {
      await widget.session.loginBiometric(method);
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  TextEditingController c(String key) =>
      fields.putIfAbsent(key, () => TextEditingController());
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final auth = widget.session.auth;
      final OtpFlow flow;
      switch (widget.mode) {
        case AuthMode.login:
          flow = await auth.login(c('username').text, c('password').text);
        case AuthMode.register:
          flow = await auth.register({
            'fullName': c('fullName').text.trim(),
            'username': c('username').text.trim(),
            'email': c('email').text.trim(),
            'phone': c('phone').text.trim(),
            'password': c('password').text,
            'confirmPassword': c('confirm').text,
          });
        case AuthMode.forgot:
          flow = await auth.forgot(c('email').text);
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OtpScreen(widget.session, flow)),
      );
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    String key,
    String label, {
    bool secret = false,
    TextInputType? keyboard,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: c(key),
      obscureText: secret && obscure,
      keyboardType: keyboard,
      autocorrect: !secret,
      enableSuggestions: !secret,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(
          secret
              ? Icons.lock_outline
              : key == 'email'
              ? Icons.alternate_email
              : key == 'phone'
              ? Icons.phone_outlined
              : key == 'fullName'
              ? Icons.badge_outlined
              : Icons.person_outline,
        ),
        suffixIcon: secret
            ? IconButton(
                onPressed: () => setState(() => obscure = !obscure),
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              )
            : null,
      ),
      validator:
          validator ??
          (v) => v == null || v.trim().isEmpty ? 'Vui lòng nhập $label' : null,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final register = widget.mode == AuthMode.register;
    final forgot = widget.mode == AuthMode.forgot;
    return Scaffold(
      appBar: widget.mode == AuthMode.login ? null : AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GreenHero(
                      eyebrow: 'Đức Attendance',
                      title: forgot
                          ? 'Lấy lại quyền truy cập'
                          : register
                          ? 'Gia nhập đội ngũ'
                          : 'Ngày làm việc,\nnhẹ nhàng hơn.',
                      subtitle: forgot
                          ? 'Xác minh email để đặt lại mật khẩu.'
                          : register
                          ? 'Tạo tài khoản và xác minh thông tin của bạn.'
                          : 'Chấm công rõ ràng. Theo dõi ca làm dễ dàng.',
                      icon: Icons.fingerprint_rounded,
                    ),
                    const SizedBox(height: 20),
                    FormSection(
                      title: forgot
                          ? 'Khôi phục tài khoản'
                          : register
                          ? 'Tạo tài khoản'
                          : 'Đăng nhập',
                      subtitle: 'Thông tin của bạn được xác minh an toàn',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.mode == AuthMode.login) ...[
                            if (widget.session.hasBiometrics)
                              Text(
                                'Tài khoản: ${widget.session.biometricAccount['username']}',
                              ),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => biometric('Face'),
                                  icon: const Icon(Icons.face_outlined),
                                  label: const Text('Khuôn mặt'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => biometric('Fingerprint'),
                                  icon: const Icon(Icons.fingerprint),
                                  label: const Text('Vân tay'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (widget.mode == AuthMode.login &&
                              widget.session.rememberedUsername != null &&
                              !widget.session.hasBiometrics)
                            Card(
                              child: ListTile(
                                leading: const Icon(
                                  Icons.account_circle_outlined,
                                ),
                                title: Text(widget.session.rememberedUsername!),
                                subtitle: const Text(
                                  'Chạm để đăng nhập trên thiết bị này',
                                ),
                                onTap: busy ? null : remembered,
                                trailing: IconButton(
                                  icon: const Icon(Icons.close),
                                  tooltip: 'Quên tài khoản đã lưu',
                                  onPressed: busy
                                      ? null
                                      : () async {
                                          try {
                                            await widget.session
                                                .forgetRemembered();
                                            if (mounted) setState(() {});
                                          } catch (e) {
                                            if (context.mounted) {
                                              message(
                                                context,
                                                e.toString(),
                                                error: true,
                                              );
                                            }
                                          }
                                        },
                                ),
                              ),
                            ),
                          if (register) field('fullName', 'Họ và tên'),
                          if (!forgot)
                            field(
                              'username',
                              'Tên đăng nhập',
                              validator: (v) =>
                                  v != null &&
                                      RegExp(r'^[A-Za-z0-9_.]{3,32}$')
                                          .hasMatch(v.trim())
                                  ? null
                                  : 'Tên đăng nhập gồm 3–32 chữ Latin, số, dấu chấm hoặc gạch dưới.',
                            ),
                          if (register || forgot)
                            field(
                              'email',
                              'Email',
                              keyboard: TextInputType.emailAddress,
                              validator: (v) =>
                                  v != null &&
                                      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                          .hasMatch(v.trim())
                                  ? null
                                  : 'Email chưa hợp lệ.',
                            ),
                          if (register)
                            field(
                              'phone',
                              'Số điện thoại',
                              keyboard: TextInputType.phone,
                            ),
                          if (!forgot)
                            field(
                              'password',
                              'Mật khẩu',
                              secret: true,
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Vui lòng nhập mật khẩu'
                                  : register && v.length < 12
                                  ? 'Mật khẩu tối thiểu 12 ký tự.'
                                  : null,
                            ),
                          if (register)
                            field(
                              'confirm',
                              'Xác nhận mật khẩu',
                              secret: true,
                              validator: (v) => v != c('password').text
                                  ? 'Mật khẩu xác nhận chưa khớp.'
                                  : null,
                            ),
                          if (register)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 20),
                              child: Text(
                                'Mật khẩu cần chữ hoa, chữ thường, số và ký tự đặc biệt. Tài khoản mới có quyền Nhân viên.',
                              ),
                            ),
                          if (widget.mode == AuthMode.login)
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text('Ghi nhớ đăng nhập'),
                              subtitle: const Text(
                                'Chạm vào tài khoản để đăng nhập lại trong 30 ngày.',
                              ),
                              value: widget.session.rememberLogin,
                              onChanged: busy
                                  ? null
                                  : (v) => setState(
                                      () => widget.session.rememberLogin =
                                          v ?? false,
                                    ),
                            ),
                          BusyButton(
                            busy: busy,
                            label: forgot
                                ? 'Tiếp tục xác minh'
                                : register
                                ? 'Đăng ký'
                                : 'Tiếp tục đăng nhập',
                            onPressed: submit,
                          ),
                          if (widget.mode == AuthMode.login) ...[
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AuthScreen(
                                          widget.session,
                                          mode: AuthMode.forgot,
                                        ),
                                      ),
                                    ),
                              child: const Text('Quên mật khẩu?'),
                            ),
                            const Divider(height: 28),
                            OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AuthScreen(
                                          widget.session,
                                          mode: AuthMode.register,
                                        ),
                                      ),
                                    ),
                              child: const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text('Tạo tài khoản nhân viên'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OtpScreen extends StatefulWidget {
  final Session session;
  final OtpFlow flow;
  const OtpScreen(this.session, this.flow, {super.key});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final form = GlobalKey<FormState>();
  final code = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  String channel = 'Email';
  String? challenge;
  DateTime? expires;
  int cooldown = 0;
  bool busy = false;
  Timer? timer;
  final firebase = FirebaseSmsService();
  String? firebaseVerificationId;
  int? firebaseResendToken;
  int firebaseRequest = 0;
  bool completingFirebase = false;
  bool get useFirebase =>
      channel == 'Sms' && widget.flow.smsProvider == 'Firebase';
  @override
  void initState() {
    super.initState();
    channel = widget.flow.channels.first;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          if (cooldown > 0) cooldown--;
        });
      }
    });
  }

  @override
  void dispose() {
    firebaseRequest++;
    timer?.cancel();
    code.dispose();
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (useFirebase) {
      await sendFirebase();
      return;
    }
    setState(() => busy = true);
    try {
      final r = await widget.session.auth.send(widget.flow, channel);
      if (!mounted) return;
      setState(() {
        challenge = r['challengeId'];
        expires = DateTime.parse(r['expiresAtUtc']);
        cooldown = 60;
      });
      message(
        context,
        'Dịch vụ đã chấp nhận gửi mã. Hãy kiểm tra ${channel == 'Sms' ? 'tin nhắn' : 'email, kể cả thư rác'}.',
      );
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verify() async {
    if (challenge == null || !form.currentState!.validate()) return;
    if (useFirebase) {
      if (firebaseVerificationId == null || completingFirebase) return;
      setState(() => busy = true);
      try {
        final token = await firebase.confirm(
          firebaseVerificationId!,
          code.text.trim(),
        );
        await completeFirebase(token);
      } catch (e) {
        if (mounted) message(context, e.toString(), error: true);
      } finally {
        if (mounted) setState(() => busy = false);
      }
      return;
    }
    setState(() => busy = true);
    try {
      final r = await widget.session.auth.verify(
        widget.flow,
        challenge!,
        code.text,
        password: widget.flow.purpose == 'ResetPassword' ? password.text : null,
      );
      if (!mounted) return;
      if (widget.flow.purpose == 'Login') {
        await widget.session.accept(r);
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      } else {
        message(context, switch (widget.flow.purpose) {
          'VerifyEmail' => 'Đã xác minh email. Nhân viên cần được Admin duyệt trước khi đăng nhập.',
          'VerifyPhone' =>
            'Đã xác minh điện thoại. Bạn có thể đăng nhập bằng SMS OTP.',
          _ => 'Đã đổi mật khẩu. Hãy đăng nhập lại.',
        });
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> sendFirebase() async {
    final request = ++firebaseRequest;
    setState(() {
      busy = true;
      firebaseVerificationId = null;
      code.clear();
    });
    try {
      await firebase.ready();
      final r = await widget.session.auth.startFirebase(widget.flow);
      if (!mounted || request != firebaseRequest) return;
      setState(() {
        challenge = r['challengeId'];
        expires = DateTime.parse(r['expiresAtUtc']);
        cooldown = 60;
      });
      await firebase.send(
        phone: r['phoneNumber'],
        resendToken: firebaseResendToken,
        onCodeSent: (id, resend) {
          if (!mounted || request != firebaseRequest) return;
          setState(() {
            firebaseVerificationId = id;
            firebaseResendToken = resend;
            busy = false;
          });
          message(
            context,
            'Firebase đã tiếp nhận yêu cầu gửi mã. Hãy kiểm tra SMS trên điện thoại.',
          );
        },
        onAutomatic: (credential) async {
          if (!mounted || request != firebaseRequest || completingFirebase) {
            return;
          }
          try {
            await completeFirebase(await firebase.tokenFor(credential));
          } catch (e) {
            if (mounted) {
              setState(() => busy = false);
              message(context, e.toString(), error: true);
            }
          }
        },
        onError: (e) {
          if (!mounted || request != firebaseRequest) return;
          setState(() => busy = false);
          message(context, e.toString(), error: true);
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        message(context, e.toString(), error: true);
      }
    }
  }

  Future<void> completeFirebase(String token) async {
    if (!mounted || completingFirebase || challenge == null) return;
    completingFirebase = true;
    setState(() => busy = true);
    try {
      final r = await widget.session.auth.verifyFirebase(
        widget.flow,
        challenge!,
        token,
      );
      if (!mounted) return;
      if (widget.flow.purpose == 'Login') {
        await widget.session.accept(r);
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      } else {
        message(context, 'Đã xác minh số điện thoại. Hãy đăng nhập lại.');
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } finally {
      completingFirebase = false;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> phone() async {
    setState(() => busy = true);
    try {
      final f = await widget.session.auth.phone(widget.flow);
      if (mounted) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => OtpScreen(widget.session, f)),
        );
      }
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seconds = expires?.difference(DateTime.now()).inSeconds.clamp(0, 300);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.flow.purpose == 'Login'
              ? 'Xác thực đăng nhập'
              : 'Xác minh tài khoản',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GreenHero(
                    eyebrow: 'XÁC THỰC TÀI KHOẢN',
                    title: 'Thêm một bước bảo vệ',
                    subtitle: channel == 'Sms'
                        ? widget.flow.maskedPhone
                        : widget.flow.maskedEmail,
                    icon: Icons.verified_user_outlined,
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    children: widget.flow.channels
                        .map(
                          (c) => ChoiceChip(
                            label: Text(c == 'Sms' ? 'SMS OTP' : 'Email OTP'),
                            selected: channel == c,
                            onSelected: busy || cooldown > 0
                                ? null
                                : (_) => setState(() {
                                    channel = c;
                                    challenge = null;
                                    expires = null;
                                    firebaseVerificationId = null;
                                    firebaseRequest++;
                                    code.clear();
                                  }),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: busy || cooldown > 0 ? null : send,
                    icon: const Icon(Icons.send_outlined),
                    label: Text(
                      cooldown > 0
                          ? 'Gửi lại sau ${cooldown}s'
                          : challenge == null
                          ? 'Gửi mã xác minh'
                          : 'Gửi lại mã',
                    ),
                  ),
                  if (seconds != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        seconds > 0
                            ? 'Mã còn khoảng ${seconds ~/ 60} phút ${seconds % 60} giây'
                            : 'Mã đã hết hạn. Hãy yêu cầu mã mới.',
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: code,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w700,
                    ),
                    autofillHints: const [AutofillHints.oneTimeCode],
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Mã OTP 6 chữ số',
                    ),
                    validator: (v) =>
                        v != null && RegExp(r'^\d{6}$').hasMatch(v)
                        ? null
                        : 'Nhập đủ 6 chữ số.',
                  ),
                  if (widget.flow.purpose == 'ResetPassword') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Mật khẩu mới',
                      ),
                      validator: (v) => v == null || v.length < 12
                          ? 'Tối thiểu 12 ký tự, gồm hoa/thường/số/ký tự đặc biệt.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: confirmPassword,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Nhập lại mật khẩu mới',
                      ),
                      validator: (v) => v != password.text
                          ? 'Mật khẩu xác nhận chưa khớp.'
                          : null,
                    ),
                  ],
                  const SizedBox(height: 20),
                  BusyButton(
                    busy: busy,
                    label: 'Xác minh',
                    onPressed:
                        challenge == null ||
                            useFirebase && firebaseVerificationId == null
                        ? null
                        : verify,
                    icon: Icons.verified_user_outlined,
                  ),
                  if (widget.flow.purpose == 'Login' &&
                      !widget.flow.phoneVerified &&
                      widget.flow.smsProvider != 'Firebase')
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: TextButton(
                        onPressed: busy ? null : phone,
                        child: const Text(
                          'Xác minh số điện thoại để dùng SMS OTP',
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  const Text(
                    'Không chia sẻ mã OTP. Mã được máy chủ kiểm tra và chỉ dùng một lần.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
