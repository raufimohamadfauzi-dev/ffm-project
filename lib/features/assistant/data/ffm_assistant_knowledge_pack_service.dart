import 'dart:convert';

import 'ffm_assistant_memory_repository.dart';

class FfmAssistantKnowledgePackPreview {
  const FfmAssistantKnowledgePackPreview({
    required this.formatVersion,
    required this.memories,
  });

  final String formatVersion;
  final List<FfmAssistantMemoryRecord> memories;

  int get total => memories.length;
}

/// Format pengetahuan portabel yang tidak membawa riwayat chat mentah.
///
/// Pack dapat dibuat oleh pengguna, diperkaya dengan LLM di luar aplikasi,
/// lalu diimpor lagi setelah preview. Aksi finansial tetap berupa draft.
class FfmAssistantKnowledgePackService {
  FfmAssistantKnowledgePackService(this._memoryRepository);

  static const formatVersion = 'ffm-assistant-knowledge-v1';
  static const _allowedKinds = {'alias', 'answer', 'habit', 'flow'};

  final FfmAssistantMemoryRepository _memoryRepository;

  Future<String> exportJson() async {
    final memories = await _memoryRepository.readAll();
    return jsonEncode({
      'formatVersion': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'purpose': 'Memori ajar Asisten FFM. Riwayat chat tidak disertakan.',
      'memories': memories.map((memory) => memory.toJson()).toList(),
    });
  }

  String buildLlmPrompt() {
    return '''Kamu membantu menyusun knowledge pack untuk Asisten FFM offline.

Balas HANYA dengan JSON valid berikut, tanpa Markdown atau teks tambahan:
{
  "formatVersion": "ffm-assistant-knowledge-v1",
  "memories": [
    {
      "kind": "answer|alias|habit|flow",
      "triggerText": "pertanyaan atau frasa pengguna",
      "valueText": "jawaban atau aturan yang aman",
      "metadata": {}
    }
  ]
}

Aturan wajib:
- Fokus hanya pada Family Finance Manager (FFM).
- Jangan pernah memberi instruksi simpan otomatis transaksi, aset, hutang, atau pengingat.
- Jika nominal, rekening, sumber dana, atau jenis transaksi belum jelas, minta klarifikasi.
- Transfer bukan pemasukan atau pengeluaran; biaya admin adalah pengeluaran terpisah.
- Jangan memasukkan nama, nomor rekening, nominal, PIN, atau data pribadi nyata.
- Gunakan Bahasa Indonesia santai, jelas, dan aman.

Masukkan ajaran pengguna berikut ke dalam JSON setelah dirapikan:
''';
  }

  FfmAssistantKnowledgePackPreview previewJson(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw const FormatException('Knowledge pack harus berbentuk objek JSON.');
    }
    final version = decoded['formatVersion']?.toString() ?? '';
    if (version != formatVersion) {
      throw const FormatException('Versi knowledge pack tidak didukung.');
    }
    final rawMemories = decoded['memories'];
    if (rawMemories is! List) {
      throw const FormatException('Daftar memories tidak ditemukan.');
    }
    final records = <FfmAssistantMemoryRecord>[];
    for (final raw in rawMemories) {
      if (raw is! Map) {
        throw const FormatException('Satu entri memory tidak valid.');
      }
      final kind = raw['kind']?.toString().trim().toLowerCase() ?? '';
      final trigger = raw['triggerText']?.toString().trim() ?? '';
      final value = raw['valueText']?.toString().trim() ?? '';
      if (!_allowedKinds.contains(kind)) {
        throw FormatException('Jenis memory "$kind" tidak didukung.');
      }
      if (trigger.isEmpty ||
          value.isEmpty ||
          trigger.length > 500 ||
          value.length > 4000) {
        throw const FormatException('Isi memory kosong atau terlalu panjang.');
      }
      final rawMetadata = raw['metadata'];
      final metadata = rawMetadata is Map
          ? rawMetadata.map((key, item) => MapEntry('$key', item))
          : <String, dynamic>{};
      final now = DateTime.now();
      records.add(
        FfmAssistantMemoryRecord(
          id: raw['id']?.toString().trim().isNotEmpty == true
              ? raw['id'].toString()
              : 'knowledge-${now.microsecondsSinceEpoch}-${records.length}',
          householdId: FfmAssistantMemoryRepository.householdId,
          kind: kind,
          triggerText: trigger,
          valueText: value,
          metadata: metadata,
          source: 'knowledge-pack',
          isArchived: false,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    return FfmAssistantKnowledgePackPreview(
      formatVersion: version,
      memories: records,
    );
  }

  Future<int> importJson(String content) async {
    final preview = previewJson(content);
    for (final memory in preview.memories) {
      await _memoryRepository.save(
        id: memory.id,
        kind: memory.kind,
        triggerText: memory.triggerText,
        valueText: memory.valueText,
        metadata: memory.metadata,
        source: memory.source,
      );
    }
    return preview.total;
  }
}
