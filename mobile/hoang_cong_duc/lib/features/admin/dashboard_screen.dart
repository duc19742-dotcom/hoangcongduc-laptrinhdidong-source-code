import '../../widgets/workforce_ui.dart';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';
import '../../widgets/editor.dart';
import '../attendance/requests_screen.dart';
import '../leave_screen.dart';
import '../timesheets_screen.dart';
import 'schedule_screen.dart';

class DashboardPanel extends StatelessWidget {
  final Session session;
  final Json data;
  const DashboardPanel(this.session, this.data, {super.key});
  void open(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  void rows(BuildContext context, String label, bool Function(Json) predicate) {
    final rows = (data['items'] as List).cast<Json>().where(predicate).toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .65,
          builder: (_, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '$label · ${dateOnly(data['date'])}',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const Text(
                'Đơn vị: ca làm. Có thể bao gồm ca qua đêm bắt đầu hôm trước.',
              ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Không có ca phù hợp.'),
                ),
              ...rows.map((r) {
                final l = r['line'] as Json;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${r['employeeName']} · ${r['employeeCode']}'),
                  subtitle: Text(
                    '${l['shift']} · ${l['location']}\n${workStatus(l['status'])}\n${vietnamTime(l['startUtc'])} → ${vietnamTime(l['endUtc'])}',
                  ),
                  isThreeLine: true,
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metrics = <(String, String, IconData, bool Function(Json))>[
      ('scheduled', 'Ca có lịch', Icons.event_note_outlined, (_) => true),
      (
        'checkIns',
        'Đã vào ca',
        Icons.login,
        (r) => r['line']['checkInUtc'] != null,
      ),
      (
        'checkOuts',
        'Đã ra ca',
        Icons.logout,
        (r) => r['line']['checkOutUtc'] != null,
      ),
      (
        'late',
        'Ca đi trễ',
        Icons.schedule,
        (r) => (r['line']['lateMinutes'] as num) > 0,
      ),
      (
        'missingIn',
        'Thiếu lượt vào',
        Icons.person_search_outlined,
        (r) => r['line']['status'] == 'MissingCheckIn',
      ),
      (
        'missingOut',
        'Thiếu lượt ra',
        Icons.warning_amber,
        (r) => r['line']['status'] == 'MissingCheckOut',
      ),
      (
        'onLeave',
        'Ca có nghỉ phép',
        Icons.beach_access_outlined,
        (r) => (r['line']['leaveMinutes'] as num) > 0,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GreenHero(
          eyebrow: 'TỔNG QUAN · ${dateOnly(data['date'])}',
          title: '${data['employees']} nhân viên có lịch',
          subtitle:
              '${data['checkIns']} ca đã vào · ${data['checkOuts']} ca đã ra',
          icon: Icons.insights_rounded,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: const Icon(Icons.pending_actions, size: 18),
                label: Text(
                  '${(data['pendingLeave'] as num? ?? 0) + (data['pendingAttendance'] as num? ?? 0) + (data['pendingSupport'] as num? ?? 0)} yêu cầu chờ xử lý',
                ),
              ),
            ],
          ),
        ),
        const SectionHeading(
          'Chấm công trong ngày',
          subtitle: 'Đơn vị: ca làm · Các nhóm có thể giao nhau',
        ),
        ResponsiveTiles(
          children: metrics
              .map(
                (m) => MetricTile(
                  value: '${data[m.$1]}',
                  label: m.$2,
                  icon: m.$3,
                  color: m.$1.startsWith('missing') || m.$1 == 'late'
                      ? const Color(0xffd97706)
                      : null,
                  onTap: () => rows(context, m.$2, m.$4),
                ),
              )
              .toList(),
        ),
        const SectionHeading('Phân bố lượt chấm công'),
        FormSection(
          title: 'Vào / ra / thiếu công',
          icon: Icons.bar_chart_rounded,
          child: DataBars([
            (
              label: 'Đã vào ca',
              value: (data['checkIns'] as num? ?? 0).toDouble(),
            ),
            (
              label: 'Đã ra ca',
              value: (data['checkOuts'] as num? ?? 0).toDouble(),
            ),
            (
              label: 'Thiếu lượt vào',
              value: (data['missingIn'] as num? ?? 0).toDouble(),
            ),
            (
              label: 'Thiếu lượt ra',
              value: (data['missingOut'] as num? ?? 0).toDouble(),
            ),
          ]),
        ),
        const SectionHeading('Yêu cầu chờ xử lý'),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.beach_access_outlined),
                title: const Text('Nghỉ phép chờ duyệt'),
                trailing: Text('${data['pendingLeave']}'),
                onTap: () => open(
                  context,
                  LeaveScreen(
                    session,
                    initialStatus: 'Pending',
                    initialDepartment: data['departmentId'] ?? '',
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('Giải trình chờ duyệt'),
                trailing: Text('${data['pendingAttendance']}'),
                onTap: () => open(
                  context,
                  RequestsScreen(
                    session,
                    initialStatus: 'Pending',
                    departmentId: data['departmentId'],
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.support_agent),
                title: const Text('Hỗ trợ lịch/thiếu công'),
                trailing: Text('${data['pendingSupport']}'),
                onTap: () => open(
                  context,
                  AttendanceSupportScreen(
                    session,
                    status: 'Pending',
                    departmentId: data['departmentId'],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Text(
          'Yêu cầu chờ xử lý tính trên mọi ngày, theo phạm vi phòng ban đã lọc.',
        ),
      ],
    );
  }
}

class DashboardScreen extends StatefulWidget {
  final Session session;
  const DashboardScreen(this.session, {super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DateTime date = DateTime.now().toUtc().add(const Duration(hours: 7));
  String department = '';
  List<Json> departments = [];
  late Future<Json> future;
  void load() => future = widget.session.api.get(
    '/dashboard?date=${date.toIso8601String().substring(0, 10)}&departmentId=$department',
  );
  @override
  void initState() {
    super.initState();
    load();
    allRows(widget.session.api, '/departments')
        .then((d) {
          if (mounted) setState(() => departments = d);
        })
        .catchError((Object e) {
          if (mounted) message(context, e.toString(), error: true);
        });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Tổng quan chấm công'),
      actions: [
        IconButton(
          tooltip: 'Tải lại',
          onPressed: () => setState(load),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100, 12, 31),
                  );
                  if (d != null && mounted) {
                    setState(() {
                      date = d;
                      load();
                    });
                  }
                },
                icon: const Icon(Icons.date_range),
                label: Text(dateOnly(date.toIso8601String())),
              ),
              DropdownButtonFormField<String>(
                initialValue: department,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Phòng ban'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Tất cả')),
                  ...departments.map(
                    (d) => DropdownMenuItem(
                      value: d['id'] as String,
                      child: Text(d['name']),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() {
                  department = v!;
                  load();
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<Json>(
            future: future,
            builder: (ctx, s) {
              if (s.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.hasError) return ErrorPanel(s.error!, () => setState(load));
              return RefreshIndicator(
                onRefresh: () async {
                  setState(load);
                  await future;
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [DashboardPanel(widget.session, s.data!)],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}
