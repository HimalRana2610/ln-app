import '../../../core/network/api_client.dart';
import 'quiz_models.dart';

/// The only place that knows how quiz endpoints are shaped.
class QuizRepository {
  QuizRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<QuizState> state(String classroomId) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.get<Map<String, dynamic>>('/classrooms/$classroomId/quiz'),
    );
    return QuizState.fromJson(json);
  }

  /// Teachers only. 409 while another question is still live.
  Future<QuizQuestion> ask(
    String classroomId, {
    required String prompt,
    required List<String> options,
    required String correctOption,
  }) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.post<Map<String, dynamic>>(
        '/classrooms/$classroomId/quiz/questions',
        data: {
          'prompt': prompt,
          'options': options,
          'correct_option': correctOption,
        },
      ),
    );
    return QuizQuestion.fromJson(json);
  }

  Future<QuizQuestion> end(String questionId) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.post<Map<String, dynamic>>('/quiz/questions/$questionId/end'),
    );
    return QuizQuestion.fromJson(json);
  }

  /// Students only. 409 if already answered or the question has ended.
  Future<QuizAnswerResult> answer(String questionId, String option) async {
    final json = await _apiClient.request<Map<String, dynamic>>(
      (dio) => dio.post<Map<String, dynamic>>(
        '/quiz/questions/$questionId/answers',
        data: {'option': option},
      ),
    );
    return QuizAnswerResult.fromJson(json);
  }
}
