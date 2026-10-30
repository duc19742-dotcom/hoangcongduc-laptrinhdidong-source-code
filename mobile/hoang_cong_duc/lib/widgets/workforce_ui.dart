import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const workforceGreen = Color(0xff16a34a);
const workforceDeep = Color(0xff14532d);

String clockTime(dynamic value) {
  final time = DateTime.tryParse(value?.toString() ?? '');
  return time == null
      ? '—'
      : DateFormat('HH:mm').format(time.toUtc().add(const Duration(hours: 7)));
}

class SectionHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  const SectionHeading(this.title, {super.key, this.subtitle, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (subtitle != null)
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        ?action,
      ],
    ),
  );
}

class GreenHero extends StatelessWidget {
  final String eyebrow, title, subtitle;
  final IconData icon;
  final Widget? child, trailing;
  const GreenHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.icon = Icons.eco_outlined,
    this.child,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [workforceDeep, Color(0xff168348)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(28),
    ),
    child: Stack(
      children: [
        Positioned(
          right: -38,
          top: -45,
          child: Icon(
            Icons.spa_outlined,
            size: 210,
            color: Colors.white.withValues(alpha: .06),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: const Color(0xff86efac), size: 19),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      eyebrow,
                      style: const TextStyle(
                        color: Color(0xffbbf7d0),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xffdcfce7), height: 1.5),
                ),
              ],
              if (child != null) ...[const SizedBox(height: 20), child!],
            ],
          ),
        ),
      ],
    ),
  );
}

class MetricTile extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;
  const MetricTile({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    this.color,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 20, color: tint),
                  ),
                  const Spacer(),
                  if (onTap != null)
                    Icon(
                      Icons.north_east,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class ResponsiveTiles extends StatelessWidget {
  final List<Widget> children;
  final int columns;
  const ResponsiveTiles({super.key, required this.children, this.columns = 2});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final count = box.maxWidth >= 640 ? columns + 1 : columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: children
            .map(
              (child) => SizedBox(
                width: (box.maxWidth - 12 * (count - 1)) / count,
                child: child,
              ),
            )
            .toList(),
      );
    },
  );
}

class QuickActionTile extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  const QuickActionTile({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle = '',
  });
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    ),
  );
}

class FormSection extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Widget child;
  const FormSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle = '',
    this.icon = Icons.edit_note_rounded,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 18),
          child,
        ],
      ),
    ),
  );
}

class FadeEntry extends StatelessWidget {
  final Widget child;
  const FadeEntry({super.key, required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240),
    tween: Tween(begin: 0, end: 1),
    child: child,
    builder: (_, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, (1 - value) * 8),
        child: child,
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  final String title, message;
  final IconData icon;
  const EmptyState({
    super.key,
    this.title = 'Chưa có dữ liệu',
    this.message = 'Dữ liệu sẽ xuất hiện tại đây khi có hoạt động mới.',
    this.icon = Icons.inbox_outlined,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .07),
          ),
          child: Icon(
            icon,
            size: 38,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class SkeletonLoading extends StatelessWidget {
  const SkeletonLoading({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 18),
        for (var i = 0; i < 3; i++)
          Container(
            height: 82,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest
                  .withValues(alpha: .6),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
      ],
    ),
  );
}

class LiveClock extends StatefulWidget {
  const LiveClock({super.key});
  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    DateFormat('HH:mm')
        .format(DateTime.now().toUtc().add(const Duration(hours: 7))),
    style: const TextStyle(
      color: Colors.white,
      fontSize: 44,
      height: 1.1,
      fontWeight: FontWeight.w700,
      letterSpacing: -1,
    ),
  );
}

class CalendarStrip extends StatelessWidget {
  final DateTime month;
  final int? selected;
  final Set<int> marked;
  final ValueChanged<int?> onChanged;
  const CalendarStrip({
    super.key,
    required this.month,
    required this.selected,
    required this.marked,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _day(context, 'Cả\ntháng', selected == null, () => onChanged(null)),
        for (
          var d = 1;
          d <= DateUtils.getDaysInMonth(month.year, month.month);
          d++
        )
          _day(
            context,
            '${['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'][DateTime(month.year, month.month, d).weekday - 1]}\n$d',
            selected == d,
            () => onChanged(d),
            dot: marked.contains(d),
          ),
      ],
    ),
  );
  Widget _day(
    BuildContext context,
    String label,
    bool active,
    VoidCallback tap, {
    bool dot = false,
  }) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Material(
      color: active
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: tap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  height: 1.6,
                  fontWeight: FontWeight.w700,
                  color: active
                      ? Theme.of(context).colorScheme.onPrimary
                      : null,
                ),
              ),
              const SizedBox(height: 5),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dot
                      ? (active ? Colors.white : workforceGreen)
                      : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ShiftTimelineCard extends StatelessWidget {
  final String title, location, date, start, end, status;
  final VoidCallback? onTap;
  final bool warning;
  const ShiftTimelineCard({
    super.key,
    required this.title,
    required this.location,
    required this.date,
    required this.start,
    required this.end,
    required this.status,
    this.onTap,
    this.warning = false,
  });
  @override
  Widget build(BuildContext context) => Card(
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
                  width: 4,
                  height: 44,
                  decoration: BoxDecoration(
                    color: warning ? const Color(0xffd97706) : workforceGreen,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(date, style: Theme.of(context).textTheme.bodySmall),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                if (onTap != null) const Icon(Icons.chevron_right, size: 20),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  '$start  →  $end',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(location),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              status,
              style: TextStyle(
                color: warning
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class DataBars extends StatelessWidget {
  final List<({String label, double value})> values;
  const DataBars(this.values, {super.key});
  @override
  Widget build(BuildContext context) {
    final max = values.fold<double>(1, (m, x) => x.value > m ? x.value : m);
    return Column(
      children: values
          .map(
            (v) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(v.label)),
                      Text(
                        v.value.toStringAsFixed(
                          v.value == v.value.roundToDouble() ? 0 : 1,
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (v.value / max).clamp(0, 1),
                      minHeight: 8,
                      color: workforceGreen,
                      backgroundColor: workforceGreen.withValues(alpha: .08),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class QrScannerFrame extends StatefulWidget {
  const QrScannerFrame({super.key});
  @override
  State<QrScannerFrame> createState() => _QrScannerFrameState();
}

class _QrScannerFrameState extends State<QrScannerFrame>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.stop();
    } else {
      controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, box) {
      final size = (box.maxWidth - 64).clamp(180.0, 280.0);
      return Center(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xff86efac),
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: controller,
                builder: (_, _) => Positioned(
                  left: 18,
                  right: 18,
                  top: 20 + controller.value * (size - 44),
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: const Color(0xff22c55e),
                      boxShadow: [
                        BoxShadow(
                          color: workforceGreen.withValues(alpha: .6),
                          blurRadius: 14,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
