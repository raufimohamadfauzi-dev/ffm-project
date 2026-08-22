import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/ffm_assistant_models.dart';

/// Satu contoh belajar yang telah disetujui pengguna dan sudah disanitasi.
/// Contoh ini tidak pernah menjadi transaksi atau perintah untuk menyimpan data.
class FfmAssistantLearningExample {
  const FfmAssistantLearningExample({
    required this.id,
    required this.householdId,
    required this.inputText,
    required this.intentLabel,
    required this.source,
    required this.schemaVersion,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String householdId;
  final String inputText;
  final String intentLabel;
  final String source;
  final int schemaVersion;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory FfmAssistantLearningExample.fromRow(AssistantLearningExample row) {
    return FfmAssistantLearningExample(
      id: row.id,
      householdId: row.householdId,
      inputText: row.inputText,
      intentLabel: row.intentLabel,
      source: row.source,
      schemaVersion: row.schemaVersion,
      isArchived: row.isArchived,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  Map<String, dynamic> toDatasetJson() => {
    'input': inputText,
    'intent': intentLabel,
    'source': source,
    'schemaVersion': schemaVersion,
  };
}

/// Sanitasi defensif untuk contoh belajar. Nominal dan penanda yang mungkin
/// pribadi diganti token sebelum dapat masuk SQLite atau dataset ekspor.
abstract final class FfmAssistantLearningSanitizer {
  static String sanitize(
    String rawText, {
    Iterable<String> protectedTerms = const [],
  }) {
    var result = rawText.trim();
    final terms =
        protectedTerms
            .map((term) => term.trim())
            .where((term) => term.length >= 3)
            .toSet()
            .toList()
          ..sort((left, right) => right.length.compareTo(left.length));
    for (final term in terms) {
      result = result.replaceAll(
        RegExp(RegExp.escape(term), caseSensitive: false),
        '<ENTITAS>',
      );
    }
    result = result.replaceAll(
      RegExp(r'\b[\w.+-]+@[\w-]+\.[\w.-]+\b'),
      '<EMAIL>',
    );
    result = result.replaceAll(
      RegExp(r'\b(?:\+?62|0)8\d{7,12}\b'),
      '<TELEPON>',
    );
    result = result.replaceAll(RegExp(r'\b\d{10,18}\b'), '<NOMOR_SENSITIF>');
    result = result.replaceAll(
      RegExp(
        r'(?<![A-Za-z])(?:rp\.?\s*)?\d{1,3}(?:[.,]\d{3})+(?![A-Za-z])|\b\d+(?:\s*(?:ribu|rb|k|juta|jt))?\b',
        caseSensitive: false,
      ),
      '<NOMINAL>',
    );
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    return result;
  }
}

/// Penyimpanan contoh belajar lokal yang hanya boleh diisi setelah persetujuan.
class FfmAssistantLearningRepository {
  FfmAssistantLearningRepository(this._database);

  static const householdId = 'local-household';
  final AppDatabase _database;

  Future<List<FfmAssistantLearningExample>> readAll({
    bool activeOnly = false,
  }) async {
    final query = _database.select(_database.assistantLearningExamples)
      ..where((row) => row.householdId.equals(householdId));
    if (activeOnly) query.where((row) => row.isArchived.equals(false));
    query.orderBy([(row) => OrderingTerm.desc(row.updatedAt)]);
    return (await query.get())
        .map(FfmAssistantLearningExample.fromRow)
        .toList();
  }

  Future<FfmAssistantLearningExample?> saveApproved({
    required String rawText,
    required FfmAssistantIntentType intent,
    Iterable<String> protectedTerms = const [],
    String source = 'user_approved',
  }) async {
    final sanitized = FfmAssistantLearningSanitizer.sanitize(
      rawText,
      protectedTerms: protectedTerms,
    );
    if (sanitized.isEmpty || sanitized.length > 500) return null;
    final now = DateTime.now();
    final id = 'assistant-learning-${now.microsecondsSinceEpoch}';
    await _database
        .into(_database.assistantLearningExamples)
        .insert(
          AssistantLearningExamplesCompanion.insert(
            id: id,
            householdId: householdId,
            inputText: sanitized,
            intentLabel: intent.name,
            source: Value(source),
            createdAt: now,
            updatedAt: Value(now),
          ),
        );
    return FfmAssistantLearningExample(
      id: id,
      householdId: householdId,
      inputText: sanitized,
      intentLabel: intent.name,
      source: source,
      schemaVersion: 1,
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> archive(String id) async {
    await (_database.update(
      _database.assistantLearningExamples,
    )..where((row) => row.id.equals(id))).write(
      AssistantLearningExamplesCompanion(
        isArchived: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deletePermanently(String id) async {
    await (_database.delete(
      _database.assistantLearningExamples,
    )..where((row) => row.id.equals(id))).go();
  }

  Future<String> exportDatasetJson() async {
    final examples = await readAll(activeOnly: true);
    return jsonEncode({
      'formatVersion': 'ffm-assistant-intent-dataset-v1',
      'exportedAt': DateTime.now().toIso8601String(),
      'purpose':
          'Contoh teranonimkan untuk evaluasi atau pelatihan intent FFM.',
      'examples': examples.map((example) => example.toDatasetJson()).toList(),
    });
  }
}
