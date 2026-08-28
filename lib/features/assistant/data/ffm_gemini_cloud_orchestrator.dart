import '../../../core/network/gemini_diagnostics.dart';
import '../../../core/network/gemini_service.dart';
import '../../../core/network/supabase_config.dart';
import 'ffm_assistant_proposal_json_service.dart';
import 'ffm_gemini_read_capability_service.dart';

class FfmGeminiCloudTurnResult {
  const FfmGeminiCloudTurnResult.success({
    required this.text,
    required this.model,
    this.statusCode,
    this.latency,
    this.usedReadCapability,
  }) : errorMessage = null;

  const FfmGeminiCloudTurnResult.failure({
    required this.errorMessage,
    required this.model,
    this.statusCode,
    this.latency,
  }) : text = null,
       usedReadCapability = null;

  final String? text;
  final String? errorMessage;
  final String model;
  final int? statusCode;
  final Duration? latency;
  final String? usedReadCapability;

  bool get ok => text != null;
}

/// Orkestrator Gemini Cloud: model berbicara, FFM tetap mengizinkan dan
/// menjalankan capability read-only bounded. Ia tidak mengetahui draft, UI,
/// executor mutasi, maupun repository aplikasi.
class FfmGeminiCloudOrchestrator {
  FfmGeminiCloudOrchestrator({
    GeminiService? gemini,
    SupabaseConfig? config,
    required this.readCapabilities,
    required this.clock,
    this.recordUsage,
  }) : _gemini = gemini ?? GeminiService(),
       _config = config ?? SupabaseConfig();

  final GeminiService _gemini;
  final SupabaseConfig _config;
  final FfmGeminiReadCapabilityService readCapabilities;
  final DateTime Function() clock;
  final Future<void> Function({
    required String code,
    required String model,
    required bool ok,
    int? httpStatus,
    Duration? latency,
  })?
  recordUsage;

  Future<FfmGeminiCloudTurnResult> run({
    required String userText,
    required String boundedContext,
    required String householdId,
  }) async {
    String? key;
    String? model;
    var verified = false;
    try {
      key = await _config.getGeminiKey();
      model = await _config.getGeminiModel();
      verified = await _config.isGeminiVerified();
    } on Object {
      // Secure storage may be unavailable; treat cloud as unverified.
    }
    if (key == null ||
        key.trim().isEmpty ||
        !verified ||
        model == null ||
        model.trim().isEmpty) {
      await _record(
        code: GeminiDiagnosticCodes.configMissing,
        model: model ?? '',
        ok: false,
      );
      return FfmGeminiCloudTurnResult.failure(
        errorMessage: 'Koneksi ke otak AI saya (Gemini) belum siap. Silakan ketuk tombol "Setup Sekarang" di atas untuk memasukkan Kunci API.',
        model: model ?? 'belum dipilih',
      );
    }
    final instruction = _instruction(boundedContext);
    GeminiResult result;
    try {
      result = await _chat(
        key: key.trim(),
        model: model.trim(),
        userText: userText,
        instruction: instruction,
      );
    } on Object {
      return FfmGeminiCloudTurnResult.failure(
        errorMessage: 'Gemini tidak dapat dihubungi saat ini. Coba lagi nanti.',
        model: model,
      );
    }
    if (!result.ok) return _failure(result);

    final request = FfmAssistantProposalJsonService.parseReadCapabilityRequest(
      result.text!,
    );
    if (request.error != null) {
      return FfmGeminiCloudTurnResult.failure(
        errorMessage: request.error!,
        model: result.model,
        statusCode: result.statusCode,
        latency: result.latency,
      );
    }
    if (request.request != null) {
      String facts;
      try {
        facts = await readCapabilities.execute(
          request.request!,
          householdId: householdId,
          now: clock(),
        );
      } on Object {
        return FfmGeminiCloudTurnResult.failure(
          errorMessage:
              'Data lokal untuk capability Gemini tidak dapat dibaca dengan aman.',
          model: result.model,
          statusCode: result.statusCode,
          latency: result.latency,
        );
      }
      try {
        result = await _chat(
          key: key.trim(),
          model: model.trim(),
          userText: userText,
          instruction:
              '$instruction\n\nHASIL CAPABILITY LOKAL TERVERIFIKASI:\n$facts\n\nSekarang jawab pertanyaan pengguna hanya dari hasil capability dan konteks resmi di atas. Jangan meminta capability lagi, jangan mengeluarkan JSON, dan jangan menyatakan data telah diubah.',
        );
      } on Object {
        return FfmGeminiCloudTurnResult.failure(
          errorMessage: 'Gemini tidak dapat menyelesaikan jawaban setelah membaca data lokal.',
          model: result.model,
          statusCode: result.statusCode,
          latency: result.latency,
        );
      }
      if (!result.ok) return _failure(result);
    }
    return FfmGeminiCloudTurnResult.success(
      text: result.text!,
      model: result.model,
      statusCode: result.statusCode,
      latency: result.latency,
      usedReadCapability: request.request?.capabilityId,
    );
  }

