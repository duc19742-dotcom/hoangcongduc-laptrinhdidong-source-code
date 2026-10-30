import '../../widgets/workforce_ui.dart';

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../models/models.dart';
import '../../services/device_service.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';
import '../../widgets/location_map.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final controller = MobileScannerController();
  bool handled = false;
  @override
  void dispose() {
    unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      title: const Text('Quét mã tại công ty'),
      actions: [
        IconButton(
          onPressed: () => controller.toggleTorch(),
          icon: const Icon(Icons.flashlight_on_outlined),
        ),
      ],
    ),
    body: Stack(
      children: [
        MobileScanner(
          controller: controller,
          onDetect: (capture) async {
            if (handled) return;
            final codes = capture.barcodes.where(
              (b) => b.rawValue != null && b.rawValue!.isNotEmpty,
            );
            if (codes.isEmpty) return;
            handled = true;
            await controller.stop();
            if (context.mounted) Navigator.pop(context, codes.first.rawValue);
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.no_photography_outlined,
                    size: 60,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Chưa mở được camera. Hãy cấp quyền Camera trong cài đặt ứng dụng.',
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: Geolocator.openAppSettings,
                    child: const Text('Mở cài đặt'),
                  ),
                ],
              ),
            ),
          ),
        ),
        const IgnorePointer(child: QrScannerFrame()),
        const Positioned(
          bottom: 40,
          left: 24,
          right: 24,
          child: Text(
            'Đặt mã QR vào khung xanh\nGiữ điện thoại ổn định để nhận mã',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ],
    ),
  );
}

class GpsScreen extends StatefulWidget {
  final Session session;
  const GpsScreen(this.session, {super.key});
  @override
  State<GpsScreen> createState() => _GpsScreenState();
}

class _GpsScreenState extends State<GpsScreen> {
  Position? position;
  Object? error;
  bool busy = false;
  List<Json> locations = [];
  String? selected;
  Json? verdict;
  @override
  void initState() {
    super.initState();
    loadLocations();
  }

