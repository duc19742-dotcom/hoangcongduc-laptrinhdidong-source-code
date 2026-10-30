import '../widgets/workforce_ui.dart';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/session.dart';
import '../widgets/common.dart';
import '../widgets/editor.dart';
import 'timesheets_screen.dart';

class LeaveScreen extends StatefulWidget {
  final Session session;
  final String initialStatus, initialDepartment;
  const LeaveScreen(
    this.session, {
    super.key,
    this.initialStatus = '',
    this.initialDepartment = '',
  });
  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  String status = '', employee = '', department = '';
  List<Json> departments = [], employees = [];
  DateTimeRange? range;
  int revision = 0;
  bool busy = false;
  bool get admin => widget.session.user!.isAdmin;
  @override
  void initState() {
    super.initState();
    status = widget.initialStatus;
    department = widget.initialDepartment;
    if (admin) loadFilters();
  }

  Future<void> loadFilters() async {
    try {
      final results = await Future.wait([
        allRows(widget.session.api, '/departments'),
        allRows(widget.session.api, '/employees'),
      ]);
      if (mounted) {
        setState(() {
          departments = results[0];
          employees = results[1];
        });
      }
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    }
  }

  String iso(DateTime d) => d.toIso8601String().substring(0, 10);
  Future<void> edit([Json? item]) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => LeaveEditor(widget.session, item: item),
      ),
    );
    if (result == true && mounted) setState(() => revision++);
  }

  Future<void> decide(Json row, String action) async {
    String? reason;
    if (admin) {
      reason = await askReason(
        context,
        action == 'approve'
            ? 'Lý do duyệt nghỉ phép'
            : action == 'reject'
            ? 'Lý do từ chối'
            : 'Lý do thu hồi phép đã duyệt',
        minimum: 5,
      );
      if (reason == null) return;
    } else if (!await confirm(context, 'Hủy đơn nghỉ phép này?')) {
      return;
    }
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.session.api.post('/leave-requests/${row['id']}/$action', {
        'reason': reason,
      });
      if (mounted) {
        message(context, 'Đã cập nhật đơn.');
        setState(() => revision++);
      }
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DataPage(
    key: ValueKey('$revision|$status|$employee|$department|$range'),
    title: admin ? 'Duyệt nghỉ phép' : 'Nghỉ phép của tôi',
    load: (page) => widget.session.api.page(
      '/leave-requests?page=$page&pageSize=20&status=$status&employeeId=$employee&departmentId=$department${range == null ? '' : '&from=${iso(range!.start)}&to=${iso(range!.end)}'}',
    ),
    header: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final value in [
                  '',
                  'Pending',
                  'Approved',
                  'Rejected',
                  'Cancelled',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(value.isEmpty ? 'Tất cả' : stateName(value)),
                      selected: status == value,
                      onSelected: busy
                          ? null
                          : (_) => setState(() => status = value),
                    ),
                  ),
              ],
            ),
          ),
          if (admin) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('departments-${departments.length}'),
              initialValue: departments.any((d) => d['id'] == department)
                  ? department
                  : '',
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
              onChanged: busy ? null : (v) => setState(() => department = v!),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: employee,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Nhân viên'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Tất cả')),
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
              onChanged: busy ? null : (v) => setState(() => employee = v!),
            ),
          ],
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text(
                  range == null
                      ? 'Lọc thời gian'
                      : '${dateOnly(iso(range!.start))} – ${dateOnly(iso(range!.end))}',
                ),
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100, 12, 31),
                    initialDateRange: range,
                  );
                  if (picked != null && mounted) setState(() => range = picked);
                },
              ),
              if (range != null)
                TextButton(
                  onPressed: () => setState(() => range = null),
                  child: const Text('Bỏ lọc ngày'),
                ),
            ],
          ),
        ],
      ),
    ),
    floatingActionButton: admin
        ? null
        : FloatingActionButton.extended(
            onPressed: busy ? null : edit,
            icon: const Icon(Icons.add),
            label: const Text('Xin nghỉ'),
          ),
    item: (row, reload) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${row['employeeName']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${dateOnly(row['fromDate'])} → ${dateOnly(row['toDate'])} · ${row['kind'] == 'HalfDay' ? 'Nửa ca' : 'Cả ngày'}',
            ),
            if (row['kind'] == 'HalfDay')
              Text(
                '${vietnamTime(row['fromUtc'])} → ${vietnamTime(row['toUtc'])}',
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(row['status']),
            ),
            Text('Lý do: ${row['reason']}'),
            if (row['decisionReason'] != null)
              Text(
                'Kết quả: ${row['decisionReason']}\nXử lý: ${vietnamTime(row['reviewedAtUtc'])}',
              ),
            if (admin)
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TimesheetsScreen(
                      widget.session,
                      initialEmployeeId: row['employeeId'],
                      initialMonth: DateTime.parse(row['fromDate']),
                    ),
                  ),
                ),
                child: const Text('Đối chiếu lịch và bảng công'),
              ),
            if (row['status'] == 'Pending')
              Wrap(
                spacing: 8,
                children: admin
                    ? [
                        FilledButton(
                          onPressed: busy ? null : () => decide(row, 'approve'),
                          child: const Text('Duyệt'),
                        ),
                        OutlinedButton(
                          onPressed: busy ? null : () => decide(row, 'reject'),
                          child: const Text('Từ chối'),
                        ),
                      ]
                    : [
                        OutlinedButton(
                          onPressed: busy ? null : () => edit(row),
                          child: const Text('Sửa đơn'),
                        ),
                        TextButton(
                          onPressed: busy ? null : () => decide(row, 'cancel'),
                          child: const Text('Hủy đơn'),
                        ),
                      ],
              ),
            if (admin && row['status'] == 'Approved')
              TextButton(
                onPressed: busy ? null : () => decide(row, 'cancel'),
                child: const Text('Thu hồi phép có lý do'),
              ),
          ],
        ),
      ),
    ),
  );
}

