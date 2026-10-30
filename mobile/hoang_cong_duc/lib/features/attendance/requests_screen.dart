import '../../widgets/workforce_ui.dart';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';
import '../../widgets/editor.dart';

class RequestsScreen extends StatefulWidget {
  final Session session;
  final String? initialStatus, departmentId;
  const RequestsScreen(
    this.session, {
    super.key,
    this.initialStatus,
    this.departmentId,
  });
  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  String? status;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    status = widget.initialStatus;
  }

  @override
  Widget build(BuildContext context) => DataPage(
    key: ValueKey('$revision-$status'),
    title: widget.session.user!.isAdmin
        ? 'Duyệt giải trình'
        : 'Giải trình của tôi',
    load: (p) => widget.session.api.page(
      '/attendance-requests?page=$p&pageSize=20${status == null ? '' : '&status=$status'}${widget.departmentId == null ? '' : '&departmentId=${widget.departmentId}'}',
    ),
    header: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [null, 'Pending', 'Approved', 'Rejected', 'Cancelled']
            .map(
              (s) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(s == null ? 'Tất cả' : stateName(s)),
                  selected: status == s,
                  onSelected: (_) => setState(() => status = s),
                ),
              ),
            )
            .toList(),
      ),
    ),
    item: (row, reload) => ItemCard(
      title: row['employeeName'],
      subtitle:
          '${actionName(row['action'])} · ${vietnamTime(row['receivedAtUtc'])}\n${row['reason']}',
      trailing: StatusPill(row['status']),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RequestDetailScreen(widget.session, row['id']),
          ),
        );
        if (mounted) setState(() => revision++);
      },
    ),
  );
}

class RequestDetailScreen extends StatefulWidget {
  final Session session;
  final String id;
  const RequestDetailScreen(this.session, this.id, {super.key});
  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  late Future<Json> future;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    future = widget.session.api.get('/attendance-requests/${widget.id}');
  }

  Future<void> decide(Json row, String action) async {
    final reason = await askReason(
      context,
      action == 'approve'
          ? 'Phê duyệt giải trình'
          : action == 'reject'
          ? 'Từ chối giải trình'
          : 'Hủy giải trình',
    );
    if (reason == null) return;
    setState(() => busy = true);
    try {
      await widget.session.api.post(
        '/attendance-requests/${widget.id}/$action',
        {'reason': reason, 'rowVersion': row['rowVersion']},
      );
      if (mounted) {
        message(context, 'Đã cập nhật kết quả.');
        setState(reload);
      }
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(Json row) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          title: 'Sửa nội dung giải trình',
          fields: [
            EditorField(
              'reason',
              'Lý do',
              type: 'multiline',
              initial: row['reason'],
            ),
          ],
          save: (body) async {
            body['rowVersion'] = row['rowVersion'];
            await widget.session.api.put(
              '/attendance-requests/${widget.id}',
              body,
            );
          },
        ),
      ),
    );
    if (mounted) setState(reload);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Hồ sơ giải trình')),
    body: FutureBuilder<Json>(
      future: future,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) return ErrorPanel(s.error!, () => setState(reload));
        final r = s.data!;
        final e = Map<String, dynamic>.from(r['evidence']);
        final policy = Map<String, dynamic>.from(e['policy']);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            GreenHero(
              eyebrow: 'HỒ SƠ GIẢI TRÌNH',
              title: r['employeeName'],
              subtitle: stateName(r['status']),
              icon: Icons.fact_check_outlined,
            ),
            const SizedBox(height: 20),
            StatusPill(r['status']),
            const SizedBox(height: 16),
            Text(
              r['employeeName'],
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(r['reason']),
            const SizedBox(height: 20),
            ItemCard(
              title: 'Bằng chứng lúc gửi',
              subtitle:
                  'Máy chủ nhận: ${vietnamTime(e['receivedAtUtc'])}\nKhoảng cách: ${(e['distanceMeters'] as num).toStringAsFixed(1)} m\nGPS: ${(e['accuracyMeters'] as num).toStringAsFixed(1)} m\n${reasonName((e['reasonCodes'] as List).join(', '))}',
              icon: Icons.fact_check_outlined,
            ),
            ItemCard(
              title: 'Quy tắc tại thời điểm gửi',
              subtitle:
                  '${policy['locationName']}\nTâm địa điểm: ${policy['latitude']}, ${policy['longitude']}\nBán kính: ${policy['radiusMeters']} m\nGPS cho phép: ${policy['maxAccuracyMeters']} m\nPhiên bản: ${policy['policyVersion']}',
              icon: Icons.rule_outlined,
            ),
            if (e['position'] != null)
              ItemCard(
                title: 'Vị trí nhân viên đã gửi',
                subtitle:
                    'Vĩ độ: ${e['position']['latitude']}\nKinh độ: ${e['position']['longitude']}\nĐộ chính xác: ${e['position']['accuracyMeters']} m',
                icon: Icons.my_location,
              ),
            if (r['decisionReason'] != null)
              ItemCard(
                title: 'Kết quả xử lý',
                subtitle:
                    '${r['decisionReason']}\n${vietnamTime(r['reviewedAtUtc'])}',
                icon: Icons.task_alt,
              ),
            if (e['attendanceRecord'] != null)
              ItemCard(
                title: 'Công đã được xác nhận',
                subtitle:
                    'Giờ công: ${vietnamTime(e['attendanceRecord']['effectiveAtUtc'])}\nGiờ ghi nhận: ${vietnamTime(e['attendanceRecord']['recordedAtUtc'])}\nNguồn: ${e['attendanceRecord']['source'] == 'AdminApproved' ? 'Admin duyệt' : 'Tự động'}',
                icon: Icons.verified_outlined,
              ),
            if (r['status'] == 'Pending') ...[
              const SizedBox(height: 12),
              if (widget.session.user!.isAdmin) ...[
                BusyButton(
                  busy: busy,
                  label: 'Phê duyệt',
                  onPressed: () => decide(r, 'approve'),
                  icon: Icons.check,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: busy ? null : () => decide(r, 'reject'),
                  child: const Text('Từ chối'),
                ),
              ] else ...[
                OutlinedButton(
                  onPressed: busy ? null : () => edit(r),
                  child: const Text('Sửa lý do'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => decide(r, 'cancel'),
                  child: const Text('Hủy yêu cầu'),
                ),
              ],
            ],
            const SizedBox(height: 24),
            Text(
              'Lịch sử xử lý',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ...(r['events'] as List).map(
              (v) => ItemCard(
                title: stateName(v['newStatus']),
                subtitle:
                    '${v['actorName']} · ${vietnamTime(v['occurredAtUtc'])}\n${v['note']}',
                icon: Icons.history,
              ),
            ),
          ],
        );
      },
    ),
  );
}
