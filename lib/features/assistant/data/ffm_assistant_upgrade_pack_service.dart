import 'dart:convert';

import '../domain/ffm_assistant_models.dart';
import 'ffm_assistant_memory_repository.dart';

/// Menyusun konteks yang pengguna salin sendiri ke LLM eksternal.
///
/// Paket ini bukan backup, bukan data transaksi, dan tidak memberi LLM akses
/// ke perangkat. Alias pribadi tidak diekspor; memori lain disamarkan sebelum
/// disalin agar LLM dapat melengkapi jawaban tanpa membutuhkan data keluarga.
class FfmAssistantUpgradePackService {
  FfmAssistantUpgradePackService(this._memoryRepository);

  final FfmAssistantMemoryRepository _memoryRepository;

  Future<String> buildPrompt() async {
    final memories = await _memoryRepository.readAll();
    final safeKnowledge = memories
        .where((memory) => !memory.isArchived)
        .map(_safeMemoryForExternalLlm)
        .toList(growable: false);
    final modules = FfmAssistantCatalog.pages
        .map(
          (page) => {
            'name': page.name,
            'aliases': page.aliases,
            'description': page.description,
            'detail': FfmAssistantCatalog.detailFor(page.destination),
          },
        )
        .toList(growable: false);
    final context = jsonEncode({
      'formatVersion': 'ffm-assistant-upgrade-context-v1',
      'scope': 'Konteks aman untuk mengusulkan knowledge pack FFM.',
      'appModules': modules,
      'existingKnowledge': safeKnowledge,
      'safetyContract': const [
        'Jangan membuat, menebak, atau menyalin saldo, nominal, transaksi, rekening, PIN, nama keluarga, nomor telepon, atau data pribadi.',
        'Jangan mengubah data FFM dan jangan memberi instruksi simpan otomatis.',
        'Transfer bukan pemasukan atau pengeluaran; biaya admin adalah pengeluaran terpisah.',
        'Jika nominal, rekening, sumber dana, jenis transaksi, atau target belum jelas, Asisten harus meminta klarifikasi.',
        'Usulkan hanya jawaban, kebiasaan, atau alur baru yang tidak bertentangan dengan knowledge yang ada.',
        'Aksi finansial FFM selalu berupa draft yang pengguna tinjau dan konfirmasi sendiri.',
      ],
    });
    return '''Kamu membantu memperkaya knowledge pack untuk Asisten FFM offline.

Konteks FFM berikut dibawa oleh pengguna secara manual. Tidak ada akses ke aplikasi, database, backup, atau internet pengguna:
$context

Tugasmu: usulkan tambahan jawaban fitur, alur aman, atau kebiasaan yang membantu pertanyaan pengguna tentang seluruh modul FFM. Jangan mengulang knowledge yang sudah ada. Jika tidak ada tambahan yang aman, gunakan daftar memories kosong.

Balas HANYA dengan JSON valid berikut, tanpa Markdown atau teks tambahan:
{
  "formatVersion": "ffm-assistant-knowledge-v1",
  "memories": [
    {
      "kind": "answer|habit|flow",
      "triggerText": "pertanyaan atau frasa pengguna",
      "valueText": "jawaban atau aturan FFM dalam Bahasa Indonesia santai",
      "metadata": {"source": "llm-upgrade"}
    }
  ]
}
''';
  }

  Map<String, Object?> _safeMemoryForExternalLlm(
    FfmAssistantMemoryRecord memory,
  ) {
    if (memory.kind == 'alias') {
      return {
        'kind': 'alias',
        'note': 'Ada alias pribadi lokal. Isi alias tidak dibagikan ke LLM.',
      };
    }
    return {
      'kind': memory.kind,
      'triggerText': _redact(memory.triggerText),
      'valueText': _redact(memory.valueText),
    };
  }

  static String _redact(String value) => value
      .replaceAllMapped(RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'), (_) => '<EMAIL>')
      .replaceAllMapped(
        RegExp(r'(?<!\d)(?:\+62|62|0)8\d{7,12}(?!\d)'),
        (_) => '<TELEPON>',
      )
      .replaceAllMapped(RegExp(r'(?<!\d)\d{4,}(?!\d)'), (_) => '<ANGKA>');
}
