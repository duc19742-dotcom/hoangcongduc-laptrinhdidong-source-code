import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import '../models/models.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  final String? code;
  const ApiException(this.message, {this.status, this.code});
  @override
  String toString() => message;
}

class ApiService {
  final String? Function() token;
  final void Function() onUnauthorized;
  final http.Client client;
  ApiService(this.token, this.onUnauthorized, {http.Client? client})
    : client = client ?? http.Client();
  Future<dynamic> request(
    String method,
    String path, {
    Json? body,
    String? idempotencyKey,
    bool binary = false,
  }) async {
    try {
      final headers = <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };
      final auth = token();
      if (auth != null) headers['Authorization'] = 'Bearer $auth';
      if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
      final req = http.Request(method, ApiConfig.endpoint(path))
        ..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      final streamed = await client
          .send(req)
          .timeout(const Duration(seconds: 25));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 25));
      if (binary && response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
      dynamic data;
      if (response.bodyBytes.isNotEmpty) {
        try {
          data = jsonDecode(utf8.decode(response.bodyBytes));
        } catch (_) {
          data = null;
        }
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return data ?? <String, dynamic>{};
      }
      if (response.statusCode == 401) onUnauthorized();
      String? detail = data is Map ? data['detail'] as String? : null;
      if (data is Map && data['errors'] is Map) {
        detail = (data['errors'] as Map).values
            .expand((v) => v is List ? v : [v])
            .join('\n');
      }
      throw ApiException(
        detail ??
            switch (response.statusCode) {
              400 => 'Dữ liệu chưa hợp lệ.',
              401 => 'Thông tin đăng nhập không đúng hoặc phiên đã hết hạn.',
              403 => 'Bạn chưa được duyệt hoặc không có quyền thực hiện.',
              404 => 'Không tìm thấy dữ liệu hoặc máy chủ chưa sẵn sàng.',
              409 => 'Dữ liệu trùng hoặc vừa được thay đổi. Hãy tải lại.',
              410 => 'Mã hoặc phiên xác minh đã hết hạn.',
              429 => 'Bạn thao tác quá nhanh. Hãy chờ rồi thử lại.',
              _ => 'Máy chủ gặp lỗi. Hãy thử lại sau.',
            },
        status: response.statusCode,
        code: data is Map ? data['code'] as String? : null,
      );
    } on TimeoutException {
      throw const ApiException(
        'Kết nối quá thời gian chờ. Hãy kiểm tra Internet và thử lại.',
      );
    } on SocketException {
      throw const ApiException('Không kết nối được Internet hoặc máy chủ.');
    } on http.ClientException {
      throw const ApiException('Không thể kết nối an toàn tới máy chủ.');
    } on FormatException {
      throw const ApiException('Ứng dụng chưa được cấu hình kết nối đúng.');
    }
  }

  Future<Json> get(String path) async =>
      Map<String, dynamic>.from(await request('GET', path));
  Future<Uint8List> download(String path) async =>
      await request('GET', path, binary: true) as Uint8List;
  Future<List<Json>> array(String path) async =>
      (await request('GET', path) as List)
          .map((x) => Map<String, dynamic>.from(x))
          .toList();
  Future<PageResult> page(String path) async =>
      PageResult.fromJson(await get(path));
  Future<Json> post(String path, Json body, {String? idempotencyKey}) async =>
      Map<String, dynamic>.from(
        await request('POST', path, body: body, idempotencyKey: idempotencyKey),
      );
  Future<Json> put(String path, Json body) async =>
      Map<String, dynamic>.from(await request('PUT', path, body: body));
  Future<void> delete(String path) async {
    await request('DELETE', path);
  }
}
