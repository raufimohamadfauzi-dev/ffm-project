import 'ffm_assistant_memory_repository.dart';

class FfmAssistantUserModelEntry {
  const FfmAssistantUserModelEntry({
    required this.id,
    required this.kind,
    required this.key,
    required this.value,
    required this.confidence,
    required this.approved,
    required this.updatedAt,
  });

  final String id;
  final String kind;
  final String key;
  final String value;
  final double confidence;
  final bool approved;
  final DateTime? updatedAt;
}

/// Memori identitas dan kebiasaan user yang tetap berada di perangkat.
/// Service ini memakai tabel assistant_memories yang sudah dimigrasikan sehingga
/// data model user dapat ikut dalam backup FFM tanpa tabel kedua yang tumpang tindih.
class FfmAssistantUserModelService {
  const FfmAssistantUserModelService(this._memories);

  final FfmAssistantMemoryRepository _memories;

  Future<FfmAssistantUserModelEntry> saveApproved({
    required String kind,
    required String key,
    required String value,
    double confidence = 1,
    String source = 'user-approved',
  }) async {
    final record = await _memories.save(
      kind: 'user_$kind',
      triggerText: key,
      valueText: value,
      source: source,
      metadata: {
        'scope': 'user-model',
        'confidence': confidence.clamp(0, 1),
        'approved': true,
      },
    );
    return _entry(record);
  }

  Future<List<FfmAssistantUserModelEntry>> readApproved({String? kind}) async {
    final records = kind == null
        ? await _memories.readActive()
        : await _memories.readActive(kind: 'user_$kind');
    return records
        .where(
          (record) =>
              // Ajaran eksplisit user (scope user-model) ATAU memori hasil
              // pembelajaran otomatis yang sudah disetujui (habit/pola).
              record.metadata['scope'] == 'user-model' ||
              record.metadata['approved'] == true,
        )
        .map(_entry)
        .toList(growable: false);
  }

  Future<String> buildContext({String? query}) async {
    final entries = await readApproved();
    final normalizedQuery = query?.trim().toLowerCase() ?? '';
    final relevant = entries.toList(growable: true)
      ..sort((left, right) {
        int score(FfmAssistantUserModelEntry entry) {
          if (normalizedQuery.isEmpty) return 0;
          final haystack = '${entry.key} ${entry.value}'.toLowerCase();
          return haystack.contains(normalizedQuery) ||
                  normalizedQuery.contains(entry.key.toLowerCase())
              ? 1
              : 0;
        }

        return score(right).compareTo(score(left));
      });
    if (relevant.isEmpty) return '';
    return relevant
        .take(24)
        .map((entry) => '${entry.kind}: ${entry.key} = ${entry.value}')
        .join('\n');
  }

  Future<void> forget(String id) => _memories.archive(id);

  FfmAssistantUserModelEntry _entry(FfmAssistantMemoryRecord record) {
    final rawConfidence = record.metadata['confidence'];
    final confidence = rawConfidence is num
        ? rawConfidence.toDouble().clamp(0, 1).toDouble()
        : 1.0;
    return FfmAssistantUserModelEntry(
      id: record.id,
      kind: record.kind.replaceFirst('user_', ''),
      key: record.triggerText,
      value: record.valueText,
      confidence: confidence,
      approved: record.metadata['approved'] != false,
      updatedAt: record.updatedAt,
    );
  }
}
