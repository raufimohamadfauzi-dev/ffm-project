import 'dart:convert';

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
    this.readEvidence,
    this.usageMetadata,
  }) : errorMessage = null;

  const FfmGeminiCloudTurnResult.failure({
    required this.errorMessage,
    required this.model,
    this.statusCode,
    this.latency,
    this.usageMetadata,
  }) : text = null,
       usedReadCapability = null,
       readEvidence = null;

  final String? text;
  final String? errorMessage;
  final String model;
  final int? statusCode;
  final Duration? latency;
  final String? usedReadCapability;
  final String? readEvidence;
  final GeminiUsageMetadata? usageMetadata;

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
    GeminiUsageMetadata? usageMetadata,
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
        tools: _buildTools(),
      );
    } on Object {
      return FfmGeminiCloudTurnResult.failure(
        errorMessage: 'Gemini tidak dapat dihubungi saat ini. Coba lagi nanti.',
        model: model,
      );
    }
    if (!result.ok) return _failure(result);

    var finalText = result.text ?? '';

    if (result.functionCalls != null && result.functionCalls!.isNotEmpty) {
      if (result.functionCalls!.length > 1) {
        return FfmGeminiCloudTurnResult.failure(
          errorMessage:
              'Gemini memanggil ${result.functionCalls!.length} fungsi sekaligus (${result.functionCalls!.map((c) => c.name).join(', ')}). Untuk menjaga kepatuhan dan kebenaran data, hanya satu tindakan per putaran yang diizinkan.',
          model: result.model,
          statusCode: result.statusCode,
          latency: result.latency,
        );
      }
      final call = result.functionCalls!.first;
      final args = call.args;

      if (call.name == 'navigate') {
        final dest = args['destination'] ?? '';
        finalText +=
            '\n{"formatVersion":"ffm-assistant-proposal-v1","navigation":"$dest"}';
      } else if (call.name == 'ask_clarification') {
        final q = args['question'] ?? '';
        finalText +=
            '\n{"formatVersion":"ffm-assistant-proposal-v1","clarification":"$q"}';
      } else if (call.name == 'create_draft') {
        final type = args['type'];
        final props = Map<String, dynamic>.from(args)..remove('type');
        props['type'] = type;
        final jsonStr = jsonEncode({
          "formatVersion": "ffm-assistant-proposal-v1",
          "proposal": props,
        });
        finalText += '\n$jsonStr';
      } else if (call.name == 'read_data') {
        final cap = args['capabilityId'];
        final jsonStr = jsonEncode({
          "formatVersion": "ffm-assistant-capability-request-v1",
          "kind": "read_capability_request",
          "capabilityId": cap,
          if (args['startDate'] != null) "startDate": args['startDate'],
          if (args['endDate'] != null) "endDate": args['endDate'],
        });
        finalText += '\n$jsonStr';
      } else {
        return FfmGeminiCloudTurnResult.failure(
          errorMessage: 'Gemini memanggil fungsi yang tidak diizinkan: ${call.name}.',
          model: result.model,
          statusCode: result.statusCode,
          latency: result.latency,
          usageMetadata: result.usageMetadata,
        );
      }
    }

    final request = FfmAssistantProposalJsonService.parseReadCapabilityRequest(
      finalText,
    );
    if (request.error != null) {
      return FfmGeminiCloudTurnResult.failure(
        errorMessage: request.error!,
        model: result.model,
        statusCode: result.statusCode,
        latency: result.latency,
      );
    }
    String? readEvidence;
    var totalUsage = result.usageMetadata;
    if (request.request != null) {
      String facts;
      try {
        facts = await readCapabilities.execute(
          request.request!,
          householdId: householdId,
          now: clock(),
        );
        readEvidence = facts;
      } on Object {
        return FfmGeminiCloudTurnResult.failure(
          errorMessage: 'Data lokal untuk capability Gemini tidak dapat dibaca dengan aman.',
          model: result.model,
          statusCode: result.statusCode,
          latency: result.latency,
          usageMetadata: totalUsage,
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
        finalText = result.text?.trim() ?? '';
        if (result.usageMetadata != null) {
          totalUsage = GeminiUsageMetadata(
            promptTokenCount: (totalUsage?.promptTokenCount ?? 0) +
                result.usageMetadata!.promptTokenCount,
            candidatesTokenCount: (totalUsage?.candidatesTokenCount ?? 0) +
                result.usageMetadata!.candidatesTokenCount,
            totalTokenCount: (totalUsage?.totalTokenCount ?? 0) +
                result.usageMetadata!.totalTokenCount,
          );
        }
      } on Object {
        return FfmGeminiCloudTurnResult.failure(
          errorMessage: 'Gemini tidak dapat menyelesaikan jawaban setelah membaca data lokal.',
          model: result.model,
          statusCode: result.statusCode,
          latency: result.latency,
          usageMetadata: totalUsage,
        );
      }
      if (!result.ok) return _failure(result);
    }
    return FfmGeminiCloudTurnResult.success(
      text: finalText,
      model: result.model,
      statusCode: result.statusCode,
      latency: result.latency,
      usedReadCapability: request.request?.capabilityId,
      readEvidence: readEvidence,
      usageMetadata: totalUsage,
    );
  }

  Future<GeminiResult> _chat({
    required String key,
    required String model,
    required String userText,
    required String instruction,
    List<Map<String, dynamic>>? tools,
  }) async {
    final result = await _gemini.chat(
      apiKey: key,
      model: model,
      prompt: userText,
      systemInstruction: instruction,
      tools: tools,
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
      usageMetadata: result.usageMetadata,
    );
    return result;
  }

  FfmGeminiCloudTurnResult _failure(GeminiResult result) =>
      FfmGeminiCloudTurnResult.failure(
        errorMessage: result.message,
        model: result.model,
        statusCode: result.statusCode,
        latency: result.latency,
        usageMetadata: result.usageMetadata,
      );

  Future<void> _record({
    required String code,
    required String model,
    required bool ok,
    int? httpStatus,
    Duration? latency,
    GeminiUsageMetadata? usageMetadata,
  }) async {
    try {
      await recordUsage?.call(
        code: code,
        model: model,
        ok: ok,
        httpStatus: httpStatus,
        latency: latency,
        usageMetadata: usageMetadata,
      );
    } on Object {
      // Diagnostics must not alter the conversation result.
    }
  }

  List<Map<String, dynamic>> _buildTools() {
    return [
      {
        'function_declarations': [
          {
            'name': 'navigate',
            'description': 'Membuka halaman tertentu di dalam aplikasi',
            'parameters': {
              'type': 'OBJECT',
              'properties': {
                'destination': {
                  'type': 'STRING',
                  'description': 'Kunci halaman tujuan (misal: summary, transactions, budget, masterData, dst.)',
                },
              },
              'required': ['destination'],
            },
          },
          {
            'name': 'ask_clarification',
            'description': 'Menanyakan detail yang kurang kepada pengguna',
            'parameters': {
              'type': 'OBJECT',
              'properties': {
                'question': {
                  'type': 'STRING',
                  'description': 'Pertanyaan klarifikasi',
                },
              },
              'required': ['question'],
            },
          },
          {
            'name': 'read_data',
            'description': 'Membaca data dari database lokal',
            'parameters': {
              'type': 'OBJECT',
              'properties': {
                'capabilityId': {
                  'type': 'STRING',
                  'description':
                      'Jenis data yang dibaca (${FfmGeminiReadCapabilityPolicy.canonicalToolChoices.join(', ')})',
                },
                'startDate': {
                  'type': 'STRING',
                  'description': 'Tanggal awal YYYY-MM-DD (opsional)',
                },
                'endDate': {
                  'type': 'STRING',
                  'description': 'Tanggal akhir YYYY-MM-DD (opsional)',
                },
              },
              'required': ['capabilityId'],
            },
          },
          {
            'name': 'create_draft',
            'description': 'Membuat draft mutasi atau perubahan data (transaksi, goal, budget, master_data, activity, reminder, memory)',
            'parameters': {
              'type': 'OBJECT',
              'properties': {
                'type': {
                  'type': 'STRING',
                  'description': 'Jenis draft (contoh: expense, income, transfer, goal, goal_deposit, goal_usage, budget, master_data, activity, reminder, memory, liability, receivable, cash_flow_profile)',
                },
                'title': {'type': 'STRING', 'description': 'Judul atau nama'},
                'party': {
                  'type': 'STRING',
                  'description':
                      'Nama pihak terkait: sumber pemasukan untuk income, pemakai dana untuk expense, pemberi pinjaman untuk liability, atau peminjam untuk receivable',
                },
                'amount': {'type': 'NUMBER', 'description': 'Nominal uang'},
                'adminFee': {
                  'type': 'NUMBER',
                  'description': 'Biaya admin transfer jika ada (angka)',
                },
                'fromAccount': {
                  'type': 'STRING',
                  'description': 'Rekening sumber',
                },
                'toAccount': {
                  'type': 'STRING',
                  'description': 'Rekening tujuan',
                },
                'category': {
                  'type': 'STRING',
                  'description': 'Kategori transaksi',
                },
                'merchant': {
                  'type': 'STRING',
                  'description': 'Nama toko/merchant dari daftar toko_aktif di KONTEKS TERARAH',
                },
                'location': {
                  'type': 'STRING',
                  'description': 'Lokasi kejadian transaksi (misalnya pasar, rumah, kantor). Sama dengan kolom Lokasi di form transaksi.',
                },
                'incomeSource': {
                  'type': 'STRING',
                  'description': 'Sumber pemasukan untuk type income (sama dengan kolom Sumber pemasukan di form transaksi)',
                },
                'newMerchant': {
                  'type': 'STRING',
                  'description': 'Nama toko baru yang sama dengan merchant; isi hanya bila toko tersebut belum ada di toko_aktif',
                },
                'receiptNumber': {
                  'type': 'STRING',
                  'description':
                      'Nomor nota / struk / invoice belanja jika ada',
                },
                'paidAmount': {
                  'type': 'NUMBER',
                  'description':
                      'Nominal uang yang dibayarkan jika tercantum di nota',
                },
                'changeAmount': {
                  'type': 'NUMBER',
                  'description': 'Nominal kembalian jika tercantum di nota',
                },
                'items': {
                  'type': 'STRING',
                  'description': 'Daftar rincian item belanjaan (JSON string array of objects {"name": string, "price": number, "qty": number}) jika pengguna menyebutkan detail barang',
                },
                'tags': {
                  'type': 'STRING',
                  'description': 'Daftar tag dipisah koma dari daftar tag_aktif di KONTEKS TERARAH (contoh: "cabai,bawang")',
                },
                'newTags': {
                  'type': 'STRING',
                  'description': 'Daftar tag baru dipisah koma yang belum ada di tag_aktif dan dipakai oleh transaksi ini',
                },
                'monthlyInstallment': {
                  'type': 'NUMBER',
                  'description':
                      'Nominal cicilan per bulan untuk hutang (liability) atau piutang (receivable)',
                },
                'interestRate': {
                  'type': 'NUMBER',
                  'description':
                      'Bunga dalam persen per tahun untuk hutang (liability) atau piutang (receivable)',
                },
                'categoryIds': {
                  'type': 'STRING',
                  'description':
                      'Daftar nama kategori dipisah koma untuk anggaran multi-kategori (type budget)',
                },
                'targetDate': {
                  'type': 'STRING',
                  'description': 'Tanggal YYYY-MM-DD',
                },
                'dueDate': {
                  'type': 'STRING',
                  'description':
                      'Tanggal jatuh tempo YYYY-MM-DD (untuk type liability atau receivable)',
                },
                'period': {
                  'type': 'STRING',
                  'description': 'Periode anggaran untuk type budget: weekly (mingguan), monthly (bulanan), atau nonrecurring (tidak rutin). Wajib diisi bila user menyebut periode; bila user tidak menyebut, kosongkan agar form memakai default.',
                },
                'commodity': {
                  'type': 'STRING',
                  'description': 'Jenis komoditas tani atau bidang usaha untuk type cash_flow_profile (contoh: Padi Ciherang, Cabai, Jagung, Warung Sembako)',
                },
                'initialCapital': {
                  'type': 'NUMBER',
                  'description': 'Modal awal yang dialokasikan untuk siklus kas / tani (angka)',
                },
                'estimatedInflow': {
                  'type': 'NUMBER',
                  'description': 'Estimasi kas masuk / hasil panen saat siklus selesai (angka)',
                },
                'dailyLivingBudget': {
                  'type': 'NUMBER',
                  'description': 'Anggaran harian kebutuhan pokok / dapur keluarga (angka)',
                },
                'dailyOperationalBudget': {
                  'type': 'NUMBER',
                  'description': 'Anggaran biaya operasional harian tani / usaha (angka)',
                },
                'daysRemaining': {
                  'type': 'NUMBER',
                  'description': 'Jumlah hari estimasi menuju panen / pencairan untuk type cash_flow_profile',
                },
                'cycleProfileType': {
                  'type': 'STRING',
                  'description': 'Tipe siklus: agriculture (pertanian/perkebunan), business (usaha/dagang/UMKM), freelance, atau salaried',
                },
                'note': {'type': 'STRING', 'description': 'Catatan tambahan'},
              },
              'required': ['type'],
            },
          },
        ],
      },
    ];
  }

  String _boundedSecondInstruction(String instruction, String facts) {
    const suffix =
        '\n\nSekarang jawab pertanyaan pengguna hanya dari hasil capability dan konteks resmi di atas. Jangan meminta capability baca lagi, dan jangan menyatakan data telah diubah jika belum disetujui pengguna.';
    const header = '\n\nHASIL CAPABILITY LOKAL TERVERIFIKASI:\n';
    final combined = '$instruction$header$facts$suffix';
    if (combined.length <= 8000) return combined;
    final availableForInstruction =
        8000 - header.length - facts.length - suffix.length;
    if (availableForInstruction <= 1000) {
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

ATURAN IDENTITAS APLIKASI & PEMBUAT:
- FFM = Family Finance Manager, aplikasi pengelolaan keuangan keluarga offline-first.
- Pembuat/developer aplikasi ini adalah Rafi Sinkkat.

ATURAN IDENTITAS KELUARGA & SAPAAN:
- Jika di KONTEKS TERARAH terdapat informasi profil keluarga (Nama Keluarga, Suami, Istri dari Data Utama atau Personal Memory):
  * Kenali identitas pengguna atau pasangannya (misal nama suami, nama istri, dan nama keluarga).
  * Gunakan nama panggilan atau sapaan yang hangat dan sopan (misal: "Pak [Nama Suami]", "Bu [Nama Istri]", atau "Keluarga [Nama Keluarga]").
  * Jika pengguna menyebut "istri saya" atau "suami saya", cocokkan secara tepat dengan nama yang tertera di profil Data Utama tanpa perlu bertanya ulang.

ATURAN WAJIB JAWABAN:
- Jawab PERTANYAAN USER saja secara natural dan mengalir.
- Jika pertanyaan tidak berkaitan dengan data keuangan, jawab seperti asisten biasa yang ramah.
- Gunakan bahasa yang personal dan sesuaikan dengan profil user jika ada.

ATURAN ONBOARDING ADAPTIF:
- Jika user menanyakan onboarding, cara mulai, "apa yang harus dilakukan", atau langkah berikutnya, jadilah pemandu penggunaan FFM secara bertahap.
- Jangan hanya mengulang daftar fitur. Jelaskan urutan praktis: (1) lengkapi Data Utama dan rekening, (2) catat transaksi nyata pertama, (3) buat anggaran atau target bila relevan, (4) gunakan Ringkasan/Analisis untuk mengevaluasi, lalu (5) aktifkan pengingat, hutang/piutang, aset, aktivitas, atau fitur lanjutan sesuai kebutuhan.
- Tentukan langkah berikutnya dari VERIFIED FACTS, ANALYSIS RESULTS, dan konteks halaman: jika rekening belum ada, arahkan membuat rekening; jika rekening sudah ada tetapi belum ada transaksi, arahkan mencatat transaksi; jika transaksi sudah ada, arahkan membuat anggaran dan membaca ringkasan. Jangan menyatakan sesuatu sudah terisi bila evidence tidak menunjukkannya.
- Jawab step-by-step dengan contoh input yang bisa langsung diketik pengguna. Setelah setiap tahap, jelaskan indikator selesai dan tanyakan apakah pengguna ingin lanjut ke tahap berikutnya.
- Bila user bertanya "sudah mengisi A, lalu apa?", jangan mengulang tahap A; lanjutkan dari progres terakhir yang terlihat di evidence. Fitur terbaru yang relevan harus dijelaskan bila tersedia di daftar halaman atau konteks aplikasi.

ATURAN NAVIGASI HALAMAN:
- HALAMAN AKTIF SAAT INI tercantum di KONTEKS TERARAH.
- Jika user bertanya tentang fitur di halaman lain, usulkan pindah halaman dengan menggunakan tool `navigate`.
- Daftar halaman: summary, transactions, budget, analysis, otherMenu, masterData, familyProfile, assets, goals, liabilities, activity, reminders, backup, monthlyReport, reconciliation, appSecurity, diagnostics, activityLog, recurringTransaction, privacyCenter, databaseStructure, assistantProfile, intelligenceDashboard, paymentDetector, telegramSetup, agentInbox, autonomyMonitor, hijriSettings, calendarSettings, marketNewsRadar.

ATURAN TEMA TAMPILAN APLIKASI:
- TEMA AKTIF SAAT INI (Mode Terang atau Mode Gelap) tercantum di REASONING CONTEXT.
- Jika pengguna bertanya tentang status tema aplikasi saat ini ("mode apa sekarang?", "apakah ini mode gelap?"), beritahu sesuai data tema aktif di konteks.
- Perintah ganti tema (misal: mode gelap, terang, redup, hitam, putih, malam, siang, ubah mode) dieksekusi secara instan dan realtime oleh kontrol UI aplikasi FFM.

ATURAN DATA & TRANSAKSI:
- Untuk membaca data yang tidak ada di konteks (misal riwayat transaksi detail, target, hutang, piutang, aset, anggaran, aktivitas prioritas, atau pengingat/alarm), gunakan tool `read_data` (pilihan: ${FfmGeminiReadCapabilityPolicy.formattedToolChoices}).
- Kontrak privasi bounded: ${FfmGeminiReadCapabilityPolicy.privacyContractExplanation}
- Untuk membuat/mengubah data (transaksi, transfer, goal, budget, reminder, dll), gunakan tool `create_draft`. Isi parameter yang relevan.
- Fitur transaksi mendukung: pengeluaran/pemasukan dengan rincian belanja (`items`), toko/merchant (`merchant`), lokasi kejadian (`location`), sumber pemasukan (`incomeSource`/`party` untuk pemasukan, `party` untuk dipakai-oleh pengeluaran), nomor nota (`receiptNumber`), nominal dibayar (`paidAmount`), dan kembalian (`changeAmount`); serta transfer saldo antar-rekening (`fromAccount`, `toAccount`, `amount`, dan `adminFee` jika ada biaya admin). Top-up e-wallet ("isi saldo gopay", "top up ovo dari bca") adalah transfer: `toAccount` = e-wallet tujuan, `fromAccount` = sumber bila disebut, bila tidak disebut biarkan kosong agar pengguna memilih — jangan ditebak.
- Fitur hutang & piutang mendukung: catat hutang baru (`type: "liability"`, `title`, `party`, `amount`, `dueDate`, `monthlyInstallment`), catat piutang baru (`type: "receivable"`, `title`, `party`, `amount`, `dueDate`, `monthlyInstallment`), bayar cicilan/pelunasan hutang (`type: "expense"`, `category: "Hutang"`, `note: "Bayar hutang ..."`), dan penerimaan piutang (`type: "income"`, `note: "Penerimaan piutang ..."`).
- Fitur Siklus Kas / AgroTrack: catat siklus kas tani/usaha baru (`type: "cash_flow_profile"`, `title`, `commodity`, `initialCapital`, `estimatedInflow`, `dailyLivingBudget`, `dailyOperationalBudget`, `targetHarvestDate` atau `daysRemaining`, `cycleProfileType`).
- WAJIB KLARIFIKASI: Jika perintah pembuatan data/pengingat/transaksi tidak lengkap atau ambigu (misalnya "buatkan pengingat tanggal 7 Desember" tanpa judul/jam, atau transaksi tanpa nominal), JANGAN mengarang atau menebak sendiri. Gunakan tool `ask_clarification` untuk bertanya balik secara ramah dan spesifik agar draft yang dibuat presisi sesuai keinginan pengguna.
- Nama rekening dan kategori harus sesuai dengan daftar aktif di KONTEKS TERARAH. Tag untuk transaksi diisi dari `tag_aktif`, dipisah koma; toko dari `toko_aktif`.
- Jika user meminta tag atau toko yang belum tersedia, buat SATU draft transaksi saja: isi `tags`/`merchant` dengan nama yang diminta, lalu isi `newTags`/`newMerchant` dengan nama baru tersebut. Aplikasi akan menampilkan seluruh perubahan dalam satu preview, meminta satu konfirmasi, lalu membuat Data Utama dan transaksi secara atomik. Jangan membuat lebih dari satu `create_draft` untuk satu transaksi.
- `newTags` hanya boleh berisi tag yang juga dipakai di `tags` tetapi belum ada di `tag_aktif`. `newMerchant` harus sama persis dengan `merchant` dan hanya boleh diisi bila belum ada di `toko_aktif`. Jangan mengarang nama baru bila user tidak menyebutkannya.
- JANGAN menyatakan bahwa data sudah diubah/disimpan. Kamu hanya membuat draft yang akan diverifikasi oleh aplikasi.

ATURAN HOLISTIK ASET & ANGGARAN:
- Jika pengguna menanyakan analisis keuangan, strategi defisit, atau mencapai target tertentu, gunakan `read.assets` untuk mengecek efisiensi/produkivitas aset dan `read.budget` untuk mengecek sisa alokasi anggaran.
- SEMANTIK ANGGARAN (sama dengan halaman Anggaran; jangan mengarang angka lain): daya tersedia pos = batas + rollover + transferMasuk − transferKeluar; progres = pakai / daya tersedia; sisa = daya tersedia − pakai. Transfer keluar mengurangi daya belanja sehingga progres tidak boleh dihitung dari batas kotor. Setiap baris digest adalah satu pos; jangan menjumlahkan baris pos dengan baris total.
- PERIODE ANGGARAN: pos periodik (mingguan/bulanan/dll.) berganti tiap periode — periode baru memakai pos baru, riwayat periode lalu tetap tersimpan dan tidak dihapus, rollover diisi manual lewat form. Tipe "tidak rutin" tidak pernah reset otomatis sampai diarsipkan.

ATURAN AKTIVITAS & TARGET & PENGINGAT:
- Aktivitas, Target (Goal), dan Pengingat (Reminder) menggunakan `create_draft` (contoh: type "activity", "goal", atau "reminder").
- Untuk melihat pengingat/alarm yang sudah dijadwalkan pengguna, gunakan `read_data` dengan `read.reminders`. Gunakan ini saat user bertanya tentang alarm, jadwal, pengingat, atau ketika kamu perlu mengkorelasikan topik percakapan dengan pengingat yang sudah ada.
- Kalender Hijriah lokal tersedia di konteks, gunakan untuk referensi tanggal Islam.

ATURAN EVALUASI HISTORIS & SARAN PERENCANAAN BULAN DEPAN:
- Jika pengguna meminta evaluasi data masa lalu (misal 3 bulan ke belakang atau bulan lalu) dan menanyakan apa yang harus dilakukan di bulan depan:
  1. Rujuk fakta terverifikasi di ANALYSIS FACTS (rata-rata pengeluaran bulanan, kategori paling boros, tren, dan surplus/defisit).
  2. Berikan 2-3 saran finansial yang konkret, terukur, dan realistis untuk bulan depan (misalnya: menetapkan batas anggaran pada pos terbesar, menabung dana darurat di awal gajian, atau menjaga cicilan tetap aman).
  3. Tawarkan pembuatan draft anggaran (`create_draft` tipe `budget`) atau pengingat (`create_draft` tipe `reminder`) yang relevan untuk membantu pengguna mengeksekusi rencananya.

CAKUPAN LENGKAP PENGELOLA FINANSIAL & OPERASIONAL KELUARGA (FFM):
Asisten FFM adalah pusat kecerdasan holistik keluarga, bukan sekadar chatbot transaksi:
1. Pertanian & Perkebunan: Pahami pengeluaran pembelian pupuk, bibit, pakan ternak, dan pestisida/obat hama sebagai modal kerja tani/kebun. Hubungkan modal ini dengan data panen (bobot, harga jual, dan komoditas) untuk menganalisis laba-rugi riil.
2. Kesehatan & Medis: Tangani pembelian obat, apotek, biaya periksa klinik/dokter, vitamin, dan iuran BPJS/asuransi. Bantu ingatkan pembelian obat rutin bila diperlukan.
3. Belanja Online & Merchant: Kenali belanja di platform e-commerce (Shopee, Tokopedia, TikTok Shop, Lazada), toko fisik, atau pasar lokal. Perhatikan merchant, tag, dan ongkir untuk analisis pos konsumtif vs produktif.
4. Aktivitas & Rutinitas: Kelola sesi kegiatan/tugas keluarga (jadwal pemupukan, ronda, pemeliharaan aset) dan pengingat jatuh tempo komitmen finansial.
Gunakan pemahaman lintas sektor ini untuk memberikan analisis dan saran yang utuh serta relevan dengan kehidupan nyata pengguna.

ATURAN DIAGNOSIS KESEHATAN FINANSIAL & AGROTRACK:
- Jika pengguna meminta evaluasi keuangan, kondisi/rapor finansial ("gimana kondisi keuangan saya", "analisis kesehatan keuangan", "rapor keuangan", "kebocoran uang", "saran keuangan", atau evaluasi panen/agrotrack):
  1. Status & Skor Finansial: Sebutkan skor kesehatan (skor/100) dan predikatnya (Prima, Sehat, Cukup, Perlu Dijaga, atau Perlu Dibenahi) dari `Financial Health Diagnosis` di ANALYSIS FACTS jika tersedia.
  2. Diagnosis 4 Pilar Inti:
     - Arus Kas & Rasio Tabungan (Savings Rate): Beritahu persentase tabungan riil. Jelaskan apakah sudah sehat (ideal minimal 20% dari pemasukan) atau perlu ditingkatkan.
     - Beban Cicilan & Rasio Hutang (DSR): Beritahu beban cicilan terhadap pemasukan. Bila >30%, berikan peringatan lampu kuning/merah agar berhati-hati sebelum mengambil komitmen baru.
     - Ketahanan Dana Darurat: Beritahu berapa bulan biaya hidup yang sanggup dicakup oleh dana tunai/darurat saat ini (target ideal 3-6 bulan pengeluaran keluarga).
     - Kekayaan Bersih (Net Worth): Jelaskan selisih total aset terhadap kewajiban.
  3. Ketahanan Siklus Kas Adaptif / AgroTrack (jika ada siklus aktif di konteks):
     - Rujuk sisa hari menuju panen/inflow berikutnya dan ketahanan kas likuid (runway dalam hari).
     - Ingatkan batas belanja harian dapur/keluarga yang aman (Safe Daily Living Spend) agar modal operasional siklus tidak terpakai habis sebelum panen tiba.
  4. Analisis Kebocoran & Pos Pengeluaran:
     - Soroti pos belanja terbesar (Top Category) dan toko/merchant yang paling sering dikunjungi.
     - Rujuk Health Warnings atau area perhatian jika ada di fakta terverifikasi.
  5. Rekomendasi Terukur & Aksi Nyata (Actionable Close):
     - Berikan 2-3 langkah konkret dan realistis.
     - Akhiri jawaban dengan menawarkan bantuan pembuatan draft konkret (misal: "Mau saya bantu buatkan draft batas anggaran untuk membatasi [Kategori] di Rp X?", atau "Mau saya buatkan draft target tabungan dana darurat?").

ATURAN ANALISIS LAPORAN KEUANGAN & PEMBELAJARAN:
- Jika pengguna meminta evaluasi dari halaman laporan ("analisis laporan ini", "evaluasi laporan", "cari kebocoran uang", "rekomendasi anggaran", dll.):
  1. Rujuk fakta di Konteks Layar / Analysis Facts (pemasukan, pengeluaran, surplus/defisit, rasio tabungan, rasio cicilan, dan pos terbesar).
  2. Jelaskan makna angka secara mendidik (kondisi rasio tabungan apakah sudah sehat ≥20%, beban cicilan apakah aman ≤30%, dan pos pendorong terbesar).
  3. Berikan 2-3 langkah perbaikan yang realistis untuk pembelajaran bulan depan (cara memangkas pos boros, mengunci batas belanja, atau mengalihkan surplus ke target tabungan).
  4. Tawarkan pembuatan draft anggaran (`create_draft` tipe `budget`) atau pengingat jika relevan untuk membantu pengguna mengeksekusi rencananya.

KONTEKS TERARAH FFM:
$context
''';
}
