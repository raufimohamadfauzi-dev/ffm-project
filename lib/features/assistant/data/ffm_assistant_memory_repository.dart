import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import 'ffm_assistant_fuzzy_matcher.dart';

/// Satu ajaran eksplisit yang telah disetujui pemilik perangkat.
///
/// Riwayat chat tidak dipindahkan ke sini. Hanya pengetahuan yang sengaja
/// diajarkan pengguna yang boleh disimpan dan diikutkan ke backup.
class FfmAssistantMemoryRecord {
  const FfmAssistantMemoryRecord({
    required this.id,
    required this.householdId,
    required this.kind,
    required this.triggerText,
    required this.valueText,
    required this.metadata,
    required this.source,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String householdId;
  final String kind;
  final String triggerText;
  final String valueText;
  final Map<String, dynamic> metadata;
  final String source;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory FfmAssistantMemoryRecord.fromRow(AssistantMemory row) {
    Map<String, dynamic> metadata = const {};
    try {
      final decoded = jsonDecode(row.metadataJson);
      if (decoded is Map<String, dynamic>) metadata = decoded;
      if (decoded is Map) {
        metadata = decoded.map((key, value) => MapEntry('$key', value));
      }
    } catch (_) {
      metadata = const {};
    }
    return FfmAssistantMemoryRecord(
      id: row.id,
      householdId: row.householdId,
      kind: row.kind,
      triggerText: row.triggerText,
      valueText: row.valueText,
      metadata: metadata,
      source: row.source,
      isArchived: row.isArchived,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'householdId': householdId,
    'kind': kind,
    'triggerText': triggerText,
    'valueText': valueText,
    'metadata': metadata,
    'source': source,
    'isArchived': isArchived,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };
}

/// Penyimpanan ajaran Asisten yang lokal, dapat ditinjau, dan dapat diarsipkan.
class FfmAssistantMemoryRepository {
  FfmAssistantMemoryRepository(this._db);

  static const householdId = 'local-household';
  final AppDatabase _db;

  Future<List<FfmAssistantMemoryRecord>> readActive({String? kind}) async {
    final query = _db.select(_db.assistantMemories)
      ..where((row) => row.householdId.equals(householdId))
      ..where((row) => row.isArchived.equals(false));
    if (kind != null) query.where((row) => row.kind.equals(kind));
    query.orderBy([
      (row) => OrderingTerm.asc(row.kind),
      (row) => OrderingTerm.asc(row.triggerText),
    ]);
    return (await query.get()).map(FfmAssistantMemoryRecord.fromRow).toList();
  }

  Future<List<FfmAssistantMemoryRecord>> readAll() async {
    final query = _db.select(_db.assistantMemories)
      ..where((row) => row.householdId.equals(householdId))
      ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]);
    return (await query.get()).map(FfmAssistantMemoryRecord.fromRow).toList();
  }

  Future<FfmAssistantMemoryRecord> save({
    String? id,
    required String kind,
    required String triggerText,
    required String valueText,
    Map<String, dynamic> metadata = const {},
    String source = 'user',
  }) async {
    final safeKind = kind.trim().toLowerCase();
    final safeTrigger = triggerText.trim();
    final safeValue = valueText.trim();
    if (safeKind.isEmpty || safeTrigger.isEmpty || safeValue.isEmpty) {
      throw ArgumentError('Jenis, pemicu, dan isi ajaran wajib diisi.');
    }
    final now = DateTime.now();
    final memoryId = id ?? 'assistant-memory-${now.microsecondsSinceEpoch}';
    await _db
        .into(_db.assistantMemories)
        .insertOnConflictUpdate(
          AssistantMemoriesCompanion.insert(
            id: memoryId,
            householdId: householdId,
            kind: safeKind,
            triggerText: safeTrigger,
            valueText: safeValue,
            metadataJson: Value(jsonEncode(metadata)),
            source: Value(source),
            isArchived: const Value(false),
            createdAt: now,
            updatedAt: Value(now),
          ),
        );
    return FfmAssistantMemoryRecord(
      id: memoryId,
      householdId: householdId,
      kind: safeKind,
      triggerText: safeTrigger,
      valueText: safeValue,
      metadata: metadata,
      source: source,
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> archive(String id) async {
    await (_db.update(
      _db.assistantMemories,
    )..where((row) => row.id.equals(id))).write(
      AssistantMemoriesCompanion(
        isArchived: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> update({
    required FfmAssistantMemoryRecord memory,
    required String kind,
    required String triggerText,
    required String valueText,
  }) async {
    final safeKind = kind.trim().toLowerCase();
    final safeTrigger = triggerText.trim();
    final safeValue = valueText.trim();
    if (safeKind.isEmpty || safeTrigger.isEmpty || safeValue.isEmpty) {
      throw ArgumentError('Jenis, pemicu, dan isi ajaran wajib diisi.');
    }
    await (_db.update(
      _db.assistantMemories,
    )..where((row) => row.id.equals(memory.id))).write(
      AssistantMemoriesCompanion(
        kind: Value(safeKind),
        triggerText: Value(safeTrigger),
        valueText: Value(safeValue),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<String> applyAliases(String input) async {
    var resolved = input;
    final aliases = await readActive(kind: 'alias');
    final ordered = aliases.toList()
      ..sort(
        (left, right) =>
            right.triggerText.length.compareTo(left.triggerText.length),
      );
    for (final alias in ordered) {
      resolved = resolved.replaceAll(
        alias.triggerText.toLowerCase(),
        alias.valueText.toLowerCase(),
      );
    }
    return resolved;
  }

  /// Menemukan jawaban ajaran yang dekat dengan pertanyaan pengguna. Ini tidak
  /// menerapkan alias atau mengubah perintah; hasilnya hanya dipakai sebagai
  /// jawaban pengetahuan bila kandidatnya cukup unik.
  Future<FfmAssistantMemoryRecord?> findFuzzyAnswer(String input) async {
    final answers = await readActive(kind: 'answer');
    return FfmAssistantFuzzyMatcher.bestUnique(
      input,
      answers,
      textOf: (record) => record.triggerText,
      minimumScore: .82,
      minimumLead: .08,
    )?.value;
  }
}