  Future<GeminiResult> _chat({
    required String key,
    required String model,
    required String userText,
    required String instruction,
  }) async {
    final result = await _gemini.chat(
      apiKey: key,
      model: model,
      prompt: userText,
      systemInstruction: instruction,
    );
    await _record(
      code:
          result.diagnosticCode ??
          (result.ok
              ? GeminiDiagnosticCodes.chatSuccess
              : GeminiDiagnosticCodes.chatError),
      model: result.model,
      ok: result.ok,
      httpStatus: result.statusCode,
      latency: result.latency,
    );
    return result;
  }

  FfmGeminiCloudTurnResult _failure(GeminiResult result) =>
      FfmGeminiCloudTurnResult.failure(
        errorMessage: result.message,
        model: result.model,
        statusCode: result.statusCode,
        latency: result.latency,
      );

  Future<void> _record({
    required String code,
    required String model,
    required bool ok,
    int? httpStatus,
    Duration? latency,
  }) async {
    try {
      await recordUsage?.call(
        code: code,
        model: model,
        ok: ok,
        httpStatus: httpStatus,
        latency: latency,
      );
    } on Object {
      // Diagnostics must not alter the conversation result.
    }
  }

  String _instruction(String context) =>
      '''
Kamu adalah Gemini Cloud untuk Asisten Family Finance Manager (FFM).
Gunakan hanya fakta dari KONTEKS TERARAH di bawah ini untuk klaim tentang data pengguna. Jangan mengarang saldo, nominal, akun, kategori, transaksi, tanggal, atau status penyimpanan.

ATURAN WAJIB JAWABAN:
- Jawab PERTANYAAN USER saja. Jangan dump konteks, capability, page info, atau data internal lainnya ke user.
- Jawaban harus RINGKAS: 1-3 kalimat saja kecuali user meminta penjelasan detail.
- Jika pertanyaan tidak berkaitan dengan data keuangan, jawab seperti asisten biasa yang helpful.

Untuk permintaan perubahan data, jangan klaim sudah menyimpan. Jika pengguna jelas meminta membuat/mencatat, keluarkan proposal JSON dengan formatVersion "ffm-assistant-proposal-v1" dan type transaction, master_data, activity, atau memory. Jika wajib kurang, gunakan {"formatVersion":"ffm-assistant-proposal-v1","clarification":"..."}. Jangan tambahkan markdown atau teks lain pada proposal JSON.

Jika jawaban membutuhkan data bulan berjalan yang belum ada di konteks, kamu BOLEH meminta satu capability baca dengan JSON saja. Pilih `read.summary` untuk total/agregat atau `read.transactions` untuk maksimal delapan transaksi terbaru tanpa merchant, rekening, kategori, catatan, maupun ID. `read.transactions` boleh memakai `startDate` dan `endDate` berformat YYYY-MM-DD hanya bila keduanya berada pada bulan berjalan dan rentangnya maksimal 14 hari. Jangan pernah meminta capability lain atau mutasi.

KONTEKS TERARAH FFM:
$context
''';
}
