import 'package:ffm_manager/features/assistant/data/ffm_assistant_local_model_gateway.dart';
import 'package:ffm_manager/features/assistant/data/ffm_local_model_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_qwen2vl_inference_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_local_model_bridge_plugin.dart';
import 'package:ffm_manager/features/assistant/data/ffm_local_inference_queue.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_runtime_knowledge.dart';

class FfmQwen2VlGateway implements FfmAssistantLocalModelGateway {
  FfmQwen2VlGateway(this._modelService, this._inferenceService);

  final FfmLocalModelService _modelService;
  final FfmQwen2VlInferenceService _inferenceService;
  bool _isNativeInitialized = false;

  Future<void> _ensureInitialized() async {
    if (_isNativeInitialized) return;

    final installed = await _modelService.getInstalled();
    if (installed == null || installed.projectorPath == null) {
      throw Exception('Model Qwen2-VL belum terinstal atau tidak lengkap.');
    }

    await FfmLocalModelBridgePlugin.initNative(
      modelPath: installed.filePath,
      mmprojPath: installed.projectorPath!,
    );
    _isNativeInitialized = true;
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
    List<String> capabilityIds = const <String>[],
  }) async {
    try {
      await _ensureInitialized();

      final knowledge = FfmAssistantRuntimeKnowledgeRegistry()
          .buildPromptContext(query: input, capabilityIds: capabilityIds);
      final systemPrompt =
          '''
Anda adalah Asisten Family Finance Manager (FFM).
Tugas Anda HANYA mengekstrak informasi keuangan atau maksud pengguna menjadi JSON yang valid.
Gunakan timezone Asia/Jakarta.
Patuhi format ffm-local-vision-proposal-v2.
proposalType yang didukung: "expense", "income", "transfer", "navigation", "read_query", "help", "out_of_domain", "unknown".
Jika pengguna meminta navigasi (buka halaman), gunakan proposalType "navigation" dan isi "actionTarget".
Jika pengguna bertanya soal data atau meminta penilaian kondisi keuangan pribadi/keluarga (misalnya kemampuan cicilan, cashflow, penghematan, target), gunakan proposalType "read_query" agar aplikasi membaca agregat lokal terlebih dahulu.
SLM tidak boleh mengarang pemasukan, pengeluaran, cicilan, saldo, periode, atau kelayakan kredit. Angka fakta harus berasal dari evidence/hasil query lokal; SLM hanya membantu memahami maksud dan menyusun penjelasan.
Jika data belum ada, gunakan "help" untuk edukasi yang jujur dan menyatakan data apa yang belum tersedia. Jangan menyatakan pinjaman disetujui, menjamin keamanan, atau memberi kepastian hasil. Jangan memberi nasihat hukum, pajak, medis, atau janji imbal hasil investasi.
Jangan menambahkan teks lain selain JSON.
Halaman aktif: ${pageContext ?? 'tidak diketahui'}.
Halaman FFM yang dikenal:
${FfmAssistantCatalog.listForChat()}
Capability yang tersedia pada halaman aktif: ${capabilityIds.isEmpty ? 'gunakan katalog FFM yang relevan' : capabilityIds.join(', ')}.
Runtime knowledge registry:
$knowledge
Jika diminta melakukan perubahan, hanya usulkan langkah dan data terstruktur; jangan mengklaim sudah menyimpan.
Domain yang diizinkan (help/read_query): fitur FFM, data FFM, laporan keuangan, literasi keuangan keluarga, cara menabung, manajemen keuangan, saran budgeting, cashflow, target, dan keputusan finansial.
Jika pengguna menanyakan topik yang BENAR-BENAR di luar keuangan keluarga dan aplikasi FFM (misalnya: budidaya ikan, politik, cuaca, resep masakan, medis), gunakan proposalType "out_of_domain" dan jangan menjawabnya.
	''';

      final result = await _inferenceService.generateProposal(
        systemPrompt: systemPrompt,
        userPrompt: input,
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
          notes: proposal.warnings.map((w) => w.message).join('; '),
          actionTarget: proposal.actionTarget,
        );
      }

      // Untuk navigasi, query, dan bantuan, hanya kembalikan ID terstruktur.
      return FfmAssistantModelProposal(
        intent: intentType,
        confidence: 0.9,
        actionTarget: proposal.proposalType == 'navigation'
            ? proposal.actionTarget
            : null,
        queryId: proposal.proposalType == 'read_query'
            ? proposal.actionTarget
            : null,
      );
    } catch (e) {
      if (e is FfmInferenceCancelledException) rethrow;
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
