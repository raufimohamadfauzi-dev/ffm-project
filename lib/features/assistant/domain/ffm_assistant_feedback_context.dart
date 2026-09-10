/// Konteks singkat untuk memperbaiki jawaban Asisten secara eksplisit.
///
/// Tidak pernah dikirim otomatis keluar aplikasi. Teks hanya dapat disalin
/// setelah pengguna menekan aksi pada kartu chat.
class FfmAssistantFeedbackContext {
  const FfmAssistantFeedbackContext({
    required this.userQuestion,
    required this.assistantAnswer,
    this.responseOrigin,
    this.pluginName,
    this.pluginCategory,
    this.pluginMetadata,
    this.verifiedFacts,
  });

  final String userQuestion;
  final String assistantAnswer;
  final String? responseOrigin;
  final String? pluginName;
  final String? pluginCategory;
  final Map<String, dynamic>? pluginMetadata;
  final String? verifiedFacts;

  String buildCopyText() =>
      '''Pertanyaan pengguna:
$userQuestion

Jawaban Asisten FFM:
$assistantAnswer''';

  String buildDeveloperReport() {
    final metadata = pluginMetadata ?? const <String, dynamic>{};
    final lines = <String>[
      'LAPORAN DIAGNOSTIK ASISTEN FFM',
      'Tujuan: bahan perbaikan developer/agent coding; tidak mengubah data otomatis.',
      '',
      'PERTANYAAN USER:',
      userQuestion,
      '',
      'JAWABAN ASISTEN:',
      assistantAnswer,
      '',
      'SUMBER JAWABAN:',
      '- Origin: ${responseOrigin ?? 'tidak diketahui'}',
      if (pluginName != null) '- Plugin: $pluginName',
      if (pluginCategory != null) '- Kategori: $pluginCategory',
      if (metadata['model'] != null) '- Model: ${metadata['model']}',
      if (metadata['usedReadCapability'] != null)
        '- Read capability: ${metadata['usedReadCapability']}',
      if (metadata['requestClass'] != null)
        '- Request class: ${metadata['requestClass']}',
      '- Status grounding: ${metadata['groundingBlocked'] == true ? 'gagal' : 'tidak diblokir'}',
      '',
      'FAKTA LOKAL YANG TERSEDIA:',
      _clip(verifiedFacts ?? 'tidak tersedia', 2400),
      '',
      'TINDAKAN YANG DIHARAPKAN:',
      'Periksa apakah pertanyaan, sumber data, kalkulasi, grounding, dan jawaban sudah sesuai. Jangan mengubah transaksi tanpa konfirmasi user.',
    ];
    return lines.join('\n');
  }

  static String _clip(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return normalized.length <= maxLength
        ? normalized
        : '${normalized.substring(0, maxLength - 1)}…';
  }

  String buildTrainingSeed() =>
      '''Bantu perbaiki knowledge Asisten FFM.

Pertanyaan pengguna:
$userQuestion

Jawaban Asisten saat ini:
$assistantAnswer

Tugas:
1. Usulkan jawaban atau alur yang lebih tepat untuk pertanyaan tersebut.
2. Jangan membuat transaksi, saldo, nominal, rekening, aset, hutang, atau data keluarga.
3. Jangan mengubah atau mengulang knowledge yang sudah ada.
4. Kembalikan hanya satu entri knowledge pack JSON dengan kind "answer" atau "flow".''';
}
