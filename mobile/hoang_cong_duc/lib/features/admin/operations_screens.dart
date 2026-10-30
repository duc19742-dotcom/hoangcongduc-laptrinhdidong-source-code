import '../../widgets/workforce_ui.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/models.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';
import '../../widgets/editor.dart';
import 'catalog_screen.dart';

class AssignmentScreen extends StatefulWidget {
  final Session session;
  const AssignmentScreen(this.session, {super.key});
  @override
  State<AssignmentScreen> createState() => _AssignmentScreenState();
}

class _AssignmentScreenState extends State<AssignmentScreen> {
  int revision = 0;
  Future<void> edit([Json? row]) async {
    try {
      final data = await Future.wait([
        allRows(widget.session.api, '/employees'),
        allRows(widget.session.api, '/shifts'),
        allRows(widget.session.api, '/work-locations'),
      ]);
      if (!mounted) return;
      if (data.any((x) => x.isEmpty)) {
        message(
          context,
          'Cần có nhân viên, ca và địa điểm trước khi phân công.',
          error: true,
        );
        return;
      }
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => EditorScreen(
            title: row == null ? 'Phân công ca' : 'Sửa phân công',
            fields: [
              EditorField(
                'employeeId',
                'Nhân viên',
                type: 'select',
                initial: row?['employeeId'],
                options: {
                  for (final x in data[0])
                    x['id'] as String:
                        '${x['employeeCode']} · ${x['fullName']}',
                },
              ),
              EditorField(
                'shiftId',
                'Ca làm',
                type: 'select',
                initial: row?['shiftId'],
                options: {
                  for (final x in data[1])
                    x['id'] as String: x['name'] as String,
                },
              ),
              EditorField(
                'workLocationId',
                'Địa điểm',
                type: 'select',
                initial: row?['workLocationId'],
                options: {
                  for (final x in data[2])
                    x['id'] as String: x['name'] as String,
                },
              ),
              EditorField(
                'workDate',
                'Ngày bắt đầu ca',
                type: 'date',
                initial:
                    row?['workDate'] ??
                    DateTime.now().toIso8601String().substring(0, 10),
              ),
              if (row == null)
                EditorField(
                  'endDate',
                  'Lặp hằng ngày đến hết ngày',
                  type: 'date',
                  initial: DateTime.now()
                      .add(const Duration(days: 30))
                      .toIso8601String()
                      .substring(0, 10),
                ),
            ],
            save: (body) async {
              if (row == null) {
                body['endDate'] ??= body['workDate'];
                await widget.session.api.post('/employee-shifts/range', body);
              } else {
                body['rowVersion'] = row['rowVersion'];
                await widget.session.api.put(
                  '/employee-shifts/${row['id']}',
                  body,
                );
              }
            },
          ),
        ),
      );
      if (saved == true && mounted) setState(() => revision++);
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    }
  }

  Future<void> remove(Json row) async {
    if (!await confirm(
      context,
      'Xóa phân công này? Ca có lần chấm công sẽ không được xóa.',
    )) {
      return;
    }
    try {
      await widget.session.api.delete('/employee-shifts/${row['id']}');
      if (mounted) setState(() => revision++);
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final future = DateTime.now()
        .add(const Duration(days: 31))
        .toIso8601String()
        .substring(0, 10);
    return DataPage(
      key: ValueKey(revision),
      title: 'Phân công ca làm',
      calendarDateKey: 'workDate',
      load: (p) => widget.session.api.page(
        '/employee-shifts?from=$today&to=$future&page=$p&pageSize=20',
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: edit,
        icon: const Icon(Icons.add),
        label: const Text('Phân công'),
      ),
      item: (r, reload) => ItemCard(
        title: r['employeeName'],
        subtitle:
            '${r['shiftName']} · ${dateOnly(r['workDate'])}\n${vietnamTime(r['startUtc'])} – ${vietnamTime(r['endUtc'])}\n${r['locationName']}',
        icon: Icons.event_available_outlined,
        onTap: () => edit(r),
        trailing: PopupMenuButton<String>(
          onSelected: (v) => v == 'edit' ? edit(r) : remove(r),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Sửa phân công')),
            PopupMenuItem(value: 'delete', child: Text('Xóa phân công')),
          ],
        ),
      ),
    );
  }
}

