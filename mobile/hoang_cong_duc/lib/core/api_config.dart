class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://hoangcongduc-001-site1.itempurl.com',
  );

  static Uri endpoint(String path) {
    final root = Uri.tryParse(baseUrl);
    if (root == null ||
        root.scheme != 'https' ||
        root.host.isEmpty ||
        root.host == 'localhost' ||
        root.host == '127.0.0.1' ||
        root.host.startsWith('192.168.') ||
        root.host.startsWith('10.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(root.host)) {
      throw const FormatException(
        'Ứng dụng chưa được cấu hình máy chủ HTTPS công khai.',
      );
    }
    return Uri.parse('${root.origin}/api/v1$path');
  }
}
