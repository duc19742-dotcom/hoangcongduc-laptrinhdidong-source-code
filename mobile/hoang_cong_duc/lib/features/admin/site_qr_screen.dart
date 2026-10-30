import '../../widgets/workforce_ui.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/models.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';
import '../../widgets/editor.dart';

class SiteQrScreen extends StatefulWidget {
  final Session session;
  const SiteQrScreen(this.session, {super.key});
  @override
  State<SiteQrScreen> createState() => _SiteQrScreenState();
}

class _SiteQrScreenState extends State<SiteQrScreen> {
  late Future<List<Json>> locations;
  String? selected, token, error, displayToken;
  DateTime nextTry = DateTime.now();
  Timer? timer;
  DateTime? deadline;
  bool busy = false;
  int refreshSeconds = 0;
  @override
  void initState() {
    super.initState();
    locations = allRows(widget.session.api, '/work-locations');
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (deadline != null &&
          DateTime.now().isAfter(
            deadline!.subtract(const Duration(seconds: 15)),
          ) &&
          !busy &&
          DateTime.now().isAfter(nextTry)) {
        refresh();
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (selected == null || busy) return;
    setState(() => busy = true);
    try {
      if (displayToken == null) {
        final d = await widget.session.api.post('/qr-sessions/display', {
          'workLocationId': selected,
        });
        displayToken = d['displayToken'];
      }
      final r = await widget.session.api.post('/qr-sessions/display/refresh', {
        'displayToken': displayToken,
      });
      if (mounted) {
        setState(() {
          token = r['qrToken'];
          deadline = DateTime.now().add(
            DateTime.parse(r['expiresAtUtc'])
                .difference(DateTime.parse(r['serverTimeUtc'])),
          );
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      nextTry = DateTime.now().add(const Duration(seconds: 5));
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seconds = deadline == null
        ? 0
        : deadline!.difference(DateTime.now()).inSeconds;
    return Scaffold(
      appBar: AppBar(title: const Text('QR chung tại công ty')),
      body: FutureBuilder<List<Json>>(
        future: locations,
        builder: (context, s) {
          if (s.hasError) {
            return ErrorPanel(
              s.error!,
              () => setState(
                () =>
                    locations = allRows(widget.session.api, '/work-locations'),
              ),
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const GreenHero(
                eyebrow: 'ĐIỂM CHẤM CÔNG',
                title: 'Một mã, cả đội ngũ',
                subtitle:
                    'QR chung cho nhân viên vào và ra ca tại đúng địa điểm',
                icon: Icons.qr_code_rounded,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'Địa điểm'),
                items: s.data!
                    .where((x) => x['isActive'] == true)
                    .map(
                      (x) => DropdownMenuItem<String>(
                        value: x['id'],
                        child: Text(x['name']),
                      ),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (v) {
                        setState(() {
                          selected = v;
                          displayToken = null;
                          token = null;
                          deadline = null;
                        });
                        refresh();
                      },
              ),
              const SizedBox(height: 24),
              const Text(
                'Dùng chung cho mọi nhân viên và lượt vào/ra. Mã tự đổi mỗi 45 giây, hiệu lực 60 giây.',
              ),
              if (token != null && seconds > 0) ...[
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        const Text(
                          'QUÉT ĐỂ CHẤM CÔNG',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: QrImageView(
                            data: token!,
                            size:
                                MediaQuery.sizeOf(context).width
                                    .clamp(180, 340) -
                                84,
                            backgroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Chip(
                          avatar: const Icon(Icons.timer_outlined, size: 18),
                          label: Text('Còn $seconds giây'),
                        ),
                        LinearProgressIndicator(
                          value: (seconds / 60).clamp(0, 1),
                          minHeight: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (seconds <= 0 && token != null)
                const Text('QR đã hết hạn. Đang chờ mã mới.'),
              const SizedBox(height: 20),
              BusyButton(
                busy: busy,
                label: 'Lấy mã mới',
                onPressed: selected == null ? null : refresh,
              ),
            ],
          );
        },
      ),
    );
  }
}
