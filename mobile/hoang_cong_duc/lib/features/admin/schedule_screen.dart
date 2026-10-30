import '../../widgets/workforce_ui.dart';

import 'package:flutter/material.dart';

import '../../state/session.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/editor.dart';

class WorkSchedulesScreen extends StatefulWidget {
  final Session session;
  const WorkSchedulesScreen(this.session, {super.key});
  @override
  State<WorkSchedulesScreen> createState() => _WorkSchedulesScreenState();
}

class _WorkSchedulesScreenState extends State<WorkSchedulesScreen> {
  int revision = 0;
  Future<void> create() async {
    try {
      final data = await Future.wait([
        allRows(widget.session.api, '/employees'),
        allRows(widget.session.api, '/shifts'),
        allRows(widget.session.api, '/work-locations'),
      ]);
      if (!mounted) return;
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => EditorScreen(
            title: 'Lịch định kỳ',
            header: const GreenHero(
              eyebrow: 'LỊCH LẶP LẠI',
              title: 'Nhịp làm việc của đội ngũ',
              subtitle: 'Lịch cá nhân và lịch mặc định công ty',
              icon: Icons.repeat_rounded,
            ),
            fields: [
              EditorField(
                'employeeId',
                'Áp dụng cho',
                type: 'select',
                initial: 'default',
                options: {
                  'default': 'Mặc định toàn công ty',
                  for (final e in data[0])
                    e['id']: '${e['employeeCode']} · ${e['fullName']}',
                },
              ),
              EditorField(
                'shiftId',
                'Ca làm',
                type: 'select',
                options: {for (final e in data[1]) e['id']: e['name']},
              ),
              EditorField(
                'workLocationId',
                'Địa điểm',
                type: 'select',
                options: {for (final e in data[2]) e['id']: e['name']},
              ),
              const EditorField(
                'weekdaysMask',
                'Ngày làm việc',
                type: 'select',
                initial: '62',
                options: {
                  '62': 'Thứ Hai – Thứ Sáu',
                  '126': 'Thứ Hai – Thứ Bảy',
                  '127': 'Cả tuần',
                  '1': 'Chủ Nhật',
                  '2': 'Thứ Hai',
                  '4': 'Thứ Ba',
                  '8': 'Thứ Tư',
                  '16': 'Thứ Năm',
                  '32': 'Thứ Sáu',
                  '64': 'Thứ Bảy',
                },
              ),
              EditorField(
                'fromDate',
                'Áp dụng từ ngày',
                type: 'date',
                initial: DateTime.now().toIso8601String().substring(0, 10),
              ),
              EditorField(
                'toDate',
                'Áp dụng đến ngày',
                type: 'date',
                initial: DateTime.now()
                    .add(const Duration(days: 365))
                    .toIso8601String()
                    .substring(0, 10),
              ),
            ],
            save: (body) async {
              body['employeeId'] = body['employeeId'] == 'default'
                  ? null
                  : body['employeeId'];
              body['weekdaysMask'] = int.parse(body['weekdaysMask']);
              await widget.session.api.post('/work-schedules', body);
            },
          ),
        ),
      );
      if (saved == true && mounted) setState(() => revision++);
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => DataPage(
    key: ValueKey(revision),
    title: 'Lịch định kỳ',
    load: (p) =>
        widget.session.api.page('/work-schedules?page=$p&pageSize=100'),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: create,
      label: const Text('Tạo lịch'),
      icon: const Icon(Icons.add),
    ),
    item: (r, reload) => ItemCard(
      title: '${r['employeeName']} · ${r['shiftName']}',
      subtitle:
          '${r['locationName']}\n${dateOnly(r['fromDate'])} – ${dateOnly(r['toDate'])}\n${r['isActive'] == true ? 'Đang áp dụng' : 'Đã ngừng'}',
      icon: Icons.repeat,
      trailing: r['isActive'] != true
          ? null
          : IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Ngừng lịch',
              onPressed: () async {
                if (!await confirm(
                  context,
                  'Ngừng áp dụng lịch định kỳ này? Lượt chấm công đã có được giữ nguyên.',
                )) {
                  return;
                }
                try {
                  await widget.session.api.delete('/work-schedules/${r['id']}');
                  if (mounted) setState(() => revision++);
                } catch (e) {
                  if (context.mounted) {
                    message(context, e.toString(), error: true);
                  }
                }
              },
            ),
    ),
  );
}

