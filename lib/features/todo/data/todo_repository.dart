import '../../../core/network/api_client.dart';
import 'todo_models.dart';

/// The only place that knows how the to-do endpoint is shaped.
class ToDoRepository {
  ToDoRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// Every assignment across my classes, in the server's order.
  Future<List<ToDoItem>> list() async {
    final json = await _apiClient.request<List<dynamic>>(
      (dio) => dio.get<List<dynamic>>('/me/todo'),
    );
    return json
        .map((item) => ToDoItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