  Future<void> loadLocations() async {
    try {
      final data = widget.session.user!.isAdmin
          ? (await widget.session.api.page('/work-locations?pageSize=100'))
                .items
          : await widget.session.api.array('/work-locations/me');
      if (mounted) {
        setState(() {
          locations = data;
          selected = data.isNotEmpty ? data.first['id'] : null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> get() async {
    setState(() {
      busy = true;
      error = null;
      verdict = null;
    });
    try {
      final p = await DeviceService.position();
      Json? v;
      if (selected != null) {
        v = await widget.session.api.post('/work-locations/$selected/verify', {
          'latitude': p.latitude,
          'longitude': p.longitude,
          'accuracyMeters': p.accuracy,
        });
      }
      if (mounted) {
        setState(() {
          position = p;
          verdict = v;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Vị trí GPS')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const GreenHero(
          eyebrow: 'XÁC MINH ĐỊA ĐIỂM',
          title: 'Bạn đang ở đâu?',
          subtitle:
              'Chỉ lấy vị trí khi bạn yêu cầu. Không theo dõi vị trí nền.',
          icon: Icons.my_location_rounded,
        ),
        const SizedBox(height: 20),
        if (locations.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: selected,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Địa điểm làm việc'),
            items: locations
                .map(
                  (x) => DropdownMenuItem(
                    value: x['id'] as String,
                    child: Text(x['name'], overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (v) => setState(() {
                    selected = v;
                    verdict = null;
                  }),
          ),
        const SizedBox(height: 20),
        if (selected != null && locations.any((l) => l['id'] == selected))
          Builder(
            builder: (_) {
              final site = locations.firstWhere((l) => l['id'] == selected);
              return LocationMap(
                latitude: (site['latitude'] as num).toDouble(),
                longitude: (site['longitude'] as num).toDouble(),
                radius: (site['radiusMeters'] as num).toDouble(),
                userLatitude: position?.latitude,
                userLongitude: position?.longitude,
                accuracy: position?.accuracy,
              );
            },
          ),
        const SizedBox(height: 12),
        BusyButton(
          busy: busy,
          label: 'Lấy và chia sẻ vị trí với máy chủ',
          onPressed: get,
          icon: Icons.gps_fixed,
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              error.toString(),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (position != null) ...[
          const SizedBox(height: 24),
          ItemCard(
            title: 'Tọa độ hiện tại',
            subtitle:
                'Vĩ độ: ${position!.latitude.toStringAsFixed(7)}\nKinh độ: ${position!.longitude.toStringAsFixed(7)}\nĐộ chính xác: ${position!.accuracy.toStringAsFixed(1)} m\nLấy mẫu: ${vietnamTime(position!.timestamp.toIso8601String())}',
            icon: Icons.location_on_outlined,
          ),
          if (verdict != null)
            ItemCard(
              title:
                  verdict!['insideRadius'] == true &&
                      verdict!['accuracyAccepted'] == true
                  ? 'GPS đạt quy tắc'
                  : 'GPS chưa đạt quy tắc',
              subtitle:
                  'Khoảng cách do máy chủ tính: ${(verdict!['distanceMeters'] as num).toStringAsFixed(1)} m\nTrong bán kính: ${verdict!['insideRadius'] == true ? 'Có' : 'Không'}\nĐộ chính xác đạt: ${verdict!['accuracyAccepted'] == true ? 'Có' : 'Không'}\nPhiên bản quy tắc: ${verdict!['policyVersion']}',
              icon: Icons.rule_outlined,
            ),
        ],
        const SizedBox(height: 16),
        TextButton(
          onPressed: Geolocator.openLocationSettings,
          child: const Text('Mở cài đặt GPS'),
        ),
        TextButton(
          onPressed: Geolocator.openAppSettings,
          child: const Text('Mở quyền truy cập ứng dụng'),
        ),
      ],
    ),
  );
}

class MotionScreen extends StatefulWidget {
  const MotionScreen({super.key});
  @override
  State<MotionScreen> createState() => _MotionScreenState();
}

class _MotionScreenState extends State<MotionScreen>
    with WidgetsBindingObserver {
  StreamSubscription<AccelerometerEvent>? subscription;
  Timer? timeout;
  AccelerometerEvent? sample;
  String? error;
  final points = <double>[];
  final deltas = <double>[];
  bool moving = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    start();
  }

  void start() {
    subscription?.cancel();
    timeout?.cancel();
    timeout = Timer(const Duration(seconds: 6), () {
      if (mounted && sample == null) {
        setState(
          () => error = 'Chưa nhận được dữ liệu cảm biến. Thiết bị có thể không hỗ trợ hoặc cảm biến đang không khả dụng.',
        );
      }
    });
    subscription =
        accelerometerEventStream(
          samplingPeriod: const Duration(milliseconds: 100),
        ).listen(
          (e) {
            timeout?.cancel();
            if (!mounted) return;
            setState(() {
              error = null;
              if (sample != null) {
                deltas.add(
                  sqrt(
                    pow(e.x - sample!.x, 2) +
                        pow(e.y - sample!.y, 2) +
                        pow(e.z - sample!.z, 2),
                  ),
                );
                if (deltas.length > 8) deltas.removeAt(0);
              }
              sample = e;
              points.add(sqrt(e.x * e.x + e.y * e.y + e.z * e.z));
              if (points.length > 80) points.removeAt(0);
              moving =
                  deltas.isNotEmpty &&
                  deltas.reduce((a, b) => a + b) / deltas.length > 0.6;
            });
          },
          onError: (Object e) {
            if (mounted) {
              setState(
                () => error = 'Thiết bị không cung cấp được dữ liệu gia tốc.',
              );
            }
          },
          cancelOnError: true,
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      start();
    } else {
      subscription?.cancel();
      subscription = null;
      timeout?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    subscription?.cancel();
    timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cảm biến chuyển động')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          moving ? Icons.vibration : Icons.smartphone,
          size: 64,
          color: const Color(0xff155eef),
        ),
        const SizedBox(height: 16),
        Text(
          sample == null
              ? 'Đang đọc cảm biến…'
              : moving
              ? 'Có chuyển động'
              : 'Tương đối đứng yên',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        if (error != null)
          ErrorPanel(
            error!,
            () => setState(() {
              error = null;
              start();
            }),
          ),
        if (sample != null) ...[
          Row(
            children: [
              _axis('X', sample!.x),
              _axis('Y', sample!.y),
              _axis('Z', sample!.z),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Độ lớn gia tốc theo thời gian (m/s²)'),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 180,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: MotionPainter(List<double>.from(points)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Gia tốc bao gồm trọng lực nên khi đứng yên tổng độ lớn thường gần 9,81 m/s². Trạng thái chuyển động là ước lượng từ biến thiên của các mẫu thật, không phải bằng chứng tuyệt đối chống gian lận.',
          ),
        ],
      ],
    ),
  );
  Widget _axis(String name, double value) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        child: Column(
          children: [
            Text(name),
            const SizedBox(height: 8),
            Text(
              value.toStringAsFixed(2),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            const Text('m/s²'),
          ],
        ),
      ),
    ),
  );
}

class MotionPainter extends CustomPainter {
  final List<double> values;
  MotionPainter(this.values);
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xffe2e8f0)
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.length < 2) return;
    final low = min(0.0, values.reduce(min) - 1);
    final high = max(12.0, values.reduce(max) + 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * size.width / (values.length - 1);
      final y = size.height - (values[i] - low) / (high - low) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xff155eef)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant MotionPainter oldDelegate) => true;
}
