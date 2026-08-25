import 'ffm_assistant_memory_repository.dart';

/// Layanan untuk menyusun context prompt upgrade pack asisten dengan perlindungan privasi.
class FfmAssistantUpgradePackService {
  const FfmAssistantUpgradePackService(this._memories);

  final FfmAssistantMemoryRepository _memories;

  Future<String> buildPrompt() async {
    final list = await _memories.readActive();
    final buffer = StringBuffer();
    buffer.writeln('ffm-assistant-upgrade-context-v1');
    buffer.writeln('Petunjuk: Jangan membuat asumsi transaksi, saldo, nominal.');
    buffer.writeln('Panduan mencakup: Data Utama, Aktivitas, Anggaran, dan Rekening.');

    for (final m in list) {
      if (m.kind == 'alias') continue; // Saring alias sensitif
      var text = m.valueText;
      // Masking nomor telepon
      text = text.replaceAll(RegExp(r'\b08\d{8,12}\b'), '<TELEPON>');
      buffer.writeln('- ${m.triggerText}: $text');
    }

    return buffer.toString();
  }
}
