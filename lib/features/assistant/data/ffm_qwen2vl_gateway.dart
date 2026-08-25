import 'package:ffm_manager/features/assistant/data/ffm_assistant_local_model_gateway.dart';
import 'package:ffm_manager/features/assistant/data/ffm_local_model_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_qwen2vl_inference_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_local_model_bridge_plugin.dart';
import 'package:ffm_manager/features/assistant/data/ffm_local_inference_queue.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_runtime_knowledge.dart';

import 'ffm_assistant_slm_follow_up_contract.dart';

class FfmQwen2VlGateway
    implements
        FfmAssistantLocalModelGateway,
        FfmAssistantSlmFollowUpGenerator,
        FfmAssistantVisionDiagnostics {
  FfmQwen2VlGateway(this._modelService, this._inferenceService);

  final FfmLocalModelService _modelService;
  final FfmQwen2VlInferenceService _inferenceService;
  bool _isNativeInitialized = false;
  FfmAssistantVisionFailure? _lastVisionFailure;

  @override
  FfmAssistantVisionFailure? get lastVisionFailure => _lastVisionFailure;

  Future<void> _ensureInitialized() async {
    if (_isNativeInitialized) return;

    final installed = await _modelService.getInstalled();
    if (installed == null || installed.projectorPath == null) {
      _lastVisionFailure = const FfmAssistantVisionFailure(
        FfmAssistantVisionFailureCode.modelUnavailable,
      );
      throw Exception('Model Qwen2-VL belum terinstal atau tidak lengkap.');
    }
    if (!installed.isVerified) {
      _lastVisionFailure = const FfmAssistantVisionFailure(
        FfmAssistantVisionFailureCode.modelNotVerified,
      );
      throw Exception('Model Qwen2-VL belum terverifikasi.');
    }

    await FfmLocalModelBridgePlugin.initNative(
      modelPath: installed.filePath,
      mmprojPath: installed.projectorPath!,
    );
    _isNativeInitialized = true;
  }

  @override
  Future<List<String>> generateFollowUpSuggestions({
    required List<String> conversationTopics,
  }) async {
    if (conversationTopics.isEmpty) return const <String>[];
    if (_inferenceService.isBusy) return const <String>[];
    try {
      await _ensureInitialized();
      final response = await _inferenceService.tryGenerateJsonWhenIdle(
        systemPrompt: '''
Anda adalah generator rekomendasi pertanyaan untuk Asisten Family Finance Manager.
Berdasarkan topik percakapan yang telah disanitasi, buat TEPAT tiga pertanyaan lanjutan dalam Bahasa Indonesia yang membantu pengguna melanjutkan topik yang sama.

ATURAN MUTLAK:
1. Keluarkan JSON valid saja: {"suggestions":["pertanyaan 1?","pertanyaan 2?","pertanyaan 3?"]}.
2. Setiap item harus pertanyaan singkat, relevan, unik, dan diakhiri tanda tanya.
3. Jangan mengarang saldo, nominal, transaksi, rekening, atau data keluarga.
4. Jangan memberi instruksi untuk menyimpan, menghapus, atau mengubah data secara otomatis.
5. Jangan membuat URL, Markdown, kode, atau teks di luar JSON.
6. Jika konteks tidak cukup, tetap buat tiga pertanyaan klarifikasi yang aman tentang topik terakhir.
''',
        userPrompt:
            'Topik percakapan terakhir:\n${conversationTopics.join('\n')}',
      );
      if (response == null) return const <String>[];
      return FfmAssistantSlmFollowUpContract.parseJsonResponse(response);
    } on Object {
      return const <String>[];
    }
  }

  @override
  Future<FfmAssistantModelProposal?> propose({
    required String input,
    String? imagePath,
  }) async => proposeWithContext(input: input, imagePath: imagePath);

  @override
  Future<FfmAssistantModelProposal?> proposeWithContext({
    required String input,
    String? imagePath,
    String? pageContext,
    String? conversationHistory,
    List<String> capabilityIds = const <String>[],
  }) async {
    _lastVisionFailure = null;
    try {
      await _ensureInitialized();

      final knowledge = FfmAssistantRuntimeKnowledgeRegistry()
          .buildPromptContext(query: input, capabilityIds: capabilityIds);
      final historySection =
          conversationHistory != null && conversationHistory.trim().isNotEmpty
          ? '\nRiwayat dialog sebelumnya:\n$conversationHistory\n'
          : '';
      final systemPrompt =
          '''
Anda adalah Asisten Family Finance Manager (FFM).
Tugas Anda mengekstrak informasi keuangan atau maksud pengguna menjadi JSON yang valid.
Gunakan timezone Asia/Jakarta.
Patuhi format ffm-local-vision-proposal-v2.
proposalType yang didukung: "expense", "income", "transfer", "navigation", "read_query", "help", "out_of_domain", "unknown".

ATURAN INTI:
1. Jika pengguna meminta navigasi (buka halaman), gunakan proposalType "navigation" dan isi "actionTarget".
2. Jika pengguna bertanya soal data atau meminta penilaian kondisi keuangan pribadi/keluarga (misalnya kemampuan cicilan, cashflow, penghematan, target), gunakan proposalType "read_query" agar aplikasi membaca agregat lokal terlebih dahulu.
3. SLM tidak boleh mengarang pemasukan, pengeluaran, cicilan, saldo, periode, atau kelayakan kredit. Angka fakta harus berasal dari evidence/hasil query lokal; SLM hanya membantu memahami maksud dan menyusun penjelasan.
4. Jika data belum ada, gunakan "help" untuk edukasi yang jujur dan menyatakan data apa yang belum tersedia.
5. Jangan menyatakan pinjaman disetujui, menjamin keamanan, atau memberi kepastian hasil.
6. Jangan memberi nasihat hukum, pajak, medis, atau janji imbal hasil investasi.
7. Jika pengguna melampirkan gambar dan meminta penjelasan visual, screenshot, atau teks error, gunakan proposalType "help" dan isi assistantMessage dengan observasi faktual singkat dari gambar. Jangan membuat transaksi, nominal, atau diagnosis teknis yang tidak tampak pada gambar.
8. Untuk pertanyaan terbuka tentang fungsi halaman/fitur FFM yang sedang aktif, proposalType boleh "help" dan assistantMessage wajib berupa jawaban singkat yang hanya bersandar pada halaman aktif, katalog FFM, capability, atau runtime knowledge yang diberikan. Jangan mengarang fitur, data pengguna, nominal, atau status penyimpanan.
9. assistantMessage maksimal 3 kalimat. Jangan menampilkan PIN, password, OTP, token, saldo, transaksi mentah, nominal, path, JSON, atau metadata teknis. Jika gambar adalah nota yang cukup terbaca dan pengguna ingin mencatatnya, gunakan proposal transaksi seperti biasa, bukan assistantMessage.

PANDUAN JAWABAN:
- Untuk pertanyaan finansial umum (asuransi, pajak, investasi dasar, dana darurat), berikan jawaban edukatif dengan disclaimer bahwa ini bukan rekomendasi personal.
- Untuk pertanyaan tentang kondisi keuangan pengguna, gunakan "read_query" agar data lokal dibaca dulu.
- Untuk permintaan saran tindak lanjut, sertakan maksimal 2-3 saran spesifik yang relevan dengan konteks.
- Jika topik benar-benar di luar keuangan keluarga dan FFM (cuaca, resep masakan, olahraga, politik), gunakan "out_of_domain".
- Topik yang masih terkait keuangan meskipun bukan fitur langsung FFM (asuransi, pajak, investasi) boleh dijawab dengan edukasi dasar dan disclaimer.

Jangan menambahkan teks lain selain JSON.
$historySection
Halaman aktif: ${pageContext ?? 'tidak diketahui'}.
Halaman FFM yang dikenal:
${FfmAssistantCatalog.listForChat()}
Capability yang tersedia pada halaman aktif: ${capabilityIds.isEmpty ? 'gunakan katalog FFM yang relevan' : capabilityIds.join(', ')}.
Runtime knowledge registry:
$knowledge
Jika diminta melakukan perubahan, hanya usulkan langkah dan data terstruktur; jangan mengklaim sudah menyimpan.
Domain yang diizinkan (help/read_query): fitur FFM, data FFM, laporan keuangan, literasi keuangan keluarga, cara menabung, manajemen keuangan, saran budgeting, cashflow, target, keputusan finansial, asuransi keluarga, perencanaan pajak, investasi dasar, dana darurat, penghasilan sampingan.
	''';

      final userPromptWithContext =
          conversationHistory != null && conversationHistory.trim().isNotEmpty
          ? '[Konteks percakapan: perhatikan respons sebelumnya]\n$input'
          : input;

      final result = await _inferenceService.generateProposal(
        systemPrompt: systemPrompt,
        userPrompt: userPromptWithContext,
        imagePath: imagePath,
      );

      // Map dari Proposal v2 (ekstraksi data murni) ke FfmAssistantModelProposal (keputusan Asisten)
      // Asisten rule-based akan menggunakan ini sebagai 'pemahaman awal' dan
      // tetap menjalankan validasinya sendiri sebelum menampilkan draf.
      final proposal = result.proposal;

      final itemsMap = <String, String>{};
      for (var i = 0; i < proposal.items.length; i++) {
        final item = proposal.items[i];
        itemsMap['item_$i'] =
            '${item.name} (${item.quantity}x @ ${item.unitPrice})';
      }

      final intentType = _mapIntentType(proposal.proposalType);

      if (proposal.needsClarification) {
        return FfmAssistantModelProposal(
          intent: FfmAssistantIntentType.unknown,
          confidence: 0.9,
          missingFields: proposal.missingFields,
          extractedFields: proposal.extractedFields,
          suggestedCapabilities: proposal.suggestedCapabilities,
          clarification: proposal.clarificationQuestion,
          reasoning: proposal.reasoning,
          notes: proposal.warnings.map((w) => w.message).join('; '),
        );
      }

      if (intentType == FfmAssistantIntentType.createExpense ||
          intentType == FfmAssistantIntentType.createIncome ||
          intentType == FfmAssistantIntentType.createTransfer) {
        final draftKind = switch (intentType) {
          FfmAssistantIntentType.createIncome => FfmAssistantDraftKind.income,
          FfmAssistantIntentType.createTransfer =>
            FfmAssistantDraftKind.transfer,
          _ => FfmAssistantDraftKind.expense,
        };

        final draft = FfmAssistantDraft(
          kind: draftKind,
          createdAt: DateTime.now(),
          date: proposal.transactionDate ?? DateTime.now(),
          title: proposal.merchantName,
          amount: proposal.totalAmount,
          categoryName: proposal.suggestedCategory,
          toAccountName: proposal.suggestedAccount,
          formValues: itemsMap,
        );

        return FfmAssistantModelProposal(
          intent: intentType,
          confidence: 0.9,
          draft: draft,
          missingFields: proposal.missingFields,
          extractedFields: proposal.extractedFields,
          suggestedCapabilities: proposal.suggestedCapabilities,
          reasoning: proposal.reasoning,
          notes: proposal.warnings.map((w) => w.message).join('; '),
          actionTarget: proposal.actionTarget,
        );
      }

      final reasoning = switch (proposal.proposalType) {
        'navigation' =>
          'Navigasi ke halaman ${proposal.actionTarget ?? 'tujuan'}',
        'read_query' => 'Baca data lokal untuk query pengguna',
        'help' => 'Berikan bantuan atau edukasi',
        'out_of_domain' => 'Topik di luar domain FFM',
        _ => 'Klasifikasi intent oleh SLM',
      };

      return FfmAssistantModelProposal(
        intent: intentType,
        confidence: 0.9,
        missingFields: proposal.missingFields,
        extractedFields: proposal.extractedFields,
        suggestedCapabilities: proposal.suggestedCapabilities,
        reasoning: reasoning,
        notes: proposal.assistantMessage,
        actionTarget: proposal.proposalType == 'navigation'
            ? proposal.actionTarget
            : null,
        queryId: proposal.proposalType == 'read_query'
            ? proposal.actionTarget
            : null,
      );
    } on FormatException {
      if (imagePath != null) {
        _lastVisionFailure = const FfmAssistantVisionFailure(
          FfmAssistantVisionFailureCode.responseInvalid,
        );
      }
      return null;
    } catch (e) {
      if (e is FfmInferenceCancelledException) rethrow;
      if (imagePath != null && _lastVisionFailure == null) {
        _lastVisionFailure = FfmAssistantVisionFailure(
          _isNativeInitialized
              ? FfmAssistantVisionFailureCode.inferenceFailed
              : FfmAssistantVisionFailureCode.nativeInitializationFailed,
        );
      }
      // Kegagalan native/model biasa tetap kembali ke interpreter lokal.
      return null;
    }
  }

  FfmAssistantIntentType _mapIntentType(String type) => switch (type) {
    'expense' => FfmAssistantIntentType.createExpense,
    'income' => FfmAssistantIntentType.createIncome,
    'transfer' => FfmAssistantIntentType.createTransfer,
    'navigation' => FfmAssistantIntentType.openPage,
    'read_query' => FfmAssistantIntentType.queryData,
    'help' => FfmAssistantIntentType.help,
    'out_of_domain' => FfmAssistantIntentType.outOfDomain,
    _ => FfmAssistantIntentType.unknown,
  };
}
