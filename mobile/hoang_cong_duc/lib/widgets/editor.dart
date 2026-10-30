import 'workforce_ui.dart';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/device_service.dart';
import 'common.dart';
import 'location_map.dart';

class EditorField {
  final String keyName, label, type;
  final dynamic initial;
  final Map<String, String>? options;
  final bool required, readOnly;
  const EditorField(
    this.keyName,
    this.label, {
    this.type = 'text',
    this.initial,
    this.options,
    this.required = true,
    this.readOnly = false,
  });
}

class EditorScreen extends StatefulWidget {
  final String title;
  final List<EditorField> fields;
  final Future<void> Function(Json) save;
  final bool fillGps;
  final Widget? header;
  final String submitLabel;
  const EditorScreen({
    super.key,
    required this.title,
    required this.fields,
    required this.save,
    this.fillGps = false,
    this.header,
    this.submitLabel = 'Lưu thay đổi',
  });
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final form = GlobalKey<FormState>();
  final controls = <String, TextEditingController>{};
  final values = <String, dynamic>{};
  bool busy = false;
  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      if (f.type == 'bool') {
        values[f.keyName] = f.initial ?? true;
      } else if (f.type == 'select') {
        values[f.keyName] = f.initial;
      } else {
        controls[f.keyName] = TextEditingController(
          text: f.initial?.toString() ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in controls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    if (widget.fillGps &&
        !await confirm(
          context,
          'Lưu tâm địa điểm ${controls['latitude']?.text}, ${controls['longitude']?.text}, bán kính ${controls['radiusMeters']?.text} m? Hãy kiểm tra bản đồ xem trước.',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      final body = <String, dynamic>{...values};
      for (final f in widget.fields) {
        if (!controls.containsKey(f.keyName)) continue;
        final text = controls[f.keyName]!.text.trim();
        body[f.keyName] = switch (f.type) {
          'number' => double.parse(text),
          'int' => int.parse(text),
          'time' => text.length == 5 ? '$text:00' : text,
          _ => text,
        };
      }
      await widget.save(body);
      if (mounted) {
        message(context, 'Đã lưu dữ liệu.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> gps() async {
    setState(() => busy = true);
    try {
      final target =
          double.tryParse(controls['maxAccuracyMeters']?.text ?? '') ?? 50;
      final p = await DeviceService.position(
        targetAccuracyMeters: target,
        requireAccuracy: true,
      );
      if (!mounted) return;
      controls['latitude']?.text = p.latitude.toStringAsFixed(7);
      controls['longitude']?.text = p.longitude.toStringAsFixed(7);
      message(
        context,
        'Đã lấy vị trí hiện tại, độ chính xác ${p.accuracy.toStringAsFixed(1)} m.',
      );
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pick(EditorField f) async {
    if (f.type == 'date') {
      final d = await showDatePicker(
        context: context,
        initialDate:
            DateTime.tryParse(controls[f.keyName]!.text) ?? DateTime.now(),
        firstDate: DateTime(1990),
        lastDate: DateTime(2100),
      );
      if (d != null) {
        controls[f.keyName]!.text =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }
    } else {
      final parts = controls[f.keyName]!.text.split(':');
      final time = await showTimePicker(
        context: context,
        initialTime: parts.length >= 2
            ? TimeOfDay(
                hour: int.tryParse(parts[0]) ?? 8,
                minute: int.tryParse(parts[1]) ?? 0,
              )
            : const TimeOfDay(hour: 8, minute: 0),
      );
      if (time != null) {
        controls[f.keyName]!.text =
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GreenHero(
                  eyebrow: 'THÔNG TIN / CẬP NHẬT',
                  title: 'Thông tin cập nhật',
                  subtitle: 'Kiểm tra thông tin trước khi lưu',
                  icon: Icons.edit_note_rounded,
                ),
                const SizedBox(height: 20),
                FormSection(
                  title: 'Thông tin chi tiết',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.header != null) ...[
                        widget.header!,
                        const SizedBox(height: 16),
                      ],
                      if (widget.fillGps)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: OutlinedButton.icon(
                            onPressed: busy ? null : gps,
                            icon: const Icon(Icons.my_location),
                            label: const Text(
                              'Dùng vị trí hiện tại làm địa điểm công ty',
                            ),
                          ),
                        ),
                      if (widget.fillGps) ...[
                        LocationMap(
                          latitude:
                              double.tryParse(
                                controls['latitude']?.text ?? '',
                              ) ??
                              double.nan,
                          longitude:
                              double.tryParse(
                                controls['longitude']?.text ?? '',
                              ) ??
                              double.nan,
                          radius:
                              double.tryParse(
                                controls['radiusMeters']?.text ?? '',
                              ) ??
                              0,
                        ),
                        const SizedBox(height: 16),
                      ],
                      ...widget.fields.map((f) {
                        if (f.type == 'bool') {
                          return SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(f.label),
                            value: values[f.keyName] as bool,
                            onChanged: busy || f.readOnly
                                ? null
                                : (v) => setState(() => values[f.keyName] = v),
                          );
                        }
                        if (f.type == 'select') {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: DropdownButtonFormField<String>(
                              initialValue: values[f.keyName],
                              isExpanded: true,
                              decoration: InputDecoration(labelText: f.label),
                              items: (f.options ?? {}).entries
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(
                                        e.value,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: busy || f.readOnly
                                  ? null
                                  : (v) =>
                                        setState(() => values[f.keyName] = v),
                              validator: (v) =>
                                  f.required && (v == null || v.isEmpty)
                                  ? 'Vui lòng chọn ${f.label}'
                                  : null,
                            ),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: TextFormField(
                            onChanged: widget.fillGps
                                ? (_) => setState(() {})
                                : null,
                            controller: controls[f.keyName],
                            obscureText: f.type == 'password',
                            autocorrect: f.type != 'password',
                            enableSuggestions: f.type != 'password',
                            readOnly:
                                f.readOnly ||
                                f.type == 'date' ||
                                f.type == 'time',
                            onTap: f.type == 'date' || f.type == 'time'
                                ? () => pick(f)
                                : null,
                            minLines: f.type == 'multiline' ? 3 : 1,
                            maxLines: f.type == 'multiline' ? 5 : 1,
                            keyboardType: switch (f.type) {
                              'number' => const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              'int' => TextInputType.number,
                              'email' => TextInputType.emailAddress,
                              'phone' => TextInputType.phone,
                              _ => TextInputType.text,
                            },
                            decoration: InputDecoration(
                              labelText: f.label,
                              suffixIcon: f.type == 'date'
                                  ? const Icon(Icons.calendar_month_outlined)
                                  : f.type == 'time'
                                  ? const Icon(Icons.schedule)
                                  : null,
                            ),
                            validator: (v) {
                              final text = v?.trim() ?? '';
                              if (f.required && text.isEmpty) {
                                return 'Vui lòng nhập ${f.label}';
                              }
                              if (f.type == 'email' &&
                                  !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                      .hasMatch(text)) {
                                return 'Email chưa hợp lệ.';
                              }
                              if ((f.type == 'number' || f.type == 'int') &&
                                  (double.tryParse(text) == null ||
                                      !double.parse(text).isFinite)) {
                                return 'Cần nhập số hợp lệ.';
                              }
                              if (f.type == 'int' &&
                                  int.tryParse(text) == null) {
                                return 'Cần nhập số nguyên.';
                              }
                              return null;
                            },
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
                      BusyButton(
                        busy: busy,
                        label: widget.submitLabel,
                        onPressed: submit,
                        icon: Icons.save_outlined,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<List<Json>> allRows(ApiService api, String path) async {
  final result = <Json>[];
  var page = 1;
  while (true) {
    final data = await api.page(
      '$path${path.contains('?') ? '&' : '?'}page=$page&pageSize=100',
    );
    result.addAll(data.items);
    if (result.length >= data.totalCount || data.items.isEmpty) break;
    page++;
  }
  return result;
}

Future<String?> askReason(
  BuildContext context,
  String title, {
  int minimum = 5,
}) async {
  final text = TextEditingController();
  final form = GlobalKey<FormState>();
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Form(
        key: form,
        child: TextFormField(
          controller: text,
          maxLength: 1000,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Lý do'),
          validator: (v) => (v?.trim().length ?? 0) < minimum
              ? 'Nhập ít nhất $minimum ký tự.'
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Quay lại'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(c, text.text.trim());
            }
          },
          child: const Text('Xác nhận'),
        ),
      ],
    ),
  );
  // The controller belongs to the dialog route and is released after its closing animation.
  Future<void>.delayed(const Duration(milliseconds: 350), text.dispose);
  return result;
}
