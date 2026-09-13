import 'package:freezed_annotation/freezed_annotation.dart';

part 'quiz_models.freezed.dart';
part 'quiz_models.g.dart';

/// Option letters in the order the four options are sent.
const quizOptionLetters = ['A', 'B', 'C', 'D'];

enum QuestionStatus {
  @JsonValue('active')
  active,
  @JsonValue('ended')
  ended;
}

/// Mirrors the backend's `QuizQuestionRead`.
@freezed
abstract class QuizQuestion with _$QuizQuestion {
  const QuizQuestion._();

  const factory QuizQuestion({
    required String id,
    @JsonKey(name: 'classroom_id') required String classroomId,
    required String prompt,

    /// Always four, in A–D order.
    required List<String> options,
    required QuestionStatus status,
    @JsonKey(name: 'started_at') required DateTime startedAt,
    @JsonKey(name: 'ended_at') DateTime? endedAt,

    /// "A"–"D". The server withholds it from students while the question is
    /// live, so the UI can simply show it whenever it is present.
    @JsonKey(name: 'correct_option') String? correctOption,
    @JsonKey(name: 'answer_count') @Default(0) int answerCount,
    @JsonKey(name: 'my_option') String? myOption,
    @JsonKey(name: 'my_is_correct') bool? myIsCorrect,
  }) = _QuizQuestion;

  factory QuizQuestion.fromJson(Map<String, dynamic> json) =>
      _$QuizQuestionFromJson(json);

  bool get isActive => status == QuestionStatus.active;

  bool get hasAnswered => myOption != null;
}

/// Mirrors the backend's `LeaderboardEntry`. Ranked by the server.
@freezed
abstract class LeaderboardEntry with _$LeaderboardEntry {
  const factory LeaderboardEntry({
    required int rank,
    @JsonKey(name: 'student_id') required String studentId,
    @JsonKey(name: 'student_name') required String studentName,
    required int correct,
    required int answered,
    @JsonKey(name: 'penalty_seconds') required num penaltySeconds,
  }) = _LeaderboardEntry;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      _$LeaderboardEntryFromJson(json);
}

/// Mirrors the backend's `QuizState`: everything the tab shows, in one poll.
@freezed
abstract class QuizState with _$QuizState {
  const factory QuizState({
    QuizQuestion? active,
    @Default(<QuizQuestion>[]) List<QuizQuestion> recent,
    @Default(<LeaderboardEntry>[]) List<LeaderboardEntry> leaderboard,

    /// How often to poll, chosen by the server so it can back off under load.
    @JsonKey(name: 'poll_interval_seconds') @Default(3) int pollIntervalSeconds,
  }) = _QuizState;

  factory QuizState.fromJson(Map<String, dynamic> json) =>
      _$QuizStateFromJson(json);
}

/// Mirrors the backend's answer response.
@freezed
abstract class QuizAnswerResult with _$QuizAnswerResult {
  const factory QuizAnswerResult({
    required String option,
    @JsonKey(name: 'is_correct') required bool isCorrect,
    @JsonKey(name: 'penalty_seconds') required num penaltySeconds,
  }) = _QuizAnswerResult;

  factory QuizAnswerResult.fromJson(Map<String, dynamic> json) =>
      _$QuizAnswerResultFromJson(json);
}