class PendingUsersScreen extends StatefulWidget {
  final Session session;
  const PendingUsersScreen(this.session, {super.key});
  @override
  State<PendingUsersScreen> createState() => _PendingUsersScreenState();
}

class _PendingUsersScreenState extends State<PendingUsersScreen> {
  int revision = 0;
  Future<bool> approveRegistration(Json row) async {
    var departments = await allRows(widget.session.api, '/departments');
    if (!mounted) return false;
    if (departments.isEmpty) {
      message(context, 'Hãy tạo phòng ban để xếp nhân viên.');
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CatalogScreen(widget.session, CatalogKind.departments),
        ),
      );
      departments = await allRows(widget.session.api, '/departments');
      if (!mounted || departments.isEmpty) return false;
    }
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          title: 'Duyệt nhân viên',
          submitLabel: 'Duyệt nhân viên',
          header: ItemCard(
            title: row['fullName'],
            subtitle:
                '${row['username']} · ${row['email']}\n${row['phoneNumber']}\nThông tin được lấy từ tài khoản đã xác minh email.',
            icon: Icons.person_outline,
          ),
          fields: [
            EditorField(
              'departmentId',
              'Phòng ban',
              type: 'select',
              initial: departments.length == 1 ? departments.first['id'] : null,
              options: {
                for (final d in departments)
                  d['id'] as String: d['name'] as String,
              },
            ),
            const EditorField(
              'employeeCode',
              'Mã nhân viên (tùy chọn)',
              required: false,
            ),
            const EditorField(
              'jobTitle',
              'Chức vụ',
              initial: 'Nhân viên',
              required: false,
            ),
          ],
          save: (body) async {
            await widget.session.api.post(
              '/users/${row['id']}/approve-registration',
              body,
            );
          },
        ),
      ),
    );
    return saved == true;
  }

  Future<void> approve(Json row) async {
    try {
      final employees = (await allRows(widget.session.api, '/employees'))
          .where(
            (e) =>
                e['userId'] == null &&
                e['isActive'] == true &&
                (e['email'] as String).toLowerCase() ==
                    (row['email'] as String).toLowerCase(),
          )
          .toList();
      if (!mounted) return;
      if (row['emailConfirmed'] != true) {
        message(context, 'Tài khoản chưa xác minh email.', error: true);
        return;
      }
      if (employees.isEmpty) {
        if (await approveRegistration(row) && mounted) {
          setState(() => revision++);
        }
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EditorScreen(
            title: 'Duyệt nhân viên',
            submitLabel: 'Duyệt nhân viên',
            fields: [
              EditorField(
                'employeeId',
                'Liên kết hồ sơ nhân viên',
                type: 'select',
                initial: employees.first['id'],
                options: {
                  for (final e in employees)
                    e['id'] as String:
                        '${e['employeeCode']} · ${e['fullName']}',
                },
              ),
            ],
            save: (body) async {
              await widget.session.api.post(
                '/users/${row['id']}/approve',
                body,
              );
            },
          ),
        ),
      );
      if (mounted) setState(() => revision++);
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    }
  }

  Future<void> reject(Json row) async {
    final reason = await askReason(context, 'Từ chối tài khoản');
    if (reason == null) return;
    try {
      await widget.session.api.post('/users/${row['id']}/reject', {
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
    title: 'Tài khoản chờ duyệt',
    load: (p) => widget.session.api.page('/users/pending?page=$p&pageSize=20'),
    item: (r, reload) => ItemCard(
      title: r['fullName'],
      subtitle:
          '${r['username']} · ${r['email']}\n${r['emailConfirmed'] == true ? 'Email đã xác minh' : 'Chưa xác minh email'}',
      icon: Icons.person_add_alt_1_outlined,
      onTap: () => approve(r),
      trailing: PopupMenuButton<String>(
        onSelected: (v) => v == 'approve' ? approve(r) : reject(r),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'approve', child: Text('Duyệt nhân viên')),
          PopupMenuItem(value: 'reject', child: Text('Từ chối')),
        ],
      ),
    ),
  );
}

