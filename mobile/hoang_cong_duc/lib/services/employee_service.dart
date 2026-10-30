import '../models/models.dart';
import 'api_service.dart';

class EmployeeService {
  final ApiService api;
  EmployeeService(this.api);
  Future<List<Employee>> list({
    String search = '',
    String? departmentId,
  }) async {
    final query = Uri(
      queryParameters: {
        'pageSize': '100',
        if (search.isNotEmpty) 'search': search,
        'departmentId': ?departmentId,
      },
    ).query;
    return (await api.page('/employees?$query')).items
        .map(Employee.fromJson)
        .toList();
  }

  Future<Employee> mine() async =>
      Employee.fromJson(await api.get('/employees/me'));
  Future<Json> save(Json body, {String? id}) => id == null
      ? api.post('/employees', body)
      : api.put('/employees/$id', body);
}
