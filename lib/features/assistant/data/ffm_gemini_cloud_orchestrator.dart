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
          errorMessage: 'Data lokal untuk capability Gemini tidak dapat dibaca dengan aman.',
          model: result.model,
          statusCode: result.statusCode,
          latency: result.latency,
        );
      }
      try {
        final secondInstruction = _boundedSecondInstruction(instruction, facts);
        result = await _chat(
          key: key.trim(),
          model: model.trim(),
          userText: userText,
          instruction: secondInstruction,
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

  String _boundedSecondInstruction(String instruction, String facts) {
    const suffix =
        '\n\nSekarang jawab pertanyaan pengguna hanya dari hasil capability dan konteks resmi di atas. Jangan meminta capability lagi, jangan mengeluarkan JSON, dan jangan menyatakan data telah diubah.';
    const header = '\n\nHASIL CAPABILITY LOKAL TERVERIFIKASI:\n';
    // Satukan ke budget global ~8000 agar panggilan kedua tidak membengkak di luar envelope.
    final combined = '$instruction$header$facts$suffix';
    if (combined.length <= 8000) return combined;
    // Prioritaskan fakta capability; potong instruction terpanjang bila kelebihan.
    final availableForInstruction =
        8000 - header.length - facts.length - suffix.length;
    if (availableForInstruction <= 1000) {
      // Fallback: potong gabungan dari belakang instruction.
      return '${instruction.substring(0, (8000 - header.length - facts.length - suffix.length - 1).clamp(500, instruction.length))}…$header$facts$suffix';
    }
    final clippedInstruction = instruction.length > availableForInstruction
        ? '${instruction.substring(0, availableForInstruction - 1)}…'
        : instruction;
    return '$clippedInstruction$header$facts$suffix';
  }

  String _instruction(String context) =>
      '''
Kamu adalah Gemini Cloud untuk Asisten Family Finance Manager (FFM).
Gunakan hanya fakta dari KONTEKS TERARAH di bawah ini untuk klaim tentang data pengguna. Jangan mengarang saldo, nominal, akun, kategori, transaksi, tanggal, atau status penyimpanan.

ATURAN WAJIB JAWABAN:
- Jawab PERTANYAAN USER saja. Jangan dump konteks, capability, page info, atau data internal lainnya ke user.
- Jawaban harus RINGKAS: 1-3 kalimat saja kecuali user meminta penjelasan detail.
- Jika pertanyaan tidak berkaitan dengan data keuangan, jawab seperti asisten biasa yang helpful.

ATURAN FOLLOW-UP:
- Jika user bertanya tentang sesuatu yang sudah dibahas sebelumnya (contoh: "tentang apa?", "berapa nominalnya?", "yang tadi"), gunakan riwayat percakapan untuk menjawab.
- Jika user bertanya "tentang apa?" atau "maksudnya?", lihat pesan asisten sebelumnya dan jelaskan dengan singkat.
- Jika user merujuk ke transaksi/data yang sudah disebut, gunakan konteks dari riwayat untuk menjawab.
- Jangan minta user mengulang pertanyaan jika konteks sudah ada di riwayat.

ATURAN PERSONAL MEMORY:
- Jika user menyebutkan informasi pribadi yang PENTING dan SPESIFIK (pekerjaan, hobi, nama pasangan, domisili, penghasilan, goal keuangan), AKU HARUS aktif menawarkan untuk mengingatnya.
- Setelah user menyebut info pribadi, tambahkan di akhir jawaban: "Mau saya ingat [info tersebut]? Balas 'ya' kalau mau."
- Jika user sudah punya personal memory di konteks, GUNAKAN untuk menjawab lebih personal. Contoh: kalau tahu user kerja sebagai guru, jawaban bisa lebih relevan dengan profesi guru.
- Jangan menawarkan save untuk info yang terlalu umum atau tidak berguna untuk konteks keuangan.
- Prioritas info yang layak diingat: pekerjaan, penghasilan, hobi, domisili, nama pasangan/anak, goal keuangan.

ATURAN WAJIB DATA UTAMA:
- Jika daftar kategori atau rekening aktif bernilai "(belum ada)", kamu TIDAK BOLEH menggunakan nama kategori/rekening yang tidak ada di daftar tersebut dalam proposal transaksi.
- Untuk transaksi expense/income, nama kategori dan rekening wajib ada di daftar "kategori_aktif" dan "rekening_aktif" pada konteks.
- Untuk transaksi income, jika user menyebut sumber pemasukan (gaji, usaha, dll), cek apakah ada di daftar "sumber_pemasukan_aktif" pada konteks.
- Jika user menyebut nama yang tidak ada di daftar, gunakan clarification untuk menanyakan apakah ingin membuat data utama baru terlebih dahulu.
- Contoh clarification: "Kategori [nama] belum ada di Data Utama. Mau buat dulu lewat perintah 'buat kategori [nama]'?"
- Untuk membuat Data Utama, gunakan type `master_data`, `target`, `name`, `fields`, dan `note` opsional.
- Target `tag` hanya memerlukan `name`; jangan meminta nominal, rekening, atau kategori transaksi.
- Target `kategori` memakai fields `type` (income/expense) dan `defaultBudgetPeriod` (none/weekly/monthly).
- Target `rekening` memakai fields `accountType` (cash/bank/ewallet) dan `openingBalance`.
- Target `toko` atau `sumber_pemasukan` boleh memakai fields `details`.
- Jika `target` atau `name` belum jelas, keluarkan `clarification`; jangan menebak field yang hilang.

UNTUK PERUBAHAN DATA:
- Jika pengguna meminta membuat/mencatat transaksi, anggaran, target, atau data lainnya, KELUARKAN proposal JSON dengan formatVersion "ffm-assistant-proposal-v1" dan type transaction, master_data, activity, goal, budget, atau memory.
- Untuk BEBERAPA item sekaligus, gunakan format array: {"formatVersion":"ffm-assistant-proposal-v1","proposals":[{...},{...}]}.
- Isi field sesuai permintaan user. Jangan klaim sudah menyimpan — draft akan diverifikasi oleh aplikasi.
- Jika informasi kurang, gunakan {"formatVersion":"ffm-assistant-proposal-v1","clarification":"..."} untuk menanyakan detail yang kurang.
- Kamu BOLEH membuat draft transaksi (expense/income/transfer), draft anggaran, draft target, draft aktivitas, atau memory baru.
- Jangan tambahkan markdown atau teks lain pada proposal JSON.
- Jika pengguna mengirim kembali proposal JSON yang sudah dikoreksi, pertahankan `formatVersion` dan `type`. Aplikasi akan memperlakukannya sebagai revisi draft aktif, bukan sebagai data yang sudah tersimpan.

ATURAN TARGET KEUANGAN:
- Untuk membuat target baru, gunakan proposal JSON dengan type "goal", field: title, amount (angka tanpa Rp), targetDate (YYYY-MM-DD), note.
- Contoh: {"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"goal","title":"Liburan ke Jepang","amount":15000000,"targetDate":"2026-12-31","note":"Tabungan bulanan Rp 1.5jt"}}

ATURAN ANGGARAN:
- Untuk membuat anggaran baru, gunakan proposal JSON dengan type "budget", field: title/kategori, amount (limit), note.
- Contoh: {"formatVersion":"ffm-assistant-proposal-v1","proposal":{"type":"budget","title":"Makanan","amount":500000,"note":"Budget bulanan makan"}}

UNTUK PERTANYAAN DATA:
- Jika jawaban membutuhkan data dari database, kamu BOLEH meminta capability baca dengan JSON. Pilih:
  - `read.summary` — total/agregat transaksi bulan berjalan
  - `read.transactions` — maksimal 8 transaksi terbaru tanpa merchant, kategori, rekening, catatan, atau ID
- `read.transactions` boleh memakai `startDate` dan `endDate` berformat YYYY-MM-DD hanya bila keduanya berada pada bulan berjalan dan rentangnya maksimal 14 hari.
- Jangan meminta capability lain, data detail lain, atau mutasi.

ATURAN AKTIVITAS:
- Untuk memulai aktivitas baru, gunakan proposal JSON dengan kind "activity" dan field title, category, notes.
- Untuk menyelesaikan aktivitas, gunakan draft kind "activityFinish" dengan targetId aktivitas yang aktif.
- Untuk menambah checkpoint/update, gunakan draft kind "activityUpdate" dengan targetId dan label (deskripsi checkpoint).
- Untuk edit judul/kategori, gunakan draft kind "activityEdit" dengan targetId dan field baru (title/category).
- Untuk arsip, gunakan draft kind "activityArchive" dengan targetId.
- Untuk hapus permanen, gunakan draft kind "activityDelete" dengan targetId.
- Selalu konfirmasi aktivitas yang akan diubah; jangan eksekusi tanpa persetujuan user.
- Jika ada banyak sesi aktif, tanyakan spesifik aktivitas mana yang dimaksud.
- Aktivitas yang masih berjalan harus diselesaikan sebelum diarsipkan atau dihapus.

KONTEKS TERARAH FFM:
$context
''';
}
