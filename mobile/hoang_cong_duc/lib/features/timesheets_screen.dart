import '../widgets/workforce_ui.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../state/session.dart';
import '../widgets/common.dart';
import '../widgets/editor.dart';

String workStatus(dynamic status) => switch (status) {
  'MissingCheckIn' => 'Thiếu lượt vào',
  'MissingCheckOut' => 'Thiếu lượt ra',
  'Scheduled' => 'Chưa đến giờ',
  'Working' => 'Đang trong ca',
  'Completed' => 'Đủ vào/ra',
  'Leave' => 'Nghỉ phép',
  'LeaveConflict' => 'Xung đột phép/công',
  _ => '$status',
};
String periodStatus(dynamic s) => switch (s) {
  'Closed' => 'Đã chốt',
  'Published' => 'Chờ xác nhận',
  _ => 'Đang tính · Chưa chốt',
};
String responseStatus(dynamic s) => switch (s) {
  'Pending' => 'Chưa xác nhận',
  'Confirmed' => 'Đã xác nhận',
  'Feedback' => 'Có phản hồi',
  'Resolved' => 'Đã xử lý phản hồi',
  'Outdated' => 'Dữ liệu đổi · Cần công bố lại',
  _ => 'Chưa công bố',
};

class TimesheetsScreen extends StatefulWidget {
  final Session session;
  final bool scheduleOnly;
  final String? initialEmployeeId;
  final DateTime? initialMonth;
  const TimesheetsScreen(
    this.session, {
    super.key,
    this.scheduleOnly = false,
    this.initialEmployeeId,
    this.initialMonth,
  });
  @override
  State<TimesheetsScreen> createState() => _TimesheetsScreenState();
}

