import '../widgets/workforce_ui.dart';
import 'timesheets_screen.dart';
import 'leave_screen.dart';
import 'admin/dashboard_screen.dart';
import 'admin/schedule_screen.dart';
import 'admin/site_qr_screen.dart';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/session.dart';
import '../widgets/common.dart';
import '../widgets/editor.dart';
import 'admin/catalog_screen.dart';
import 'admin/operations_screens.dart';
import 'attendance/check_in_screen.dart';
import 'attendance/requests_screen.dart';
import 'device/device_screens.dart';
import 'employee/records_screens.dart';

typedef _HomeAction = ({
  String title,
  String detail,
  IconData icon,
  Widget screen,
});

class HomeScreen extends StatefulWidget {
  final Session session;
  const HomeScreen(this.session, {super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selected = 0;
  late Future<Json> summary;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    final day = now.toIso8601String().substring(0, 10);
    summary = widget.session.user!.isAdmin
        ? widget.session.api.get('/dashboard?date=$day')
        : widget.session.api.get('/timesheets/${now.year}/${now.month}');
  }

  Future<void> open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted && widget.session.user != null) setState(load);
  }

  List<_HomeAction> actions() {
    final s = widget.session, u = s.user!;
    return <_HomeAction>[
      if (u.isAdmin)
        (
          title: 'QR theo ca',
          detail: 'Tạo và thu hồi phiên theo ca',
          icon: Icons.qr_code_2,
          screen: QrGeneratorScreen(s),
        ),
      (
        title: u.isAdmin ? 'Duyệt nghỉ phép' : 'Nghỉ phép',
        detail: 'Đơn nghỉ và kết quả xử lý',
        icon: Icons.beach_access_outlined,
        screen: LeaveScreen(s),
      ),
      (
        title: 'Lịch sử chấm công',
        detail: 'Các lượt vào/ra đã ghi nhận',
        icon: Icons.history,
        screen: HistoryScreen(s),
      ),
      if (u.isAdmin)
        (
          title: 'Tổng quan theo ngày',
          detail: 'Lọc ngày, phòng ban và danh sách ca',
          icon: Icons.dashboard_outlined,
          screen: DashboardScreen(s),
        ),
      if (u.isAdmin) ...[
        (
          title: 'Nhân viên',
          detail: 'Hồ sơ, tìm kiếm, trạng thái',
          icon: Icons.groups_outlined,
          screen: CatalogScreen(s, CatalogKind.employees),
        ),
        (
          title: 'Phòng ban',
          detail: 'Tổ chức đội ngũ',
          icon: Icons.apartment,
          screen: CatalogScreen(s, CatalogKind.departments),
        ),
        (
          title: 'Ca làm việc',
          detail: 'Giờ vào, ra và ca qua đêm',
          icon: Icons.schedule,
          screen: CatalogScreen(s, CatalogKind.shifts),
        ),
        (
          title: 'Lịch định kỳ',
          detail: 'Ngày làm và ca theo nhân viên',
          icon: Icons.repeat,
          screen: WorkSchedulesScreen(s),
        ),
        (
          title: 'Phân công',
          detail: 'Lịch làm theo nhân viên',
          icon: Icons.event_available,
          screen: AssignmentScreen(s),
        ),
        (
          title: 'Địa điểm',
          detail: 'Tâm và bán kính GPS',
          icon: Icons.location_on_outlined,
          screen: CatalogScreen(s, CatalogKind.locations),
        ),
        (
          title: 'Tạo QR',
          detail: 'Phiên chấm công ngắn hạn',
          icon: Icons.qr_code,
          screen: SiteQrScreen(s),
        ),
        (
          title: 'Thống kê',
          detail: 'Công đã xác nhận',
          icon: Icons.bar_chart_rounded,
          screen: StatisticsScreen(s),
        ),
        (
          title: 'Hỗ trợ lịch và thiếu công',
          detail: 'Xử lý yêu cầu nhân viên',
          icon: Icons.support_agent,
          screen: AttendanceSupportScreen(s),
        ),
        (
          title: 'Duyệt tài khoản',
          detail: 'Liên kết hồ sơ nhân viên',
          icon: Icons.person_add_alt_1_outlined,
          screen: PendingUsersScreen(s),
        ),
        (
          title: 'Duyệt giải trình',
          detail: 'Bằng chứng và nhật ký',
          icon: Icons.fact_check_outlined,
          screen: RequestsScreen(s),
        ),
        (
          title: 'Nhật ký hệ thống',
          detail: 'Theo dõi thao tác quản trị',
          icon: Icons.manage_history,
          screen: AuditScreen(s),
        ),
      ] else ...[
        (
          title: 'Chấm công',
          detail: 'QR và GPS vào / ra ca',
          icon: Icons.fingerprint,
          screen: CheckInScreen(s),
        ),
        (
          title: 'Lịch làm việc',
          detail: 'Ca đã được phân công',
          icon: Icons.calendar_month_outlined,
          screen: TimesheetsScreen(s, scheduleOnly: true),
        ),
        (
          title: 'Giải trình',
          detail: 'Theo dõi kết quả xử lý',
          icon: Icons.fact_check_outlined,
          screen: RequestsScreen(s),
        ),
        (
          title: 'Hỗ trợ lịch và thiếu công',
          detail: 'Bổ sung lịch hoặc quên ra ca',
          icon: Icons.support_agent,
          screen: AttendanceSupportScreen(s),
        ),
        (
          title: 'Lần cần xác minh',
          detail: 'Xem lượt quét và gửi giải trình',
          icon: Icons.pending_actions,
          screen: AttemptsScreen(s),
        ),
      ],
      (
        title: 'GPS hiện tại',
        detail: 'Tọa độ và độ chính xác',
        icon: Icons.my_location,
        screen: GpsScreen(s),
      ),
      (
        title: 'Chuyển động',
        detail: 'Gia tốc và biểu đồ thật',
        icon: Icons.vibration,
        screen: const MotionScreen(),
      ),
    ];
  }

  Widget actionGrid(List<_HomeAction> entries) => ResponsiveTiles(
    children: entries
        .map(
          (e) => QuickActionTile(
            title: e.title,
            subtitle: e.detail,
            icon: e.icon,
            onTap: () => open(e.screen),
          ),
        )
        .toList(),
  );
  Widget management(String title, String subtitle, List<_HomeAction> entries) =>
      ListView(
        padding: const EdgeInsets.all(20),
        children: [
          GreenHero(
            eyebrow: 'ĐỨC ATTENDANCE / QUẢN TRỊ',
            title: title,
            subtitle: subtitle,
            icon: Icons.workspaces_outline,
          ),
          const SizedBox(height: 20),
          actionGrid(entries),
        ],
      );
  @override
  Widget build(BuildContext context) {
    final s = widget.session, u = s.user!, entries = actions();
    const team = {'Nhân viên', 'Phòng ban', 'Duyệt tài khoản'};
    const shifts = {'Ca làm việc', 'Lịch định kỳ', 'Phân công'};
    const location = {'Địa điểm', 'Tạo QR', 'GPS hiện tại', 'QR theo ca'};
    final labels = u.isAdmin
        ? ['Tổng quan', 'Nhân sự', 'Lịch ca', 'QR/GPS', 'Báo cáo']
        : ['Trang chủ', 'Chấm công', 'Lịch làm', 'Bảng công', 'Cá nhân'];
    final icons = u.isAdmin
        ? [
            Icons.grid_view_rounded,
            Icons.groups_outlined,
            Icons.calendar_month_outlined,
            Icons.qr_code_rounded,
            Icons.bar_chart_rounded,
          ]
        : [
            Icons.space_dashboard_outlined,
            Icons.qr_code_scanner_rounded,
            Icons.calendar_month_outlined,
            Icons.table_chart_outlined,
            Icons.person_outline,
          ];
    Widget content;
    if (u.isAdmin && selected > 0) {
      content = switch (selected) {
        1 => management(
          'Đội ngũ của bạn',
          'Hồ sơ nhân viên và tài khoản chờ duyệt',
          entries.where((e) => team.contains(e.title)).toList(),
        ),
        2 => management(
          'Sắp xếp lịch làm',
          'Ca làm, lịch định kỳ và phân công',
          entries.where((e) => shifts.contains(e.title)).toList(),
        ),
        3 => management(
          'Điểm chấm công',
          'QR ngắn hạn kết hợp vị trí GPS',
          entries.where((e) => location.contains(e.title)).toList(),
        ),
        _ => management(
          'Công và báo cáo',
          'Đối soát, xác nhận và quản lý kỳ công',
          [
            (
              title: 'Bảng công',
              detail: 'Tổng hợp tháng và xuất Excel',
              icon: Icons.table_chart_outlined,
              screen: TimesheetsScreen(s),
            ),
            ...entries.where(
              (e) => {
                'Thống kê',
                'Lịch sử chấm công',
                'Tổng quan theo ngày',
                'Nhật ký hệ thống',
              }.contains(e.title),
            ),
          ],
        ),
      };
    } else if (!u.isAdmin && selected > 0) {
      content = switch (selected) {
        1 => CheckInScreen(s),
        2 => TimesheetsScreen(s, scheduleOnly: true),
        3 => TimesheetsScreen(s),
        _ => ProfileScreen(s),
      };
    } else {
      content = RefreshIndicator(
        onRefresh: () async {
          setState(load);
          await summary;
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xffdcfce7),
                  backgroundImage: u.avatarBytes == null
                      ? null
                      : MemoryImage(u.avatarBytes!),
                  child: u.avatarBytes == null
                      ? const Icon(Icons.person_outline, color: workforceDeep)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        u.isAdmin ? 'Không gian quản trị' : 'Chào ngày mới',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        u.name,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Hồ sơ',
                  onPressed: () => open(
                    Scaffold(
                      appBar: AppBar(title: const Text('Hồ sơ')),
                      body: ProfileScreen(s),
                    ),
                  ),
                  icon: const Icon(Icons.person_outline),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FutureBuilder<Json>(
              future: summary,
              builder: (context, snap) {
                if (snap.hasError) {
                  return ErrorPanel(snap.error!, () => setState(load));
                }
                if (!snap.hasData) return const SkeletonLoading();
                return FadeEntry(
                  child: u.isAdmin
                      ? DashboardPanel(s, snap.data!)
                      : _EmployeeOverview(
                          s,
                          snap.data!,
                          onCheck: () => open(CheckInScreen(s)),
                        ),
                );
              },
            ),
            SectionHeading(
              u.isAdmin ? 'Cần xử lý' : 'Công việc của tôi',
              subtitle: u.isAdmin
                  ? 'Duyệt đơn và xử lý ngoại lệ'
                  : 'Các thao tác thường dùng',
            ),
            actionGrid(
              entries
                  .where(
                    (e) => u.isAdmin
                        ? e.title.startsWith('Duyệt') ||
                              e.title.startsWith('Hỗ trợ')
                        : {
                            'Nghỉ phép',
                            'Lịch sử chấm công',
                            'Giải trình',
                            'Hỗ trợ lịch và thiếu công',
                          }.contains(e.title),
                  )
                  .toList(),
            ),
            if (u.isAdmin) ...[
              const SectionHeading('Quản lý nhanh'),
              actionGrid(
                entries
                    .where(
                      (e) => {
                        'Nhân viên',
                        'Phân công',
                        'Tạo QR',
                        'Thống kê',
                      }.contains(e.title),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 20),
            Card(
              child: ExpansionTile(
                key: const PageStorageKey('home-utilities'),
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Tiện ích'),
                subtitle: const Text('GPS, cảm biến và các thao tác khác'),
                childrenPadding: const EdgeInsets.all(12),
                children: [
                  actionGrid(
                    entries
                        .where(
                          (e) => u.isAdmin
                              ? !{
                                      'Nhân viên',
                                      'Phân công',
                                      'Tạo QR',
                                      'Thống kê',
                                    }.contains(e.title) &&
                                    !e.title.startsWith('Duyệt') &&
                                    !e.title.startsWith('Hỗ trợ')
                              : {
                                  'GPS hiện tại',
                                  'Chuyển động',
                                  'Lần cần xác minh',
                                  'Lịch làm việc',
                                }.contains(e.title),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: !u.isAdmin && selected > 0 && selected < 4
          ? null
          : AppBar(
              title: Text(
                !u.isAdmin && selected == 4 ? 'Hồ sơ' : 'Đức Attendance',
              ),
              actions: [
                if (selected == 0)
                  IconButton(
                    tooltip: 'Làm mới tổng quan',
                    onPressed: () => setState(load),
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
      body: SafeArea(top: false, child: content),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: (i) => setState(() => selected = i),
          destinations: [
            for (var i = 0; i < labels.length; i++)
              NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
          ],
        ),
      ),
    );
  }
}

class _EmployeeOverview extends StatelessWidget {
  final Session session;
  final Json data;
  final VoidCallback onCheck;
  const _EmployeeOverview(this.session, this.data, {required this.onCheck});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.parse(data['serverTimeUtc'])
        .toUtc()
        .add(const Duration(hours: 7));
    final today = now.toIso8601String().substring(0, 10);
    final items = (data['items'] as List).cast<Json>();
    final sheets = items.map((x) => x['data'] as Json).toList();
    final lines = sheets
        .expand((x) => (x['lines'] as List).cast<Json>())
        .toList();
    final todayLines = lines.where((x) => x['date'] == today).toList();
    final upcoming = lines
        .where(
          (x) =>
              DateTime.parse(x['startUtc'])
                  .isAfter(DateTime.parse(data['serverTimeUtc'])),
        )
        .take(3)
        .toList();
    final recent =
        lines
            .where((x) => x['checkInUtc'] != null || x['checkOutUtc'] != null)
            .toList()
          ..sort(
            (a, b) => '${b['checkOutUtc'] ?? b['checkInUtc']}'.compareTo(
              '${a['checkOutUtc'] ?? a['checkInUtc']}',
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GreenHero(
          eyebrow: 'HÔM NAY · ${dateOnly(today)}',
          title: todayLines.isEmpty
              ? 'Sẵn sàng ngày mới'
              : todayLines.first['shift'],
          subtitle: todayLines.isEmpty
              ? 'Chưa có ca được phân công hôm nay.'
              : todayLines.first['location'],
          icon: Icons.schedule_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LiveClock(),
              const SizedBox(height: 4),
              const Text(
                'Giờ điện thoại · Việt Nam',
                style: TextStyle(color: Color(0xffbbf7d0), fontSize: 12),
              ),
              const SizedBox(height: 18),
              if (todayLines.isNotEmpty) ...[
                Text(
                  '${clockTime(todayLines.first['startUtc'])} — ${clockTime(todayLines.first['endUtc'])}  ·  ${workStatus(todayLines.first['status'])}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: workforceDeep,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: onCheck,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Chấm công vào / ra'),
              ),
            ],
          ),
        ),
        for (final line in todayLines)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${line['shift']} · ${workStatus(line['status'])}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _punch(
                            context,
                            'Vào ca',
                            clockTime(line['checkInUtc']),
                            Icons.login,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 36,
                          color: Theme.of(context).dividerColor,
                        ),
                        Expanded(
                          child: _punch(
                            context,
                            'Ra ca',
                            clockTime(line['checkOutUtc']),
                            Icons.logout,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SectionHeading('Tháng này', subtitle: 'Số liệu công đã ghi nhận'),
        ResponsiveTiles(
          children: [
            MetricTile(
              value:
                  '${sheets.fold<num>(0, (n, s) => n + (s['attendedDays'] as num))}',
              label: 'Ngày có chấm vào',
              icon: Icons.event_available_outlined,
            ),
            MetricTile(
              value:
                  '${sheets.fold<num>(0, (n, s) => n + (s['confirmedHours'] as num))}',
              label: 'Giờ làm xác nhận',
              icon: Icons.timelapse,
            ),
            MetricTile(
              value:
                  '${sheets.fold<num>(0, (n, s) => n + (s['lateShifts'] as num))}',
              label: 'Ca đi trễ',
              icon: Icons.schedule,
              color: const Color(0xffd97706),
            ),
            MetricTile(
              value:
                  '${lines.where((x) => DateTime.parse(x['startUtc']).isAfter(DateTime.parse(data['serverTimeUtc']))).length}',
              label: 'Ca sắp tới trong tháng',
              icon: Icons.calendar_month_outlined,
            ),
          ],
        ),
        const SectionHeading('Lịch sắp tới'),
        if (upcoming.isEmpty)
          const EmptyState(
            title: 'Chưa có ca sắp tới',
            message: 'Xem tab Lịch làm để kiểm tra các tháng khác.',
            icon: Icons.event_note_outlined,
          ),
        ...upcoming.map(
          (l) => ShiftTimelineCard(
            title: l['shift'],
            location: l['location'],
            date: dateOnly(l['date']),
            start: clockTime(l['startUtc']),
            end: clockTime(l['endUtc']),
            status: workStatus(l['status']),
          ),
        ),
        const SectionHeading('Hoạt động gần đây'),
        if (recent.isEmpty) const Text('Chưa có lượt chấm công trong tháng.'),
        ...recent
            .take(2)
            .map(
              (l) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xffdcfce7),
                  child: Icon(Icons.check, color: workforceDeep),
                ),
                title: Text(l['shift']),
                subtitle: Text(
                  '${dateOnly(l['date'])} · ${clockTime(l['checkInUtc'])} → ${clockTime(l['checkOutUtc'])}',
                ),
              ),
            ),
        for (final item in items)
          if (item['responseStatus'] == 'Pending' &&
              data['status'] == 'Published')
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TimesheetsScreen(session)),
              ),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Bảng công cần bạn xác nhận'),
            ),
        _ActivityInbox(session, key: ValueKey(data['serverTimeUtc'])),
      ],
    );
  }

  Widget _punch(
    BuildContext context,
    String label,
    String time,
    IconData icon,
  ) => Column(
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 6),
      Text(
        time,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _ActivityInbox extends StatefulWidget {
  final Session session;
  const _ActivityInbox(this.session, {super.key});
  @override
  State<_ActivityInbox> createState() => _ActivityInboxState();
}

class _ActivityInboxState extends State<_ActivityInbox> {
  late Future<List<PageResult>> future;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() => future = Future.wait([
    widget.session.api.page('/attendance-requests?status=Pending&pageSize=3'),
    widget.session.api.page('/leave-requests?status=Pending&pageSize=3'),
  ]);
  @override
  Widget build(BuildContext context) => FutureBuilder<List<PageResult>>(
    future: future,
    builder: (context, s) {
      if (s.hasError) {
        return ItemCard(
          title: 'Chưa tải được yêu cầu đang chờ',
          subtitle: s.error.toString(),
          icon: Icons.cloud_off_outlined,
          onTap: () => setState(load),
        );
      }
      if (!s.hasData) return const LinearProgressIndicator(minHeight: 2);
      final requests = s.data![0], leaves = s.data![1];
      if (requests.totalCount + leaves.totalCount == 0) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading('Yêu cầu đang chờ'),
          for (final row in requests.items)
            ItemCard(
              title: 'Giải trình · Chờ xử lý',
              subtitle: '${dateOnly(row['createdAtUtc'])}\n${row['reason']}',
              icon: Icons.fact_check_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      RequestDetailScreen(widget.session, row['id']),
                ),
              ),
            ),
          for (final row in leaves.items)
            ItemCard(
              title: 'Nghỉ phép · Chờ xử lý',
              subtitle:
                  '${dateOnly(row['fromDate'])} — ${dateOnly(row['toDate'])}\n${row['reason']}',
              icon: Icons.beach_access_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => LeaveScreen(widget.session)),
              ),
            ),
        ],
      );
    },
  );
}

