import '../widgets/workforce_ui.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../state/session.dart';
import '../state/app_preferences.dart';
import '../widgets/common.dart';
import '../widgets/editor.dart';

class SettingsScreen extends StatefulWidget {
  final Session session;
  const SettingsScreen(this.session, {super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool busy = false;
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> toggle(String method, bool value) async {
    if (value) {
      final allowed = await confirm(
        context,
        method == 'Face'
            ? 'Đăng ký khuôn mặt bằng 2 ảnh chính diện, đủ sáng. Mẫu đặc trưng được mã hóa trên server và có thể xóa. Đây là bản demo, có nguy cơ bị đánh lừa bằng ảnh/video. Bạn đồng ý đăng ký?'
            : 'Bật đăng nhập vân tay cho tài khoản này? Cần đăng nhập bằng mật khẩu + OTP trong 5 phút gần nhất.',
      );
      if (!allowed) return;
    }
    await run(() async {
      if (value) {
        await widget.session.enrollBiometric(method);
      } else {
        await widget.session.removeBiometric(method);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final prefs = s.preferences;
    final own = s.currentBiometrics;
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const GreenHero(
            eyebrow: 'CÁ NHÂN HÓA',
            title: 'Theo cách của bạn',
            subtitle: 'Giao diện, bảo mật và hồ sơ ở cùng một nơi',
            icon: Icons.tune_rounded,
          ),
          const SectionHeading('Giao diện'),
          FormSection(
            title: 'Hiển thị và màu sắc',
            icon: Icons.palette_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                DropdownButtonFormField<ThemeMode>(
                  isExpanded: true,
                  initialValue: prefs.mode,
                  decoration: const InputDecoration(labelText: 'Màu nền'),
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('Theo hệ thống'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text('Sáng'),
                    ),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('Tối')),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => run(() async {
                          await prefs.update(theme: v);
                        }),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<double>(
                  isExpanded: true,
                  initialValue: prefs.fontScale,
                  decoration: const InputDecoration(
                    labelText: 'Cỡ chữ bổ sung',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 1,
                      child: Text('Mặc định theo hệ thống'),
                    ),
                    DropdownMenuItem(value: 1.15, child: Text('Lớn hơn 15%')),
                    DropdownMenuItem(value: 1.3, child: Text('Lớn hơn 30%')),
                    DropdownMenuItem(value: 1.5, child: Text('Lớn hơn 50%')),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => run(() async {
                          await prefs.update(scale: v);
                        }),
                ),
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Xem trước: Đức Attendance\nChấm công rõ ràng, dễ đọc.',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Màu chủ đạo'),
                Wrap(
                  spacing: 12,
                  children: [
                    for (final color in AppPreferences.colors)
                      IconButton.filledTonal(
                        tooltip: color == 0xff16a34a
                            ? 'Xanh lá Premium'
                            : color == 0xff155eef
                            ? 'Xanh dương'
                            : color == 0xff137547
                            ? 'Xanh lá'
                            : color == 0xff7950b5
                            ? 'Tím'
                            : 'Cam',
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                await prefs.update(seed: color);
                              }),
                        icon: Icon(
                          prefs.color == color
                              ? Icons.check_circle
                              : Icons.circle,
                          color: Color(color),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FormSection(
            title: 'Đăng nhập và bảo mật',
            icon: Icons.shield_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Bật phương thức sau khi đăng nhập bằng mật khẩu + OTP. Phiên thiết bị có hiệu lực 30 ngày.',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Đăng nhập bằng vân tay'),
                  subtitle: const Text(
                    'Dùng cảm biến vân tay và khóa bảo mật Android',
                  ),
                  value: own && s.biometricAccount['fingerprintId'] != null,
                  onChanged: busy ? null : (v) => toggle('Fingerprint', v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Đăng nhập bằng khuôn mặt'),
                  subtitle: const Text(
                    'Demo: camera so khớp mẫu, chưa chống ảnh/video nâng cao',
                  ),
                  value: own && s.biometricAccount['faceToken'] != null,
                  onChanged: busy ? null : (v) => toggle('Face', v),
                ),
                if (busy) const LinearProgressIndicator(),
                if (s.rememberedUsername != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.no_accounts_outlined),
                    title: Text(
                      'Quên tài khoản đã lưu: ${s.rememberedUsername}',
                    ),
                    onTap: busy ? null : () => run(s.forgetRemembered),
                  ),
              ],
            ),
          ),
          const SectionHeading('Thông tin cá nhân'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('Cập nhật hồ sơ cá nhân'),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PersonalProfileScreen(s),
                      ),
                    );
                    if (mounted && s.user != null) setState(() {});
                  },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.badge_outlined),
            title: Text(
              s.user!.isAdmin
                  ? 'Duyệt yêu cầu sửa họ tên'
                  : 'Yêu cầu sửa họ tên nhân sự',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => NameRequestsScreen(s)),
                  ),
          ),
        ],
      ),
    );
  }
}

