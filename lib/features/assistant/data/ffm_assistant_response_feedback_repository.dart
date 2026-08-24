import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import 'ffm_assistant_learning_repository.dart';

enum FfmAssistantResponseFeedbackKind { incorrect, incomplete, unhelpful }

enum FfmAssistantResponseFeedbackReviewStatus { pending, approved, rejected }

class FfmAssistantResponseFeedback {
  const FfmAssistantResponseFeedback({
    required this.id,
    required this.questionText,
    required this.responseText,
    required this.kind,
    required this.reviewStatus,
    required this.isArchived,
    required this.createdAt,
    this.note,
    this.pageContext,
    this.updatedAt,
  });

  final String id;
  final String questionText;
  final String responseText;
  final FfmAssistantResponseFeedbackKind kind;
  final FfmAssistantResponseFeedbackReviewStatus reviewStatus;
  final bool isArchived;
  final DateTime createdAt;
  final String? note;
  final String? pageContext;
  final DateTime? updatedAt;

  factory FfmAssistantResponseFeedback.fromRow(AssistantResponseFeedback row) =>
      FfmAssistantResponseFeedback(
        id: row.id,
        questionText: row.questionText,
        responseText: row.responseText,
        kind: FfmAssistantResponseFeedbackKind.values.firstWhere(
          (item) => item.name == row.feedbackKind,
          orElse: () => FfmAssistantResponseFeedbackKind.unhelpful,
        ),
        reviewStatus: FfmAssistantResponseFeedbackReviewStatus.values
            .firstWhere(
              (item) => item.name == row.reviewStatus,
              orElse: () => FfmAssistantResponseFeedbackReviewStatus.pending,
            ),
        isArchived: row.isArchived,
        createdAt: row.createdAt,
        note: row.note,
        pageContext: row.pageContext,
        updatedAt: row.updatedAt,
      );
}

/// Antrean review feedback jawaban Agent. Tidak ada feedback yang otomatis
/// menjadi knowledge, preference, intent, maupun mutasi data.
class FfmAssistantResponseFeedbackRepository {
  FfmAssistantResponseFeedbackRepository(
    this._database, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const householdId = 'local-household';
  final AppDatabase _database;
  final DateTime Function() _clock;

  Future<FfmAssistantResponseFeedback?> record({
    required String questionText,
    required String responseText,
    required FfmAssistantResponseFeedbackKind kind,
    String? note,
    String? pageContext,
    Iterable<String> protectedTerms = const [],
  }) async {
    final question = FfmAssistantLearningSanitizer.sanitize(
      questionText,
      protectedTerms: protectedTerms,
    );
    final response = FfmAssistantLearningSanitizer.sanitize(
      responseText,
      protectedTerms: protectedTerms,
    );
    final sanitizedNote = note == null
        ? null
        : FfmAssistantLearningSanitizer.sanitize(
            note,
            protectedTerms: protectedTerms,
          );
    if (question.isEmpty ||
        response.isEmpty ||
        question.length > 500 ||
        response.length > 1200) {
      return null;
    }
    final now = _clock();
    final id = 'assistant-feedback-${now.microsecondsSinceEpoch}';
    await _database
        .into(_database.assistantResponseFeedbacks)
        .insert(
          AssistantResponseFeedbacksCompanion.insert(
            id: id,
            householdId: householdId,
            questionText: question,
            responseText: response,
            feedbackKind: kind.name,
            note: Value(sanitizedNote?.isEmpty == true ? null : sanitizedNote),
            pageContext: Value(_bounded(pageContext, 120)),
            createdAt: now,
          ),
        );
    return FfmAssistantResponseFeedback(
      id: id,
      questionText: question,
      responseText: response,
      kind: kind,
      reviewStatus: FfmAssistantResponseFeedbackReviewStatus.pending,
      isArchived: false,
      createdAt: now,
      note: sanitizedNote?.isEmpty == true ? null : sanitizedNote,
      pageContext: _bounded(pageContext, 120),
    );
  }

  Future<List<FfmAssistantResponseFeedback>> readPending() async {
    final rows =
        await (_database.select(_database.assistantResponseFeedbacks)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.reviewStatus.equals(
                      FfmAssistantResponseFeedbackReviewStatus.pending.name,
                    ) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
            .get();
    return rows.map(FfmAssistantResponseFeedback.fromRow).toList();
  }

  Future<void> setReviewStatus(
    String id,
    FfmAssistantResponseFeedbackReviewStatus status,
  ) async {
    await (_database.update(
      _database.assistantResponseFeedbacks,
    )..where((row) => row.id.equals(id))).write(
      AssistantResponseFeedbacksCompanion(
        reviewStatus: Value(status.name),
        updatedAt: Value(_clock()),
      ),
    );
  }

  Future<void> archive(String id) async {
    await (_database.update(
      _database.assistantResponseFeedbacks,
    )..where((row) => row.id.equals(id))).write(
      AssistantResponseFeedbacksCompanion(
        isArchived: const Value(true),
        updatedAt: Value(_clock()),
      ),
    );
  }

  String? _bounded(String? value, int maxLength) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized.length <= maxLength
        ? normalized
        : normalized.substring(0, maxLength);
  }
}
