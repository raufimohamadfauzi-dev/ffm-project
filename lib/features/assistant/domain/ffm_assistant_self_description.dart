import 'ffm_assistant_capabilities.dart';
import 'ffm_assistant_models.dart';

class FfmAssistantSelfDescriptionService {
  const FfmAssistantSelfDescriptionService();

  static const appName = 'Family Finance Manager (FFM)';
  static const appPurpose =
      'aplikasi pengelolaan keuangan keluarga offline-first dengan pendamping lokal';
  static const creatorName = 'Rafi Sinkkat';
  static const creatorYouTube =
      'https://youtube.com/@clipsmartt?si=T4-4Zja6FZlcgdDe';
  static const creatorTikTok =
      'https://www.tiktok.com/@clip.smarts?_r=1&_t=ZS-997Uzi7kXma';

  static final RegExp _creatorQuestionPattern = RegExp(
    r'pembuat|developer|pengembang|creator|pencipta|rafi',
    caseSensitive: false,
  );

  /// Menjamin jawaban untuk pertanyaan seputar pembuat selalu menyertakan
  /// kedua tautan sosial resmi — apa pun hasil rangkuman SLM.
  String ensureSocialLinks({
    required String question,
    required String response,
  }) {
    if (!_creatorQuestionPattern.hasMatch(question)) return response;
    var value = response;
    if (!value.contains(creatorYouTube)) {
      value = '$value\n\nYouTube: [$creatorYouTube]($creatorYouTube)';
    }
    if (!value.contains(creatorTikTok)) {
      value = '$value\nTikTok: [$creatorTikTok]($creatorTikTok)';
    }
    return value;
  }

  static const defaultImplementedCapabilityIds = <String>{
    'read.summary',
    'read.transactions',
    'read.accounts',
    'read.categories',
    'read.analysis',
    'read.activity',
    'read.budget',
    'read.goals',
    'read.assets',
    'read.liabilities',
    'read.receivable',
    'read.recurring',
    'read.reminders',
    'read.model_status',
    'draft.income',
    'draft.expense',
    'draft.transfer',
    'draft.activity',
    'draft.daily_note',
    'draft.reminder',
    'draft.goal',
    'draft.asset',
    'draft.liability',
    'draft.receivable',
    'draft.budget',
    'draft.master_data',
    'mutate.save_draft',
    'verify.saved_draft',
    'mutate.update',
    'mutate.archive',
    'verify.transaction_mutation',
    'verify.activity_mutation',
    'verify.goal_mutation',
    'verify.reminder_mutation',
    'verify.daily_note_mutation',
  };

  String build({
    Iterable<String> implementedCapabilityIds = defaultImplementedCapabilityIds,
    bool slmConfigured = false,
    FfmAssistantDestination? currentDestination,
  }) {
    final implemented = <String>{
      ...implementedCapabilityIds,
      for (final destination in FfmAssistantDestination.values)
        'navigate.${destination.name}',
    };
    final available = FfmAssistantCapabilityRegistry.all
        .where((capability) => implemented.contains(capability.id))
        .toList(growable: false);
    final availableLabels = available
        .where((capability) => capability.id.startsWith('read.'))
        .map((capability) => capability.label.toLowerCase())
        .join(', ');
    final canSaveDraft =
        implemented.contains('mutate.save_draft') &&
        implemented.contains('verify.saved_draft');
    final draftLabels = <String>[
      if (implemented.contains('draft.income') && canSaveDraft) 'pemasukan',
      if (implemented.contains('draft.expense') && canSaveDraft) 'pengeluaran',
      if (implemented.contains('draft.transfer') && canSaveDraft) 'transfer',
      if (implemented.contains('draft.activity') && canSaveDraft) 'aktivitas',
      if (implemented.contains('draft.daily_note') && canSaveDraft)
        'Catatan Harian',
    ];
    final mutationLabels = available
        .where(
          (capability) =>
              capability.risk == FfmAssistantCapabilityRisk.mutation &&
              capability.id != 'mutate.save_draft',
        )
        .map((capability) => capability.label.toLowerCase())
        .join(', ');
    final missing = FfmAssistantCapabilityRegistry.all
        .where(
          (capability) =>
              !implemented.contains(capability.id) &&
              !capability.id.startsWith('navigate.'),
        )
        .map((capability) => capability.label.toLowerCase())
        .toSet()
        .take(6)
        .join(', ');
    final pageText = currentDestination == null
        ? ''
        : ' Halaman aktif saat ini: ${_pageName(currentDestination)}.';

    final currentActions = <String>[
      'menjelaskan identitas, pembuat, halaman, fungsi menu, dan batas fitur FFM dari katalog aplikasi',
      'berpindah ke halaman yang tersedia melalui arahan yang kamu setujui',
      'memberikan edukasi literasi keuangan keluarga (budgeting, menabung, cashflow, manajemen finansial, dana darurat, asuransi, pajak keluarga, investasi dasar, penghasilan sampingan)',
      if (availableLabels.isNotEmpty) availableLabels,
      if (draftLabels.isNotEmpty) 'menyiapkan draft ${draftLabels.join(', ')}',
      if (canSaveDraft) 'menampilkan preview, menunggu konfirmasi, menyimpan mutation yang disetujui, lalu memverifikasi hasilnya',
      'menyiapkan preview laporan berbasis data lokal dan membantu menyusun narasi',
      'memberi penjelasan berdasarkan ringkasan database lokal tanpa mengirim raw database ke model',
      'menjawab pertanyaan finansial umum (asuransi, pajak, investasi dasar, dana darurat) dengan edukasi dan disclaimer yang tepat',
      'memberikan saran tindak lanjut yang relevan berdasarkan konteks percakapan dan data keuangan',
    ];
    return '''Aku adalah Asisten FFM, pendamping lokal di $appName.

$appName adalah $appPurpose. Aplikasi ini membantu mencatat transaksi, mengatur anggaran, memantau rekening, aset, hutang/piutang, target, pengingat, aktivitas, Catatan Harian, laporan, cadangan data, privasi, dan model asisten lokal.$pageText

Pembuat aplikasi ini adalah **$creatorName**.
YouTube: [$creatorYouTube]($creatorYouTube)
TikTok: [$creatorTikTok]($creatorTikTok)

Yang bisa kulakukan sekarang:
${currentActions.map((action) => '- $action;').join('\n')}

Aturan keamanan:
- draft tidak sama dengan data tersimpan;
- setiap perubahan permanen membutuhkan preview dan konfirmasi kamu;
- tidak ada autosave, penghapusan diam-diam, atau pengiriman data ke cloud;
- angka utama berasal dari database/aggregator lokal, bukan karangan SLM.

${slmConfigured ? 'Jika model SLM lokal siap, aku dapat memahami bahasa alami, membantu narasi atau insight, serta menjawab pertanyaan finansial umum dengan konteks data keuanganmu. Jika belum siap, aku memakai aturan lokal dan tetap memberi tahu statusnya.' : 'Model SLM lokal belum dikonfirmasi siap; saat ini aku mengandalkan aturan lokal dan menjelaskan status sebenarnya.'}

Masih dalam pengembangan: $missing.
${mutationLabels.isEmpty ? '' : 'Mutation terkonfirmasi yang tersedia: $mutationLabels.'}

Aku akan menyebutkan status sebenarnya dan tidak akan mengaku bisa menjalankan fitur yang belum memiliki adapter.''';
  }

  String _pageName(FfmAssistantDestination destination) =>
      FfmAssistantCatalog.findByDestination(destination)?.name ??
      destination.name;
}
