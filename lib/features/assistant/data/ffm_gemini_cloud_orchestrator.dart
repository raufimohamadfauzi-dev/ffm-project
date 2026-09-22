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
  static const int maxReadSteps = 4;
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
    String? conversationHistory,
    GeminiImageInput? image,
    List<GeminiImageInput>? images,
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
    final parsedHistory = conversationHistory != null
        ? _parseConversationHistory(conversationHistory)
        : const <Map<String, String>>[];
    GeminiResult result;
    try {
      result = await _chat(
        key: key.trim(),
        model: model.trim(),
        userText: userText,
        instruction: instruction,
        tools: _buildTools(),
        history: parsedHistory,
        image: image,
        images: images,
      );
    } on Object {
      return FfmGeminiCloudTurnResult.failure(
        errorMessage: 'Gemini tidak dapat dihubungi saat ini. Coba lagi nanti.',
        model: model,
      );
    }
    if (!result.ok) return _failure(result);

    var finalText = result.text ?? '';
    final usedCapabilities = <String>[];
    final accumulatedEvidence = <String>[];
    final seenRequests = <String>{};
    var totalUsage = result.usageMetadata;
    var readStep = 0;

    while (readStep < maxReadSteps) {
      if (result.functionCalls != null && result.functionCalls!.isNotEmpty) {
        // Enforce single function call per turn.
        if (result.functionCalls!.length > 1) {
          return FfmGeminiCloudTurnResult.failure(
            errorMessage: 'Gemini memanggil 2 fungsi sekaligus; hanya satu tindakan per putaran diizinkan.',
            model: result.model,
            statusCode: result.statusCode,
            latency: result.latency,
            usageMetadata: totalUsage,
          );
        }
        // Process the single function call.
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
        } else if (call.name == 'set_theme') {
          final theme = args['theme'] ?? 'system';
          final jsonStr = jsonEncode({
            "formatVersion": "ffm-assistant-proposal-v1",
            "proposal": {
              "type": "set_theme",
              "theme": theme,
            },
          });
          finalText += '\n$jsonStr';
        } else if (call.name == 'set_hijri_adjustment') {
          final adjustment = args['adjustment'] ?? 0;
          final jsonStr = jsonEncode({
            "formatVersion": "ffm-assistant-proposal-v1",
            "proposal": {
              "type": "set_hijri_adjustment",
              "adjustment": adjustment,
            },
          });
          finalText += '\n$jsonStr';
        } else if (call.name == 'market_refresh') {
          final jsonStr = jsonEncode({
            "formatVersion": "ffm-assistant-proposal-v1",
            "proposal": {
              "type": "market_refresh",
            },
          });
          finalText += '\n$jsonStr';
        } else if (call.name == 'read_data') {
          final cap = args['capabilityId'];
          final jsonStr = jsonEncode({
            "formatVersion": "ffm-assistant-capability-request-v1",
            "kind": "read_capability_request",
            "capabilityId": cap,
            "arguments": {
              if (args['startDate'] != null) "startDate": args['startDate'],
              if (args['endDate'] != null) "endDate": args['endDate'],
            },
          });
          finalText += '\n$jsonStr';
        } else {
          return FfmGeminiCloudTurnResult.failure(
            errorMessage:
                'Gemini memanggil fungsi yang tidak diizinkan: ${call.name}.',
            model: result.model,
            statusCode: result.statusCode,
            latency: result.latency,
            usageMetadata: totalUsage,
          );
        }
      }

      final request =
          FfmAssistantProposalJsonService.parseReadCapabilityRequest(finalText);
      if (request.error != null) {
        return FfmGeminiCloudTurnResult.failure(
          errorMessage: request.error!,
          model: result.model,
          statusCode: result.statusCode,
          latency: result.latency,
          usageMetadata: totalUsage,
        );
      }

      // Jika tidak ada permintaan read capability, berhenti dari read loop.
      if (request.request == null) {
        break;
      }

      readStep++;
      final capId = request.request!.capabilityId;
      final reqSignature =
          '$capId:${request.request!.startDate ?? ""}:${request.request!.endDate ?? ""}';

      // Anti-loop: jika permintaan identik sudah dibaca pada giliran ini, hentikan perulangan.
      if (seenRequests.contains(reqSignature)) {
        if (accumulatedEvidence.isNotEmpty) {
          finalText = _friendlyFallback(accumulatedEvidence.join('\n\n'));
        }
        break;
      }
      seenRequests.add(reqSignature);
      usedCapabilities.add(capId);

      String facts;
      try {
        facts = await readCapabilities.execute(
          request.request!,
          householdId: householdId,
          now: clock(),
        );
        accumulatedEvidence.add(facts);
      } on Object {
        return FfmGeminiCloudTurnResult.failure(
          errorMessage: 'Data lokal untuk capability Gemini tidak dapat dibaca dengan aman.',
          model: result.model,
          statusCode: result.statusCode,
          latency: result.latency,
          usageMetadata: totalUsage,
        );
      }

      final isLastAllowedStep = readStep >= maxReadSteps;
      final allFacts = accumulatedEvidence.join('\n\n');

      try {
        final nextInstruction = _boundedInstructionWithEvidence(
          instruction,
          allFacts,
          isFinalStep: isLastAllowedStep,
        );
        result = await _chat(
          key: key.trim(),
          model: model.trim(),
          userText: userText,
          instruction: nextInstruction,
          tools: isLastAllowedStep ? null : _buildTools(),
          image: image,
          images: images,
        );
        finalText = result.text?.trim() ?? '';
        if (result.usageMetadata != null) {
          totalUsage = GeminiUsageMetadata(
            promptTokenCount:
                (totalUsage?.promptTokenCount ?? 0) +
                result.usageMetadata!.promptTokenCount,
            candidatesTokenCount:
                (totalUsage?.candidatesTokenCount ?? 0) +
                result.usageMetadata!.candidatesTokenCount,
            totalTokenCount:
                (totalUsage?.totalTokenCount ?? 0) +
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

      // Jika langkah terakhir tercapai, akhiri loop
      if (isLastAllowedStep) {
        break;
      }
    }

    // Sebelum return success, pastikan teks akhir tidak berupa payload request capability JSON mentah.
    // Jika masih berupa read_capability_request, ganti dengan fallback evidence lokal yang aman.
    final remainingRequest =
        FfmAssistantProposalJsonService.parseReadCapabilityRequest(finalText);
    if (remainingRequest.request != null) {
      if (accumulatedEvidence.isNotEmpty) {
        finalText = _friendlyFallback(accumulatedEvidence.join('\n\n'));
      } else {
        try {
          final facts = await readCapabilities.execute(
            remainingRequest.request!,
            householdId: householdId,
            now: clock(),
          );
          accumulatedEvidence.add(facts);
          finalText = _friendlyFallback(facts);
        } catch (_) {
          finalText = 'Data yang diminta sudah diperiksa pada database lokal.';
        }
      }
    }
    if (finalText.contains('read_capability_request') ||
        finalText.contains(
          'formatVersion":"ffm-assistant-capability-request',
        )) {
      finalText = accumulatedEvidence.isNotEmpty
          ? _friendlyFallback(accumulatedEvidence.join('\n\n'))
          : 'Data yang diminta sudah diperiksa pada database lokal.';
    } else if (finalText.contains('Reminders digest') ||
        (finalText.contains('|waktu=') && finalText.contains('|ulang='))) {
      // Jika model mengembalikan raw digest pipe string, ubah menjadi bahasa manusia
      finalText = _friendlyFallback(finalText);
    } else if (finalText.trim().isEmpty && accumulatedEvidence.isNotEmpty) {
      finalText = _friendlyFallback(accumulatedEvidence.join('\n\n'));
    }

    return FfmGeminiCloudTurnResult.success(
      text: finalText,
      model: result.model,
      statusCode: result.statusCode,
      latency: result.latency,
      usedReadCapability: usedCapabilities.isEmpty
          ? null
          : usedCapabilities.join(', '),
      readEvidence: accumulatedEvidence.isEmpty
          ? null
          : accumulatedEvidence.join('\n\n'),
      usageMetadata: totalUsage,
    );
  }

  Future<GeminiResult> _chat({
    required String key,
    required String model,
    required String userText,
    required String instruction,
    List<Map<String, dynamic>>? tools,
    List<Map<String, String>> history = const [],
    GeminiImageInput? image,
    List<GeminiImageInput>? images,
  }) async {
    final result = await _gemini.chat(
      apiKey: key,
      model: model,
      prompt: userText,
      systemInstruction: instruction,
      tools: tools,
      history: history,
      image: image,
      images: images,
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

  String _friendlyFallback(String rawEvidence) {
    if (rawEvidence.trim().isEmpty) {
      return 'Data sudah diperiksa pada database lokal.';
    }

    var cleaned = rawEvidence
        .replaceAll(
          RegExp(r'FLUTTER_[A-Z_]+:?[^;\n|]*', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'Unhandled exception:[^;\n|]*', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'#\d+\s+[^;\n|]*'), '')
        .replaceAll(
          RegExp(
            r'string is not well-formed UTF-16[^;\n|]*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    if (cleaned.isEmpty) {
      return 'Data sudah diperiksa pada database lokal.';
    }

    if (cleaned.contains('Reminders digest') || cleaned.contains('|waktu=')) {
      if (cleaned.contains('belum ada pengingat aktif')) {
        return 'Saat ini belum ada pengingat atau alarm aktif yang tersimpan.';
      }
      cleaned = cleaned.replaceFirst(
        RegExp(r'^Reminders digest\s*(\([^)]*\))?:\s*', caseSensitive: false),
        '',
      );
      final items = cleaned.split(RegExp(r';\s*|\n+'));
      final buffer = StringBuffer(
        'Berikut daftar pengingat aktif yang terdaftar:\n',
      );
      var validCount = 0;
      for (final item in items) {
        final trimmed = item.trim();
        if (trimmed.isEmpty ||
            trimmed.startsWith('… (+') ||
            trimmed.startsWith('(+')) {
          continue;
        }
        final parts = trimmed.split('|');
        final title = parts.first.replaceAll(RegExp(r'^\s*-\s*'), '').trim();
        if (title.isEmpty) continue;

        String? waktu;
        String? ulang;
        String? catatan;
        for (var i = 1; i < parts.length; i++) {
          final p = parts[i];
          if (p.startsWith('waktu=')) {
            waktu = p.substring('waktu='.length).trim();
          } else if (p.startsWith('ulang=')) {
            ulang = p.substring('ulang='.length).trim();
          } else if (p.startsWith('catatan=')) {
            catatan = p.substring('catatan='.length).trim();
          }
        }

        buffer.write('- **$title**');
        final details = <String>[];
        if (waktu != null && waktu.isNotEmpty) details.add('Waktu: $waktu');
        if (ulang != null && ulang.isNotEmpty && ulang != 'sekali') {
          details.add('Ulang: $ulang');
        }
        if (details.isNotEmpty) {
          buffer.write(' (${details.join(', ')})');
        }
        if (catatan != null &&
            catatan.isNotEmpty &&
            !catatan.contains('FLUTTER_') &&
            catatan != '<NOMINAL>') {
          buffer.write('\n  Catatan: $catatan');
        }
        buffer.writeln();
        validCount++;
      }
      if (validCount > 0) {
        return buffer.toString().trim();
      }
    }

    cleaned = cleaned
        .replaceAll(RegExp(r'\s*\|\s*'), ' • ')
        .replaceAll(RegExp(r'[{}[\]"]'), '');

    return cleaned;
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
            'description': 'Membuat draft mutasi atau perubahan data. Jenis draft yang tersedia: FINANSIAL (expense, income, transfer, transaction_update, transaction_archive, transaction_delete), TARGET (goal, goal_deposit, goal_usage, goal_update, goal_archive), HUTANG_PIUTANG (liability, liability_payment, liability_update, liability_archive, receivable, receivable_payment, receivable_update, receivable_archive), ASET (asset, asset_update, asset_archive), ANGGARAN (budget_update, budget_archive), MASTER_DATA (master_data, merchant_update, merchant_archive, merchant_delete, tag_update, tag_archive, tag_delete, income_source_update, income_source_archive, income_source_delete, category_update, category_archive, category_delete, account_update, account_archive, account_delete), PENGINGAT (reminder, reminder_update, reminder_archive, reminder_complete), AKTIVITAS (activity, daily_note, daily_note_archive, task, task_update, task_complete, task_reopen, task_archive, routine, routine_update, routine_mark_complete, routine_unmark_complete, routine_activate, routine_deactivate, routine_archive, schedule, schedule_update, schedule_archive, activity_archive, activity_delete, activity_finish, activity_update, activity_edit, meter_reading), TRANSAKSI_BERKALA (recurring_transaction_update, recurring_transaction_archive), PEMANTAUAN (monitoring_job), MEMORY (memory)',
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
                  'description': 'Nama pihak terkait: sumber pemasukan untuk income, pemakai dana untuk expense, pemberi pinjaman untuk liability, atau peminjam untuk receivable',
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
                  'description': 'Nominal cicilan per bulan untuk hutang (liability) atau piutang (receivable)',
                },
                'interestRate': {
                  'type': 'NUMBER',
                  'description': 'Bunga dalam persen per tahun untuk hutang (liability) atau piutang (receivable)',
                },
                'categoryIds': {
                  'type': 'STRING',
                  'description': 'Daftar nama kategori dipisah koma untuk anggaran multi-kategori (type budget)',
                },
                'targetDate': {
                  'type': 'STRING',
                  'description': 'Tanggal YYYY-MM-DD',
                },
                'time': {
                  'type': 'STRING',
                  'description': 'Jam dan menit pengingat format HH:mm (contoh: "08:00", "14:30", "19:00"). Wajib diisi untuk pengingat (type: "reminder").',
                },
                'soundName': {
                  'type': 'STRING',
                  'description': 'Nama nada dering pengingat jika pengguna menyebutkan preferensi nada (contoh: "Standar", "Adzan", "Gentle Bells")',
                },
                'reminderMode': {
                  'type': 'STRING',
                  'description': 'Mode pengingat: "notification" (notifikasi biasa) atau "alarm" (alarm nyaring berdering). Default "notification" kecuali jika pengguna secara eksplisit meminta alarm/jam weker/bunyi nyaring.',
                },
                'destinationRoute': {
                  'type': 'STRING',
                  'description': 'Kunci halaman tujuan yang dibuka saat notifikasi/alarm diklik (contoh: "liabilities" untuk hutang/cicilan, "goals" untuk target, "budget" untuk anggaran, "transactions" untuk transaksi, "activity" untuk aktivitas/tugas).',
                },
                'recurrence': {
                  'type': 'STRING',
                  'description': 'Pengulangan pengingat: "once" (sekali), "daily" (setiap hari), atau "weekly" (setiap pekan). Default "once".',
                },
                'weekdays': {
                  'type': 'STRING',
                  'description': 'Daftar angka hari (1=Senin, 7=Minggu) dipisah koma untuk pengulangan mingguan (contoh: "1,3,5" untuk Senin, Rabu, Jumat).',
                },
                'dueDate': {
                  'type': 'STRING',
                  'description': 'Tanggal jatuh tempo YYYY-MM-DD (untuk type liability atau receivable)',
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
                  'description':
                      'Anggaran biaya operasional harian tani / usaha (angka)',
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
                'meterId': {
                  'type': 'STRING',
                  'description': 'ID meteran untuk type meter_reading (dapatkan dari read.electricity result)',
                },
                'readingKwh': {
                  'type': 'NUMBER',
                  'description': 'Angka pembacaan kWh untuk type meter_reading',
                },
                'meterNumber': {
                  'type': 'STRING',
                  'description': 'Nomor meter/IDPEL untuk metadata utilityProposal (format digits only, 9-13 digit)',
                },
                'tokenCode': {
                  'type': 'STRING',
                  'description': 'Kode token 20 digit untuk metadata utilityProposal',
                },
                'creditedKwh': {
                  'type': 'NUMBER',
                  'description': 'Jumlah kWh yang terisi untuk metadata utilityProposal',
                },
                'timestamp': {
                  'type': 'STRING',
                  'description': 'Timestamp pembelian token untuk metadata utilityProposal (format ISO 8601 atau YYYY-MM-DD)',
                },
              },
              'required': ['type'],
            },
          },
        ],
      },
      {
        'name': 'set_theme',
        'description': 'Mengubah tema tampilan aplikasi (dark, light, atau system)',
        'parameters': {
          'type': 'OBJECT',
          'properties': {
            'theme': {
              'type': 'STRING',
              'description': 'Tema aplikasi: "dark" untuk mode gelap, "light" untuk mode terang, atau "system" untuk mengikuti pengaturan sistem',
            },
          },
          'required': ['theme'],
        },
      },
      {
        'name': 'set_hijri_adjustment',
        'description': 'Mengubah offset kalender Hijriah untuk koreksi Hilal lokal (-2 sampai +2 hari)',
        'parameters': {
          'type': 'OBJECT',
          'properties': {
            'adjustment': {
              'type': 'NUMBER',
              'description': 'Offset hari: -2, -1, 0, 1, atau 2. Default 0 berarti tanpa koreksi',
            },
          },
          'required': ['adjustment'],
        },
      },
      {
        'name': 'market_refresh',
        'description': 'Memperbarui data berita pasar dan kurs valas dari API publik',
        'parameters': {
          'type': 'OBJECT',
          'properties': {},
          'required': [],
        },
      },
    ];
  }

  String _boundedInstructionWithEvidence(
    String instruction,
    String facts, {
    bool isFinalStep = true,
  }) {
    final suffix = isFinalStep
        ? '\n\nSekarang jawab pertanyaan pengguna hanya dari hasil capability dan konteks resmi di atas. Jangan meminta capability baca lagi, dan jangan menyatakan data telah diubah jika belum disetujui pengguna. JANGAN meng-echo pesan teknis mentah seperti "STATUS_DATA_TOKEN_LISTRIK:", "DATA_TOKEN_LISTRIK:", "SNAPSHOT_KEUANGAN:", "DIGEST_TRANSAKSI:", "evidence bounded:", atau label teknis lainnya. Konversi semua informasi menjadi respons alami dalam Bahasa Indonesia.'
        : '\n\nHasil pembacaan data lokal terverifikasi sejauh ini tercantum di atas. Jika masih memerlukan sumber data lain yang relevan, panggil read_data berikutnya; jika data sudah mencukupi, jawab pertanyaan pengguna sekarang secara tuntas. JANGAN meng-echo pesan teknis mentah; konversi menjadi respons alami.';
    const header = '\n\nHASIL CAPABILITY LOKAL TERVERIFIKASI:\n';
    final combined = '$instruction$header$facts$suffix';
    if (combined.length <= 12000) return combined;
    final availableForInstruction =
        12000 - header.length - facts.length - suffix.length;
    if (availableForInstruction <= 1000) {
      return '${instruction.substring(0, (12000 - header.length - facts.length - suffix.length - 1).clamp(500, instruction.length))}…$header$facts$suffix';
    }
    final clippedInstruction = instruction.length > availableForInstruction
        ? '${instruction.substring(0, availableForInstruction - 1)}…'
        : instruction;
    return '$clippedInstruction$header$facts$suffix';
  }

  /// Parses formatted conversation history into structured user/model pairs
  /// suitable for Gemini multi-turn API.
  List<Map<String, String>> _parseConversationHistory(String history) {
    final result = <Map<String, String>>[];
    final lines = history.split('\n');
    final buffer = StringBuffer();
    String? currentRole;

    for (final line in lines) {
      if (line.startsWith('Pengguna: ')) {
        if (currentRole != null && buffer.isNotEmpty) {
          result.add({'role': currentRole, 'text': buffer.toString().trim()});
          buffer.clear();
        }
        currentRole = 'user';
        buffer.writeln(line.substring('Pengguna: '.length));
      } else if (line.startsWith('Asisten: ')) {
        if (currentRole != null && buffer.isNotEmpty) {
          result.add({'role': currentRole, 'text': buffer.toString().trim()});
          buffer.clear();
        }
        currentRole = 'model';
        buffer.writeln(line.substring('Asisten: '.length));
      } else if (line.trimLeft().startsWith('[Draft:') ||
          line.trimLeft().startsWith('[Item') ||
          line.trimLeft().startsWith('[Konteks')) {
        // Skip metadata/draft annotation lines — not part of conversation.
      } else if (currentRole != null && line.trim().isNotEmpty) {
        buffer.writeln(line);
      }
    }

    if (currentRole != null && buffer.isNotEmpty) {
      result.add({'role': currentRole, 'text': buffer.toString().trim()});
    }

    return result;
  }

  String _instruction(String context) =>
      '''
Kamu adalah Gemini Cloud untuk Asisten Family Finance Manager (FFM).
WAKTU LOKAL OTORITATIF SISTEM: ${_gregorianDateContext()}
Gunakan hanya fakta dari KONTEKS TERARAH di bawah ini untuk klaim tentang data pengguna. Jangan mengarang saldo, nominal, akun, kategori, transaksi, tanggal, atau status penyimpanan.

ATURAN IDENTITAS APLIKASI & PEMBUAT:
- FFM = Family Finance Manager, aplikasi pengelolaan keuangan keluarga hybrid: data aplikasi tetap otoritatif, tool deterministik menghitung angka, dan Gemini Cloud membantu memahami/menjelaskan secara natural.
- Pembuat/developer aplikasi ini adalah Rafi Sinkkat.

ATURAN IDENTITAS KELUARGA & SAPAAN:
- Jika di KONTEKS TERARAH terdapat informasi profil keluarga (Nama Keluarga, Suami, Istri dari Data Utama atau Personal Memory):
  * Kenali identitas pengguna atau pasangannya (misal nama suami, nama istri, dan nama keluarga).
  * Gunakan nama panggilan atau sapaan yang hangat dan sopan (misal: "Pak [Nama Suami]", "Bu [Nama Istri]", atau "Keluarga [Nama Keluarga]").
  * Jika pengguna menyebut "istri saya" atau "suami saya", cocokkan secara tepat dengan nama yang tertera di profil Data Utama tanpa perlu bertanya ulang.

ATURAN WAJIB JAWABAN & CAKUPAN TANYA JAWAB:
- Jawab PERTANYAAN USER secara natural, cerdas, dan mengalir dalam Bahasa Indonesia.
- Jangan membatasi diri hanya pada perintah catat data: jawab setiap pertanyaan umum, konsultasi, edukasi keuangan, tips hemat, perbandingan, perhitungan, atau obrolan santai keluarga dengan ramah dan solutif.
- JANGAN meminta tool `read_data` jika pertanyaan bersifat umum, tanya-jawab santai, edukasi, definisi, saran umum, atau mengulas apa yang sudah dibahas di riwayat obrolan.
- Jika data yang dibutuhkan (seperti daftar pengingat, transaksi, atau saldo) SUDAH TERSEDIA di KONTEKS TERARAH di bawah atau HASIL CAPABILITY LOKAL, LANGSUNG gunakan data tersebut untuk menjawab. JANGAN memanggil tool `read_data` untuk data yang sudah ada di konteks!
- Gunakan bahasa yang personal dan sesuaikan dengan profil user jika ada.

ATURAN MEMORI PERCAKAPAN & DAYA TANGGAP:
- Selalu perhatikan riwayat percakapan sebelumnya (BOUNDED CONVERSATION HISTORY). Ingat topik, nama barang, nominal, atau saran yang telah dibahas di putaran percakapan sebelumnya.
- Jika pengguna mengajukan pertanyaan lanjutan (misal: "lalu bagaimana?", "yang tadi maksudnya apa?", "bagaimana dengan yang sebelumnya?"), jawab dengan menyambung konteks percakapan sebelumnya secara runtut.
- Jika pengguna mengirim teks ulang atau menanyakan kembali hal yang sama, tanggapi dengan ramah, jelas, dan percaya diri; jangan pernah mengabaikan atau gagal merespons.
- Tunjukkan pemahaman konteks percakapan yang kuat sehingga pengguna merasa didampingi oleh asisten yang sungguh-sungguh mengingat percakapan mereka.
- Jika jawaban singkat pengguna seperti "mau", "mau dong", "iya", atau "boleh" muncul setelah Asisten menawarkan tindakan spesifik, anggap itu sebagai persetujuan atas tawaran terakhir. Lanjutkan tindakan tersebut dengan konteks lama; jangan kembali ke menu umum atau meminta pengguna mengulang topik. Jika masih ada detail wajib yang kurang, tanyakan hanya detail itu (misalnya jam pengingat), lalu buat draft setelah lengkap.

ATURAN ONBOARDING ADAPTIF:
- Jika user menanyakan onboarding, cara mulai, "apa yang harus dilakukan", atau langkah berikutnya, jadilah pemandu penggunaan FFM secara bertahap.
- Sebelum menjawab "apa yang harus saya lakukan sekarang?" atau "apa yang mau Anda tanyakan kepada saya?", baca STATUS ONBOARDING LOKAL, VERIFIED FACTS, ANALYSIS FACTS, dan halaman aktif. Jangan bertanya hal yang datanya sudah tersedia; tanyakan hanya satu hal yang paling penting dan masih kosong.
- Jangan hanya mengulang daftar fitur. Jelaskan urutan praktis: (1) lengkapi Data Utama dan rekening, (2) catat transaksi nyata pertama, (3) buat anggaran atau target bila relevan, (4) gunakan Ringkasan/Analisis untuk mengevaluasi, lalu (5) aktifkan pengingat, hutang/piutang, aset, aktivitas, atau fitur lanjutan sesuai kebutuhan.
- Tentukan langkah berikutnya dari VERIFIED FACTS, ANALYSIS RESULTS, dan konteks halaman: jika rekening belum ada, arahkan membuat rekening; jika rekening sudah ada tetapi belum ada transaksi, arahkan mencatat transaksi; jika transaksi sudah ada, arahkan membuat anggaran dan membaca ringkasan. Jangan menyatakan sesuatu sudah terisi bila evidence tidak menunjukkannya.
- Bedakan user baru dan user lama berdasarkan STATUS ONBOARDING LOKAL, bukan berdasarkan sapaan atau memory. User baru membutuhkan setup awal; user lama langsung diberi langkah lanjutan yang belum terpenuhi.
- Jawab step-by-step dengan contoh input yang bisa langsung diketik pengguna. Setelah setiap tahap, jelaskan indikator selesai dan tanyakan apakah pengguna ingin lanjut ke tahap berikutnya.
- Bila user bertanya "sudah mengisi A, lalu apa?", jangan mengulang tahap A; lanjutkan dari progres terakhir yang terlihat di evidence. Fitur terbaru yang relevan harus dijelaskan bila tersedia di daftar halaman atau konteks aplikasi.

ATURAN NAVIGASI HALAMAN:
- HALAMAN AKTIF SAAT INI tercantum di KONTEKS TERARAH.
- Jika user bertanya tentang fitur di halaman lain, usulkan pindah halaman dengan menggunakan tool `navigate`.
- Daftar halaman lengkap: summary, transactions, budget, analysis, otherMenu, masterData, familyProfile, assets, goals, liabilities, activity, reminders, backup, monthlyReport, reconciliation, appSecurity, diagnostics, activityLog, recurringTransaction, privacyCenter, databaseStructure, assistantProfile, intelligenceDashboard, paymentDetector, telegramSetup, agentInbox, autonomyMonitor, hijriSettings, calendarSettings, marketNewsRadar, utilityMeter, assistantIssueLog.
- ALIASES PENTING untuk mengenali intent navigasi dengan akurat:
  * Token Listrik/utilityMeter: "token listrik", "listrik", "meteran", "token PLN", "beli token", "cek token", "IDPEL", "nomor meter"
  * Asisten Log/assistantIssueLog: "log asisten", "masalah asisten", "error asisten", "laporan asisten", "jawaban bermasalah"
  * Intelligence Dashboard/assistantProfile: "setup asisten", "konfigurasi asisten", "memori asisten", "Gemini", "Supabase", "koneksi cloud"
  * Agent Inbox/autonomyMonitor: "laporan asisten", "insight", "rekomendasi", "monitoring agent", "otonomi"
  * Payment Detector/paymentDetector: "notifikasi pembayaran", "deteksi pembayaran", "pembayaran otomatis", "notifikasi bank"
  * Telegram Setup/telegramSetup: "bot Telegram", "laporan mingguan", "alarm boncos", "keluarga"
  * Market News Radar/marketNewsRadar: "berita pasar", "harga komoditas", "radar berita", "pasar"
  * Hijri Settings/hijriSettings: "kalender Hijriah", "Hilal", "tanggal Islam", "tanggal Hijriah"
  * Calendar Settings/calendarSettings: "Google Calendar", "smartwatch", "sinkronisasi", "jam tangan pintar"
- Jika user menyebutkan fitur yang tidak ada di daftar di atas, jangan membuat halaman baru. Jelaskan bahwa fitur tersebut belum tersedia dan tawarkan fitur terdekat yang mungkin relevan.
- ATURAN KHUSUS HALAMAN TOKEN LISTRIK (utilityMeter):
  * Capability yang relevan: `read.electricity` untuk membaca data token listrik dan meteran
  * Jika user bertanya tentang data token listrik dan evidence menunjukkan "BELUM_ADA_DATA_PEMBELIAN_TOKEN", usulkan navigasi ke halaman utilityMeter untuk mendaftarkan meteran pertama
  * Jika user ingin melihat detail meteran, riwayat pembelian, atau analisis konsumsi, usulkan navigasi ke halaman utilityMeter
  * Jika user menyebutkan "lihat meteran", "cek meteran", "detail token", atau frasa serupa, usulkan navigasi ke halaman utilityMeter
- Navigasi ke halaman yang sudah ada: Gunakan tool `navigate` dengan destination yang tepat sesuai daftar di atas.

ATURAN STRUKTUR HALAMAN AKTIVITAS & CATATAN HARIAN (`activity`):
- Halaman Aktivitas & Catatan Harian (`activity`) disederhanakan dan leluasa tanpa tumpukan kolom berantakan:
  1. `⏱️ Timer`: Khusus aktivitas berdurasi (sedang berjalan / selesai).
  2. `📝 Catatan Harian`: Menyatukan seluruh catatan teks, log panen, dan catatan kejadian ke dalam satu linimasa terpadu. Catatan tidak harus dibuat setiap hari dan bukan aktivitas bertimer. Tag dianjurkan untuk penyaringan, tetapi tidak wajib.
  3. `Filter Sheet`: Seluruh filter (Kategori, Periode Waktu, Tipe Sesi, Arsip) berada di Bottom Sheet yang dipanggil via tombol filter di sebelah Search Bar.
  4. Bila pengguna meminta membaca atau mencatat peristiwa/panen/teks harian (misal "catat panen 100 kg pepaya"), AI memahami bahwa ini adalah bagian dari Catatan Harian (`daily_note` / `read.dailyNotes`), dan langsung mengarah ke draf atau linimasa Catatan Harian yang benar.

ATURAN TEMA TAMPILAN APLIKASI:
- TEMA AKTIF SAAT INI (Mode Terang atau Mode Gelap) tercantum di REASONING CONTEXT.
- Jika pengguna bertanya tentang status tema aplikasi saat ini ("mode apa sekarang?", "apakah ini mode gelap?"), beritahu sesuai data tema aktif di konteks.
- Perintah ganti tema (misal: mode gelap, terang, redup, hitam, putih, malam, siang, ubah mode) dieksekusi secara instan dan realtime oleh kontrol UI aplikasi FFM.

ATURAN DATA & TRANSAKSI:
- Untuk membaca data yang tidak ada di konteks (misal riwayat transaksi detail, target, hutang, piutang, aset, anggaran, aktivitas prioritas, atau pengingat/alarm), gunakan tool `read_data` (pilihan: ${FfmGeminiReadCapabilityPolicy.formattedToolChoices}).
- Kontrak privasi bounded: ${FfmGeminiReadCapabilityPolicy.privacyContractExplanation}
- Untuk membuat/mengubah data (transaksi, transfer, goal, budget, reminder, dll), gunakan tool `create_draft`. Isi parameter yang relevan.
- REVISI ACTIVE DRAFT & PENANGANAN PENOLAKAN ("bukan" / "salah" / "keliru"):
  * Jika pengguna merespons dengan penolakan atau koreksi (misal: "bukan", "bukan gitu", "salah", "bukan transaksi tapi note", "bukan uang keluar tapi uang masuk", "bukan 50rb tapi 75rb"):
    * Kamu WAJIB LANGSUNG membatalkan atau menyesuaikan asumsi sebelumnya tanpa membela diri.
    * Jika pengguna mengoreksi jenis fitur (misal: "bukan transaksi tapi catatan/note" atau "bukan timer tapi catatan biasa"), SEGERA buat draft atau eksekusi intent yang benar (misal: `create_draft` tipe `daily_note` atau `read.dailyNotes`).
  * Jika terdapat ACTIVE DRAFT di konteks terarah dan pengguna memberikan koreksi detail (misal: "itu uang masuk bukan uang keluar", "ubah jadi pemasukan", "ganti nominal jadi 75rb", "pakai rekening BCA", "kategori Jajan"):
    * Kamu WAJIB memanggil tool `create_draft` dengan membawa seluruh data draft yang sudah disesuaikan agar draft di layar pengguna ter-update.
    * Jika pengguna mengoreksi bahwa transaksi tersebut adalah pemasukan/uang masuk (bukan pengeluaran), ubah parameter `type: "income"`, dan jadikan rekening yang disebut sebagai rekening tujuan (`toAccount`).
    * Sebaliknya jika dari pemasukan menjadi pengeluaran, ubah parameter `type: "expense"`, dan jadikan rekening yang disebut sebagai rekening sumber (`fromAccount`).
- Fitur transaksi mendukung: pengeluaran/pemasukan dengan rincian belanja (`items`), toko/merchant (`merchant`), lokasi kejadian (`location`), sumber pemasukan (`incomeSource`/`party` untuk pemasukan, `party` untuk dipakai-oleh pengeluaran), nomor nota (`receiptNumber`), nominal dibayar (`paidAmount`), dan kembalian (`changeAmount`); serta transfer saldo antar-rekening (`fromAccount`, `toAccount`, `amount`, dan `adminFee` jika ada biaya admin). Top-up e-wallet ("isi saldo gopay", "top up ovo dari bca") adalah transfer: `toAccount` = e-wallet tujuan, `fromAccount` = sumber bila disebut, bila tidak disebut biarkan kosong agar pengguna memilih — jangan ditebak.
- Fitur hutang & piutang mendukung: catat hutang baru (`type: "liability"`, `title`, `party`, `amount`, `dueDate`, `monthlyInstallment`), catat piutang baru (`type: "receivable"`, `title`, `party`, `amount`, `dueDate`, `monthlyInstallment`), bayar cicilan/pelunasan hutang (`type: "liability_payment"`, `targetId`, `amount`, `accountId`, `date`, `note`), dan penerimaan piutang (`type: "receivable_payment"`, `targetId`, `amount`, `accountId`, `date`, `note`). PENTING: Gunakan type yang sesuai (liability_payment/receivable_payment) agar sisa hutang/piutang berkurang otomatis. Jangan gunakan expense/income biasa untuk pembayaran hutang/piutang.
- Fitur Siklus Kas / AgroTrack: catat siklus kas tani/usaha baru (`type: "cash_flow_profile"`, `title`, `commodity`, `initialCapital`, `estimatedInflow`, `dailyLivingBudget`, `dailyOperationalBudget`, `targetHarvestDate` atau `daysRemaining`, `cycleProfileType`).
- WAJIB KLARIFIKASI: Jika perintah pembuatan data/pengingat/transaksi tidak lengkap atau ambigu (misalnya "buatkan pengingat tanggal 7 Desember" tanpa judul/jam, atau transaksi tanpa nominal), JANGAN mengarang atau menebak sendiri. Gunakan tool `ask_clarification` untuk bertanya balik secara ramah dan spesifik agar draft yang dibuat presisi sesuai keinginan pengguna.
- ATURAN WAJIB TAG TRANSAKSI PEMBELIAN / PENGELUARAN:
  * Transaksi pengeluaran/pembelian (`type: "expense"`, belanja, beli barang/jasa) WAJIB memiliki tag penanda.
  * Jika pengguna meminta mencatat pembelian/pengeluaran tetapi BELUM menyebutkan tag (misalnya: "beli pupuk 75rb", "catat belanja beras 100rb"):
    - JANGAN membuat draf tanpa tag atau menebak-nebak tag sendiri.
    - KAMU WAJIB MEMANGGIL tool `ask_clarification` untuk bertanya balik secara ramah dan menyebutkan pilihan tag yang sudah ada dari `tag_aktif` di KONTEKS TERARAH (contoh: "Untuk pembelian ini, mau dikelompokkan ke tag apa? Pilihan yang sudah ada di Data Utama: #kebun, #pribadi, #operasional (atau sebutkan tag baru jika ingin dibuatkan).").
  * Jika pengguna menyebutkan tag baru yang belum ada di `tag_aktif`: langsung buat draf transaksi dengan `newTags: "nama_tag_baru"` dan `tags: "nama_tag_baru"`. Aplikasi akan membuat tag baru di Data Utama dan transaksi secara atomik dalam satu konfirmasi tanpa perlu dialog tambahan.
  * Jika pengguna sudah menyebutkan tag (atau setelah pengguna memilih/menjawab tag dari pertanyaan klarifikasi): SEGERA panggil tool `create_draft` lengkap dengan `tags` (atau `newTags`) beserta detail nominal, rekening, kategori, dsb. agar kartu konfirmasi draf transaksi langsung muncul di layar pengguna.
- Nama rekening dan kategori harus sesuai dengan daftar aktif di KONTEKS TERARAH. Tag untuk transaksi diisi dari `tag_aktif`, dipisah koma; toko dari `toko_aktif`.
- Catatan Harian (`type: "daily_note"`) boleh memakai tag Data Utama. Jika pengguna secara eksplisit meminta tag baru sekaligus mencatat kejadian, buat SATU draft dengan `tags` dan `newTags` berisi nama tag tersebut. Aplikasi akan membuat tag, Catatan Harian, dan relasinya secara atomik setelah satu konfirmasi. Jangan pecah menjadi draft Data Utama terpisah.
- Jika user meminta tag atau toko yang belum tersedia, buat SATU draft transaksi saja: isi `tags`/`merchant` dengan nama yang diminta, lalu isi `newTags`/`newMerchant` dengan nama baru tersebut. Aplikasi akan menampilkan seluruh perubahan dalam satu preview, meminta satu konfirmasi, lalu membuat Data Utama dan transaksi secara atomik. Jangan membuat lebih dari satu `create_draft` untuk satu transaksi.
- JANGAN menyatakan bahwa data sudah diubah/disimpan. Kamu hanya membuat draft yang akan diverifikasi oleh aplikasi.
- ATURAN TRANSPARANSI & EKSEKUSI SARAN: Jangan pernah memberikan janji manis palsu atau mengklaim bisa melakukan tindakan jika kamu belum memanggil tool `create_draft` atau `navigate`. Tawarkan HANYA aksi yang memang bisa dieksekusi oleh aplikasi. Apabila aksi belum dapat dieksekusi otomatis oleh tool, jujurlah kepada pengguna dan berikan panduan langkah demi langkah cara melakukannya secara manual di menu aplikasi. Saat pengguna menyetujui saranmu ("iya", "boleh", "buatkan"), kamu WAJIB memanggil `create_draft` secara langsung agar kartu konfirmasi nyata muncul di layar pengguna.

ATURAN HOLISTIK ASET & ANGGARAN:
- Jika pengguna menanyakan analisis keuangan, strategi defisit, atau mencapai target tertentu, gunakan `read.assets` untuk mengecek efisiensi/produkivitas aset dan `read.budget` untuk mengecek sisa alokasi anggaran.
- SEMANTIK ANGGARAN (sama dengan halaman Anggaran; jangan mengarang angka lain): daya tersedia pos = batas + rollover + transferMasuk − transferKeluar; progres = pakai / daya tersedia; sisa = daya tersedia − pakai. Transfer keluar mengurangi daya belanja sehingga progres tidak boleh dihitung dari batas kotor. Setiap baris digest adalah satu pos; jangan menjumlahkan baris pos dengan baris total.
- PERIODE ANGGARAN: pos periodik (mingguan/bulanan/dll.) berganti tiap periode — periode baru memakai pos baru, riwayat periode lalu tetap tersimpan dan tidak dihapus, rollover diisi manual lewat form. Tipe "tidak rutin" tidak pernah reset otomatis sampai diarsipkan.

ATURAN KHUSUS TOKEN LISTRIK / METERAN:
- Untuk pertanyaan pengecekan keberadaan data (cek/ada/tidak ada/terdaftar/isinya), fokus pada menjawab status data dengan jelas dan akurat berdasarkan data di KONTEKS TERARAH.
- Jangan otomatis menawarkan untuk membuat data baru kecuali user secara eksplisit meminta (menggunakan kata "daftar", "buat", "tambah", "catat", "beli").
- Bedakan antara pertanyaan "cek status" vs "perintah aksi":
  * "ada/tidak ada/terdaftar/berapa/berapa banyak" → jawab status data dengan jelas
  * "daftar/buat/tambah/catat/beli" → tawarkan aksi/draft yang sesuai
- Jika user bertanya hal yang sama atau sangat mirip dengan pertanyaan sebelumnya, berikan respons yang lebih ringkas dan merujuk ke jawaban sebelumnya jika tidak ada perubahan data.
- Data meteran listrik mencakup: IDPEL, nama meteran, nama pelanggan, tarif/daya, token terakhir, riwayat pembelian, dan analisis konsumsi.
- Untuk pertanyaan spesifik per meteran (misal "berapa tagihan rumah A bulan ini?"), gunakan `read.electricity` dan filter berdasarkan nama meteran yang disebut.
- PEMBELIAN TOKEN LISTRIK (DRAFT EXPENSE Dengan UTILITYPROPOSAL):
  * Pembelian token listrik dicatat sebagai `type: "expense"` biasa dengan metadata `utilityProposal` yang menghubungkan transaksi ke halaman Token Listrik.
  * Format metadata utilityProposal:
    ```json
    {
      "metadata": {
        "utilityProposal": {
          "meterId": "uuid-meter",
          "meterNumber": "12345678901",
          "tokenCode": "12345678901234567890",
          "amount": 50000,
          "adminFee": 2500,
          "creditedKwh": 45.5,
          "timestamp": "2026-09-22T10:30:00"
        }
      }
    }
    ```
  * Parameter yang dibutuhkan:
    - `meterId`: ID meteran (dapatkan dari `read.electricity` result atau minta klarifikasi jika user menyebutkan nama meteran)
    - `meterNumber`: Nomor meter/IDPEL (9-13 digit, digits only)
    - `tokenCode`: Kode token 20 digit (opsional, bisa diperoleh dari struk)
    - `amount`: Nominal pembelian (wajib)
    - `adminFee`: Biaya admin (opsional, default 0)
    - `creditedKwh`: Jumlah kWh yang terisi (opsional)
    - `timestamp`: Tanggal pembelian (opsional, default sekarang)
  * Contoh: "beli token listrik 50rb untuk rumah" → panggil `read.electricity` dulu untuk mendapatkan meterId "rumah", lalu buat draft expense dengan metadata utilityProposal
  * Jika user menyebutkan nama meteran tapi meterId tidak tersedia dari `read.electricity`, minta klarifikasi: "Untuk meteran mana? Pilihan yang ada: Rumah (12345678901), Sawah (11223344556)"
  * Jika user menyebutkan nomor meter/IDPEL langsung, gunakan nomor tersebut sebagai `meterNumber` dan minta klarifikasi untuk memastikan nama meteran jika ada lebih dari satu meteran.
- PEMBACAAN METERAN (DRAFT METER_READING):
  * Pembacaan meteran dicatat sebagai `type: "meter_reading"` dengan parameter:
    - `meterId`: ID meteran (dapatkan dari `read.electricity` result)
    - `readingKwh`: Angka pembacaan kWh (wajib)
    - `recordedAt`: Tanggal pembacaan (opsional, default sekarang)
    - `note`: Catatan tambahan (opsional)
  * Contoh: "catat pembacaan meteran rumah 12345 kWh" → panggil `read.electricity` dulu untuk mendapatkan meterId "rumah", lalu buat draft meter_reading
  * Jika user menyebutkan nama meteran tapi meterId tidak tersedia, minta klarifikasi seperti di atas.
- ANALISIS & SOLUSI TOKEN LISTRIK:
  * Untuk pertanyaan analisis konsumsi ("analisis konsumsi listrik", "boros atau hemat listrik saya?", "estimasi habis token"), gunakan `read.electricity` untuk menghitung:
    - Rata-rata harian dan estimasi bulanan dari riwayat pembelian
    - Estimasi kapan token akan habis berdasarkan burn rate
    - Status konsumsi (hemat/sedang/tinggi) berdasarkan biaya per kWh
    - Rekomendasi hemat listrik berdasarkan data konsumsi yang ada
  * Untuk pertanyaan solusi ("bagaimana menghemat listrik", "solusi untuk mengurangi tagihan listrik"), berikan rekomendasi konkret berdasarkan data konsumsi:
    - Jika biaya per kWh > Rp2000: sarankan hemat listrik (matikan peralatan yang tidak dipakai)
    - Jika biaya per kWh > Rp1500: sarankan perhatikan peralatan yang menyala terus
    - Jika biaya per kWh < Rp1500: puji efisiensi dan sarankan pertahankan kebiasaan
  * Analisis memerlukan minimal 2 pembelian token per meteran untuk menghitung burn rate yang akurat.
- PENTING: Jika evidence menunjukkan "BELUM_ADA_DATA_PEMBELIAN_TOKEN" atau status data kosong lainnya, JANGAN meng-echo pesan teknis mentah. Konversi menjadi respons alami dalam Bahasa Indonesia seperti: "Belum ada riwayat pembelian token listrik yang tercatat" atau "Data token listrik masih kosong." Jangan menampilkan format "STATUS_DATA_TOKEN_LISTRIK:", "DATA_TOKEN_LISTRIK:", atau label teknis lainnya ke pengguna. Sama berlaku untuk label lain seperti "SNAPSHOT_KEUANGAN:" atau "DIGEST_TRANSAKSI:".

ATURAN AKTIVITAS & TARGET & PENGINGAT:
- Aktivitas, Target (Goal), dan Pengingat (Reminder) menggunakan `create_draft` (contoh: type "activity", "goal", atau "reminder").
- ATURAN WAJIB PENGINGAT (REMINDER) SUPER LENGKAP:
  * DRAF PENGINGAT HARUS SUPER LENGKAP BESERTA JAM: Draf pengingat (`type: "reminder"`) WAJIB memiliki `title` yang jelas, `targetDate` (format YYYY-MM-DD), dan JAM (`time` format HH:mm, contoh "08:00", "14:30", "19:00"). Jangan membuat draf tanpa jam atau berasumsi jam 00:00!
  * WAJIB KLARIFIKASI JIKA JAM BELUM LENGKAP:
    - Jika pengguna meminta membuat pengingat tetapi BELUM menyebutkan jam/waktu spesifiknya (misalnya: "ingatkan bayar listrik besok", "ingatkan beli pulsa", "buat pengingat bayar pdam tanggal 20"):
      KAMU WAJIB MEMANGGIL tool `ask_clarification` TERLEBIH DAHULU untuk menanyakan jam berapa ingin diingatkan (contoh: "Mau saya ingatkan jam berapa untuk [judul]? Misalnya jam 08:00 pagi atau 19:00 malam?").
      JANGAN memanggil `create_draft` sebelum jam/waktunya jelas!
    - Begitu pengguna menyebutkan jamnya (misal: "jam 8 pagi", "jam 19.30", "pukul 14.00") ATAU jika pengguna sejak awal sudah menyebutkan jam (misal: "ingatkan bayar listrik besok jam 8 pagi"):
      Panggil tool `create_draft` dengan `type: "reminder"`, `title`, `targetDate`, dan `time` (format HH:mm) yang presisi. Jika pengguna meminta alarm nyaring/weker, sertakan `reminderMode: "alarm"`. Jika pengguna meminta pengulangan harian/mingguan (misal: "setiap hari", "tiap hari", "setiap senin"), sertakan `recurrence: "daily"` atau `recurrence: "weekly"` beserta `weekdays: "1"` (1=Senin..7=Minggu).
    - Dengan draf yang super lengkap ini, pengguna tinggal mengklik satu kali konfirmasi tanpa perlu repot mengedit apa pun lagi.
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

ATURAN ANALISIS HALAMAN SPESIFIK:
- Jika user bertanya tentang fitur spesifik di halaman tertentu (contoh: "analisis dari halaman Anggaran", "cek dari halaman Target", "lihat dari halaman Token Listrik"):
  1. Jika HALAMAN AKTIF berbeda dari halaman yang diminta, USULKAN pindah halaman dengan tool `navigate` ke halaman yang relevan.
  2. Jika HALAMAN AKTIF sudah sesuai, gunakan capability read yang sesuai dengan halaman tersebut:
     * Halaman Anggaran → `read.budget`
     * Halaman Target → `read.goals`
     * Halaman Token Listrik → `read.electricity`
     * Halaman Hutang & Piutang → `read.liabilities` atau `read.receivables`
     * Halaman Aset → `read.assets`
     * Halaman Aktivitas → `read.activities`
     * Halaman Pengingat → `read.reminders`
     * Halaman Transaksi → `read.transactions`
     * Halaman Ringkasan → `read.summary`
  3. Setelah mendapatkan data, berikan analisis yang sesuai dengan konteks halaman tersebut.

ATURAN PEMAHAMAN KONTEKS HALAMAN & FITUR:
- Jika user bertanya "apa yang ada di halaman X" atau "isi halaman X":
  1. Jika HALAMAN AKTIF sudah X, gunakan capability read yang sesuai dan jelaskan isi data yang ada.
  2. Jika HALAMAN AKTIF bukan X, USULKAN pindah halaman dengan tool `navigate` ke halaman X, lalu jelaskan bahwa setelah pindah halaman bisa dianalisis lebih detail.
- Jika user bertanya "cara pakai halaman X" atau "bagaimana menggunakan fitur X":
  1. Berikan penjelasan singkat dan praktis tentang cara menggunakan fitur tersebut.
  2. Jika memerlukan aksi konkret, tawarkan untuk membuat draft atau navigasi ke halaman tersebut.

ATURAN PENANGANAN ERROR DATA & DIAGNOSTIK:
- Jika user melaporkan "asisten salah menjawab" atau "asisten tidak bisa akses data":
  1. USULKAN pindah ke halaman "Asisten Log" (assistantIssueLog) untuk melihat masalah yang tercatat.
  2. Jelaskan bahwa di halaman Asisten Log bisa dilihat jawaban yang bermasalah dan bisa diekspor laporan untuk developer.
- Jika `read.electricity` mengembalikan pesan "ADA_DATA_PEMBELIAN_TAPI_TIDAK_DALAM_RENTANG_WAKTU":
  1. Jelaskan bahwa ada data pembelian token tercatat tapi tidak dalam rentang waktu yang diminta.
  2. Sebutkan rentang waktu data yang ada dan tawarkan untuk melihat data dalam rentang waktu tersebut atau tanpa filter tanggal.
- Jika user bertanya "apa yang salah" atau "kenapa tidak bisa akses":
  1. Cek apakah ini masalah data kosong, filter tanggal tidak sesuai, atau error sistem.
  2. Berikan penjelasan jelas dan solusi konkret (perbaiki filter tanggal, pindah halaman, atau buat data baru).

ATURAN PENGATURAN SISTEM:
- Jika user meminta mengubah tema tampilan ("ubah tema jadi gelap", "mode dark", "tema terang", "ikuti sistem"):
  1. Gunakan tool `set_theme` dengan parameter "dark", "light", atau "system".
  2. Jelaskan bahwa tema akan diubah sesuai permintaan.
- Jika user meminta mengoreksi kalender Hijriah ("koreksi Hilal", "geser tanggal Hijriah", "offset Hijriah"):
  1. Gunakan tool `set_hijri_adjustment` dengan parameter -2, -1, 0, 1, atau 2.
  2. Jelaskan bahwa tanggal Hijriah akan digeser sesuai koreksi lokal.
- Jika user meminta refresh data pasar ("refresh berita", "update kurs", "refresh pasar"):
  1. Gunakan tool `market_refresh` untuk memperbarui data dari API publik.
  2. Jelaskan bahwa data berita dan kurs valas akan diperbarui.

KONTEKS TERARAH FFM:
$context
''';

  String _gregorianDateContext() {
    final now = clock().toLocal();
    const weekdays = <String>[
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Minggu',
    ];
    const months = <String>[
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    return '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year} pukul ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} waktu lokal perangkat. Jangan menyebut hari lain sebagai hari ini.';
  }
}
