import '../../widgets/workforce_ui.dart';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../models/models.dart';
import '../../services/attendance_service.dart';
import '../../services/api_service.dart';
import '../../services/device_service.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';
import '../../widgets/editor.dart';
import '../../widgets/location_map.dart';
import '../device/device_screens.dart';

class CheckInScreen extends StatefulWidget {
  final Session session;
  const CheckInScreen(this.session, {super.key});
  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  late Future<PageResult> future;
  List<Json> assignments = [];
  String? selected, qr, key;
  String action = 'CheckIn';
  Position? position;
  bool busy = false;
  Json? result;
  double get targetAccuracy {
    for (final item in assignments) {
      if (item['id'] == selected) {
        return (item['maxAccuracyMeters'] as num?)?.toDouble() ?? 50;
      }
    }
    return 50;
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    future = widget.session.api.page('/attendance/options?action=$action').then(
      (page) {
        if (mounted && selected == null && page.items.length == 1) {
          selected = page.items.single['id'];
        }
        return page;
      },
    );
  }

  void resetIntent() {
    key = null;
    result = null;
  }

  Future<void> gps() async {
    setState(() {
      busy = true;
      position = null;
    });
    try {
      final p = await DeviceService.position(
        targetAccuracyMeters: targetAccuracy,
      );
      if (mounted) {
        setState(() {
          position = p;
          resetIntent();
        });
      }
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (selected == null || busy) return;
    setState(() => busy = true);
    try {
      if (key == null) {
        // Settle GPS first, preserving the short lifetime of the scanned QR.
        position = null;
        result = null;
        position = await DeviceService.position(
          targetAccuracyMeters: targetAccuracy,
        );
        if (!mounted) return;
        final scanned = await Navigator.push<String>(
          context,
          MaterialPageRoute(builder: (_) => const ScannerScreen()),
        );
        if (!mounted || scanned == null) return;
        qr = scanned;
        if (!DeviceService.isFresh(position!)) {
          position = await DeviceService.position(
            targetAccuracyMeters: targetAccuracy,
          );
          if (!mounted) return;
        }
        key = const Uuid().v4();
      }
      final r = await AttendanceService(widget.session.api).submit(
        action: action,
        assignmentId: selected!,
        qrToken: qr!,
        position: position!,
        idempotencyKey: key!,
      );
      if (mounted) {
        setState(() {
          result = r;
          qr = null;
          key = null;
        });
      }
    } catch (e) {
      if (e is ApiException &&
          e.status != null &&
          e.status! < 500 &&
          e.status != 429) {
        key = null;
        qr = null;
      }
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> requestSchedule() async {
    final reason = await askReason(
      context,
      'Yêu cầu bổ sung lịch',
      minimum: 10,
    );
    if (reason == null || !mounted) return;
    try {
      await widget.session.api.post('/attendance-support', {
        'kind': 'MissingSchedule',
        'reason': reason,
      });
      if (mounted) message(context, 'Đã gửi yêu cầu cho Admin.');
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    }
  }

  Future<void> request() async {
    final reason = await askReason(
      context,
      'Giải trình chấm công',
      minimum: 10,
    );
    if (reason == null) return;
    setState(() => busy = true);
    try {
      await widget.session.api.post('/attendance-requests', {
        'attemptId': result!['attemptId'],
        'reason': reason,
      });
      if (mounted) {
        message(
          context,
          'Đã gửi giải trình. Công chỉ được xác nhận sau khi Admin duyệt.',
        );
        setState(() => result!['canCreateRequest'] = false);
      }
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chấm công hôm nay')),
    body: FutureBuilder<PageResult>(
      future: future,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) return ErrorPanel(s.error!, () => setState(load));
        assignments = s.data!.items;
        if (assignments.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Chưa có ca phù hợp hoặc ca đã hoàn tất. Mở Lịch làm việc để kiểm tra, hoặc gửi yêu cầu bổ sung lịch cho Admin.',
                    textAlign: TextAlign.center,
                  ),
                  TextButton(
                    onPressed: () => setState(load),
                    child: const Text('Tải lại'),
                  ),
                  OutlinedButton(
                    onPressed: requestSchedule,
                    child: const Text('Yêu cầu bổ sung lịch'),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      action = action == 'CheckIn' ? 'CheckOut' : 'CheckIn';
                      selected = null;
                      load();
                    }),
                    child: Text(
                      action == 'CheckIn'
                          ? 'Chuyển sang chấm công ra'
                          : 'Chuyển sang chấm công vào',
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const GreenHero(
              eyebrow: 'QR + GPS',
              title: 'Ghi nhận ngày làm',
              subtitle: 'Lấy vị trí mới, quét mã và xác nhận trên máy chủ',
              icon: Icons.qr_code_scanner_rounded,
            ),
            const SizedBox(height: 20),
            FormSection(
              title: 'Ca làm và thao tác',
              icon: Icons.event_available_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selected,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Ca được phân công',
                    ),
                    items: assignments
                        .map(
                          (x) => DropdownMenuItem(
                            value: x['id'] as String,
                            child: Text(
                              '${x['shiftName']} · ${x['locationName'] ?? ''} · ${dateOnly(x['workDate'])}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            selected = v;
                            position = null;
                            qr = null;
                            resetIntent();
                          }),
                  ),
                  const SizedBox(height: 20),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'CheckIn',
                        label: Text('Vào ca'),
                        icon: Icon(Icons.login),
                      ),
                      ButtonSegment(
                        value: 'CheckOut',
                        label: Text('Ra ca'),
                        icon: Icon(Icons.logout),
                      ),
                    ],
                    selected: {action},
                    onSelectionChanged: busy
                        ? null
                        : (v) => setState(() {
                            action = v.first;
                            position = null;
                            selected = null;
                            load();
                            qr = null;
                            resetIntent();
                          }),
                  ),
                ],
              ),
            ),
            if (selected != null)
              Builder(
                builder: (_) {
                  final matches = assignments.where((x) => x['id'] == selected);
                  if (matches.isEmpty) return const SizedBox.shrink();
                  final a = matches.first;
                  return ShiftTimelineCard(
                    title: a['shiftName'],
                    location: a['locationName'] ?? '',
                    date: dateOnly(a['workDate']),
                    start: clockTime(a['startUtc']),
                    end: clockTime(a['endUtc']),
                    status: a['hasCheckOut'] == true
                        ? 'Đã ra ca'
                        : a['hasCheckIn'] == true
                        ? 'Đã vào ca'
                        : 'Chưa vào ca',
                  );
                },
              ),
            if (selected != null &&
                assignments.any(
                  (x) => x['id'] == selected && x['latitude'] != null,
                ))
              Builder(
                builder: (_) {
                  final site = assignments.firstWhere(
                    (x) => x['id'] == selected,
                  );
                  final distance = position == null
                      ? null
                      : Geolocator.distanceBetween(
                          position!.latitude,
                          position!.longitude,
                          (site['latitude'] as num).toDouble(),
                          (site['longitude'] as num).toDouble(),
                        );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LocationMap(
                        latitude: (site['latitude'] as num).toDouble(),
                        longitude: (site['longitude'] as num).toDouble(),
                        radius: (site['radiusMeters'] as num).toDouble(),
                        userLatitude: position?.latitude,
                        userLongitude: position?.longitude,
                        accuracy: position?.accuracy,
                      ),
                      Text(
                        'Bán kính ${site['radiusMeters']} m · GPS yêu cầu ≤ ${site['maxAccuracyMeters']} m',
                      ),
                      if (distance != null)
                        Text(
                          'Ước tính ${distance.toStringAsFixed(1)} m · ${position!.accuracy > targetAccuracy
                              ? 'GPS chưa đạt'
                              : distance > (site['radiusMeters'] as num)
                              ? 'Ngoài vùng'
                              : 'Trong vùng'}\nMẫu GPS: ${vietnamTime(position!.timestamp.toIso8601String())}. Máy chủ kiểm tra lại khi gửi.',
                        ),
                      const SizedBox(height: 12),
                    ],
                  );
                },
              ),
            ItemCard(
              title: position == null ? 'Vị trí chấm công' : 'Đã lấy mẫu GPS',
              subtitle: position == null
                  ? 'Bấm chấm công để lấy GPS ổn định, sau đó quét QR công ty.'
                  : '${position!.latitude.toStringAsFixed(6)}, ${position!.longitude.toStringAsFixed(6)}\nSai số ước tính ${position!.accuracy.toStringAsFixed(1)} m',
              icon: Icons.my_location,
              onTap: busy ? null : gps,
              trailing: IconButton(
                onPressed: busy ? null : gps,
                icon: const Icon(Icons.refresh),
              ),
            ),
            const SizedBox(height: 12),
            BusyButton(
              busy: busy,
              label: key == null
                  ? (action == 'CheckIn' ? 'Chấm công vào' : 'Chấm công ra')
                  : 'Thử gửi lại',
              onPressed: selected != null ? submit : null,
              icon: Icons.check_circle_outline,
            ),
            const SizedBox(height: 16),
            const Text(
              'Quét QR chung tại công ty; giờ theo máy chủ và GPS trong bán kính cho phép. Trường hợp cần kiểm tra thêm có thể gửi giải trình.',
            ),
            if (result != null) ...[
              const SizedBox(height: 24),
              Center(
                child: Icon(
                  result!['status'] == 'Accepted'
                      ? Icons.check_circle_rounded
                      : Icons.location_off_outlined,
                  size: 64,
                  color: result!['status'] == 'Accepted'
                      ? workforceGreen
                      : Theme.of(context).colorScheme.error,
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      StatusPill(result!['status']),
                      const SizedBox(height: 16),
                      Text(
                        result!['status'] == 'Accepted'
                            ? (result!['punctuality'] == 'Late'
                                  ? 'Đã ghi nhận · Đi trễ ${result!['lateMinutes']} phút'
                                  : result!['punctuality'] == 'OnTime'
                                  ? 'Đã ghi nhận · Đúng giờ'
                                  : result!['punctuality'] == 'EarlyLeave'
                                  ? 'Đã ghi nhận · Ra ca sớm'
                                  : 'Đã ghi nhận chấm công ra')
                            : 'Chưa xác nhận công — cần giải trình',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Thời điểm máy chủ nhận: ${vietnamTime(result!['receivedAtUtc'])}\nKhoảng cách: ${(result!['distanceMeters'] as num).toStringAsFixed(1)} m\nĐộ chính xác: ${(result!['accuracyMeters'] as num).toStringAsFixed(1)} m',
                      ),
                      if ((result!['reasonCodes'] as List).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            reasonName(
                              (result!['reasonCodes'] as List).join(', '),
                            ),
                          ),
                        ),
                      if (result!['canCreateRequest'] == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: OutlinedButton(
                            onPressed: busy ? null : request,
                            child: const Text('Gửi giải trình cho Admin'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}