class QrGeneratorScreen extends StatefulWidget {
  final Session session;
  const QrGeneratorScreen(this.session, {super.key});
  @override
  State<QrGeneratorScreen> createState() => _QrGeneratorScreenState();
}

class _QrGeneratorScreenState extends State<QrGeneratorScreen> {
  late Future<List<List<Json>>> future;
  String? shift, location;
  String action = 'CheckIn';
  DateTime date = DateTime.now();
  bool busy = false;
  Json? qr;
  Timer? timer;
  int remaining = 0;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && qr != null) {
        setState(
          () =>
              remaining = DateTime.parse(qr!['expiresAtUtc'])
                  .difference(DateTime.now())
                  .inSeconds
                  .clamp(0, 120),
        );
      }
    });
  }

  void load() {
    future = Future.wait([
      allRows(widget.session.api, '/shifts'),
      allRows(widget.session.api, '/work-locations'),
    ]);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> generate() async {
    if (shift == null || location == null) {
      message(context, 'Hãy chọn ca và địa điểm.', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final value = await widget.session.api.post('/qr-sessions', {
        'shiftId': shift,
        'workLocationId': location,
        'workDate': date.toIso8601String().substring(0, 10),
        'action': action,
        'ttlSeconds': 60,
      });
      if (mounted) {
        setState(() {
          qr = value;
          remaining = 60;
        });
      }
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> revoke() async {
    if (qr == null) return;
    try {
      await widget.session.api.delete('/qr-sessions/${qr!['id']}');
      if (mounted) setState(() => qr = null);
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tạo QR chấm công')),
    body: FutureBuilder<List<List<Json>>>(
      future: future,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) return ErrorPanel(s.error!, () => setState(load));
        final data = s.data!;
        if (data.any((x) => x.isEmpty)) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Cần tạo ca làm và địa điểm công ty trước.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const GreenHero(
              eyebrow: 'QR THEO CA',
              title: 'Phiên chấm công',
              subtitle: 'Chọn đúng ca, địa điểm và lượt vào/ra',
              icon: Icons.qr_code_2,
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: shift,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ca làm'),
              items: data[0]
                  .where((x) => x['isActive'] == true)
                  .map(
                    (x) => DropdownMenuItem(
                      value: x['id'] as String,
                      child: Text(x['name']),
                    ),
                  )
                  .toList(),
              onChanged: busy ? null : (v) => setState(() => shift = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: location,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Địa điểm'),
              items: data[1]
                  .where((x) => x['isActive'] == true)
                  .map(
                    (x) => DropdownMenuItem(
                      value: x['id'] as String,
                      child: Text(x['name']),
                    ),
                  )
                  .toList(),
              onChanged: busy ? null : (v) => setState(() => location = v),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ngày bắt đầu ca'),
              subtitle: Text(dateOnly(date.toIso8601String())),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 90)),
                );
                if (d != null) setState(() => date = d);
              },
            ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'CheckIn', label: Text('Vào ca')),
                ButtonSegment(value: 'CheckOut', label: Text('Ra ca')),
              ],
              selected: {action},
              onSelectionChanged: busy
                  ? null
                  : (v) => setState(() => action = v.first),
            ),
            const SizedBox(height: 20),
            BusyButton(
              busy: busy,
              label: 'Tạo QR có hiệu lực 60 giây',
              onPressed: generate,
              icon: Icons.qr_code,
            ),
            if (qr != null) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        remaining > 0 ? 'Còn $remaining giây' : 'QR đã hết hạn',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      if (remaining > 0)
                        QrImageView(
                          data: qr!['qrToken'],
                          version: QrVersions.auto,
                          size: (MediaQuery.sizeOf(context).width - 100).clamp(
                            140,
                            260,
                          ),
                          backgroundColor: Colors.white,
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.all(40),
                          child: Icon(Icons.timer_off_outlined, size: 80),
                        ),
                      const SizedBox(height: 12),
                      Text(actionName(qr!['action'])),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: revoke,
                        child: const Text('Thu hồi phiên QR'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Hiển thị QR trên màn hình khác để nhân viên quét bằng điện thoại. Mỗi nhân viên chỉ dùng được phiên này một lần.',
              ),
            ],
          ],
        );
      },
    ),
  );
}

