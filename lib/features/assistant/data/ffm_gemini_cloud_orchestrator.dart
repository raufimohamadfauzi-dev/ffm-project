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
          "formatVersion": "ffm-assistant-proposal-v1",
          "read": {
            "capabilityId": cap,
            if (args['startDate'] != null) "startDate": args['startDate'],
            if (args['endDate'] != null) "endDate": args['endDate'],
          },
        });
        finalText += '\n$jsonStr';
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
        finalText = result.text?.trim() ?? '';
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
      text: finalText,
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
                  'description': 'Jenis data yang dibaca (contoh: read.summary, read.transactions, read.goals, read.liabilities, read.receivables, read.activities, read.reminders, read.assets, read.budget, read.hijriDate)',
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
                  'description': 'Jenis draft (contoh: expense, income, transfer, goal, goal_deposit, goal_usage, budget, master_data, activity, reminder, memory)',
                },
                'title': {'type': 'STRING', 'description': 'Judul atau nama'},
                'amount': {'type': 'NUMBER', 'description': 'Nominal uang'},
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
                'newMerchant': {
                  'type': 'STRING',
                  'description': 'Nama toko baru yang sama dengan merchant; isi hanya bila toko tersebut belum ada di toko_aktif',
                },
                'tags': {
                  'type': 'STRING',
                  'description': 'Daftar tag dipisah koma dari daftar tag_aktif di KONTEKS TERARAH (contoh: "cabai,bawang")',
                },
                'newTags': {
                  'type': 'STRING',
                  'description': 'Daftar tag baru dipisah koma yang belum ada di tag_aktif dan dipakai oleh transaksi ini',
                },
                'targetDate': {
                  'type': 'STRING',
                  'description': 'Tanggal YYYY-MM-DD',
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

ATURAN WAJIB JAWABAN:
- Jawab PERTANYAAN USER saja secara natural dan mengalir.
- Jika pertanyaan tidak berkaitan dengan data keuangan, jawab seperti asisten biasa yang ramah.
- Gunakan bahasa yang personal dan sesuaikan dengan profil user jika ada.

ATURAN NAVIGASI HALAMAN:
- HALAMAN AKTIF SAAT INI tercantum di KONTEKS TERARAH.
- Jika user bertanya tentang fitur di halaman lain, usulkan pindah halaman dengan menggunakan tool `navigate`.
- Daftar halaman: summary, transactions, budget, analysis, otherMenu, masterData, assets, goals, liabilities, activity, reminders, backup, monthlyReport, reconciliation, appSecurity, diagnostics, activityLog, recurringTransaction, privacyCenter, databaseStructure, assistantProfile, intelligenceDashboard.

ATURAN DATA & TRANSAKSI:
- Untuk membaca data yang tidak ada di konteks (misal riwayat transaksi detail, target, hutang, piutang, aset, anggaran, aktivitas prioritas, atau pengingat/alarm), gunakan tool `read_data` (pilihan: `read.summary`, `read.transactions`, `read.goals`, `read.liabilities`, `read.receivables`, `read.activities`, `read.reminders`, `read.assets`, `read.budget`).
- Untuk membuat/mengubah data (transaksi, goal, budget, reminder, dll), gunakan tool `create_draft`. Isi parameter yang relevan.
- WAJIB KLARIFIKASI: Jika perintah pembuatan data/pengingat/transaksi tidak lengkap atau ambigu (misalnya "buatkan pengingat tanggal 7 Desember" tanpa judul/jam, atau transaksi tanpa nominal), JANGAN mengarang atau menebak sendiri. Gunakan tool `ask_clarification` untuk bertanya balik secara ramah dan spesifik agar draft yang dibuat presisi sesuai keinginan pengguna.
- Nama rekening dan kategori harus sesuai dengan daftar aktif di KONTEKS TERARAH. Tag untuk transaksi diisi dari `tag_aktif`, dipisah koma; toko dari `toko_aktif`.
- Jika user meminta tag atau toko yang belum tersedia, buat SATU draft transaksi saja: isi `tags`/`merchant` dengan nama yang diminta, lalu isi `newTags`/`newMerchant` dengan nama baru tersebut. Aplikasi akan menampilkan seluruh perubahan dalam satu preview, meminta satu konfirmasi, lalu membuat Data Utama dan transaksi secara atomik. Jangan membuat lebih dari satu `create_draft` untuk satu transaksi.
- `newTags` hanya boleh berisi tag yang juga dipakai di `tags` tetapi belum ada di `tag_aktif`. `newMerchant` harus sama persis dengan `merchant` dan hanya boleh diisi bila belum ada di `toko_aktif`. Jangan mengarang nama baru bila user tidak menyebutkannya.
- JANGAN menyatakan bahwa data sudah diubah/disimpan. Kamu hanya membuat draft yang akan diverifikasi oleh aplikasi.

ATURAN HOLISTIK ASET & ANGGARAN:
- Jika pengguna menanyakan analisis keuangan, strategi defisit, atau mencapai target tertentu, gunakan `read.assets` untuk mengecek efisiensi/produkivitas aset dan `read.budget` untuk mengecek sisa alokasi anggaran.

ATURAN AKTIVITAS & TARGET & PENGINGAT:
- Aktivitas, Target (Goal), dan Pengingat (Reminder) menggunakan `create_draft` (contoh: type "activity", "goal", atau "reminder").
- Untuk melihat pengingat/alarm yang sudah dijadwalkan pengguna, gunakan `read_data` dengan `read.reminders`. Gunakan ini saat user bertanya tentang alarm, jadwal, pengingat, atau ketika kamu perlu mengkorelasikan topik percakapan dengan pengingat yang sudah ada.
- Kalender Hijriah lokal tersedia di konteks, gunakan untuk referensi tanggal Islam.

KONTEKS TERARAH FFM:
$context
''';
}
