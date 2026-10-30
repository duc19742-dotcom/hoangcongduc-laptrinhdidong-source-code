import '../../widgets/workforce_ui.dart';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/employee_service.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';
import '../../widgets/editor.dart';
import '../settings_screen.dart';

class HistoryScreen extends StatefulWidget {
  final Session session;
  const HistoryScreen(this.session, {super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTimeRange range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );
  String? employeeId;
  List<Json> employees = [];
  @override
  void initState() {
    super.initState();
    if (widget.session.user!.isAdmin) {
      allRows(widget.session.api, '/employees')
          .then((x) {
            if (mounted) setState(() => employees = x);
          })
          .catchError((Object e) {
            if (mounted) message(context, e.toString(), error: true);
          });
    }
  }

  Future<void> pick() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now(),
      initialDateRange: range,
    );
    if (r != null) {
      if (r.duration.inDays > 93) {
        if (mounted) message(context, 'Chọn tối đa 93 ngày.', error: true);
        return;
      }
      setState(() => range = r);
    }
  }

  @override
  Widget build(BuildContext context) {
    final from = range.start.toIso8601String().substring(0, 10),
        to = range.end.toIso8601String().substring(0, 10);
    return DataPage(
      key: ValueKey('$from-$to-$employeeId'),
      title: widget.session.user!.isAdmin
          ? 'Quản lý chấm công'
          : 'Lịch sử chấm công',
      load: (p) => widget.session.api.page(
        '${widget.session.user!.isAdmin ? '/attendance' : '/attendance/me'}?from=$from&to=$to&page=$p&pageSize=20${employeeId == null ? '' : '&employeeId=$employeeId'}',
      ),
      header: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${dateOnly(from)} – ${dateOnly(to)}'),
              trailing: const Icon(Icons.date_range),
              onTap: pick,
            ),
            if (widget.session.user!.isAdmin)
              DropdownButtonFormField<String>(
                initialValue: employeeId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Nhân viên'),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('Tất cả nhân viên'),
                  ),
                  ...employees.map(
                    (x) => DropdownMenuItem(
                      value: x['id'] as String,
                      child: Text(
                        x['fullName'],
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => employeeId = v),
              ),
          ],
        ),
      ),
      item: (r, reload) => ItemCard(
        title:
            '${clockTime(r['effectiveAtUtc'])}  ·  ${actionName(r['action'])}',
        subtitle:
            '${vietnamTime(r['effectiveAtUtc'])}\n${r['shiftName']} · ${dateOnly(r['workDate'])}\n${r['source'] == 'AdminCorrection'
                ? 'Admin bổ sung theo giải trình'
                : r['source'] == 'AdminApproved'
                ? 'Được Admin xác minh'
                : 'Tự động xác nhận'}\n${r['distanceMeters'] == null || r['accuracyMeters'] == null ? 'Không có GPS: bản ghi điều chỉnh có nhật ký Admin' : 'Khoảng cách ${(r['distanceMeters'] as num).toStringAsFixed(1)} m · GPS ${(r['accuracyMeters'] as num).toStringAsFixed(1)} m'}',
        icon: r['action'] == 'CheckOut' ? Icons.logout : Icons.login,
      ),
    );
  }
}

class ScheduleScreen extends StatelessWidget {
  final Session session;
  const ScheduleScreen(this.session, {super.key});
  @override
  Widget build(BuildContext context) {
    final start = DateTime.now()
        .subtract(const Duration(days: 1))
        .toIso8601String()
        .substring(0, 10);
    final end = DateTime.now()
        .add(const Duration(days: 30))
        .toIso8601String()
        .substring(0, 10);
    return DataPage(
      title: 'Lịch làm việc của tôi',
      calendarDateKey: 'workDate',
      load: (p) => session.api.page(
        '/employee-shifts/me?from=$start&to=$end&page=$p&pageSize=20',
      ),
      item: (r, reload) => ItemCard(
        title: r['shiftName'],
        subtitle:
            'Ngày ${dateOnly(r['workDate'])}\n${vietnamTime(r['startUtc'])} – ${vietnamTime(r['endUtc'])}\n${r['locationName']}',
        icon: Icons.event_available,
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  final Session session;
  const ProfileScreen(this.session, {super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<Employee>? future;
  @override
  void initState() {
    super.initState();
    if (!widget.session.user!.isAdmin) {
      future = EmployeeService(widget.session.api).mine();
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.session.user!;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        GreenHero(
          eyebrow: u.isAdmin ? 'QUẢN TRỊ VIÊN' : 'HỒ SƠ CỦA BẠN',
          title: u.name,
          subtitle: '@${u.username}',
          icon: Icons.badge_outlined,
          trailing: CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white,
            backgroundImage: u.avatarBytes == null
                ? null
                : MemoryImage(u.avatarBytes!),
            child: u.avatarBytes == null
                ? const Icon(Icons.person_outline, color: workforceDeep)
                : null,
          ),
        ),
        const SectionHeading('Tài khoản và công việc'),
        ItemCard(
          title: 'Thông tin tài khoản',
          subtitle:
              'Tên đăng nhập: ${u.username}\nEmail: ${u.email}\nEmail: ${u.emailConfirmed ? 'Đã xác minh' : 'Chưa xác minh'}\nĐiện thoại: ${u.phoneNumberConfirmed ? 'Đã xác minh' : 'Chưa xác minh'}',
          icon: Icons.person_outline,
        ),
        if (future != null)
          FutureBuilder<Employee>(
            future: future,
            builder: (context, s) {
              if (s.hasError) {
                return ErrorPanel(
                  s.error!,
                  () => setState(
                    () => future = EmployeeService(widget.session.api).mine(),
                  ),
                );
              }
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final e = s.data!;
              return ItemCard(
                title: 'Hồ sơ nhân viên',
                subtitle:
                    'Mã: ${e.code}\nPhòng ban: ${e.departmentName}\nChức vụ: ${e.jobTitle}\nNgày vào làm: ${dateOnly(e.hireDate)}\nSố điện thoại: ${e.phone}',
                icon: Icons.badge_outlined,
              );
            },
          ),
        const SizedBox(height: 24),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Cài đặt'),
          subtitle: const Text('Giao diện, sinh trắc học và hồ sơ'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SettingsScreen(widget.session)),
            );
            if (mounted && widget.session.user != null) {
              setState(
                () => future = widget.session.user!.isAdmin
                    ? null
                    : EmployeeService(widget.session.api).mine(),
              );
            }
          },
        ),
        OutlinedButton.icon(
          onPressed: () async {
            if (!await confirm(context, 'Đăng xuất khỏi tài khoản này?')) {
              return;
            }
            try {
              await widget.session.logout();
            } catch (e) {
              if (context.mounted) {
                message(
                  context,
                  'Đã xóa phiên trên thiết bị. Máy chủ chưa xác nhận thu hồi phiên do lỗi kết nối.',
                  error: true,
                );
              }
            }
          },
          icon: const Icon(Icons.logout),
          label: const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Đăng xuất'),
          ),
        ),
      ],
    );
  }
}
