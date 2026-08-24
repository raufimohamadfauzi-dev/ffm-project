import 'ffm_assistant_models.dart';

class FfmAssistantProactiveSuggestion {
  const FfmAssistantProactiveSuggestion({
    required this.id,
    required this.message,
    required this.suggestedPrompt,
    required this.destination,
  });

  final String id;
  final String message;
  final String suggestedPrompt;
  final FfmAssistantDestination? destination;
}

/// Saran ringan berbasis context lokal. Tidak menjalankan capability dan tidak
/// membaca transaksi mentah; user tetap harus mengetuk saran atau mengetik.
class FfmAssistantProactiveSuggestionService {
  const FfmAssistantProactiveSuggestionService();

  FfmAssistantProactiveSuggestion? suggest({
    required FfmAssistantDestination? destination,
    required bool modelReady,
    required bool hasConversation,
  }) {
    if (!modelReady) {
      return const FfmAssistantProactiveSuggestion(
        id: 'setup-local-model',
        message: 'AI lokal belum siap. Kamu bisa mengunduh SLM dari GitHub atau mengimpor bundle offline.',
        suggestedPrompt: 'siapkan AI lokal',
        destination: FfmAssistantDestination.localModel,
      );
    }
    if (hasConversation) return null;
    return switch (destination) {
      FfmAssistantDestination.transactions =>
        const FfmAssistantProactiveSuggestion(
          id: 'summarize-transactions',
          message: 'Aku bisa membaca transaksi pada filter halaman ini atau menyiapkan draft dari perintahmu.',
          suggestedPrompt: 'ringkas transaksi di halaman ini',
          destination: FfmAssistantDestination.transactions,
        ),
      FfmAssistantDestination.budget => const FfmAssistantProactiveSuggestion(
        id: 'review-budget',
        message: 'Aku bisa membantu membaca pemakaian anggaran dan menunjukkan kategori yang perlu diperhatikan.',
        suggestedPrompt: 'ringkas anggaran di halaman ini',
        destination: FfmAssistantDestination.budget,
      ),
      FfmAssistantDestination.analysis => const FfmAssistantProactiveSuggestion(
        id: 'explain-analysis',
        message: 'Aku bisa menjelaskan pola pada analisis ini berdasarkan data lokal yang tersimpan.',
        suggestedPrompt: 'jelaskan analisis di halaman ini',
        destination: FfmAssistantDestination.analysis,
      ),
      FfmAssistantDestination.goals => const FfmAssistantProactiveSuggestion(
        id: 'review-goal',
        message: 'Aku bisa membantu mengecek progres target atau menyiapkan setoran tanpa langsung menyimpan.',
        suggestedPrompt: 'cek progres target di halaman ini',
        destination: FfmAssistantDestination.goals,
      ),
      FfmAssistantDestination.masterData =>
        const FfmAssistantProactiveSuggestion(
          id: 'review-master-data',
          message: 'Aku bisa mengecek apakah Data Utama sudah cukup untuk mulai mencatat, tanpa menambah data sendiri.',
          suggestedPrompt: 'cek kesiapan Data Utama',
          destination: FfmAssistantDestination.masterData,
        ),
      FfmAssistantDestination.activity => const FfmAssistantProactiveSuggestion(
        id: 'review-activities',
        message: 'Aku bisa membantu melihat aktivitas yang aktif atau menyiapkan aktivitas baru untuk kamu tinjau.',
        suggestedPrompt: 'cek aktivitas yang perlu diperhatikan',
        destination: FfmAssistantDestination.activity,
      ),
      FfmAssistantDestination.reminders =>
        const FfmAssistantProactiveSuggestion(
          id: 'review-reminders',
          message: 'Aku bisa membantu meninjau pengingat aktif atau menyiapkan pengingat baru tanpa langsung menjadwalkannya.',
          suggestedPrompt: 'cek pengingat aktif',
          destination: FfmAssistantDestination.reminders,
        ),
      _ => const FfmAssistantProactiveSuggestion(
        id: 'ask-ffm',
        message: 'Aku siap membaca konteks halaman ini, menjawab pertanyaan, atau menyiapkan pekerjaan untuk kamu tinjau.',
        suggestedPrompt: 'apa yang bisa dilakukan di halaman ini?',
        destination: null,
      ),
    };
  }
}
