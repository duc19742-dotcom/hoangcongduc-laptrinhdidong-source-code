import '../../widgets/workforce_ui.dart';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';
import '../../widgets/editor.dart';

enum CatalogKind { employees, departments, shifts, locations }

class CatalogScreen extends StatefulWidget {
  final Session session;
  final CatalogKind kind;
  const CatalogScreen(this.session, this.kind, {super.key});
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  int revision = 0;
  String search = '';
  String? department;
  List<Json> departments = [];
  String get path => switch (widget.kind) {
    CatalogKind.employees => '/employees',
    CatalogKind.departments => '/departments',
    CatalogKind.shifts => '/shifts',
    CatalogKind.locations => '/work-locations',
  };
  String get title => switch (widget.kind) {
    CatalogKind.employees => 'Quản lý nhân viên',
    CatalogKind.departments => 'Phòng ban',
    CatalogKind.shifts => 'Ca làm việc',
    CatalogKind.locations => 'Địa điểm công ty',
  };
  @override
  void initState() {
    super.initState();
    if (widget.kind == CatalogKind.employees) {
      allRows(widget.session.api, '/departments')
          .then((v) {
            if (mounted) setState(() => departments = v);
          })
          .catchError((Object e) {
            if (mounted) message(context, e.toString(), error: true);
          });
    }
  }