class _TimesheetsScreenState extends State<TimesheetsScreen> {
  DateTime month = DateTime.now().toUtc().add(const Duration(hours: 7));
  late Future<Json> future;
  final search = TextEditingController();
  List<Json> departments = [], employees = [];
  String? department, employee;
  int page = 1;
  int? selectedDay;
  String lineFilter = 'All';
  bool busy = false;
  String get base => '/timesheets/${month.year}/${month.month}';
  String get filters =>
      '${department == null ? '' : '&departmentId=$department'}${employee == null ? '' : '&employeeId=$employee'}&search=${Uri.encodeQueryComponent(search.text.trim())}';
  bool get admin => widget.session.user!.isAdmin;
  @override
  void initState() {
    super.initState();
    month = widget.initialMonth ?? month;
    employee = widget.initialEmployeeId;
    load();
    if (admin) {
      allRows(widget.session.api, '/employees')
          .then((d) {
            if (mounted) setState(() => employees = d);
          })
          .catchError((Object e) {
            if (mounted) message(context, e.toString(), error: true);
          });
      allRows(widget.session.api, '/departments')
          .then((d) {
            if (mounted) setState(() => departments = d);
          })
          .catchError((Object e) {
            if (mounted) message(context, e.toString(), error: true);
          });
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void load() =>
      future = widget.session.api.get('$base?page=$page&pageSize=20$filters');
  void shiftMonth(int delta) => setState(() {
    month = DateTime(month.year, month.month + delta);
    selectedDay = null;
    page = 1;
    load();
  });
  Future<void> perform(String path, Json body) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.session.api.post(path, body);
      if (mounted) {
        message(context, 'Đã cập nhật bảng công.');
        setState(load);
      }
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> periodAction(String action) async {
    String? reason;
    if (action == 'publish') {
      if (!await confirm(
        context,
        'Công bố TOÀN BỘ bảng công tháng ${month.month}/${month.year}? Bộ lọc chỉ áp dụng xem/xuất. Phiên bản mới yêu cầu nhân viên xác nhận lại.',
      )) {
        return;
      }
    } else if (action == 'close') {
      if (!await confirm(
        context,
        'Chốt TOÀN BỘ kỳ ${month.month}/${month.year}? Các thay đổi công, lịch và nghỉ phép trong kỳ sẽ bị khóa.',
      )) {
        return;
      }
    } else {
      reason = await askReason(context, 'Lý do mở lại kỳ công', minimum: 5);
      if (reason == null) return;
    }
    await perform('$base/$action', {'reason': reason});
  }

  Future<void> exceptionalClose() async {
    final reason = await askReason(
      context,
      'Chốt ngoại lệ: ghi lý do chấp nhận công thiếu/chưa xác nhận. Không dùng để bỏ qua xung đột phép/công.',
      minimum: 5,
    );
    if (reason != null) await perform('$base/close', {'reason': reason});
  }

  Future<void> export() async {
    setState(() => busy = true);
    try {
      final bytes = await widget.session.api.download(
        '$base/export?${filters.substring(1)}',
      );
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/Bang-cong-${month.year}-${month.month.toString().padLeft(2, '0')}-${DateTime.now().millisecondsSinceEpoch}.xlsx',
      );
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ],
          title: 'Bảng công tháng',
        ),
      );
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.scheduleOnly ? 'Lịch làm việc' : 'Bảng công tháng'),
      actions: [
        IconButton(
          tooltip: 'Tải lại',
          onPressed: busy ? null : () => setState(load),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Tháng trước',
                onPressed: busy || month.year <= 2000 && month.month == 1
                    ? null
                    : () => shiftMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${month.month.toString().padLeft(2, '0')}/${month.year}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Tháng sau',
                onPressed: busy || month.year >= 2100 && month.month == 12
                    ? null
                    : () => shiftMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        if (admin)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: ExpansionTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Tìm kiếm và bộ lọc'),
                subtitle: Text(
                  department != null ||
                          employee != null ||
                          search.text.isNotEmpty
                      ? 'Đang áp dụng bộ lọc'
                      : 'Tất cả nhân viên',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: department ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Phòng ban'),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Tất cả phòng ban'),
                      ),
                      ...departments.map(
                        (d) => DropdownMenuItem(
                          value: d['id'] as String,
                          child: Text(d['name']),
                        ),
                      ),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            department = v == '' ? null : v;
                            page = 1;
                            load();
                          }),
                  ),
                  const SizedBox(height: 8),
                  if (employees.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      initialValue: employee ?? '',
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Nhân viên'),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Tất cả nhân viên'),
                        ),
                        ...employees.map(
                          (e) => DropdownMenuItem(
                            value: e['id'] as String,
                            child: Text(
                              '${e['fullName']} · ${e['employeeCode']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              employee = v == '' ? null : v;
                              page = 1;
                              load();
                            }),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: 'Tìm tên hoặc mã nhân viên',
                      suffixIcon: IconButton(
                        tooltip: 'Tìm',
                        onPressed: () => setState(() {
                          page = 1;
                          load();
                        }),
                        icon: const Icon(Icons.search),
                      ),
                    ),
                    onSubmitted: (_) => setState(() {
                      page = 1;
                      load();
                    }),
                  ),
                ],
              ),
            ),
          ),
        if (busy) const LinearProgressIndicator(),
        Expanded(
          child: FutureBuilder<Json>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return ErrorPanel(snap.error!, () => setState(load));
              }
              final data = snap.data!,
                  items = (data['items'] as List).cast<Json>();
              return RefreshIndicator(
                onRefresh: () async {
                  setState(load);
                  await future;
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    GreenHero(
                      eyebrow: widget.scheduleOnly
                          ? 'LỊCH LÀM VIỆC'
                          : 'ĐỐI SOÁT CÔNG',
                      title:
                          '${month.month.toString().padLeft(2, '0')} / ${month.year}',
                      subtitle: widget.scheduleOnly
                          ? 'Chọn ngày để xem ca và địa điểm'
                          : '${periodStatus(data['status'])} · Phiên bản ${data['revision']}',
                      icon: widget.scheduleOnly
                          ? Icons.calendar_month_outlined
                          : Icons.table_chart_outlined,
                    ),
                    CalendarStrip(
                      month: month,
                      selected: selectedDay,
                      marked: items
                          .expand(
                            (item) =>
                                (item['data']['lines'] as List).cast<Json>(),
                          )
                          .map((l) => DateTime.parse(l['date']).day)
                          .toSet(),
                      onChanged: (day) => setState(() => selectedDay = day),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final f in [
                            ('All', 'Tất cả'),
                            ('Missing', 'Thiếu công'),
                            ('Late', 'Đi trễ'),
                            ('Leave', 'Nghỉ phép'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(f.$2),
                                selected: lineFilter == f.$1,
                                onSelected: (_) =>
                                    setState(() => lineFilter = f.$1),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!widget.scheduleOnly &&
                        (admin || data['exceptionReason'] != null))
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${periodStatus(data['status'])} · Phiên bản ${data['revision']}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Text(
                                'Giờ Việt Nam · Giờ làm đã xác nhận và nghỉ phép được thống kê riêng.',
                              ),
                              if (data['exceptionReason'] != null)
                                Text(
                                  'Lý do chốt ngoại lệ: ${data['exceptionReason']}',
                                ),
                              if (admin)
                                ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  title: const Text('Xuất file và quản lý kỳ'),
                                  leading: const Icon(Icons.settings_outlined),
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: busy ? null : export,
                                          icon: const Icon(
                                            Icons.file_download_outlined,
                                          ),
                                          label: const Text('Xuất Excel'),
                                        ),
                                        if (data['status'] != 'Closed')
                                          OutlinedButton(
                                            onPressed: busy
                                                ? null
                                                : () => periodAction('publish'),
                                            child: const Text(
                                              'Công bố phiên bản',
                                            ),
                                          ),
                                        if (data['status'] == 'Published') ...[
                                          FilledButton(
                                            onPressed: busy
                                                ? null
                                                : () => periodAction('close'),
                                            child: const Text('Chốt kỳ'),
                                          ),
                                          TextButton(
                                            onPressed: busy
                                                ? null
                                                : exceptionalClose,
                                            child: const Text(
                                              'Chốt có lý do ngoại lệ',
                                            ),
                                          ),
                                        ],
                                        if (data['status'] == 'Closed')
                                          OutlinedButton(
                                            onPressed: busy
                                                ? null
                                                : () => periodAction('reopen'),
                                            child: const Text('Mở lại kỳ'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          'Không có dữ liệu phù hợp. Ngày không có lịch không tính là vắng.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ...items.map((item) => sheetCard(item, data)),
                    if (admin)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: page > 1 && !busy
                                ? () => setState(() {
                                    page--;
                                    load();
                                  })
                                : null,
                            child: const Text('Trước'),
                          ),
                          Text('Trang $page · ${data['totalCount']} nhân viên'),
                          TextButton(
                            onPressed:
                                page * 20 < (data['totalCount'] as int) && !busy
                                ? () => setState(() {
                                    page++;
                                    load();
                                  })
                                : null,
                            child: const Text('Sau'),
                          ),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
  Widget sheetCard(Json item, Json period) {
    final d = item['data'] as Json, lines = (d['lines'] as List).cast<Json>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${d['employeeName']} · ${d['employeeCode']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('${d['department']}'),
            if (!widget.scheduleOnly) ...[
              const SizedBox(height: 8),
              ResponsiveTiles(
                children: [
                  MetricTile(
                    value: '${d['confirmedHours']}',
                    label: 'Giờ làm xác nhận',
                    icon: Icons.schedule_outlined,
                  ),
                  MetricTile(
                    value: '${d['leaveHours']}',
                    label: 'Giờ nghỉ phép',
                    icon: Icons.beach_access_outlined,
                  ),
                  MetricTile(
                    value: '${d['scheduledShifts']}',
                    label: 'Ca / ${d['scheduledDays']} ngày có lịch',
                    icon: Icons.calendar_month_outlined,
                  ),
                  MetricTile(
                    value: '${d['attendedDays']}',
                    label: 'Ngày có vào',
                    icon: Icons.login_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${d['lateShifts']} ca trễ · ${d['earlyShifts']} ca về sớm · ${d['missingShifts']} ca thiếu công',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                responseStatus(item['responseStatus']),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (item['feedback'] != null)
                Text('Phản hồi: ${item['feedback']}'),
              if (item['resolution'] != null)
                Text('Kết quả xử lý: ${item['resolution']}'),
              if (period['status'] == 'Published' &&
                  item['responseStatus'] == 'Pending' &&
                  !admin)
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              if (await confirm(
                                context,
                                'Xác nhận bảng công phiên bản ${period['revision']} là đúng?',
                              )) {
                                await perform(
                                  '/timesheets/snapshots/${item['snapshotId']}/respond',
                                  {'status': 'Confirmed'},
                                );
                              }
                            },
                      child: const Text('Xác nhận công'),
                    ),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final note = await askReason(
                                context,
                                'Phản hồi bảng công',
                                minimum: 5,
                              );
                              if (note != null) {
                                await perform(
                                  '/timesheets/snapshots/${item['snapshotId']}/respond',
                                  {'status': 'Feedback', 'note': note},
                                );
                              }
                            },
                      child: const Text('Gửi phản hồi'),
                    ),
                  ],
                ),
              if (admin &&
                  item['responseStatus'] == 'Feedback' &&
                  period['status'] == 'Published')
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final reason = await askReason(
                            context,
                            'Kết quả xử lý phản hồi',
                            minimum: 5,
                          );
                          if (reason != null) {
                            await perform(
                              '/timesheets/snapshots/${item['snapshotId']}/resolve',
                              {'reason': reason},
                            );
                          }
                        },
                  child: const Text('Xử lý phản hồi'),
                ),
            ],
            const Divider(),
            if (lines.isEmpty) const Text('Chưa có lịch trong tháng.'),
            ...lines
                .where(
                  (l) =>
                      (selectedDay == null ||
                          DateTime.parse(l['date']).day == selectedDay) &&
                      (lineFilter == 'All' ||
                          lineFilter == 'Missing' &&
                              l['status'].toString().startsWith('Missing') ||
                          lineFilter == 'Late' &&
                              (l['lateMinutes'] as num) > 0 ||
                          lineFilter == 'Leave' &&
                              (l['leaveMinutes'] as num) > 0),
                )
                .map(
                  (l) => ShiftTimelineCard(
                    title: l['shift'],
                    location: l['location'],
                    date: dateOnly(l['date']),
                    start: clockTime(l['startUtc']),
                    end: clockTime(l['endUtc']),
                    status:
                        '${workStatus(l['status'])}${(l['lateMinutes'] as num) > 0 ? ' · Trễ ${l['lateMinutes']} phút' : ''}',
                    warning:
                        l['status'].toString().startsWith('Missing') ||
                        l['status'] == 'LeaveConflict',
                    onTap: () => detail(l),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  void detail(Json l) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${dateOnly(l['date'])} · ${l['shift']}',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            Text('${l['location']} · ${workStatus(l['status'])}'),
            const SizedBox(height: 12),
            Text(
              'Ca: ${vietnamTime(l['startUtc'])} → ${vietnamTime(l['endUtc'])}\nCho phép trễ: ${l['graceMinutes']} phút\nVào: ${vietnamTime(l['checkInUtc'])}\nRa: ${vietnamTime(l['checkOutUtc'])}\nTrễ: ${l['lateMinutes']} phút · Về sớm: ${l['earlyMinutes']} phút\nThời gian làm xác nhận: ${l['workedMinutes'] == null ? 'Chưa đủ vào/ra' : '${l['workedMinutes']} phút'}\nNghỉ phép: ${l['leaveMinutes']} phút\nNguồn vào: ${l['inSource'] ?? '—'}\nNguồn ra: ${l['outSource'] ?? '—'}',
            ),
            for (final key in ['inAttemptId', 'outAttemptId'])
              if (l[key] != null)
                TextButton(
                  onPressed: () async {
                    try {
                      final evidence = await widget.session.api.get(
                        '/attendance/attempts/${l[key]}',
                      );
                      if (ctx.mounted) {
                        await showDialog<void>(
                          context: ctx,
                          builder: (_) => AlertDialog(
                            title: Text(
                              key == 'inAttemptId'
                                  ? 'Bằng chứng vào'
                                  : 'Bằng chứng ra',
                            ),
                            content: Text(
                              'Máy chủ nhận: ${vietnamTime(evidence['receivedAtUtc'])}\nKhoảng cách: ${evidence['distanceMeters']} m\nSai số: ${evidence['accuracyMeters']} m\n${reasonName((evidence['reasonCodes'] as List).join(', '))}',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Đóng'),
                              ),
                            ],
                          ),
                        );
                      }
                    } catch (e) {
                      if (ctx.mounted) message(ctx, e.toString(), error: true);
                    }
                  },
                  child: Text(
                    key == 'inAttemptId'
                        ? 'Xem bằng chứng lượt vào'
                        : 'Xem bằng chứng lượt ra',
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}
