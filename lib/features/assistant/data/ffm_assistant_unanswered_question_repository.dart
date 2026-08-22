import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import 'ffm_assistant_learning_repository.dart';

/// Item antrean pertanyaan yang perlu diperbaiki lewat Pusat Latihan.
class FfmAssistantUnansweredQuestion {
  const FfmAssistantUnansweredQuestion({
    required this.id,
    required this.questionText,
    required this.pageContext,
    required this.occurrenceCount,
    required this.isResolved,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String questionText;
  final String? pageContext;
  final int occurrenceCount;
  final bool isResolved;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory FfmAssistantUnansweredQuestion.fromRow(
    AssistantUnansweredQuestion row,
  ) => FfmAssistantUnansweredQuestion(
    id: row.id,
    questionText: row.questionText,
    pageContext: row.pageContext,
    occurrenceCount: row.occurrenceCount,
    isResolved: row.isResolved,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  Map<String, dynamic> toLlmJson() => {
    'question': questionText,
    if (pageContext != null) 'pageContext': pageContext,
    'timesAsked': occurrenceCount,
  };
}

/// Penyimpanan lokal untuk pertanyaan fallback. Tidak ada data finansial mentah
/// yang ditulis karena semua teks disanitasi sebelum menjadi antrean.
class FfmAssistantUnansweredQuestionRepository {
  FfmAssistantUnansweredQuestionRepository(this._database);

  static const householdId = 'local-household';
  final AppDatabase _database;

  Future<void> record({
    required String rawQuestion,
    String? pageContext,
  }) async {
    final sanitized = FfmAssistantLearningSanitizer.sanitize(rawQuestion);
    if (sanitized.isEmpty || sanitized.length > 500) return;
    final existingQuery =
        _database.select(_database.assistantUnansweredQuestions)..where(
          (row) =>
              row.householdId.equals(householdId) &
              row.questionText.equals(sanitized) &
              row.isResolved.equals(false),
        );
    final existing = await existingQuery.getSingleOrNull();
    final now = DateTime.now();
    if (existing != null) {
      await (_database.update(
        _database.assistantUnansweredQuestions,
      )..where((row) => row.id.equals(existing.id))).write(
        AssistantUnansweredQuestionsCompanion(
          occurrenceCount: Value(existing.occurrenceCount + 1),
          updatedAt: Value(now),
          pageContext: Value(pageContext ?? existing.pageContext),
        ),
      );
      return;
    }
    await _database
        .into(_database.assistantUnansweredQuestions)
        .insert(
          AssistantUnansweredQuestionsCompanion.insert(
            id: 'assistant-unanswered-${now.microsecondsSinceEpoch}',
            householdId: householdId,
            questionText: sanitized,
            pageContext: Value(pageContext),
            createdAt: now,
            updatedAt: Value(now),
          ),
        );
  }

  Future<List<FfmAssistantUnansweredQuestion>> readOpen() async {
    final query = _database.select(_database.assistantUnansweredQuestions)
      ..where(
        (row) =>
            row.householdId.equals(householdId) & row.isResolved.equals(false),
      )
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]);
    return (await query.get())
        .map(FfmAssistantUnansweredQuestion.fromRow)
        .toList();
  }

  Future<void> markResolved(String id) =>
      (_database.update(
        _database.assistantUnansweredQuestions,
      )..where((row) => row.id.equals(id))).write(
        AssistantUnansweredQuestionsCompanion(
          isResolved: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> deletePermanently(String id) => (_database.delete(
    _database.assistantUnansweredQuestions,
  )..where((row) => row.id.equals(id))).go();

  Future<String> exportForExternalLlm() async {
    final questions = await readOpen();
    return jsonEncode({
      'formatVersion': 'ffm-assistant-unanswered-v1',
      'purpose': 'Pertanyaan tersanitasi yang membutuhkan knowledge baru.',
      'rules': [
        'Jangan membuat data transaksi, saldo, rekening, aset, hutang, atau keluarga.',
        'Kembalikan satu entri knowledge pack JSON dengan kind answer atau flow untuk setiap pertanyaan.',
        'Jangan mengulang knowledge yang sudah ada.',
      ],
      'questions': questions.map((item) => item.toLlmJson()).toList(),
    });
  }
}
