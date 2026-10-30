import 'dart:convert';
import 'dart:typed_data';

typedef Json = Map<String, dynamic>;

class UserProfile {
  final String? displayName, avatarDataUrl;
  String get name =>
      displayName?.trim().isNotEmpty == true ? displayName! : fullName;
  Uint8List? get avatarBytes {
    try {
      return avatarDataUrl == null
          ? null
          : base64Decode(avatarDataUrl!.split(',').last);
    } catch (_) {
      return null;
    }
  }

  final String id, fullName, username, email, role, approvalStatus;
  final String? employeeId;
  final bool emailConfirmed, phoneNumberConfirmed;
  const UserProfile({
    this.displayName,
    this.avatarDataUrl,
    required this.id,
    required this.fullName,
    required this.username,
    required this.email,
    required this.role,
    required this.approvalStatus,
    this.employeeId,
    required this.emailConfirmed,
    required this.phoneNumberConfirmed,
  });
  bool get isAdmin => role == 'Admin';
  factory UserProfile.fromJson(Json j) => UserProfile(
    displayName: j['displayName'],
    avatarDataUrl: j['avatarDataUrl'],
    id: j['id'],
    fullName: j['fullName'],
    username: j['username'],
    email: j['email'],
    role: j['role'],
    approvalStatus: j['approvalStatus'],
    employeeId: j['employeeId'],
    emailConfirmed: j['emailConfirmed'] == true,
    phoneNumberConfirmed: j['phoneNumberConfirmed'] == true,
  );
  Json toJson() => {
    'displayName': displayName,
    'avatarDataUrl': avatarDataUrl,
    'id': id,
    'fullName': fullName,
    'username': username,
    'email': email,
    'role': role,
    'approvalStatus': approvalStatus,
    'employeeId': employeeId,
    'emailConfirmed': emailConfirmed,
    'phoneNumberConfirmed': phoneNumberConfirmed,
  };
}

class Employee {
  final String id,
      code,
      name,
      email,
      phone,
      departmentId,
      departmentName,
      jobTitle,
      hireDate,
      rowVersion;
  final bool active;
  const Employee({
    required this.id,
    required this.code,
    required this.name,
    required this.email,
    required this.phone,
    required this.departmentId,
    required this.departmentName,
    required this.jobTitle,
    required this.hireDate,
    required this.rowVersion,
    required this.active,
  });
  factory Employee.fromJson(Json j) => Employee(
    id: j['id'],
    code: j['employeeCode'],
    name: j['fullName'],
    email: j['email'],
    phone: j['phone'],
    departmentId: j['departmentId'],
    departmentName: j['departmentName'] ?? '',
    jobTitle: j['jobTitle'] ?? '',
    hireDate: j['hireDate'],
    rowVersion: j['rowVersion'],
    active: j['isActive'] == true,
  );
  Json toJson() => {
    'id': id,
    'employeeCode': code,
    'fullName': name,
    'email': email,
    'phone': phone,
    'departmentId': departmentId,
    'departmentName': departmentName,
    'jobTitle': jobTitle,
    'hireDate': hireDate,
    'rowVersion': rowVersion,
    'isActive': active,
  };
}

class Department {
  final String id, code, name, rowVersion;
  const Department({
    required this.id,
    required this.code,
    required this.name,
    required this.rowVersion,
  });
  factory Department.fromJson(Json j) => Department(
    id: j['id'],
    code: j['code'],
    name: j['name'],
    rowVersion: j['rowVersion'],
  );
  Json toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'rowVersion': rowVersion,
  };
}

class PageResult {
  final List<Json> items;
  final int totalCount, page, pageSize;
  const PageResult(this.items, this.totalCount, this.page, this.pageSize);
  factory PageResult.fromJson(Json j) => PageResult(
    (j['items'] as List).map((v) => Map<String, dynamic>.from(v)).toList(),
    j['totalCount'] ?? 0,
    j['page'] ?? 1,
    j['pageSize'] ?? 20,
  );
}

class OtpFlow {
  final String id, token, purpose, maskedEmail, maskedPhone;
  final List<String> channels;
  final bool phoneVerified;
  final String smsProvider;
  const OtpFlow(
    this.id,
    this.token,
    this.purpose,
    this.maskedEmail,
    this.maskedPhone,
    this.channels,
    this.phoneVerified, [
    this.smsProvider = 'Backend',
  ]);
  factory OtpFlow.fromJson(Json j) => OtpFlow(
    j['flowId'],
    j['flowToken'],
    j['purpose'],
    j['maskedEmail'] ?? '',
    j['maskedPhone'] ?? '',
    List<String>.from(j['availableChannels'] ?? ['Email']),
    j['phoneVerified'] == true,
    j['smsProvider'] ?? 'Backend',
  );
  Json toJson() => {'flowId': id, 'flowToken': token};
}