class AttemptsScreen extends StatefulWidget {
  final Session session;
  const AttemptsScreen(this.session, {super.key});
  @override
  State<AttemptsScreen> createState() => _AttemptsScreenState();
}

class _AttemptsScreenState extends State<AttemptsScreen> {
  int revision = 0;
  Future<void> request(Json row) async {
    if (row['outcome'] != 'NeedsReview' || row['hasRequest'] == true) return;
    final reason = await askReason(
      context,
      'Giải trình lần chấm công',
      minimum: 10,
    );
    if (reason == null) return;
    try {
      await widget.session.api.post('/attendance-requests', {
        'attemptId': row['id'],
        'reason': reason,
      });
      if (mounted) {
        message(context, 'Đã gửi yêu cầu xác minh.');
        setState(() => revision++);
      }
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => DataPage(
    key: ValueKey(revision),
    title: 'Các lần chấm công',
    load: (p) =>
        widget.session.api.page('/attendance/attempts?page=$p&pageSize=20'),
    item: (r, reload) => ItemCard(
      title: actionName(r['action']),
      subtitle:
          '${vietnamTime(r['receivedAtUtc'])}\n${reasonName(r['reasonCode'])}${r['hasRequest'] == true ? '\nĐã có yêu cầu giải trình' : ''}',
      trailing: StatusPill(r['outcome']),
      icon: Icons.fact_check_outlined,
      onTap: () => request(r),
    ),
  );
}

class AuditScreen extends StatelessWidget {
  final Session session;
  const AuditScreen(this.session, {super.key});
  @override
  Widget build(BuildContext context) => DataPage(
    title: 'Nhật ký hệ thống',
    load: (p) => session.api.page('/audit-logs?page=$p&pageSize=20'),
    item: (r, reload) => ItemCard(
      title: '${r['entityType']} · ${r['action']}',
      subtitle:
          '${vietnamTime(r['createdAtUtc'])}\nMã đối tượng: ${r['entityId'] ?? '—'}',
      icon: Icons.manage_history,
    ),
  );
}