class PersonalProfileScreen extends StatefulWidget {
  final Session session;
  const PersonalProfileScreen(this.session, {super.key});
  @override
  State<PersonalProfileScreen> createState() => _PersonalProfileScreenState();
}

class _PersonalProfileScreenState extends State<PersonalProfileScreen> {
  late final TextEditingController name;
  String? avatar;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.session.user!.name);
    avatar = widget.session.user!.avatarDataUrl;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> photo() async {
    setState(() => busy = true);
    widget.session.authenticationInProgress = true;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (file == null) return;
      final image = img.decodeImage(await file.readAsBytes());
      if (image == null) throw Exception('Ảnh không hợp lệ.');
      final bytes = img.encodeJpg(
        img.copyResize(img.bakeOrientation(image), width: 256),
        quality: 75,
      );
      if (bytes.length > 100000) throw Exception('Ảnh quá lớn, chọn ảnh khác.');
      if (mounted) {
        setState(
          () => avatar = 'data:image/jpeg;base64,${base64Encode(bytes)}',
        );
      }
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      widget.session.authenticationInProgress = false;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (name.text.trim().length < 2 || name.text.trim().length > 80) {
      message(context, 'Tên hiển thị cần 2–80 ký tự.', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final result = await widget.session.api.put('/profile', {
        'displayName': name.text.trim(),
        'avatarDataUrl': avatar,
      });
      widget.session.updateUser(result);
      if (mounted) message(context, 'Đã cập nhật hồ sơ.');
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> contact(String kind) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          title: kind == 'Email' ? 'Đổi email' : 'Đổi số điện thoại',
          fields: [
            EditorField(
              'value',
              kind == 'Email' ? 'Email mới' : 'Số điện thoại mới',
              type: kind == 'Email' ? 'email' : 'phone',
            ),
            const EditorField(
              'password',
              'Mật khẩu hiện tại',
              type: 'password',
            ),
          ],
          save: (body) async {
            final change = await widget.session.api.post(
              '/profile/contact/start',
              {'kind': kind, ...body},
            );
            if (!mounted) return;
            final confirmed = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => EditorScreen(
                  title: 'Xác minh thay đổi liên hệ',
                  header: Text(
                    'Nhập mã gửi đến email hiện tại và ${kind == 'Email' ? 'email' : 'số điện thoại'} mới. Mỗi mã có hiệu lực 5 phút.',
                  ),
                  fields: const [
                    EditorField('currentCode', 'OTP email hiện tại'),
                    EditorField('newCode', 'OTP địa chỉ mới'),
                  ],
                  save: (codes) async {
                    await widget.session.api.post('/profile/contact/confirm', {
                      'id': change['id'],
                      ...codes,
                    });
                    await widget.session.clear();
                  },
                ),
              ),
            );
            if (confirmed != true) {
              throw Exception(
                'Chưa xác minh, thông tin liên hệ cũ được giữ nguyên.',
              );
            }
          },
        ),
      ),
    );
    if (result == true && mounted) {
      message(context, 'Đã thay đổi. Hãy đăng nhập lại.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hồ sơ cá nhân')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (avatar != null)
            Center(
              child: ClipOval(
                child: Image.memory(
                  base64Decode(avatar!.split(',').last),
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(Icons.person, size: 96),
                ),
              ),
            ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            children: [
              TextButton.icon(
                onPressed: busy ? null : photo,
                icon: const Icon(Icons.photo_outlined),
                label: const Text('Chọn ảnh'),
              ),
              if (avatar != null)
                TextButton(
                  onPressed: busy ? null : () => setState(() => avatar = null),
                  child: const Text('Xóa ảnh'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: name,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Tên hiển thị'),
          ),
          const Text(
            'Tên hiển thị không thay thế họ tên trong hồ sơ nhân sự. Mã nhân viên, phòng ban, chức vụ và lịch ca do Admin quản lý.',
          ),
          const SizedBox(height: 16),
          BusyButton(busy: busy, label: 'Lưu hồ sơ', onPressed: save),
          const Divider(height: 32),
          OutlinedButton(
            onPressed: busy ? null : () => contact('Email'),
            child: const Text('Đổi email có xác minh'),
          ),
          OutlinedButton(
            onPressed: busy ? null : () => contact('Phone'),
            child: const Text('Đổi số điện thoại có xác minh'),
          ),
          const Text(
            'Đổi số điện thoại cần gửi được SMS đến số mới. Nếu dịch vụ SMS chưa được cấu hình, thông tin hiện tại được giữ nguyên.',
          ),
        ],
      ),
    );
  }
}

