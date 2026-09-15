import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_knowledge_index.dart';

void main() {
  test('memilih sumber transaksi dan historis secara bounded', () {
    final plan = FfmAssistantKnowledgeIndex.planForRequest(
      'Berapa pengeluaran saya tahun lalu?',
    );

    expect(plan.sourceIds, contains('summary'));
    expect(plan.sourceIds, contains('transactions'));
    expect(plan.toBoundedPrompt(), contains('read-only'));
    expect(plan.toBoundedPrompt(), isNot(contains('SQL bebas')));
  });

  test('memilih onboarding dan profil untuk pertanyaan langkah berikutnya', () {
    final plan = FfmAssistantKnowledgeIndex.planForRequest(
      'Apa yang harus saya lakukan sekarang?',
    );

    expect(plan.sourceIds, contains('onboarding'));
    expect(plan.sourceIds, contains('profile'));
  });

  test('memilih sumber aktivitas dan pengingat', () {
    final plan = FfmAssistantKnowledgeIndex.planForRequest(
      'Apakah ada aktivitas dan alarm minggu ini?',
    );

    expect(plan.sourceIds, contains('activity'));
    expect(plan.sourceIds, contains('reminders'));
  });

  test('memilih sumber riwayat percakapan untuk pertanyaan obrolan lalu', () {
    final plan = FfmAssistantKnowledgeIndex.planForRequest(
      'Apa yang pernah kita bicarakan tentang target tabungan?',
    );

    expect(plan.sourceIds, contains('chat_history'));
  });

  test('catatan harian memilih activity dan tidak fallback ke summary', () {
    final plan = FfmAssistantKnowledgeIndex.planForRequest(
      'catatan harian isinya apa saja terbaru',
    );

    expect(plan.sourceIds, contains('activity'));
    expect(plan.sourceIds, isNot(contains('summary')));
  });

  test('pertanyaan halaman aktif memilih page_context bukan summary', () {
    final plan = FfmAssistantKnowledgeIndex.planForRequest(
      'jadi sekarang sedang di halaman apa',
    );

    expect(plan.sourceIds, contains('page_context'));
    expect(plan.sourceIds, isNot(contains('summary')));
  });
}