  void refresh() => setState(() => revision++);
  Future<void> edit([Json? row]) async {
    try {
      List<EditorField> fields;
      switch (widget.kind) {
        case CatalogKind.departments:
          fields = [
            EditorField('code', 'Mã phòng ban', initial: row?['code']),
            EditorField('name', 'Tên phòng ban', initial: row?['name']),
          ];
        case CatalogKind.shifts:
          fields = [
            EditorField('code', 'Mã ca', initial: row?['code']),
            EditorField('name', 'Tên ca', initial: row?['name']),
            EditorField(
              'startLocalTime',
              'Giờ bắt đầu',
              type: 'time',
              initial: row?['startLocalTime'] ?? '08:00',
            ),
            EditorField(
              'endLocalTime',
              'Giờ kết thúc',
              type: 'time',
              initial: row?['endLocalTime'] ?? '17:00',
            ),
            EditorField(
              'endsNextDay',
              'Kết thúc vào ngày hôm sau',
              type: 'bool',
              initial: row?['endsNextDay'] ?? false,
            ),
            EditorField(
              'lateGraceMinutes',
              'Số phút cho phép trễ',
              type: 'int',
              initial: row?['lateGraceMinutes'] ?? 5,
            ),
            EditorField(
              'isActive',
              'Đang sử dụng',
              type: 'bool',
              initial: row?['isActive'] ?? true,
            ),
          ];
        case CatalogKind.locations:
          fields = [
            EditorField('name', 'Tên địa điểm', initial: row?['name']),
            EditorField(
              'latitude',
              'Vĩ độ',
              type: 'number',
              initial: row?['latitude'],
            ),
            EditorField(
              'longitude',
              'Kinh độ',
              type: 'number',
              initial: row?['longitude'],
            ),
            EditorField(
              'radiusMeters',
              'Bán kính chấm công (m)',
              type: 'number',
              initial: row?['radiusMeters'] ?? 150,
            ),
            EditorField(
              'maxAccuracyMeters',
              'Độ chính xác GPS tối đa (m)',
              type: 'number',
              initial: row?['maxAccuracyMeters'] ?? 50,
            ),
            EditorField(
              'isActive',
              'Đang sử dụng',
              type: 'bool',
              initial: row?['isActive'] ?? true,
            ),
          ];
        case CatalogKind.employees:
          final ds = await allRows(widget.session.api, '/departments');
          if (!mounted) return;
          if (ds.isEmpty) {
            message(
              context,
              'Hãy tạo phòng ban trước khi thêm nhân viên.',
              error: true,
            );
            return;
          }
          final linked = row?['userId'] != null;
          fields = [
            EditorField(
              'employeeCode',
              'Mã nhân viên',
              initial: row?['employeeCode'],
            ),
            EditorField('fullName', 'Họ và tên', initial: row?['fullName']),
            EditorField(
              'email',
              'Email',
              type: 'email',
              initial: row?['email'],
              readOnly: linked,
            ),
            EditorField(
              'phone',
              'Số điện thoại',
              type: 'phone',
              initial: row?['phone'],
              readOnly: linked,
            ),
            EditorField(
              'departmentId',
              'Phòng ban',
              type: 'select',
              initial: row?['departmentId'],
              options: {
                for (final x in ds) x['id'] as String: x['name'] as String,
              },
            ),
            EditorField(
              'jobTitle',
              'Chức vụ',
              initial: row?['jobTitle'] ?? '',
              required: false,
            ),
            EditorField(
              'hireDate',
              'Ngày vào làm',
              type: 'date',
              initial:
                  row?['hireDate'] ??
                  DateTime.now().toIso8601String().substring(0, 10),
            ),
            EditorField(
              'isActive',
              'Đang hoạt động',
              type: 'bool',
              initial: row?['isActive'] ?? true,
            ),
          ];
      }
      if (!mounted) return;
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => EditorScreen(
            title: row == null ? 'Thêm mới' : 'Cập nhật',
            fields: fields,
            fillGps: widget.kind == CatalogKind.locations,
            save: (body) async {
              if (row != null) body['rowVersion'] = row['rowVersion'];
              if (row == null) {
                await widget.session.api.post(path, body);
              } else {
                await widget.session.api.put('$path/${row['id']}', body);
              }
            },
          ),
        ),
      );
      if (saved == true && mounted) refresh();
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    }
  }

  Future<void> remove(Json row) async {
    if (!await confirm(
      context,
      'Xóa bản ghi này? Dữ liệu có lịch sử hoặc đang được sử dụng sẽ được máy chủ bảo vệ.',
    )) {
      return;
    }
    try {
      await widget.session.api.delete('$path/${row['id']}');
      if (mounted) {
        message(context, 'Đã xóa dữ liệu.');
        refresh();
      }
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    }
  }

  Future<void> status(Json row) async {
    final reason = await askReason(
      context,
      row['isActive'] == true
          ? 'Ngừng hoạt động nhân viên'
          : 'Kích hoạt nhân viên',
    );
    if (reason == null) return;
    try {
      await widget.session.api.request(
        'PATCH',
        '/employees/${row['id']}/status',
        body: {'isActive': row['isActive'] != true, 'reason': reason},
      );
      if (mounted) refresh();
    } catch (e) {
      if (mounted) message(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => DataPage(
    key: ValueKey('$revision|$search|$department'),
    title: title,
    load: (page) {
      final query = Uri(
        queryParameters: {
          'page': '$page',
          'pageSize': '20',
          if (search.isNotEmpty) 'search': search,
          'departmentId': ?department,
        },
      ).query;
      return widget.session.api.page('$path?$query');
    },
    floatingActionButton: FloatingActionButton.extended(
      onPressed: edit,
      icon: const Icon(Icons.add),
      label: const Text('Thêm mới'),
    ),
    header: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GreenHero(
          eyebrow: 'QUẢN LÝ / DANH MỤC',
          title: title,
          subtitle: switch (widget.kind) {
            CatalogKind.employees => 'Hồ sơ và trạng thái của đội ngũ',
            CatalogKind.departments => 'Cấu trúc phòng ban trong công ty',
            CatalogKind.shifts => 'Giờ vào, ra và quy tắc ca làm',
            CatalogKind.locations => 'Tâm địa điểm và bán kính GPS',
          },
          icon: widget.kind == CatalogKind.employees
              ? Icons.groups_outlined
              : Icons.workspaces_outline,
        ),
        if (widget.kind == CatalogKind.employees)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Tìm họ tên hoặc mã nhân viên',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (s) => setState(() => search = s.trim()),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: department,
                  decoration: const InputDecoration(labelText: 'Phòng ban'),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Tất cả phòng ban'),
                    ),
                    ...departments.map(
                      (x) => DropdownMenuItem(
                        value: x['id'] as String,
                        child: Text(x['name'], overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => department = v),
                ),
              ],
            ),
          ),
      ],
    ),
    item: (row, reload) {
      final name = (row['fullName'] ?? row['name']).toString();
      final subtitle = switch (widget.kind) {
        CatalogKind.employees =>
          '${row['employeeCode']} · ${row['departmentName']}\n${row['email']}\n${row['isActive'] == true ? 'Đang hoạt động' : 'Ngừng hoạt động'}',
        CatalogKind.departments => 'Mã: ${row['code']}',
        CatalogKind.shifts =>
          '${row['code']} · ${row['startLocalTime']} – ${row['endLocalTime']}${row['endsNextDay'] == true ? ' (+1 ngày)' : ''}',
        CatalogKind.locations =>
          'Bán kính ${row['radiusMeters']} m · GPS ≤ ${row['maxAccuracyMeters']} m\nQuy tắc v${row['policyVersion']}',
      };
      return ItemCard(
        title: name,
        subtitle: subtitle,
        icon: widget.kind == CatalogKind.employees
            ? Icons.person_outline
            : widget.kind == CatalogKind.locations
            ? Icons.location_on_outlined
            : Icons.business_outlined,
        onTap: () => edit(row),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') {
              edit(row);
            } else if (v == 'status') {
              status(row);
            } else {
              remove(row);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Cập nhật')),
            if (widget.kind == CatalogKind.employees)
              const PopupMenuItem(
                value: 'status',
                child: Text('Đổi trạng thái'),
              ),
            const PopupMenuItem(value: 'delete', child: Text('Xóa hợp lệ')),
          ],
        ),
      );
    },
  );
}