class LeaveEditor extends StatefulWidget {
  final Session session;
  final Json? item;
  const LeaveEditor(this.session, {super.key, this.item});
  @override
  State<LeaveEditor> createState() => _LeaveEditorState();
}

class _LeaveEditorState extends State<LeaveEditor> {
  final form = GlobalKey<FormState>();
  late TextEditingController reason;
  late DateTime from, to;
  String kind = 'FullDay', half = 'First';
  String? selected;
  List<Json> shifts = [];
  bool busy = false, loading = false;
  Object? error;
  @override
  void initState() {
    super.initState();
    final item = widget.item;
    from =
        DateTime.tryParse(item?['fromDate'] ?? '') ??
        DateTime.now().toUtc().add(const Duration(hours: 7));
    to = DateTime.tryParse(item?['toDate'] ?? '') ?? from;
    kind = item?['kind'] ?? 'FullDay';
    reason = TextEditingController(text: item?['reason'] ?? '');
    if (kind == 'HalfDay') loadShifts();
  }

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  String iso(DateTime d) => d.toIso8601String().substring(0, 10);
  Future<void> loadShifts() async {
    final day = iso(from);
    setState(() {
      loading = true;
      error = null;
      selected = null;
      shifts = [];
    });
    try {
      final data = await widget.session.api.get(
        '/timesheets/${from.year}/${from.month}',
      );
      if (!mounted || iso(from) != day) return;
      final items = data['items'] as List;
      setState(() {
        shifts = items
            .expand((e) => (e['data']['lines'] as List).cast<Json>())
            .where((l) => l['date'] == day)
            .toList();
        if (shifts.length == 1) selected = shifts.single['startUtc'];
        final oldStart = DateTime.tryParse(widget.item?['fromUtc'] ?? '');
        final oldEnd = DateTime.tryParse(widget.item?['toUtc'] ?? '');
        if (oldStart != null && oldEnd != null) {
          for (final shift in shifts) {
            final start = DateTime.parse(shift['startUtc']);
            final end = DateTime.parse(shift['endUtc']);
            if (!oldStart.isBefore(start) && !oldEnd.isAfter(end)) {
              selected = shift['startUtc'];
              half = oldStart.isAtSameMomentAs(start) ? 'First' : 'Second';
              break;
            }
          }
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> pick(bool first) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: first ? from : to,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (first) {
        from = picked;
        if (to.isBefore(from) || kind == 'HalfDay') to = from;
      } else {
        to = picked;
      }
    });
    if (kind == 'HalfDay') await loadShifts();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    if (kind == 'HalfDay' && selected == null) {
      message(context, 'Hãy chọn ca làm.', error: true);
      return;
    }
    if (to.isBefore(from)) {
      message(context, 'Ngày kết thúc phải từ ngày bắt đầu.', error: true);
      return;
    }
    if (!await confirm(
      context,
      'Gửi đơn ${kind == 'HalfDay' ? (half == 'First' ? 'nghỉ nửa đầu ca' : 'nghỉ nửa cuối ca') : 'nghỉ cả ngày'} từ ${dateOnly(iso(from))} đến ${dateOnly(iso(to))}?',
    )) {
      return;
    }
    setState(() => busy = true);
    try {
      final body = <String, dynamic>{
        'fromDate': iso(from),
        'toDate': iso(to),
        'kind': kind,
        'reason': reason.text.trim(),
        'shiftStartUtc': kind == 'HalfDay' ? selected : null,
        'half': kind == 'HalfDay' ? half : null,
      };
      if (widget.item == null) {
        await widget.session.api.post('/leave-requests', body);
      } else {
        await widget.session.api.put(
          '/leave-requests/${widget.item!['id']}',
          body,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.item == null ? 'Đăng ký nghỉ phép' : 'Sửa đơn nghỉ phép',
      ),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const GreenHero(
              eyebrow: 'THỜI GIAN CỦA BẠN',
              title: 'Đăng ký nghỉ phép',
              subtitle: 'Chọn ngày, ca và ghi lý do để quản lý xem xét.',
              icon: Icons.beach_access_outlined,
            ),
            const SizedBox(height: 20),
            FormSection(
              title: 'Chi tiết kỳ nghỉ',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Thời lượng'),
                    items: const [
                      DropdownMenuItem(
                        value: 'FullDay',
                        child: Text('Cả ngày'),
                      ),
                      DropdownMenuItem(
                        value: 'HalfDay',
                        child: Text('Nửa ca làm việc'),
                      ),
                    ],
                    onChanged: busy || loading
                        ? null
                        : (v) {
                            setState(() {
                              kind = v!;
                              if (kind == 'HalfDay') to = from;
                            });
                            if (kind == 'HalfDay') loadShifts();
                          },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Từ ngày'),
                    subtitle: Text(dateOnly(iso(from))),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: busy || loading ? null : () => pick(true),
                  ),
                  if (kind == 'FullDay')
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Đến ngày'),
                      subtitle: Text(dateOnly(iso(to))),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: busy ? null : () => pick(false),
                    ),
                  if (loading) const LinearProgressIndicator(),
                  if (error != null)
                    TextButton(
                      onPressed: loadShifts,
                      child: Text('$error · Tải lại ca'),
                    ),
                  if (kind == 'HalfDay' && !loading) ...[
                    if (shifts.isEmpty)
                      const Text(
                        'Ngày này chưa có lịch. Hãy chọn ngày khác hoặc liên hệ Admin.',
                      ),
                    DropdownButtonFormField<String>(
                      key: ValueKey('$selected|${iso(from)}'),
                      initialValue: selected,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Ca nghỉ'),
                      items: shifts
                          .map(
                            (l) => DropdownMenuItem(
                              value: l['startUtc'] as String,
                              child: Text(
                                '${l['shift']} · ${vietnamTime(l['startUtc'])}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (v) => setState(() => selected = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: half,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Khoảng nghỉ',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'First',
                          child: Text('Nửa đầu ca'),
                        ),
                        DropdownMenuItem(
                          value: 'Second',
                          child: Text('Nửa cuối ca'),
                        ),
                      ],
                      onChanged: busy ? null : (v) => setState(() => half = v!),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Mỗi nửa bằng một nửa thời lượng của ca đã chọn, không mặc định 4 giờ.',
                      ),
                    ),
                  ],
                  TextFormField(
                    controller: reason,
                    decoration: const InputDecoration(labelText: 'Lý do nghỉ'),
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 1000,
                    validator: (v) => (v?.trim().length ?? 0) < 5
                        ? 'Nhập ít nhất 5 ký tự.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  BusyButton(
                    busy: busy,
                    label: 'Gửi đơn nghỉ phép',
                    onPressed: loading ? null : submit,
                    icon: Icons.send_outlined,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