class NameRequestsScreen extends StatefulWidget {
  final Session session;
  const NameRequestsScreen(this.session, {super.key});
  @override
  State<NameRequestsScreen> createState() => _NameRequestsScreenState();
}

class _NameRequestsScreenState extends State<NameRequestsScreen> {
  int revision = 0;
  Future<void> create() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          title: 'Yêu cầu sửa họ tên',
          fields: [
            EditorField(
              'fullName',
              'Họ tên nhân sự đề nghị',
              initial: widget.session.user!.fullName,
            ),
          ],
          save: (body) async {
            await widget.session.api.post('/profile/name', body);
          },
        ),
      ),
    );
    if (saved == true && mounted) setState(() => revision++);
  }

  @override
  Widget build(BuildContext context) => DataPage(
    key: ValueKey(revision),
    title: 'Yêu cầu sửa họ tên',
    load: (p) =>
        widget.session.api.page('/profile/name-requests?page=$p&pageSize=100'),
    floatingActionButton: widget.session.user!.isAdmin
        ? null
        : FloatingActionButton.extended(
            onPressed: create,
            icon: const Icon(Icons.add),
            label: const Text('Gửi yêu cầu'),
          ),
    item: (r, reload) => ItemCard(
      title: '${r['currentName']} → ${r['requestedName']}',
      subtitle: '${stateName(r['status'])}\n${r['decisionReason'] ?? ''}',
      icon: Icons.badge_outlined,
      onTap: !widget.session.user!.isAdmin || r['status'] != 'Pending'
          ? null
          : () async {
              final approve = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Xử lý yêu cầu họ tên'),
                  content: Text('${r['currentName']} → ${r['requestedName']}'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Từ chối'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Duyệt'),
                    ),
                  ],
                ),
              );
              if (approve == null || !context.mounted) return;
              final reason = await askReason(
                context,
                'Lý do xử lý',
                minimum: 5,
              );
              if (reason == null) return;
              try {
                await widget.session.api.post(
                  '/profile/name-requests/${r['id']}/${approve ? 'approve' : 'reject'}',
                  {'reason': reason},
                );
                if (mounted) setState(() => revision++);
              } catch (e) {
                if (context.mounted) {
                  message(context, e.toString(), error: true);
                }
              }
            },
    ),
  );
}