class AttendanceSupportScreen extends StatefulWidget {
  final Session session;
  final String? status, departmentId;
  const AttendanceSupportScreen(
    this.session, {
    super.key,
    this.status,
    this.departmentId,
  });
  @override
  State<AttendanceSupportScreen> createState() =>
      _AttendanceSupportScreenState();
}

class _AttendanceSupportScreenState extends State<AttendanceSupportScreen> {
  int revision = 0;
  Future<void> correctCheckout(Json row) async {
    try {
      final end = DateTime.now().toUtc().add(const Duration(hours: 7));
      final from = end.subtract(const Duration(days: 31));
      final assignments = await allRows(
        widget.session.api,
        '/employee-shifts?employeeId=${row['employeeId']}&from=${from.toIso8601String().substring(0, 10)}&to=${end.toIso8601String().substring(0, 10)}',
      );
      if (!mounted) return;
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => EditorScreen(
            title: 'Bổ sung giờ ra có giải trình',
            fields: [
              EditorField(
                'employeeShiftId',
                'Ca cần bổ sung',
                type: 'select',
                options: {
                  for (final a in assignments)
                    a['id']: '${dateOnly(a['workDate'])} · ${a['shiftName']}',
                },
              ),
              EditorField(
                'date',
                'Ngày ra ca (giờ Việt Nam)',
                type: 'date',
                initial: end.toIso8601String().substring(0, 10),
              ),
              const EditorField(
                'time',
                'Giờ ra thực tế',
                type: 'time',
                initial: '17:00',
              ),
              const EditorField(
                'reason',
                'Lý do và căn cứ duyệt',
                type: 'multiline',
              ),
            ],
            save: (body) async {
              final time = body['time'] as String;
              final utc = DateTime.parse('${body['date']}T$time+07:00').toUtc();
              await widget.session.api.post(
                '/attendance-support/${row['id']}/checkout',
                {
                  'employeeShiftId': body['employeeShiftId'],
                  'effectiveAtUtc': utc.toIso8601String(),
                  'reason': body['reason'],
                },
              );
            },
          ),
        ),
      );
      if (saved == true && mounted) setState(() => revision++);
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    }
  }

  Future<void> create() async {
    final kind = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Loại yêu cầu'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'MissingSchedule'),
            child: const Text('Bổ sung lịch làm'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'MissingCheckOut'),
            child: const Text('Quên chấm công ra'),
          ),
        ],
      ),
    );
    if (kind == null || !mounted) return;
    final reason = await askReason(
      context,
      'Nêu ngày, ca và nội dung cần hỗ trợ',
      minimum: 10,
    );
    if (reason == null) return;
    try {
      await widget.session.api.post('/attendance-support', {
        'kind': kind,
        'reason': reason,
      });
      if (mounted) setState(() => revision++);
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => DataPage(
    key: ValueKey(revision),
    title: 'Hỗ trợ lịch và thiếu công',
    load: (p) => widget.session.api.page(
      '/attendance-support?page=$p&pageSize=100${widget.status == null ? '' : '&status=${widget.status}'}${widget.departmentId == null ? '' : '&departmentId=${widget.departmentId}'}',
    ),
    floatingActionButton: widget.session.user!.isAdmin
        ? null
        : FloatingActionButton.extended(
            onPressed: create,
            label: const Text('Gửi yêu cầu'),
            icon: const Icon(Icons.add),
          ),
    item: (r, reload) => ItemCard(
      title:
          '${r['employeeName']} · ${r['kind'] == 'MissingSchedule' ? 'Bổ sung lịch' : 'Quên ra ca'}',
      subtitle: '${r['reason']}\n${r['status']}\n${r['decisionReason'] ?? ''}',
      icon: Icons.support_agent,
      onTap: !widget.session.user!.isAdmin || r['status'] != 'Pending'
          ? null
          : () async {
              if (r['kind'] == 'MissingCheckOut') {
                await correctCheckout(r);
                return;
              }
              final reason = await askReason(
                context,
                'Ghi kết quả xử lý (lịch/công cần sửa tại mục tương ứng)',
                minimum: 5,
              );
              if (reason == null) return;
              try {
                await widget.session.api.post(
                  '/attendance-support/${r['id']}/resolve',
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