class StatisticsScreen extends StatefulWidget {
  final Session session;
  const StatisticsScreen(this.session, {super.key});
  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late Future<Json> future;
  DateTimeRange range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 6)),
    end: DateTime.now(),
  );
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    future = widget.session.api.get(
      '/attendance/statistics?from=${range.start.toIso8601String().substring(0, 10)}&to=${range.end.toIso8601String().substring(0, 10)}',
    );
  }

  Future<void> pick() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: range,
    );
    if (r != null) {
      if (r.duration.inDays > 93) {
        if (mounted) {
          message(context, 'Khoảng thống kê tối đa 93 ngày.', error: true);
        }
        return;
      }
      setState(() {
        range = r;
        load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Thống kê chấm công'),
      actions: [
        IconButton(onPressed: pick, icon: const Icon(Icons.date_range)),
        IconButton(
          onPressed: () => setState(load),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<Json>(
      future: future,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) return ErrorPanel(s.error!, () => setState(load));
        final d = s.data!;
        final daily = List<Json>.from(d['daily']);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            GreenHero(
              eyebrow: 'BÁO CÁO CHẤM CÔNG',
              title: '${d['confirmedHours']} giờ xác nhận',
              subtitle:
                  '${dateOnly(range.start.toIso8601String())} — ${dateOnly(range.end.toIso8601String())}',
              icon: Icons.insights_rounded,
            ),
            const SectionHeading('Số liệu tổng hợp'),
            ResponsiveTiles(
              children: [
                MetricTile(
                  value: '${d['checkIns']}',
                  label: 'Lượt vào ca',
                  icon: Icons.login,
                ),
                MetricTile(
                  value: '${d['checkOuts']}',
                  label: 'Lượt ra ca',
                  icon: Icons.logout,
                ),
                MetricTile(
                  value: '${d['lateCheckIns']}',
                  label: 'Lượt đi trễ',
                  icon: Icons.schedule,
                  color: const Color(0xffd97706),
                ),
                MetricTile(
                  value: '${d['openShifts']}',
                  label: 'Ca chưa ra',
                  icon: Icons.pending_actions,
                  color: const Color(0xffd97706),
                ),
              ],
            ),
            const SectionHeading('Lượt chấm công theo ngày'),
            if (daily.isEmpty)
              const EmptyState(
                message: 'Không có lượt chấm công trong khoảng ngày đã chọn.',
              )
            else
              FormSection(
                title: 'Phân bố theo ngày',
                icon: Icons.bar_chart_rounded,
                child: DataBars(
                  daily
                      .map(
                        (x) => (
                          label: dateOnly(x['date']),
                          value: (x['count'] as num).toDouble(),
                        ),
                      )
                      .toList(),
                ),
              ),
            const SizedBox(height: 20),
            const Text(
              'Chỉ tính công đã xác nhận. Tổng giờ dựa trên cặp vào/ra hoàn chỉnh; lượt chờ giải trình chưa được cộng.',
            ),
          ],
        );
      },
    ),
  );
}
