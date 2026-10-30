import 'workforce_ui.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';

String vietnamTime(dynamic value) {
  if (value == null) return '—';
  final date = DateTime.tryParse(value.toString());
  if (date == null) return value.toString();
  return DateFormat('dd/MM/yyyy HH:mm')
      .format(date.toUtc().add(const Duration(hours: 7)));
}

String dateOnly(dynamic value) {
  if (value == null) return '—';
  final date = DateTime.tryParse(value.toString());
  return date == null
      ? value.toString()
      : DateFormat('dd/MM/yyyy').format(date);
}

String actionName(dynamic value) =>
    value == 'CheckOut' ? 'Chấm công ra' : 'Chấm công vào';
String stateName(dynamic value) => switch (value) {
  'Pending' => 'Chờ xử lý',
  'Approved' => 'Đã duyệt',
  'Rejected' => 'Từ chối',
  'Cancelled' => 'Đã hủy',
  'Accepted' => 'Đã xác nhận',
  'NeedsReview' => 'Cần xác minh',
  _ => value?.toString() ?? '—',
};
String reasonName(String value) => value
    .replaceAll('OutsideGeofence', 'Ngoài bán kính công ty')
    .replaceAll('LowGpsAccuracy', 'Độ chính xác GPS chưa đạt');
void message(BuildContext context, String text, {bool error = false}) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: SingleChildScrollView(child: Text(text)),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
Future<bool> confirm(BuildContext context, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xác nhận'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    ) ??
    false;

class BusyButton extends StatelessWidget {
  final bool busy;
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  const BusyButton({
    super.key,
    required this.busy,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward_rounded,
  });
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: busy ? null : onPressed,
    icon: busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon),
    label: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(label),
    ),
  );
}

class ErrorPanel extends StatelessWidget {
  final Object error;
  final VoidCallback retry;
  const ErrorPanel(this.error, this.retry, {super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: workforceGreen),
          const SizedBox(height: 16),
          Text(error.toString(), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    ),
  );
}

class StatusPill extends StatelessWidget {
  final String value;
  const StatusPill(this.value, {super.key});
  @override
  Widget build(BuildContext context) {
    final good = ['Approved', 'Accepted'].contains(value);
    final bad = ['Rejected', 'Cancelled'].contains(value);
    final color = good
        ? Colors.teal
        : bad
        ? Colors.red
        : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        stateName(value),
        style: TextStyle(
          color: Theme.of(context).brightness == Brightness.dark
              ? color.shade200
              : color.shade800,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class DataPage extends StatefulWidget {
  final String title;
  final Future<PageResult> Function(int page) load;
  final Widget Function(Json row, VoidCallback reload) item;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? header;
  final String? calendarDateKey;
  const DataPage({
    super.key,
    required this.title,
    required this.load,
    required this.item,
    this.actions,
    this.floatingActionButton,
    this.header,
    this.calendarDateKey,
  });
  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  int page = 1;
  late Future<PageResult> future;
  bool calendar = false;
  int? selectedDay;
  DateTime? calendarMonth;
  @override
  void initState() {
    super.initState();
    future = widget.load(page);
  }

  void reload() {
    setState(() => future = widget.load(page));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(onPressed: reload, icon: const Icon(Icons.refresh)),
        ...?widget.actions,
      ],
    ),
    floatingActionButton: widget.floatingActionButton,
    body: Column(
      children: [
        Expanded(
          child: FutureBuilder<PageResult>(
            future: future,
            builder: (context, s) {
              if (s.connectionState != ConnectionState.done) {
                return const SkeletonLoading();
              }
              if (s.hasError) return ErrorPanel(s.error!, reload);
              final data = s.data!;
              final dates =
                  widget.calendarDateKey == null
                        ? <DateTime>[]
                        : data.items
                              .map(
                                (r) => DateTime.tryParse(
                                  '${r[widget.calendarDateKey]}',
                                ),
                              )
                              .whereType<DateTime>()
                              .toList()
                    ..sort();
              final month =
                  calendarMonth ??
                  (dates.isEmpty ? DateTime.now() : dates.first);
              final visibleItems = calendar && selectedDay != null
                  ? data.items
                        .where(
                          (r) => DateUtils.isSameDay(
                            DateTime.tryParse('${r[widget.calendarDateKey]}'),
                            DateTime(month.year, month.month, selectedDay!),
                          ),
                        )
                        .toList()
                  : data.items;
              return Column(
                children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        reload();
                        await future;
                      },
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          if (widget.calendarDateKey != null) ...[
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(
                                  value: false,
                                  icon: Icon(Icons.view_agenda_outlined),
                                  label: Text('Danh sách'),
                                ),
                                ButtonSegment(
                                  value: true,
                                  icon: Icon(Icons.calendar_month_outlined),
                                  label: Text('Lịch'),
                                ),
                              ],
                              selected: {calendar},
                              onSelectionChanged: (v) => setState(() {
                                calendar = v.first;
                                selectedDay = null;
                              }),
                            ),
                            if (calendar) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Tháng trước',
                                    onPressed: () => setState(() {
                                      calendarMonth = DateTime(
                                        month.year,
                                        month.month - 1,
                                      );
                                      selectedDay = null;
                                    }),
                                    icon: const Icon(Icons.chevron_left),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Trang hiện tại · ${month.month}/${month.year}',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Tháng sau',
                                    onPressed: () => setState(() {
                                      calendarMonth = DateTime(
                                        month.year,
                                        month.month + 1,
                                      );
                                      selectedDay = null;
                                    }),
                                    icon: const Icon(Icons.chevron_right),
                                  ),
                                ],
                              ),
                              CalendarStrip(
                                month: month,
                                selected: selectedDay,
                                marked: dates
                                    .where(
                                      (d) =>
                                          d.year == month.year &&
                                          d.month == month.month,
                                    )
                                    .map((d) => d.day)
                                    .toSet(),
                                onChanged: (day) =>
                                    setState(() => selectedDay = day),
                              ),
                            ],
                          ],
                          if (widget.header != null) ...[
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: widget.header!,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${data.totalCount} mục',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge,
                                  ),
                                ),
                                const Icon(
                                  Icons.view_agenda_outlined,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                          ...visibleItems.isEmpty
                              ? [const EmptyState()]
                              : visibleItems
                                    .map((x) => widget.item(x, reload))
                                    .map((child) => FadeEntry(child: child))
                                    .toList(),
                        ],
                      ),
                    ),
                  ),
                  if (data.totalCount > data.pageSize)
                    SafeArea(
                      top: false,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: page > 1
                                ? () {
                                    page--;
                                    reload();
                                  }
                                : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Text('Trang $page · ${data.totalCount} mục'),
                          IconButton(
                            onPressed: page * data.pageSize < data.totalCount
                                ? () {
                                    page++;
                                    reload();
                                  }
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class ItemCard extends StatelessWidget {
  final String title, subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final IconData icon;
  const ItemCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.icon = Icons.description_outlined,
  });
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    size: 23,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                if (trailing != null)
                  Flexible(
                    child: Align(
                      alignment: Alignment.topRight,
                      widthFactor: 1,
                      child: trailing!,
                    ),
                  )
                else if (onTap != null)
                  const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 14),
              ...subtitle
                  .split('\n')
                  .where((line) => line.trim().isNotEmpty)
                  .map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        line,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    ),
  );
}
