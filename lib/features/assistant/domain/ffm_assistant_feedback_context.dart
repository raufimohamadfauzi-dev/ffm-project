/// Konteks singkat untuk memperbaiki jawaban Asisten secara eksplisit.
///
/// Tidak pernah dikirim otomatis keluar aplikasi. Teks hanya dapat disalin
/// setelah pengguna menekan aksi pada kartu chat.
class FfmAssistantFeedbackContext {
  const FfmAssistantFeedbackContext({
    required this.userQuestion,
    required this.assistantAnswer,
  });

  final String userQuestion;
  final String assistantAnswer;

  String buildCopyText() =>
      '''Pertanyaan pengguna:
$userQuestion

Jawaban Asisten FFM:
$assistantAnswer''';

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
