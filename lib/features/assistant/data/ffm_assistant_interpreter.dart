import 'package:drift/drift.dart' hide Column;

import '../../../core/database/app_context.dart';
import '../../../core/database/app_database.dart';
import '../../../core/diagnostics/app_diagnostics_service.dart';
import '../../advisor/domain/usecases/budget_guard_service.dart';
import '../../hijri/domain/hijri_calendar_service.dart';
import 'ffm_assistant_memory_repository.dart';
import 'ffm_assistant_user_model_service.dart';
import 'ffm_assistant_local_memory.dart';
import 'ffm_assistant_local_calendar.dart';
import 'ffm_assistant_proposal_json_service.dart';
import 'ffm_assistant_query_tools.dart';
import 'ffm_assistant_financial_snapshot_service.dart';
import 'ffm_assistant_personalization_repository.dart';
import 'ffm_assistant_typo_normalizer.dart';
import '../domain/ffm_assistant_action_tool.dart';
import '../domain/ffm_assistant_execution_limits.dart';
import '../domain/ffm_assistant_models.dart';
import '../domain/ffm_assistant_self_description.dart';
import '../domain/ffm_assistant_reasoning_context.dart';
import '../domain/ffm_assistant_financial_education.dart';
import 'ffm_assistant_knowledge_base.dart';
import '../domain/ffm_agent_harness.dart';
import 'ffm_agent_plugins.dart';

/// Interpreter lokal berbasis aturan. Ia tidak pernah menulis database; semua
/// perubahan dikembalikan sebagai draft untuk dipreview dan dikonfirmasi user.
import 'ffm_assistant_local_model_gateway.dart';
import 'ffm_local_inference_queue.dart';

class FfmAssistantInterpreter {
  FfmAssistantInterpreter(
    this._database, {
    FfmAssistantLocalMemory? memory,
    FfmAssistantLocalModelGateway? modelGateway,
    DateTime Function()? clock,
    AppDiagnosticsService? diagnostics,
    FfmAssistantSelfDescriptionService? selfDescription,
    FfmAssistantPersonalizationRepository? personalization,
    Future<bool> Function()? slmReadyCheck,
  }) : _memory = memory ?? FfmAssistantLocalMemory(),
       _modelGateway = modelGateway,
       _personalization =
           personalization ?? FfmAssistantPersonalizationRepository(_database),
       _slmReadyCheck = slmReadyCheck,
       _taughtMemory = FfmAssistantMemoryRepository(_database),
       _clock = clock ?? DateTime.now,
       _diagnostics = diagnostics ?? AppDiagnosticsService(),
       _selfDescription =
           selfDescription ?? const FfmAssistantSelfDescriptionService() {
    _financialSnapshot = FfmAssistantFinancialSnapshotService(_database);
    _queryRegistry = FfmAssistantQueryRegistry(_database, clock: _clock);
    _actionRegistry = FfmAssistantContextualActionRegistry(clock: _clock);
    _harness = createDefaultHarness(_database);
  }

  final AppDatabase _database;
  final FfmAssistantLocalMemory _memory;
  final FfmAssistantLocalModelGateway? _modelGateway;
  final FfmAssistantPersonalizationRepository _personalization;
  final Future<bool> Function()? _slmReadyCheck;
  final FfmAssistantMemoryRepository _taughtMemory;
  final DateTime Function() _clock;
  final AppDiagnosticsService _diagnostics;
  final FfmAssistantSelfDescriptionService _selfDescription;
  final _financialEducation = const FfmAssistantFinancialEducationService();
  final _knowledgeBase = const FfmAssistantKnowledgeBase();

  /// Memori entitas sesi — dipakai untuk coreference resolution dalam satu
  /// sesi percakapan. Tidak dipersistensikan ke database.
  final _sessionMemory = _FfmSessionEntityMemory();
  late final FfmAssistantFinancialSnapshotService _financialSnapshot;
  late final FfmAssistantQueryRegistry _queryRegistry;
  late final FfmAssistantContextualActionRegistry _actionRegistry;

  /// Harness modular ala DeepSeek Harness — 14 plugin Mata/Tangan/Logika offline.
  late final FfmAgentHarness _harness;

  Future<bool> _isSlmReady() async {
    final check = _slmReadyCheck;
    if (check == null) return false;
    try {
      return await check();
    } on Object {
      return false;
    }
  }

  Future<List<FfmAssistantIntent>> interpretMany(
    String rawText, {
    FfmAssistantDestination? currentDestination,
    String? pageContext,
    String? lastAssistantMessage,
    String? conversationHistory,
    List<String> capabilityIds = const <String>[],
  }) async {
    final commands = _splitCompositeCommands(rawText);
    if (commands.length >
        FfmAssistantExecutionLimits.maxSubCommandsPerMessage) {
      return [
        FfmAssistantIntent(
          rawText: rawText,
          normalizedText: _normalize(rawText),
          type: FfmAssistantIntentType.unknown,
          confidence: 1,
          response: FfmAssistantExecutionLimits.tooComplexMessage,
        ),
      ];
    }
    if (commands.length <= 1) {
      return [
        await interpret(
          rawText,
          currentDestination: currentDestination,
          pageContext: pageContext,
          lastAssistantMessage: lastAssistantMessage,
          conversationHistory: conversationHistory,
          capabilityIds: capabilityIds,
        ),
      ];
    }
    final results = <FfmAssistantIntent>[];
    for (final command in commands) {
      results.add(
        await interpret(
          command,
          currentDestination: currentDestination,
          pageContext: pageContext,
          lastAssistantMessage: lastAssistantMessage,
          conversationHistory: conversationHistory,
          capabilityIds: capabilityIds,
        ),
      );
    }
    return results;
  }

  // ── PILAR 1: Multi-Action Chaining ─────────────────────────────────────────
  /// Memecah teks perintah majemuk menjadi sub-perintah terpisah.
  ///
  /// Mendukung pemisahan via:
  /// - Tanda baca: `;`, baris baru
  /// - Konjungsi temporal: *lalu*, *kemudian*, *terus*, *selanjutnya*, *setelah itu*
  /// - Konjungsi aditif di antara dua kata kerja aksi: *dan*, *serta*, *juga*
  ///   (hanya jika kedua sisi berisi kata kerja aksi finansial agar kalimat deskriptif
  ///   seperti *"rekening BCA dan Mandiri"* tidak ikut dipecah).
  static List<String> _splitCompositeCommands(String rawText) {
    // Pemisah eksplisit: titik koma, baris baru, konjungsi temporal.
    final explicit = rawText
        .split(
          RegExp(
            r'\s*(?:;|\n|\blalu\b|\bterus\b|\bkemudian\b|\bselanjutnya\b|\bsetelah itu\b)\s*',
            caseSensitive: false,
          ),
        )
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (explicit.length > 1) return explicit;

    // Pemisah aditif: *dan*/*serta*/*juga* di antara dua kata kerja aksi.
    const actionVerbs = <String>[
      'catat',
      'tambah',
      'buat',
      'ingatkan',
      'simpan',
      'transfer',
      'pindahkan',
      'bayar',
      'hapus',
      'ubah',
      'update',
      'buka',
    ];
    final conjPattern = RegExp(r'\b(dan|serta|juga)\b', caseSensitive: false);
    final parts = rawText.split(conjPattern);
    if (parts.length < 2) return [rawText.trim()];

    // Pastikan kedua sisi mengandung kata kerja aksi.
    final result = <String>[];
    var pending = parts[0].trim();
    for (var i = 1; i < parts.length; i++) {
      final next = parts[i].trim();
      final pendingHasVerb = actionVerbs.any((v) => pending.contains(v));
      final nextHasVerb = actionVerbs.any((v) => next.contains(v));
      if (pendingHasVerb && nextHasVerb) {
        result.add(pending);
        pending = next;
      } else {
        pending = '$pending ${parts[i]}'.trim();
      }
    }
    if (pending.isNotEmpty) result.add(pending);
    return result.where((s) => s.isNotEmpty).toList();
  }

  /// Menjawab pertanyaan lanjutan hanya terhadap draft yang masih tertahan.
  /// Tidak ada insert atau update data FFM pada tahap ini.
  Future<List<FfmAssistantIntent>> resolvePendingDialog(
    String rawText,
    FfmAssistantPendingDialog pending, {
    FfmAssistantDestination? currentDestination,
    String? pageContext,
    List<String> capabilityIds = const <String>[],
  }) async {
    final normalized = _normalize(rawText);
    if (_containsAny(normalized, const ['batal', 'jangan jadi'])) {
      return [
        FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.cancel,
          confidence: 1,
          response: 'Oke, draft ini dibatalkan. Belum ada data yang tersimpan.',
        ),
      ];
    }
    final initial = pending.draft;
    if (initial == null) {
      if (pending.missingFields.contains('jenis transaksi')) {
        final isIncome = _containsAny(normalized, const [
          'pemasukan',
          'uang masuk',
          'masuk',
        ]);
        final isExpense = _containsAny(normalized, const [
          'pengeluaran',
          'uang keluar',
          'keluar',
        ]);
        if (isIncome != isExpense) {
          return [
            await interpret(
              '$rawText ${pending.originalRequest}',
              currentDestination: currentDestination,
              pageContext: pageContext,
              capabilityIds: capabilityIds,
            ),
          ];
        }
        return [
          FfmAssistantIntent(
            rawText: rawText,
            normalizedText: normalized,
            type: FfmAssistantIntentType.unknown,
            confidence: .45,
            clarification: 'Aku masih perlu pilih jenisnya dulu: ini pemasukan atau pengeluaran? Tidak ada data yang disimpan.',
          ),
        ];
      }
      return [
        await interpret(
          rawText,
          currentDestination: currentDestination,
          pageContext: pageContext,
          capabilityIds: capabilityIds,
        ),
      ];
    }

    var draft = initial;
    if (pending.missingFields.contains('nominal')) {
      final amount = FfmAssistantAmountParser.parse(normalized);
      if (amount != null) draft = draft.copyWith(amount: amount);
    }
    final accounts = await _activeAccounts();
    final matchingAccounts = accounts
        .where((account) => normalized.contains(account.name.toLowerCase()))
        .toList(growable: false);
    if (matchingAccounts.length == 1) {
      final accountName = matchingAccounts.single.name;
      if (pending.missingFields.contains('rekening asal')) {
        draft = draft.copyWith(fromAccountName: accountName);
      }
      if (pending.missingFields.contains('rekening tujuan')) {
        draft = draft.copyWith(toAccountName: accountName);
      }
    }
    if (draft.kind == FfmAssistantDraftKind.profile) {
      final profileValues = _extractProfileValues(rawText);
      if (profileValues.isNotEmpty) {
        draft = draft.copyWith(
          formValues: {...draft.formValues, ...profileValues},
          note: [
            ...{...draft.formValues, ...profileValues}.entries,
          ].map((entry) => '${entry.key}: ${entry.value}').join('\n'),
        );
      }
    }

    final resolved = _intentForDraft(
      pending.originalRequest,
      _normalize(pending.originalRequest),
      draft,
    );
    if (resolved.needsClarification) {
      final accountMissing =
          (pending.missingFields.contains('rekening asal') ||
              pending.missingFields.contains('rekening tujuan')) &&
          matchingAccounts.isEmpty;
      return [
        FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: resolved.type,
          destination: resolved.destination,
          draft: draft,
          confidence: .6,
          clarification:
              '${resolved.clarification ?? pending.prompt}${accountMissing ? ' Rekening yang kamu sebut belum ada. Sebut rekening yang terdaftar atau buat dulu lewat “tambah rekening [nama]”.' : ''}',
        ),
      ];
    }
    return [
      FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: resolved.type,
        destination: resolved.destination,
        draft: draft,
        confidence: .9,
        response: 'Sip, datanya sudah lengkap. Cek draft ini dulu sebelum kamu simpan.',
      ),
    ];
  }

  Future<FfmAssistantIntent> interpret(
    String rawText, {
    FfmAssistantDestination? currentDestination,
    String? imagePath,
    String? pageContext,
    String? lastAssistantMessage,
    String? conversationHistory,
    List<String> capabilityIds = const <String>[],
  }) async {
    var normalized = _normalize(rawText);

    // Semua guard deterministik berjalan lebih dahulu. Jika tidak menangani
    // permintaan, barulah SLM lokal dicoba sebagai classifier/proposal maker.
    // Dengan urutan ini, PIN, diagnostik, konfirmasi, dan query lokal tidak
    // pernah diserahkan kepada teks bebas dari model.

    // Fallback rule-based
    if (normalized.isEmpty && imagePath == null) {
      return _unknown(
        rawText,
        normalized,
        'Tulis atau ucapkan dulu yang mau kamu lakukan, ya.',
      );
    }

    // Lampiran selalu mendapat kesempatan melalui visi lokal sebelum bantuan
    // halaman aktif atau katalog aturan dapat mengambil alih pertanyaan singkat.
    if (imagePath != null) {
      return _interpretImageRequest(
        rawText,
        normalized,
        imagePath: imagePath,
        currentDestination: currentDestination,
        pageContext: pageContext,
        conversationHistory: conversationHistory,
        capabilityIds: capabilityIds,
      );
    }

    // ── PILAR 0: Kesadaran Konteks Percakapan (Conversational Dialogue Turn) ───
    // Sadari tanggapan pengguna terhadap pertanyaan/sapaan asisten sebelumnya
    // agar dialog terasa terhubung dan alami (misalnya "ada", "iya", "mau").
    final conversationalTurn = await _resolveConversationalDialogueTurn(
      rawText,
      normalized,
      lastAssistantMessage: lastAssistantMessage,
    );
    if (conversationalTurn != null) return conversationalTurn;

    final proposal = FfmAssistantProposalJsonService.parse(
      rawText,
      createdAt: _clock(),
    );
    if (proposal.draft != null) {
      return _intentForDraft(rawText, normalized, proposal.draft!);
    }
    if (proposal.error != null) {
      return _unknown(rawText, normalized, proposal.error!);
    }

    final userProfileIntent = _parseUserProfileMemory(rawText, normalized);
    if (userProfileIntent != null) return userProfileIntent;
    final aliasIntent = _parseAliasMemory(rawText, normalized);
    if (aliasIntent != null) return aliasIntent;
    normalized = await _memory.applyAliases(normalized);
    normalized = await _taughtMemory.applyAliases(normalized);

    // ── PILAR 2: Coreference Resolution ─────────────────────────────────────
    // Selesaikan kata ganti/rujukan ke entitas terakhir yang ada di memori
    // sesi sebelum menjalankan guard deterministik lebih lanjut.
    if (_sessionMemory.hasAnyEntity) {
      normalized = _sessionMemory.resolveCoref(normalized);
    }

    // Kalender Hijriah selalu lebih spesifik daripada jawaban ajaran umum
    // seperti “tanggal berapa sekarang”, jadi harus diprioritaskan.
    if (_isHijriDateRequest(normalized)) {
      final now = _clock();
      final isTomorrow = _containsAny(normalized, const ['besok', 'esok']);
      final targetDate = isTomorrow ? now.add(const Duration(days: 1)) : now;
      final hijri = await HijriCalendarService(_database)
          .convert(AppContext.householdId, targetDate);
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.calendarQuery,
        confidence: 1,
        response:
            'Tanggal Hijriah ${isTomorrow ? 'besok' : 'sekarang'}: ${_formatHijriDate(hijri)}. Ini mengikuti pengaturan Kalender Hijriah FFM di perangkat kamu.',
      );
    }

    final taughtAnswer = await _findTaughtAnswer(normalized);
    if (taughtAnswer != null) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: .95,
        response: taughtAnswer.valueText,
      );
    }

    // ── PILAR 3: Knowledge Base 15 Fitur & Zakat ────────────────────────────
    // Dipanggil sebelum query data atau SLM agar pertanyaan panduan
    // dijawab deterministik tanpa membebani model, KECUALI query analisis data spesifik.
    final isLoanAffordabilityQuery = _containsAny(normalized, const [
      'cicilan maksimal',
      'kemampuan cicilan',
      'kemampuan pinjaman',
      'batas cicilan',
      'bisa pinjam berapa',
      'hitung cicilan',
      'simulasi pinjaman',
      'simulasi kredit',
    ]);
    final financialEducation = isLoanAffordabilityQuery
        ? null
        : _financialEducation.answer(normalized);
    final isActionRequest = _containsAny(normalized, const [
      'buat',
      'tambah',
      'catat',
      'simpan',
      'ubah',
      'hapus',
      'buka',
      'jalankan',
    ]);
    final isQuestion = _containsAny(normalized, const [
      'bagaimana',
      'gimana',
      'cara',
      'apa ',
      'berapa',
      'boleh',
      'sebaiknya',
      'mengapa',
      'kenapa',
      'tips',
    ]);
    if (financialEducation != null && isQuestion && !isActionRequest) {
      final personalContext = await _buildPersonalFinancialContext();
      final contextNote = personalContext.isNotEmpty
          ? '\n\n**Kondisi kamu:** $personalContext'
          : '';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 1,
        response:
            '${financialEducation.title}\n${financialEducation.message}$contextNote',
      );
    }

    final isHowToQuestion = _containsAny(normalized, const [
      'cara',
      'gimana',
      'bagaimana',
      'langkah',
      'tutorial',
      'petunjuk',
    ]);
    final kbEntry = _knowledgeBase.findAnswer(normalized);
    if (kbEntry != null && (isHowToQuestion || normalized.contains('apa'))) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: .97,
        response: '**${kbEntry.title}**\n\n${kbEntry.answer}',
      );
    }

    final calendarAnswer = FfmAssistantLocalCalendar.answer(
      normalized,
      now: _clock(),
    );
    if (calendarAnswer != null) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.calendarQuery,
        confidence: 1,
        response: calendarAnswer,
      );
    }

    final basicQuestion = FfmAssistantCatalog.classifyBasicQuestion(normalized);
    if (basicQuestion != null && !_isNavigationRequest(normalized)) {
      if (basicQuestion.kind == FfmAssistantBasicQuestionKind.completeness) {
        final queryAnswer = await _queryRegistry.tryAnswer(
          normalized,
          householdId: AppContext.householdId,
        );
        if (queryAnswer != null) {
          return FfmAssistantIntent(
            rawText: rawText,
            normalizedText: normalized,
            type: FfmAssistantIntentType.queryData,
            destination: basicQuestion.page.destination,
            confidence: .98,
            response: '${queryAnswer.title}\n${queryAnswer.message}',
          );
        }
      }
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.featureHelp,
        destination: basicQuestion.page.destination,
        confidence: .98,
        response: FfmAssistantCatalog.answerBasicQuestion(basicQuestion),
      );
    }

    // ── GREETING & SAPAAN ──────────────────────────────────────────────────
    if (_containsAny(normalized, const [
      'halo',
      'hai',
      'hello',
      'hi',
      'hei',
      'assalamualaikum',
      "assalamu'alaikum",
      'selamat pagi',
      'selamat siang',
      'selamat sore',
      'selamat malam',
      'tes',
      'test',
      'ping',
    ])) {
      final isSlm = await _isSlmReady();
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 1,
        response:
            'Halo! Aku Asisten FFM, siap membantu mencatat transaksi, mengelola anggaran, memeriksa saldo, atau membaca foto struk belanja.${isSlm ? '\n\n✨ **AI Lokal Aktif**: Model Qwen2-VL 2B siap memproses teks dan foto struk secara offline.' : ''}\n\nAda yang bisa kubantu hari ini?',
      );
    }

    // ── VISION & BACA STRUK CAPABILITY ──────────────────────────────────────
    if (_containsAny(normalized, const [
      'bisa membaca struk',
      'bisa baca struk',
      'bisa baca nota',
      'bisa scan struk',
      'baca struk',
      'baca nota',
      'scan struk',
      'foto struk',
      'baca gambar',
      'bisa lihat gambar',
      'bisa melihat gambar',
      'bisa ocr',
      'bisa vision',
      'ekstrak nota',
      'baca bukti transfer',
    ])) {
      final isSlm = await _isSlmReady();
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 1,
        response: isSlm
            ? 'Ya, aku bisa membaca foto struk belanja, nota, atau bukti transfer secara langsung menggunakan model AI lokal (Qwen2-VL 2B) 100% offline! 📸\n\n**Caranya:** Tekan tombol klip lampiran (📎) di samping kolom input untuk memilih foto dari kamera/galeri. Aku akan mengekstrak toko, tanggal, dan rincian belanja menjadi draf transaksi untuk kamu konfirmasi.'
            : 'Fitur pembacaan struk belanja didukung oleh model AI lokal Qwen2-VL 2B. Model lokal belum aktif di perangkat ini; kamu bisa memasangnya melalui menu **Lainnya** → **Model Asisten Lokal**.',
      );
    }

    if (_containsAny(normalized, const [
      'kamu siapa',
      'kamu itu siapa',
      'anda siapa',
      'asisten siapa',
      'asisten ini siapa',
      'aplikasi apa ini',
      'ini aplikasi apa',
      'ffm itu apa',
      'dia itu siapa',
      'asisten ffm itu apa',
      'siapa pembuat aplikasi',
      'pembuat aplikasi ini siapa',
      'siapa yang membuat kamu',
      'siapa yang buat kamu',
      'siapa pembuatmu',
      'siapa penciptamu',
      'rafi sinkkat siapa',
      'siapa rafi sinkkat',
      'siapa rafi',
      'rafi siapa',
      'creator kamu siapa',
      'dibuat oleh siapa',
      'kamu bisa apa',
      'kamu bisa apa saja',
      'sekarang bisa apa',
      'sekarang bisa apa saja',
      'asisten bisa apa',
      'anda bisa apa',
      'kemampuan kamu',
      'kemampuanmu',
      'kemampuan asisten',
      'apa saja yang kamu bisa',
      'kamu dapat melakukan apa',
      'tugas kamu',
    ])) {
      final slmConfigured = await _isSlmReady();
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.assistantIdentity,
        confidence: 1,
        response: _selfDescription.build(
          slmConfigured: slmConfigured,
          currentDestination: currentDestination,
        ),
      );
    }

    if (_isSlmStatusRequest(normalized)) {
      final isSlmReady = await _isSlmReady();
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        destination: FfmAssistantDestination.localModel,
        confidence: 1,
        response: isSlmReady
            ? 'Ya, AI lokal sedang siap dipakai di perangkat ini. Kamu dapat tetap memakai chat biasa; model lokal hanya membantu memahami bahasa dan gambar, lalu hasilnya tetap diperiksa FFM sebelum menjadi draft.'
            : 'Belum, AI lokal belum siap dipakai di perangkat ini. Chat dan fitur FFM lain tetap dapat digunakan tanpa SLM. Untuk memasangnya, buka Model Asisten Lokal.',
      );
    }

    if (_isCashVerificationStatement(normalized)) {
      return _verifyCashAccount(rawText, normalized);
    }

    if (normalized == 'cash') {
      const clarification =
          'Maksud Cash yang mana? Kamu bisa pilih: cek apakah rekening Cash sudah ada, tambah rekening Cash, atau pakai Cash sebagai sumber transaksi. Aku belum mengubah data apa pun.';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 1,
        response: clarification,
        clarification: clarification,
      );
    }

    if (_isBudgetNavigationRequest(normalized)) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.openPage,
        destination: FfmAssistantDestination.budget,
        confidence: 1,
        response: 'Siap, aku arahkan ke halaman Anggaran. Tekan Buka untuk melihat dan mengatur anggaran.',
      );
    }

    if (_containsAny(normalized, const [
      'data lokal',
      'apa itu data lokal',
      'maksud data lokal',
      'kenapa data lokal',
      'privasi data',
      'keamanan data',
      'apakah data aman',
      'apakah offline',
      'apakah butuh internet',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 1,
        response: '**Data Lokal** berarti seluruh data keuangan keluarga (transaksi, rekening, anggaran, aset, dan catatan hutang) disimpan 100% di penyimpanan internal HP kamu menggunakan database SQLite lokal.\n\n🛡️ **Keunggulan Privasi FFM:**\n- **100% Offline**: Tidak ada data keuangan yang dikirim ke cloud atau server internet.\n- **Tanpa Tracking**: Tidak ada analitik atau pelacakan pihak ketiga.\n- **AI On-Device**: Model AI pembaca struk dan pemroses bahasa alami berjalan mandiri di dalam RAM/chipset HP kamu.',
      );
    }

    if (_isOtherMenuListRequest(normalized)) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.listPages,
        destination: FfmAssistantDestination.otherMenu,
        confidence: 1,
        response:
            'Menu Lainnya memiliki ${FfmAssistantCatalog.otherMenuItems.length} menu berikut beserta fungsinya:\n${FfmAssistantCatalog.listOtherMenuForChat()}',
      );
    }

    if (_containsAny(normalized, const [
      'halaman apa saja',
      'ada berapa halaman',
      'berapa halaman',
      'jumlah halaman',
      'halaman ada berapa',
      'halaman berapa',
      'menu apa saja',
      'fitur apa saja',
      'ada menu apa',
      'menu ada berapa',
      'bisa apa saja',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.listPages,
        confidence: 1,
        response:
            'FFM punya ${FfmAssistantCatalog.pages.length} halaman yang bisa kamu buka. Ini daftar dan fungsi singkatnya:\n${FfmAssistantCatalog.listForChat()}',
      );
    }

    if (_isReadRequest(normalized) &&
        _containsAny(normalized, const ['ulang', 'baca lagi', 'bacakan'])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.readLastResponse,
        confidence: .95,
      );
    }

    if (_containsAny(normalized, const [
      'ada error apa',
      'error apa',
      'error terakhir',
      'cek error',
      'cek bug',
      'kenapa tadi gagal',
      'masalah aplikasi',
    ])) {
      return _diagnosticStatus(rawText, normalized);
    }

    if (_containsAny(normalized, const [
      'lupa pin',
      'lupa kunci aplikasi',
      'pin lupa',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.openPage,
        destination: FfmAssistantDestination.appSecurity,
        confidence: .98,
        response: 'Aku buka Kunci aplikasi. Demi keamanan, PIN tidak bisa diganti tanpa PIN lama. Tekan “Lupa PIN?” untuk melihat langkah reset data aplikasi dan impor cadangan.',
      );
    }

    if (_containsAny(normalized, const [
      'ganti pin',
      'ubah pin',
      'ganti kunci aplikasi',
      'matikan pin',
      'aktifkan pin',
      'buat pin aplikasi',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.openPage,
        destination: FfmAssistantDestination.appSecurity,
        confidence: .98,
        response: 'Siap, aku buka Kunci aplikasi. PIN lama dan PIN baru kamu masukkan di keypad khusus, bukan di chat. Setelah PIN baru kamu ulangi, kamu tetap diminta konfirmasi terakhir sebelum berubah.',
      );
    }

    if (_containsAny(normalized, const [
      'batal',
      'jangan jadi',
      'hapus semua draft',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.cancel,
        confidence: 1,
        response: 'Oke, draft yang sedang dibahas tidak akan disimpan.',
      );
    }
    if (_containsAny(normalized, const [
      'ok simpan',
      'oke simpan',
      'konfirmasi simpan',
      'ya simpan',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.confirm,
        confidence: 1,
      );
    }

    final dailyNoteMutation = await _parseDailyNoteMutation(
      rawText,
      normalized,
    );
    if (dailyNoteMutation != null) return dailyNoteMutation;

    final taskMutation = await _parseTaskMutation(rawText, normalized);
    if (taskMutation != null) return taskMutation;

    final routineMutation = await _parseRoutineMutation(rawText, normalized);
    if (routineMutation != null) return routineMutation;

    final scheduleMutation = await _parseScheduleMutationSafe(
      rawText,
      normalized,
    );
    if (scheduleMutation != null) return scheduleMutation;

    final activityMutation = await _parseActivityMutation(rawText, normalized);
    if (activityMutation != null) return activityMutation;

    final reminderMutation = await _parseReminderMutation(rawText, normalized);
    if (reminderMutation != null) return reminderMutation;

    final assetMutation = await _parseAssetMutation(rawText, normalized);
    if (assetMutation != null) return assetMutation;

    final liabilityMutation = await _parseLiabilityMutation(
      rawText,
      normalized,
    );
    if (liabilityMutation != null) return liabilityMutation;

    final receivableMutation = await _parseReceivableMutation(
      rawText,
      normalized,
    );
    if (receivableMutation != null) return receivableMutation;

    final recurringMutation = await _parseRecurringTransactionMutation(
      rawText,
      normalized,
    );
    if (recurringMutation != null) return recurringMutation;

    final goalMutation = await _parseGoalMutation(rawText, normalized);
    if (goalMutation != null) return goalMutation;

    final transactionMutation = await _parseTransactionMutation(
      rawText,
      normalized,
    );
    if (transactionMutation != null) {
      _sessionMemory.updateFromDraft(
        accountName:
            transactionMutation.draft?.fromAccountName ??
            transactionMutation.draft?.toAccountName,
        categoryName: transactionMutation.draft?.categoryName,
        amount: transactionMutation.draft?.amount,
      );
      return transactionMutation;
    }

    final correction = _parseCorrection(rawText, normalized);
    if (correction != null) return correction;

    if (_isSetupRequest(normalized)) {
      return _setupGuide(rawText, normalized);
    }

    if (_isDraftHelpRequest(normalized)) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 1,
        response: 'Rancangan itu isi sementara yang aku siapkan hanya saat kamu memang minta tambah atau ubah data. Rancangan belum menyimpan apa pun. Di kartu rancangan kamu bisa lihat data yang akan dibuka, benarkan pesan kalau maksudnya salah, lalu pilih “Buka & cek” untuk mengisi form resmi. Kalau cuma bertanya fungsi fitur, aku seharusnya menjawab tanpa membuat rancangan.',
      );
    }

    if (_isDatabaseStructureRequest(normalized) &&
        !_isNavigationRequest(normalized)) {
      final queryAnswer = await _queryRegistry.tryAnswer(
        normalized,
        householdId: AppContext.householdId,
      );
      if (queryAnswer != null) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.queryData,
          confidence: .98,
          response: '${queryAnswer.title}\n${queryAnswer.message}',
        );
      }
    }

    final featureHelp = _isNavigationRequest(normalized)
        ? null
        : _featureHelp(
            rawText,
            normalized,
            currentDestination: currentDestination,
          );
    if (featureHelp != null) return featureHelp;

    if (_isWeeklyAnalysisRequest(normalized)) {
      return _weeklyAnalysis(rawText, normalized);
    }

    if (_isTransactionStats(normalized)) {
      return _transactionStats(rawText, normalized);
    }

    if (_isFinancialWarningRequest(normalized)) {
      return _financialWarnings(rawText, normalized);
    }

    if (_isCurrentPageRequest(normalized) && currentDestination != null) {
      return _currentPageContext(rawText, normalized, currentDestination);
    }

    if (!_isNavigationRequest(normalized)) {
      final queryAnswer = await _queryRegistry.tryAnswer(
        normalized,
        householdId: AppContext.householdId,
      );
      if (queryAnswer != null) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.queryData,
          confidence: .98,
          response: '${queryAnswer.title}\n${queryAnswer.message}',
        );
      }
    }

    if (_containsAny(normalized, const [
      'buat json',
      'bikin json',
      'template json',
    ])) {
      return _jsonTemplateHelp(rawText, normalized);
    }
    if (_containsAny(normalized, const [
      'fungsi json',
      'json buat apa',
      'jelaskan json',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.explainJson,
        destination: FfmAssistantDestination.backup,
        confidence: .9,
        response: 'JSON adalah format data terstruktur. Di FFM, JSON bisa dipakai untuk mengekspor data lokal, menyiapkan prompt ke LLM di luar aplikasi, atau mengimpor batch transaksi sebagai draft. JSON tidak pernah langsung disimpan tanpa kamu cek dan konfirmasi.',
      );
    }
    if (_containsAny(normalized, const [
      'buat laporan',
      'laporan bulan ini',
      'jadi pdf',
      'ke pdf',
      'jadi html',
      'ke html',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.exportReport,
        destination: FfmAssistantDestination.backup,
        confidence: .9,
        response: 'Aku buka Ekspor & cadangan. Pilih PDF atau HTML; laporan akan dibuat dari data lokal pada periode yang kamu pilih.',
      );
    }

    final directDestination = _parseDestination(normalized);
    if (directDestination != null &&
        _containsAny(normalized, const [
          'buka',
          'pindah',
          'ke halaman',
          'ke bagian',
          'arah ke',
          'bawa ke',
          'pergi ke halaman',
          'pergi ke menu',
          'masuk halaman',
          'masuk menu',
          'tampilkan',
        ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.openPage,
        destination: directDestination.destination,
        confidence: .98,
        response:
            'Siap, aku pindahkan kamu ke ${directDestination.name}. Tekan “Buka & cek” kalau sudah siap.',
      );
    }

    if (_isAmbiguousLoan(normalized)) {
      return _unknown(
        rawText,
        normalized,
        'Aku perlu pastikan arahnya dulu: kamu meminjam dari orang itu, atau orang itu meminjam dari kamu? Sebut “hutang” atau “piutang”, ya.',
      );
    }

    // ── HARNESS DISPATCH ──────────────────────────────────────────────────────
    // Plugin Mata / Tangan / Logika berjalan sebelum SLM. Karena semua plugin
    // 100% offline dan deterministik, hasilnya lebih cepat dan lebih hemat
    // memori dibandingkan memanggil model bahasa untuk query yang sudah ada
    // jawaban lokalnya.
    //
    // GUARD: Jika kalimat berisi kata kerja aksi (catat, buat, atur, tambah…),
    // lewati harness agar parser draft rule-based tetap menanganinya.
    final _isActionCommand = RegExp(
      r'\b(catat|buat|tambah|atur|mulai|selesai|simpan|transfer|pindah|bayar|hapus|ubah|update|ingatkan|input)\b',
      caseSensitive: false,
    ).hasMatch(normalized);

    if (!_isActionCommand) {
      final harnessResult = await _harness.dispatch(
        FfmHarnessContext(
          rawText: rawText,
          normalizedText: normalized,
          householdId: AppContext.householdId,
          now: _clock(),
        ),
      );
      if (harnessResult != null) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.queryData,
          confidence: .97,
          response: harnessResult.text,
        );
      }
    }

    final modelIntent = await _tryModelFirst(
      rawText,
      normalized,
      imagePath: imagePath,
      pageContext: pageContext,
      conversationHistory: conversationHistory,
      capabilityIds: capabilityIds,
      currentDestination: currentDestination,
    );
    if (modelIntent != null) {
      if (modelIntent.type == FfmAssistantIntentType.outOfDomain) {
        // Coba klasifikasi lebih lanjut: apakah topik ini masih relevan dengan keuangan?
        final financialHints = _containsAny(normalized, const [
          'asuransi',
          'pajak',
          'investasi',
          'pinjaman',
          'kredit',
          'utang',
          'hutang',
          'gaji',
          'penghasilan',
          'bisnis',
          'usaha',
          'modal',
          'untung',
          'rugi',
          'cashflow',
        ]);
        if (financialHints) {
          return FfmAssistantIntent(
            rawText: rawText,
            normalizedText: normalized,
            type: FfmAssistantIntentType.help,
            confidence: 0.8,
            response:
                'Topik ini masih terkait keuangan, tapi aku belum punya panduan spesifik untuk itu. '
                'Aku bisa bantu dengan:\n'
                '• Mencatat transaksi terkait sebagai draft\n'
                '• Mengecek data keuangan yang sudah ada\n'
                '• Memberikan edukasi dasar tentang topik keuangan\n\n'
                'Coba jelaskan lebih spesifik apa yang ingin kamu lakukan, atau ketik *"bisa apa?"* untuk melihat semua kemampuanku.',
          );
        }
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.outOfDomain,
          confidence: 1,
          response:
              'Maaf, aku dirancang khusus sebagai asisten keuangan keluarga untuk FFM. '
              'Topik ini di luar cakupanku dan di luar fitur yang bisa aku tangani.\n\n'
              'Yang bisa aku bantu:\n'
              '• Mencatat transaksi & mengelola anggaran\n'
              '• Mengecek saldo, progres tabungan, dan analisis pengeluaran\n'
              '• Edukasi keuangan keluarga (budgeting, menabung, utang, investasi dasar)\n'
              '• Membaca foto struk belanja\n\n'
              'Ada yang ingin kamu tanyakan soal keuangan?',
        );
      }
      return modelIntent;
    }
    if (imagePath != null) {
      return _unknown(
        rawText,
        normalized,
        'Maaf, aku tidak bisa memproses foto ini. Coba foto ulang atau pastikan fitur AI lokal sudah terpasang.',
      );
    }

    final accounts = await _activeAccounts();
    final categories = await _activeCategories();
    final contextualDraft = await _actionRegistry.buildDraft(
      input: rawText,
      activePage: currentDestination,
    );
    if (contextualDraft != null) {
      return _intentForDraft(rawText, normalized, contextualDraft);
    }
    final draft = _parseFinancialDraft(
      rawText,
      normalized,
      accounts,
      categories,
    );
    if (draft != null) {
      _sessionMemory.updateFromDraft(
        accountName: draft.fromAccountName ?? draft.toAccountName,
        categoryName: draft.categoryName,
        amount: draft.amount,
      );
      return _intentForDraft(rawText, normalized, draft);
    }

    final mentionsAccount = _containsAny(normalized, const [
      'rekening',
      'akun',
      'bank',
    ]);
    if (FfmAssistantAmountParser.parse(normalized) != null &&
        mentionsAccount &&
        _matchAccount(normalized, accounts) == null) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.unknown,
        confidence: .45,
        clarification: 'Rekening yang kamu sebut belum ada di Data Utama. Ini pemasukan atau pengeluaran? Setelah itu aku siapkan draft dulu—tidak ada yang tersimpan otomatis.',
      );
    }

    return _unknown(
      rawText,
      normalized,
      _unsupportedQuestionHelp(normalized) ??
          (_isKnownFfmFeatureGap(normalized)
              ? 'Pertanyaanmu berkaitan dengan fitur FFM, tetapi pengecekan khususnya belum tersedia di aturan lokal saat ini. Aku simpan sebagai gap fitur di Pengetahuan Asisten pada menu Lainnya supaya bisa disalin atau diekspor untuk update berikutnya. Tidak ada data yang dibuat atau diubah.'
              : 'Aku belum punya jawaban yang pas untuk itu. Kalau ada typo, tekan “Benarkan & kirim ulang”. Kalau pertanyaannya memang belum terjawab, aku simpan di Pengetahuan Asisten pada menu Lainnya. Di sana kamu bisa salin atau ekspor pertanyaannya untuk bahan update aplikasi.'),
    );
  }

  Future<FfmAssistantIntent> _interpretImageRequest(
    String rawText,
    String normalized, {
    required String imagePath,
    required FfmAssistantDestination? currentDestination,
    required String? pageContext,
    required String? conversationHistory,
    required List<String> capabilityIds,
  }) async {
    final modelIntent = await _tryModelFirst(
      rawText,
      normalized,
      imagePath: imagePath,
      pageContext: pageContext,
      conversationHistory: conversationHistory,
      capabilityIds: capabilityIds,
      currentDestination: currentDestination,
    );
    if (modelIntent != null) return modelIntent;
    final diagnostics = _modelGateway is FfmAssistantVisionDiagnostics
        ? _modelGateway as FfmAssistantVisionDiagnostics
        : null;
    final visionFailure =
        diagnostics?.lastVisionFailure ??
        const FfmAssistantVisionFailure(
          FfmAssistantVisionFailureCode.proposalRejected,
        );
    return _unknown(
      rawText,
      normalized,
      '${visionFailure.userMessage}${visionFailure.code == FfmAssistantVisionFailureCode.proposalRejected || visionFailure.code == FfmAssistantVisionFailureCode.responseInvalid ? ' Kamu boleh mencoba lampirkan ulang gambar yang lebih jelas.' : ''}',
      responseOrigin: FfmAssistantResponseOrigin.localFallback,
      visionFailure: visionFailure,
    );
  }

  /// Memahami respon percakapan multi-turn yang menanggapi pesan/pertanyaan
  /// asisten sebelumnya (seperti sapaan, tawaran bantuan, atau klarifikasi).
  Future<FfmAssistantIntent?> _resolveConversationalDialogueTurn(
    String rawText,
    String normalized, {
    String? lastAssistantMessage,
  }) async {
    if (lastAssistantMessage == null || lastAssistantMessage.trim().isEmpty) {
      return null;
    }
    final normalizedLast = _normalize(lastAssistantMessage);
    final words = normalized.trim().split(RegExp(r'\s+'));
    if (words.length > 7) return null;

    final isGreetingLast =
        normalizedLast.contains('ada yang bisa kubantu') ||
        normalizedLast.contains('bisa aku bantu') ||
        normalizedLast.contains('siap membantu') ||
        normalizedLast.contains('halo') ||
        normalizedLast.contains('hai');

    // 1. Kasus Penolakan / Selesai ("tidak", "enggak", "belum", "makasih", "cukup", "gak ada")
    final isNegativeOrDone = _containsAny(normalized, const [
      'tidak',
      'enggak',
      'nggak',
      'belum',
      'cukup',
      'makasih',
      'terima kasih',
      'nanti dulu',
      'sudah',
      'udah',
      'gak ada',
      'ngga ada',
      'ga ada',
    ]);

    if (isGreetingLast && isNegativeOrDone) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 0.98,
        response: 'Baik, tidak masalah! Jika sewaktu-waktu butuh bantuan mencatat transaksi atau mengecek anggaran, tinggal sapa aku lagi ya. Selamat beraktivitas!',
      );
    }

    // 2. Kasus Sapaan & Penawaran Bantuan Afirmatif ("ada", "iya", "mau", "bisa", dsb.)
    final isAffirmative = _containsAny(normalized, const [
      'ada',
      'iya',
      'ya',
      'yep',
      'yup',
      'mau',
      'bisa',
      'oke',
      'ok',
      'tolong',
      'bantu',
      'siap',
      'lanjut',
      'dong',
      'tentu',
      'boleh',
    ]);

    if (isGreetingLast && isAffirmative) {
      final isSlm = await _isSlmReady();
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 0.98,
        response:
            'Sip! Aku siap membantu. Kamu bisa langsung ketik atau pilih tindakan berikut:\n\n'
            '• **Catat transaksi** — contoh: *"catat beli makan 25rb"* atau *"gaji masuk 5jt"*\n'
            '• **Cek ringkasan keuangan** — contoh: *"berapa saldo sekarang"* atau *"anggaran bulan ini"*\n'
            '• **Evaluasi pinjaman** — contoh: *"apakah bisa ambil cicilan 500rb per bulan"*\n'
            '• **Foto struk belanja** — tekan tombol klip (📎) untuk baca struk offline${isSlm ? ' (didukung AI Qwen2-VL)' : ''}\n\n'
            'Ada yang ingin kamu mulai terlebih dahulu?',
      );
    }

    // 3. Kasus Permintaan Lanjut ("lanjut", "bagaimana", "lalu apa", "terus gimana")
    if (_containsAny(normalized, const [
      'lanjut',
      'terus',
      'lalu apa',
      'bagaimana',
    ])) {
      if (normalizedLast.contains('draft') || normalizedLast.contains('draf')) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.help,
          confidence: 0.95,
          response: 'Kamu bisa meninjau draf di atas lalu tekan **Simpan** untuk mencatatnya, atau tulis koreksinya jika ada nominal/kategori yang ingin diubah.',
        );
      }
    }

    // 4. Kasus Keraguan / Thinking ("hmm", "bentar", "bentar ya", "sebentar")
    if (_containsAny(normalized, const [
      'hmm',
      'hm',
      'hmmmm',
      'bentar',
      'bentar ya',
      'sebentar',
      'tunggu',
      'tunggu ya',
      'thinking',
    ])) {
      if (normalizedLast.contains('draft') || normalizedLast.contains('draf')) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.help,
          confidence: 0.95,
          response: 'Take your time! Draft-nya masih aman di atas. Kalau sudah yakin, tekan **Simpan**. Kalau ada yang perlu diubah, tinggal bilang aja.',
        );
      }
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 0.9,
        response:
            'Silakan ambil waktu. Aku di sini kalau sudah siap melanjutkan.',
      );
    }

    // 5. Kasus Pujian ("bagus", "keren", "hebat", "mantap", "top")
    if (_containsAny(normalized, const [
      'bagus',
      'keren',
      'hebat',
      'mantap',
      'top',
      'sip',
      'asik',
      'jos',
      'ok mantap',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 0.95,
        response: 'Makasih! Senang bisa bantu. Kalau butuh bantuan lagi, langsung aja ketik atau bilang apa yang mau dilakukan.',
      );
    }

    // 6. Kasus Kritik ("kurang tepat", "salah", "bukan gitu", "keliru")
    if (_containsAny(normalized, const [
      'kurang tepat',
      'salah',
      'bukan gitu',
      'keliru',
      'kurang',
      'kok salah',
      'terlalu',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 0.9,
        response: 'Maaf ya kalau kurang tepat. Bisa diperjelas lagi apa yang salah atau apa yang kamu mau? Aku akan coba perbaiki.',
      );
    }

    // 7. Kasus Permintaan Penjelasan ("kenapa", "maksudnya", "bisa jelaskan", "gimana caranya")
    if (_containsAny(normalized, const [
      'kenapa',
      'maksudnya',
      'bisa jelaskan',
      'gimana caranya',
      'bagaimana bisa',
      'jelaskan',
      'penjelasan',
    ])) {
      if (normalizedLast.contains('draft') || normalizedLast.contains('draf')) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.help,
          confidence: 0.95,
          response: 'Draft adalah data sementara yang aku siapkan berdasarkan permintaanmu. Draft belum tersimpan ke database — kamu perlu review dan tekan **Simpan** sendiri. Ini untuk memastikan tidak ada yang salah sebelum data benar-benar dicatat.',
        );
      }
      if (normalizedLast.contains('transfer')) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.help,
          confidence: 0.95,
          response: 'Transfer di FFM adalah pemindahan dana antar rekening milikmu. Transfer tidak mengubah total kekayaan bersih, hanya memindahkan saldo dari satu dompet ke dompet lain. Biaya admin transfer dicatat sebagai pengeluaran terpisah.',
        );
      }
      if (normalizedLast.contains('anggaran') ||
          normalizedLast.contains('budget')) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.help,
          confidence: 0.95,
          response: 'Anggaran membantu kamu membatasi pengeluaran per kategori dalam satu periode. FFM akan memantau pengeluaran aktual terhadap batas yang kamu tetapkan dan memberi peringatan saat mendekati batas.',
        );
      }
    }

    // 8. Kasus "Apa lagi yang bisa kamu lakukan?" / "Apa selanjutnya?"
    if (_containsAny(normalized, const [
      'apa lagi',
      'apa selanjutnya',
      'apa yang bisa',
      'bisa apa lagi',
      'fitur lain',
    ])) {
      final isSlm = await _isSlmReady();
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 0.95,
        response:
            'Selain yang tadi, aku juga bisa:\n\n'
            '• **Cek saldo rekening** — *"berapa saldo BCA?"*\n'
            '• **Lihat progres tabungan** — *"progres tabungan liburan"*\n'
            '• **Analisis pengeluaran** — *"kategori mana paling boros?"*\n'
            '• **Hitung zakat** — *"hitung zakat mal"*${isSlm ? '\n• **Baca foto struk** — kirim foto struk belanja' : ''}\n\n'
            'Mau coba yang mana?',
      );
    }

    return null;
  }

  Future<FfmAssistantIntent> _diagnosticStatus(
    String rawText,
    String normalized,
  ) async {
    final latest = await _diagnostics.latestEntry();
    if (latest == null) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.diagnosticStatus,
        destination: FfmAssistantDestination.diagnostics,
        confidence: 1,
        response: 'Belum ada error teknis yang tercatat di FFM. Kalau masalahnya muncul lagi, coba ulangi lalu tanya aku lagi atau buka Bantuan perbaikan untuk salin laporan aman.',
      );
    }
    final time = latest.occurredAt.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final formattedTime =
        '${twoDigits(time.day)}/${twoDigits(time.month)}/${time.year} ${twoDigits(time.hour)}:${twoDigits(time.minute)}';
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.diagnosticStatus,
      destination: FfmAssistantDestination.diagnostics,
      confidence: 1,
      response:
          'Ada error teknis terbaru di ${latest.feature} pada $formattedTime. Kode: ${latest.code}. Ringkasan aman: ${latest.summary}. Dampak: ${latest.impact} Buka Bantuan perbaikan untuk lihat dan salin laporan yang sudah disaring.',
    );
  }

  Future<FfmAssistantIntent?> _tryModelFirst(
    String rawText,
    String normalized, {
    String? imagePath,
    String? pageContext,
    String? conversationHistory,
    List<String> capabilityIds = const <String>[],
    FfmAssistantDestination? currentDestination,
  }) async {
    final gateway = _modelGateway;
    if (gateway == null) return null;
    FfmAssistantModelProposal? proposal;
    try {
      final userContext = await FfmAssistantUserModelService(_taughtMemory)
          .buildContext(query: normalized);
      final evidenceScope = FfmAssistantReasoningEvidencePolicy.forRequest(
        normalized,
      );
      final financialContext = evidenceScope.includeFinancialSummary
          ? _financialSnapshot.buildBoundedPrompt(
              await _financialSnapshot.readCurrentMonth(
                householdId: AppContext.householdId,
                now: _clock(),
              ),
            )
          : '';
      final masterDataContext = evidenceScope.includeMasterData
          ? await _financialSnapshot.buildMasterDataContext(
              householdId: AppContext.householdId,
            )
          : '';
      final personalizationContext = await _personalization
          .buildPersonalizedContext(
            householdId: AppContext.householdId,
            query: normalized,
          );
      final reasoningContext = FfmAssistantReasoningContext(
        request: rawText,
        capturedAt: _clock(),
        currentPage: currentDestination,
        pageSummary: [
          if (pageContext != null && pageContext.trim().isNotEmpty) pageContext,
          financialContext,
          masterDataContext,
        ].join('\\n'),
        capabilityIds: capabilityIds,
        approvedUserContext: userContext,
        personalizationContext: personalizationContext,
        modelReady: true,
        recentTransactions: evidenceScope.includeRecentTransactions
            ? await _recentTransactionSummaries(
                householdId: AppContext.householdId,
              )
            : const <String>[],
      );
      final modelContext = reasoningContext.toBoundedPrompt();
      proposal = await gateway
          .proposeWithContext(
            input: rawText,
            imagePath: imagePath,
            pageContext: modelContext.isEmpty ? null : modelContext,
            conversationHistory: conversationHistory,
            capabilityIds: capabilityIds,
          )
          .timeout(const Duration(seconds: 15), onTimeout: () => null);
    } catch (error) {
      if (error is FfmInferenceCancelledException) rethrow;
      // Native/model failure is not an assistant failure; continue with the
      // deterministic local interpreter below.
      return null;
    }
    if (proposal == null || !proposal.isUsable) return null;

    if (proposal.clarification != null &&
        proposal.clarification!.trim().isNotEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.unknown,
        confidence: proposal.confidence,
        clarification: proposal.clarification!.trim(),
        responseMode: FfmAssistantResponseMode.localModel,
        responseOrigin: FfmAssistantResponseOrigin.localSlm,
      );
    }

    if (proposal.intent == FfmAssistantIntentType.help) {
      final imageObservation = _safeImageObservation(
        imagePath: imagePath,
        message: proposal.notes,
      );
      if (imagePath != null && imageObservation == null) return null;
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: proposal.confidence,
        responseMode: FfmAssistantResponseMode.localModel,
        response: imageObservation,
        responseOrigin: FfmAssistantResponseOrigin.localSlm,
      );
    }

    if (proposal.intent == FfmAssistantIntentType.outOfDomain) {
      final imageObservation = _safeImageObservation(
        imagePath: imagePath,
        message: proposal.notes,
      );
      if (imageObservation != null) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.help,
          confidence: proposal.confidence,
          responseMode: FfmAssistantResponseMode.localModel,
          response: imageObservation,
          responseOrigin: FfmAssistantResponseOrigin.localSlm,
        );
      }
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.outOfDomain,
        confidence: proposal.confidence,
        responseMode: FfmAssistantResponseMode.localModel,
        responseOrigin: FfmAssistantResponseOrigin.localSlm,
      );
    }

    if (proposal.intent == FfmAssistantIntentType.openPage) {
      final target = proposal.actionTarget;
      if (target == null || target.trim().isEmpty) return null;
      final page = _parseDestination(_normalize(target));
      if (page == null) return null;
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.openPage,
        destination: page.destination,
        confidence: proposal.confidence,
        responseMode: FfmAssistantResponseMode.localModel,
        response:
            'Siap, aku pindahkan kamu ke ${page.name}. Tekan “Buka & cek” kalau sudah siap.',
        responseOrigin: FfmAssistantResponseOrigin.localSlm,
      );
    }

    if (proposal.intent == FfmAssistantIntentType.queryData) {
      final answer = await _queryRegistry.tryAnswer(
        normalized,
        householdId: AppContext.householdId,
      );
      if (answer == null) return null;
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.queryData,
        confidence: proposal.confidence,
        responseMode: FfmAssistantResponseMode.localModel,
        response: '${answer.title}\n${answer.message}',
        responseOrigin: FfmAssistantResponseOrigin.localSlm,
      );
    }

    if (proposal.intent == FfmAssistantIntentType.createExpense ||
        proposal.intent == FfmAssistantIntentType.createIncome ||
        proposal.intent == FfmAssistantIntentType.createTransfer) {
      final draft = proposal.draft;
      if (draft == null) return null;
      // Reuse deterministic validation and clarification rules. The model never
      // gets to choose account/category IDs or write to the database.
      final validated = _intentForDraft(rawText, normalized, draft);
      return validated.copyWith(
        responseMode: FfmAssistantResponseMode.localModel,
        responseOrigin: FfmAssistantResponseOrigin.localSlm,
        response:
            validated.response ??
            'Draf dari AI lokal siap ditinjau. Belum ada data yang disimpan.',
      );
    }

    // Help/unknown and malformed/ambiguous actions fall back to the existing
    // deterministic interpreter rather than displaying model-authored prose.
    return null;
  }

  String? _safeImageObservation({
    required String? imagePath,
    required String? message,
  }) {
    if (imagePath == null || message == null) return null;
    final compact = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length < 4 || compact.length > 720) return null;
    return 'Dari gambar ini, aku membaca: $compact';
  }

  Future<List<Account>> _activeAccounts() =>
      (_database.select(_database.accounts)..where(
            (row) =>
                row.householdId.equals(AppContext.householdId) &
                row.isArchived.equals(false) &
                row.isActive.equals(true),
          ))
          .get();

  bool _isSlmStatusRequest(String text) => _containsAny(text, const [
    'sudah terhubung slm',
    'udah terhubung slm',
    'slm sudah terhubung',
    'slm terhubung',
    'ai lokal sudah terhubung',
    'model lokal sudah terhubung',
    'ai lokal sudah siap',
    'model lokal sudah siap',
  ]);

  bool _isCashVerificationStatement(String text) => _containsAny(text, const [
    'sudah saya tambahkan cash',
    'sudah tambah cash',
    'cash sudah ditambahkan',
    'cash sudah ada',
  ]);

  bool _isBudgetNavigationRequest(String text) => _containsAny(text, const [
    'cek halaman anggaran',
    'cek halaman budget',
    'buka halaman anggaran',
    'buka halaman budget',
  ]);

  Future<FfmAssistantIntent> _verifyCashAccount(
    String rawText,
    String normalized,
  ) async {
    final accounts = await _activeAccounts();
    final matches = accounts
        .where((account) {
          final name = account.name.trim().toLowerCase();
          final type = account.type.trim().toLowerCase();
          return name == 'cash' || type == 'cash' || type == 'tunai';
        })
        .toList(growable: false);
    final response = matches.isEmpty
        ? 'Aku belum menemukan rekening aktif bernama atau bertipe Cash di Data Utama. Mungkin belum tersimpan, masih tidak aktif, atau namanya berbeda. Kamu bisa buka Data Utama untuk mengeceknya.'
        : matches.length == 1
        ? 'Ya, aku menemukan satu rekening Cash yang aktif di Data Utama. Aku tidak mengubah saldo atau data apa pun.'
        : 'Aku menemukan ${matches.length} rekening Cash yang aktif di Data Utama. Aku tidak mengubah saldo atau data apa pun.';
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.help,
      confidence: 1,
      response: response,
    );
  }

  Future<List<Category>> _activeCategories() =>
      (_database.select(_database.categories)..where(
            (row) =>
                row.householdId.equals(AppContext.householdId) &
                row.isActive.equals(true),
          ))
          .get();

  Future<List<String>> _recentTransactionSummaries({
    required String householdId,
    int limit = 5,
  }) async {
    final rows =
        await (_database.select(_database.transactions)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isArchived.equals(false) &
                    row.isDeleted.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.date)])
              ..limit(limit))
            .get();
    return rows
        .map(
          (row) =>
              '${row.type == 'income' ? 'Pemasukan' : 'Pengeluaran'} ${row.amount.abs()} pada ${row.date.toIso8601String().substring(0, 10)}',
        )
        .toList();
  }

  Future<FfmAssistantMemoryRecord?> _findTaughtAnswer(String normalized) async {
    final records = await _taughtMemory.readActive(kind: 'answer');
    final matches = records
        .where((record) {
          final trigger = _normalize(record.triggerText);
          return trigger.isNotEmpty &&
              (normalized == trigger || normalized.contains(trigger));
        })
        .toList(growable: false);
    if (matches.length == 1) return matches.single;
    return _taughtMemory.findFuzzyAnswer(normalized);
  }

  Future<FfmAssistantIntent> _setupGuide(
    String rawText,
    String normalized,
  ) async {
    final household = await (_database.select(
      _database.households,
    )..where((row) => row.id.equals(AppContext.householdId))).getSingleOrNull();
    final accounts = await _activeAccounts();
    final categories = await _activeCategories();
    final hasNamedHousehold =
        household != null &&
        household.name.trim().isNotEmpty &&
        household.name.trim().toLowerCase() != 'keluarga';
    final expenseCategories = categories
        .where((item) => item.type == 'expense')
        .length;
    final incomeCategories = categories
        .where((item) => item.type == 'income')
        .length;
    final steps = <String>[];
    if (!hasNamedHousehold) {
      steps.add(
        '1. Isi nama keluarga di Data Utama. Nama suami/istri boleh kamu isi kalau memang perlu.',
      );
    }
    if (accounts.isEmpty) {
      steps.add(
        '${steps.length + 1}. Tambah rekening yang dipakai, misalnya Tunai atau rekening bank. Isi saldo awal sesuai uang yang benar-benar ada sekarang.',
      );
    }
    if (expenseCategories == 0 || incomeCategories == 0) {
      steps.add(
        '${steps.length + 1}. Lengkapi kategori pemasukan dan pengeluaran agar riwayat lebih gampang dibaca.',
      );
    }
    steps.add(
      '${steps.length + 1}. Catat transaksi pertama. Pilih rekening bila uangnya memang perlu mengubah saldo; kalau sumber dana belum tahu, biarkan sebagai “Belum terlacak”.',
    );
    steps.add(
      '${steps.length + 1}. Setelah ada catatan, atur Anggaran mingguan/bulanan kalau kamu mau memantau batas belanja.',
    );
    final condition = accounts.isEmpty
        ? 'Saat ini belum ada rekening aktif.'
        : 'Saat ini ada ${accounts.length} rekening aktif.';
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.setupGuide,
      confidence: 1,
      response:
          '$condition Kategori aktif: $expenseCategories pengeluaran dan $incomeCategories pemasukan. Kita mulai dari yang paling kepake ya:\n${steps.join('\n')}',
    );
  }

  FfmAssistantIntent? _featureHelp(
    String rawText,
    String normalized, {
    FfmAssistantDestination? currentDestination,
  }) {
    final isQuestion = _containsAny(normalized, const [
      'fungsi',
      'buat apa',
      'apa itu',
      'apa saja',
      'ada apa',
      'isinya',
      'isi ',
      'fitur ',
      'menu ',
      'cara ',
      'gimana ',
      'bagaimana ',
      'jelaskan',
    ]);
    if (!isQuestion) return null;
    if (_containsAny(normalized, const [
      'fungsi tag',
      'tag buat apa',
      'apa itu tag',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.featureHelp,
        confidence: 1,
        response: 'Tag itu penanda tambahan transaksi, bukan kategori dan tidak mengubah saldo. Contohnya “belanja pasar”, “panen cabai”, atau “keperluan anak”. Tag berguna buat cari dan menyaring transaksi yang punya tema sama. Tambah atau rapikan tag di Data Utama.',
      );
    }
    if (_containsAny(normalized, const [
      'fungsi lampiran',
      'lampiran buat apa',
      'apa itu lampiran',
      'foto nota buat apa',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.featureHelp,
        confidence: 1,
        response: 'Lampiran dipakai untuk menyimpan bukti, misalnya foto nota atau dokumen transaksi. Lampiran biasa tidak mengubah nominal. Kalau punya hasil dari LLM, kamu bisa impor JSON transaksi lalu cek dan edit isinya sebelum disimpan.',
      );
    }
    if (_containsAny(normalized, const [
      'cara catat belanja',
      'cara input belanja',
      'cara catat pengeluaran',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.featureHelp,
        confidence: 1,
        response: 'Buka Transaksi, pilih Pengeluaran, isi nominal dan kategori, lalu pilih rekening atau Tunai jika belanja itu memang mengurangi saldo. Kalau sumber uangnya belum tahu, pilih “Belum terlacak” supaya saldo rekening tidak berubah. Tambahkan catatan atau lampiran kalau perlu, lalu cek dan simpan.',
      );
    }
    if (_containsAny(normalized, const [
      'transfer dengan admin',
      'cara transfer',
      'biaya admin transfer',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.featureHelp,
        confidence: 1,
        response: 'Untuk transfer, pilih rekening asal dan tujuan. Nominal transfer hanya memindahkan saldo, jadi tidak dihitung sebagai pemasukan atau pengeluaran. Kalau ada biaya admin, isi nominal adminnya; FFM akan mencatat biaya itu sebagai pengeluaran terpisah dari rekening asal.',
      );
    }
    if (_containsAny(normalized, const [
      'anggaran tidak rutin',
      'budget tidak rutin',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.featureHelp,
        confidence: 1,
        response: 'Anggaran Tidak Rutin cocok untuk kebutuhan yang tidak dibeli tiap bulan, misalnya sandal atau perbaikan rumah. Batasnya tidak direset otomatis seperti anggaran bulanan. Pengeluaran baru akan mengisi rincian aktual dari transaksi yang memang sudah kamu simpan.',
      );
    }
    if (_containsAny(normalized, const [
      'cara impor json',
      'cara pakai json',
      'kolom json',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.featureHelp,
        confidence: 1,
        response: 'JSON dipakai untuk menyiapkan banyak data sekaligus sebagai draft. Untuk transaksi, tiap baris biasanya berisi tipe, tanggal, nominal, kategori, rekening, catatan, dan bila perlu rincian item. Untuk transfer tambahkan rekening asal, tujuan, serta biaya admin bila ada. Tempel JSON di Transaksi, cek preview dan revisi, lalu konfirmasi. Tidak ada data yang masuk otomatis.',
      );
    }
    final page = FfmAssistantCatalog.findByText(normalized);
    final asksAboutCurrentPage = _containsAny(normalized, const [
      'halaman ini',
      'menu ini',
      'fitur di sini',
      'fitur halaman ini',
      'yang ada di sini',
      'isi halaman ini',
      'menu yang ini',
    ]);
    final asksAboutPage = page != null || asksAboutCurrentPage;
    final destination =
        page?.destination ?? (asksAboutCurrentPage ? currentDestination : null);
    if (destination != null && asksAboutPage) {
      final targetPage =
          page ?? FfmAssistantCatalog.findByDestination(destination);
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.featureHelp,
        destination: destination,
        confidence: 1,
        response:
            '${targetPage?.name ?? 'Halaman ini'}: ${FfmAssistantCatalog.detailFor(destination)}',
      );
    }
    return null;
  }

  FfmAssistantIntent _jsonTemplateHelp(String rawText, String normalized) {
    final type = _containsAny(normalized, const ['mutasi', 'rekening'])
        ? 'mutasi rekening'
        : _containsAny(normalized, const ['cadangan', 'backup'])
        ? 'cadangan data'
        : _containsAny(normalized, const ['laporan', 'pdf', 'html'])
        ? 'laporan'
        : null;
    if (type == null) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.createJsonTemplate,
        confidence: .9,
        response: 'Kamu mau JSON untuk apa dulu: impor transaksi, mutasi rekening, cadangan data, atau bahan laporan? Sebut salah satunya, nanti aku arahkan ke template dan jelaskan kolomnya.',
      );
    }
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.createJsonTemplate,
      destination: FfmAssistantDestination.backup,
      confidence: .9,
      response:
          'Aku buka Ekspor & cadangan untuk template $type. Salin templatenya, isi atau perbaiki di LLM di luar aplikasi, lalu tempel balik untuk preview. Hasil impor tetap draft sampai kamu konfirmasi.',
    );
  }

  Future<FfmAssistantIntent> _transactionStats(
    String rawText,
    String normalized,
  ) async {
    final now = DateTime.now();
    final period = _transactionPeriod(now, normalized);
    final start = period.$1;
    final end = period.$2;
    final label = period.$3;
    final transactions =
        await (_database.select(_database.transactions)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isDeleted.equals(false) &
                  row.date.isBiggerOrEqualValue(start) &
                  row.date.isSmallerThanValue(end),
            ))
            .get();
    final transfers =
        await (_database.select(_database.transfers)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isDeleted.equals(false) &
                  row.date.isBiggerOrEqualValue(start) &
                  row.date.isSmallerThanValue(end),
            ))
            .get();
    final income = transactions.where((item) => item.type == 'income').length;
    final expense = transactions.where((item) => item.type == 'expense').length;
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.transactionStats,
      confidence: 1,
      response:
          '$label kamu punya ${transactions.length + transfers.length} catatan: $income pemasukan, $expense pengeluaran, dan ${transfers.length} transfer. Transfer tetap tidak dihitung sebagai arus kas, ya.',
    );
  }

  Future<FfmAssistantIntent> _weeklyAnalysis(
    String rawText,
    String normalized,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
    final isLastWeek = _containsAny(normalized, const [
      'minggu lalu',
      'minggu kemarin',
    ]);
    final start = isLastWeek
        ? thisWeekStart.subtract(const Duration(days: 7))
        : thisWeekStart;
    final end = start.add(const Duration(days: 7));
    final label = isLastWeek ? 'Minggu lalu' : 'Minggu ini';
    final transactions =
        await (_database.select(_database.transactions)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isDeleted.equals(false) &
                  row.date.isBiggerOrEqualValue(start) &
                  row.date.isSmallerThanValue(end),
            ))
            .get();
    final transfers =
        await (_database.select(_database.transfers)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isDeleted.equals(false) &
                  row.date.isBiggerOrEqualValue(start) &
                  row.date.isSmallerThanValue(end),
            ))
            .get();
    if (transactions.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.weeklyAnalysis,
        destination: FfmAssistantDestination.analysis,
        confidence: 1,
        response:
            '$label belum punya transaksi yang tersimpan, jadi aku belum bisa bikin analisa. Kalau ada belanja atau pemasukan yang belum dicatat, masukkan dulu sebagai draft lalu cek sebelum simpan.',
      );
    }
    final categories = await (_database.select(
      _database.categories,
    )..where((row) => row.householdId.equals(AppContext.householdId))).get();
    final categoryNames = {
      for (final category in categories) category.id: category.name,
    };
    final income = transactions
        .where((item) => item.type == 'income')
        .fold<int>(0, (total, item) => total + item.amount.abs());
    final expenseTransactions = transactions
        .where((item) => item.type == 'expense')
        .toList();
    final expense = expenseTransactions.fold<int>(
      0,
      (total, item) => total + item.amount.abs(),
    );
    final byCategory = <String, int>{};
    for (final transaction in expenseTransactions) {
      final name = categoryNames[transaction.categoryId] ?? 'Tanpa kategori';
      byCategory.update(
        name,
        (total) => total + transaction.amount.abs(),
        ifAbsent: () => transaction.amount.abs(),
      );
    }
    final biggest = byCategory.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    final biggestText = biggest.isEmpty
        ? 'Belum ada pengeluaran tercatat.'
        : 'Pengeluaran terbesar: ${biggest.take(3).map((item) => '${item.key} ${_formatRupiah(item.value)}').join(', ')}.';
    final net = income - expense;
    final netText = net > 0
        ? 'arus kas surplus ${_formatRupiah(net)}'
        : net < 0
        ? 'arus kas defisit ${_formatRupiah(net.abs())}'
        : 'arus kas seimbang';
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.weeklyAnalysis,
      destination: FfmAssistantDestination.analysis,
      confidence: 1,
      response:
          '$label, dari ${transactions.length} transaksi yang tersimpan: pemasukan ${_formatRupiah(income)}, pengeluaran ${_formatRupiah(expense)}, jadi $netText. $biggestText Ada ${transfers.length} transfer; transfer tidak masuk hitungan arus kas.',
    );
  }

  (DateTime, DateTime, String) _transactionPeriod(
    DateTime now,
    String normalized,
  ) {
    if (_containsAny(normalized, const ['hari ini', 'hari sekarang'])) {
      final start = DateTime(now.year, now.month, now.day);
      return (start, start.add(const Duration(days: 1)), 'Hari ini');
    }
    if (_containsAny(normalized, const ['minggu ini', 'minggu sekarang'])) {
      final start = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - DateTime.monday));
      return (start, start.add(const Duration(days: 7)), 'Minggu ini');
    }
    final start = DateTime(now.year, now.month);
    return (start, DateTime(now.year, now.month + 1), 'Bulan ini');
  }

  Future<FfmAssistantIntent> _financialWarnings(
    String rawText,
    String normalized,
  ) async {
    final service = BudgetGuardService(_database);
    final suggestions = await service.check(AppContext.householdId);
    final isBudgetQuestion = _containsAny(normalized, const [
      'anggaran',
      'budget',
      'batas belanja',
    ]);
    final visibleSuggestions = isBudgetQuestion
        ? suggestions
              .where(
                (item) =>
                    item.kind == FinancialGuardKind.budgetExceeded ||
                    item.kind == FinancialGuardKind.budgetNearLimit ||
                    item.kind == FinancialGuardKind.budgetFastUse,
              )
              .toList(growable: false)
        : suggestions;
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.financialWarnings,
      destination: isBudgetQuestion
          ? FfmAssistantDestination.budget
          : FfmAssistantDestination.summary,
      confidence: 1,
      response: service.responseForAssistant(
        visibleSuggestions,
        emptyMessage: isBudgetQuestion
            ? 'Belum ada anggaran aktif yang melewati batas, mendekati batas, atau memakai dana lebih cepat dari periode resminya.'
            : null,
      ),
    );
  }

  Future<FfmAssistantIntent> _currentPageContext(
    String rawText,
    String normalized,
    FfmAssistantDestination destination,
  ) async {
    final page = FfmAssistantCatalog.findByDestination(destination);
    final pageName = page?.name ?? 'halaman ini';
    if (_isCurrentPageLabelRequest(normalized)) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        destination: destination,
        confidence: 1,
        response:
            'Sekarang kamu ada di halaman $pageName. ${page?.description ?? 'Kamu bisa bertanya fungsi halaman ini atau data yang ingin dicek.'}',
      );
    }
    if (destination == FfmAssistantDestination.summary ||
        destination == FfmAssistantDestination.transactions) {
      final stats = await _transactionStats(rawText, normalized);
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.transactionStats,
        destination: destination,
        confidence: 1,
        response: 'Kamu lagi di $pageName. ${stats.response}',
      );
    }
    if (destination == FfmAssistantDestination.budget) {
      final warnings = await _financialWarnings(rawText, normalized);
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.financialWarnings,
        destination: destination,
        confidence: 1,
        response: 'Kamu lagi di Anggaran. ${warnings.response}',
      );
    }
    if (destination == FfmAssistantDestination.activity) {
      final activeSessions =
          await (_database.select(_database.activitySessions)..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isArchived.equals(false) &
                    row.status.equals('active'),
              ))
              .get();
      final count = activeSessions.length;
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        destination: destination,
        confidence: 1,
        response: count == 0
            ? 'Kamu lagi di Aktivitas. Belum ada aktivitas yang sedang jalan. Kamu bisa mulai dari tombol Tambah atau bilang “mulai perjalanan”.'
            : 'Kamu lagi di Aktivitas. Ada $count aktivitas yang masih jalan: ${activeSessions.map((item) => item.title).join(', ')}.',
      );
    }
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.help,
      destination: destination,
      confidence: 1,
      response:
          'Kamu lagi di $pageName. ${page?.description ?? 'Kamu bisa bilang data apa yang mau dicek.'}',
    );
  }

  bool _isOtherMenuListRequest(String text) =>
      (text.contains('menu lainnya') || text.contains('bagian lainnya')) &&
      _containsAny(text, const [
        'apa saja',
        'daftar',
        'isi',
        'fitur',
        'menu',
        'tampilkan',
        'fungsi',
        'ada apa',
      ]);

  bool _isNavigationRequest(String text) => _containsAny(text, const [
    'buka',
    'pindah',
    'ke halaman',
    'ke bagian',
    'arah ke',
    'bawa ke',
    'pergi ke halaman',
    'pergi ke menu',
    'masuk halaman',
    'masuk menu',
    'tampilkan',
  ]);

  bool _isCurrentPageRequest(String text) =>
      _isCurrentPageLabelRequest(text) ||
      _containsAny(text, const [
        'halaman ini',
        'di sini ada apa',
        'di sini ada data apa',
        'kondisi halaman ini',
        'baca halaman ini',
      ]);

  bool _isCurrentPageLabelRequest(String text) => _containsAny(text, const [
    'saya sedang di halaman apa',
    'sedang di halaman apa',
    'sekarang di halaman apa',
    'lagi di halaman apa',
    'saya ada di halaman apa',
    'saya lagi di halaman apa',
    'halaman sekarang apa',
    'ini halaman apa',
    'nama halaman ini',
  ]);

  bool _isDatabaseStructureRequest(String text) {
    final namesDatabase = RegExp(
      r'\b(database|basis data|struktur database|struktur data|tabel)\b',
    ).hasMatch(text);
    final asksAppData =
        text.contains('ada data apa saja') &&
        (text.contains('aplikasi') || text.contains('ffm'));
    return namesDatabase || asksAppData;
  }

  FfmAssistantIntent _intentForDraft(
    String rawText,
    String normalized,
    FfmAssistantDraft draft,
  ) {
    final config = switch (draft.kind) {
      FfmAssistantDraftKind.transfer => (
        type: FfmAssistantIntentType.createTransfer,
        destination: FfmAssistantDestination.transactions,
        action: 'transfer',
      ),
      FfmAssistantDraftKind.income => (
        type: FfmAssistantIntentType.createIncome,
        destination: FfmAssistantDestination.transactions,
        action: 'pemasukan',
      ),
      FfmAssistantDraftKind.expense => (
        type: FfmAssistantIntentType.createExpense,
        destination: FfmAssistantDestination.transactions,
        action: 'pengeluaran',
      ),
      FfmAssistantDraftKind.goalDeposit => (
        type: FfmAssistantIntentType.createGoalDeposit,
        destination: FfmAssistantDestination.transactions,
        action: 'setoran target',
      ),
      FfmAssistantDraftKind.goalUsage => (
        type: FfmAssistantIntentType.createGoalUsage,
        destination: FfmAssistantDestination.transactions,
        action: 'pemakaian dana target',
      ),
      FfmAssistantDraftKind.liability => (
        type: FfmAssistantIntentType.createLiability,
        destination: FfmAssistantDestination.liabilities,
        action: 'hutang',
      ),
      FfmAssistantDraftKind.liabilityUpdate => (
        type: FfmAssistantIntentType.updateLiability,
        destination: FfmAssistantDestination.liabilities,
        action: 'ubah hutang',
      ),
      FfmAssistantDraftKind.liabilityArchive => (
        type: FfmAssistantIntentType.archiveLiability,
        destination: FfmAssistantDestination.liabilities,
        action: 'arsip hutang',
      ),
      FfmAssistantDraftKind.receivable => (
        type: FfmAssistantIntentType.createReceivable,
        destination: FfmAssistantDestination.liabilities,
        action: 'piutang',
      ),
      FfmAssistantDraftKind.receivableUpdate => (
        type: FfmAssistantIntentType.updateReceivable,
        destination: FfmAssistantDestination.liabilities,
        action: 'ubah piutang',
      ),
      FfmAssistantDraftKind.receivableArchive => (
        type: FfmAssistantIntentType.archiveReceivable,
        destination: FfmAssistantDestination.liabilities,
        action: 'arsip piutang',
      ),
      FfmAssistantDraftKind.recurringTransactionUpdate => (
        type: FfmAssistantIntentType.updateRecurringTransaction,
        destination: FfmAssistantDestination.recurringTransaction,
        action: 'ubah Transaksi Berkala',
      ),
      FfmAssistantDraftKind.recurringTransactionArchive => (
        type: FfmAssistantIntentType.archiveRecurringTransaction,
        destination: FfmAssistantDestination.recurringTransaction,
        action: 'nonaktifkan Transaksi Berkala',
      ),
      FfmAssistantDraftKind.goal => (
        type: FfmAssistantIntentType.createGoal,
        destination: FfmAssistantDestination.goals,
        action: 'target keuangan',
      ),
      FfmAssistantDraftKind.asset => (
        type: FfmAssistantIntentType.createAsset,
        destination: FfmAssistantDestination.assets,
        action: 'aset',
      ),
      FfmAssistantDraftKind.assetUpdate => (
        type: FfmAssistantIntentType.updateAsset,
        destination: FfmAssistantDestination.assets,
        action: 'ubah aset',
      ),
      FfmAssistantDraftKind.assetArchive => (
        type: FfmAssistantIntentType.archiveAsset,
        destination: FfmAssistantDestination.assets,
        action: 'arsip aset',
      ),
      FfmAssistantDraftKind.budget => (
        type: FfmAssistantIntentType.createBudget,
        destination: FfmAssistantDestination.budget,
        action: 'anggaran',
      ),
      FfmAssistantDraftKind.masterData => (
        type: FfmAssistantIntentType.createMasterData,
        destination: FfmAssistantDestination.masterData,
        action: 'Data Utama',
      ),
      FfmAssistantDraftKind.reminder => (
        type: FfmAssistantIntentType.createReminder,
        destination: FfmAssistantDestination.reminders,
        action: 'pengingat',
      ),
      FfmAssistantDraftKind.reminderUpdate => (
        type: FfmAssistantIntentType.updateReminder,
        destination: FfmAssistantDestination.reminders,
        action: 'ubah pengingat',
      ),
      FfmAssistantDraftKind.activity => (
        type: FfmAssistantIntentType.createActivity,
        destination: FfmAssistantDestination.activity,
        action: 'aktivitas',
      ),
      FfmAssistantDraftKind.dailyNote => (
        type: FfmAssistantIntentType.createDailyNote,
        destination: FfmAssistantDestination.activity,
        action: 'Catatan Harian',
      ),
      FfmAssistantDraftKind.dailyNoteArchive => (
        type: FfmAssistantIntentType.archiveDailyNote,
        destination: FfmAssistantDestination.activity,
        action: 'arsip Catatan Harian',
      ),
      FfmAssistantDraftKind.task => (
        type: FfmAssistantIntentType.createTask,
        destination: FfmAssistantDestination.activity,
        action: 'Tugas',
      ),
      FfmAssistantDraftKind.taskUpdate => (
        type: FfmAssistantIntentType.updateTask,
        destination: FfmAssistantDestination.activity,
        action: 'ubah Tugas',
      ),
      FfmAssistantDraftKind.taskComplete => (
        type: FfmAssistantIntentType.completeTask,
        destination: FfmAssistantDestination.activity,
        action: 'selesaikan Tugas',
      ),
      FfmAssistantDraftKind.taskReopen => (
        type: FfmAssistantIntentType.reopenTask,
        destination: FfmAssistantDestination.activity,
        action: 'buka kembali Tugas',
      ),
      FfmAssistantDraftKind.taskArchive => (
        type: FfmAssistantIntentType.archiveTask,
        destination: FfmAssistantDestination.activity,
        action: 'arsip Tugas',
      ),
      FfmAssistantDraftKind.routine => (
        type: FfmAssistantIntentType.createRoutine,
        destination: FfmAssistantDestination.activity,
        action: 'Rutinitas',
      ),
      FfmAssistantDraftKind.routineUpdate => (
        type: FfmAssistantIntentType.updateRoutine,
        destination: FfmAssistantDestination.activity,
        action: 'ubah Rutinitas',
      ),
      FfmAssistantDraftKind.routineMarkComplete => (
        type: FfmAssistantIntentType.markRoutineComplete,
        destination: FfmAssistantDestination.activity,
        action: 'tandai Rutinitas hari ini',
      ),
      FfmAssistantDraftKind.routineUnmarkComplete => (
        type: FfmAssistantIntentType.unmarkRoutineComplete,
        destination: FfmAssistantDestination.activity,
        action: 'batalkan tanda Rutinitas hari ini',
      ),
      FfmAssistantDraftKind.routineActivate => (
        type: FfmAssistantIntentType.activateRoutine,
        destination: FfmAssistantDestination.activity,
        action: 'aktifkan Rutinitas',
      ),
      FfmAssistantDraftKind.routineDeactivate => (
        type: FfmAssistantIntentType.deactivateRoutine,
        destination: FfmAssistantDestination.activity,
        action: 'nonaktifkan Rutinitas',
      ),
      FfmAssistantDraftKind.routineArchive => (
        type: FfmAssistantIntentType.archiveRoutine,
        destination: FfmAssistantDestination.activity,
        action: 'arsip Rutinitas',
      ),
      FfmAssistantDraftKind.schedule => (
        type: FfmAssistantIntentType.createSchedule,
        destination: FfmAssistantDestination.activity,
        action: 'Jadwal',
      ),
      FfmAssistantDraftKind.scheduleUpdate => (
        type: FfmAssistantIntentType.updateSchedule,
        destination: FfmAssistantDestination.activity,
        action: 'ubah Jadwal',
      ),
      FfmAssistantDraftKind.scheduleArchive => (
        type: FfmAssistantIntentType.archiveSchedule,
        destination: FfmAssistantDestination.activity,
        action: 'arsip Jadwal',
      ),
      FfmAssistantDraftKind.profile => (
        type: FfmAssistantIntentType.createProfile,
        destination: FfmAssistantDestination.assistantProfile,
        action: 'profil',
      ),
      FfmAssistantDraftKind.reminderArchive => (
        type: FfmAssistantIntentType.archiveReminder,
        destination: FfmAssistantDestination.reminders,
        action: 'arsip pengingat',
      ),
      FfmAssistantDraftKind.goalUpdate => (
        type: FfmAssistantIntentType.updateGoal,
        destination: FfmAssistantDestination.goals,
        action: 'perubahan target keuangan',
      ),
      FfmAssistantDraftKind.goalArchive => (
        type: FfmAssistantIntentType.archiveGoal,
        destination: FfmAssistantDestination.goals,
        action: 'arsip target keuangan',
      ),
      FfmAssistantDraftKind.transactionUpdate => (
        type: FfmAssistantIntentType.updateTransaction,
        destination: FfmAssistantDestination.transactions,
        action: 'perubahan transaksi',
      ),
      FfmAssistantDraftKind.transactionArchive => (
        type: FfmAssistantIntentType.archiveTransaction,
        destination: FfmAssistantDestination.transactions,
        action: 'arsip transaksi',
      ),
      FfmAssistantDraftKind.transactionDelete => (
        type: FfmAssistantIntentType.deleteTransaction,
        destination: FfmAssistantDestination.transactions,
        action: 'hapus transaksi',
      ),
      FfmAssistantDraftKind.activityArchive => (
        type: FfmAssistantIntentType.archiveActivity,
        destination: FfmAssistantDestination.activity,
        action: 'arsip aktivitas',
      ),
      FfmAssistantDraftKind.activityDelete => (
        type: FfmAssistantIntentType.deleteActivity,
        destination: FfmAssistantDestination.activity,
        action: 'hapus aktivitas',
      ),
    };
    if (draft.kind == FfmAssistantDraftKind.masterData) {
      final target = _masterDataTargetName(draft.categoryName);
      final name = draft.title?.trim();
      final nameDetail = name == null || name.isEmpty
          ? ''
          : ' dengan nama sementara “$name”';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.createMasterData,
        destination: FfmAssistantDestination.masterData,
        draft: draft,
        confidence: .9,
        response:
            'Aku akan membuka form $target di Data Utama$nameDetail. Belum ada data yang disimpan. Kamu bisa cek dan lengkapi kolom yang belum ada, lalu tekan Simpan sendiri di form.',
      );
    }
    final missing = <String>[];
    const amountKinds = {
      FfmAssistantDraftKind.income,
      FfmAssistantDraftKind.expense,
      FfmAssistantDraftKind.transfer,
      FfmAssistantDraftKind.goalDeposit,
      FfmAssistantDraftKind.goalUsage,
      FfmAssistantDraftKind.goal,
      FfmAssistantDraftKind.goalUpdate,
      FfmAssistantDraftKind.liability,
      FfmAssistantDraftKind.receivable,
      FfmAssistantDraftKind.asset,
      FfmAssistantDraftKind.budget,
    };
    if (amountKinds.contains(draft.kind) && !draft.hasAmount) {
      missing.add('nominal');
    }
    if (draft.kind == FfmAssistantDraftKind.transfer) {
      if (draft.fromAccountName == null) missing.add('rekening asal');
      if (draft.toAccountName == null) missing.add('rekening tujuan');
    }
    if ((draft.kind == FfmAssistantDraftKind.liability ||
            draft.kind == FfmAssistantDraftKind.receivable) &&
        (draft.partyName == null || draft.partyName!.isEmpty)) {
      missing.add('nama orangnya');
    }
    if (draft.kind == FfmAssistantDraftKind.profile &&
        draft.formValues.isNotEmpty) {
      for (final field in const ['Nama', 'Pekerjaan', 'Rutinitas', 'Tujuan']) {
        final value = draft.formValues[field];
        if (value == null || value.trim().isEmpty) {
          missing.add(field.toLowerCase());
        }
      }
    }
    final safetyWarning = switch (draft.kind) {
      FfmAssistantDraftKind.transfer => FfmAssistantSanityCheck.transferWarning(
        amount: draft.amount,
        fromAccount: draft.fromAccountName,
        toAccount: draft.toAccountName,
        adminFee: draft.adminFee,
      ),
      FfmAssistantDraftKind.income =>
        FfmAssistantSanityCheck.transactionWarning(
          amount: draft.amount,
          isIncome: true,
        ),
      FfmAssistantDraftKind.expense =>
        FfmAssistantSanityCheck.transactionWarning(
          amount: draft.amount,
          isIncome: false,
        ),
      _ => null,
    };
    final clarification = missing.isEmpty
        ? safetyWarning
        : 'Aku sudah menyiapkan draft ${config.action}, tapi masih butuh ${missing.join(', ')}.';
    final categoryHint = draft.categoryName == null
        ? ''
        : ' Kategori ${draft.categoryName} sudah aku pilih dari Data Utama.';
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: config.type,
      destination: config.destination,
      draft: draft,
      confidence: missing.isEmpty ? .9 : .55,
      clarification: clarification,
      response: missing.isEmpty
          ? 'Draft ${config.action} sudah siap.$categoryHint Cek dulu, lalu konfirmasi di halaman terkait.'
          : null,
    );
  }

  Map<String, String> _extractProfileValues(String rawText) {
    final values = <String, String>{};
    final patterns = <String, RegExp>{
      'Nama': RegExp(
        r'(?:nama(?: saya|ku)?|panggil(?: saya| aku)?)\s*(?:adalah|:)?\s*([^,;.\n]+)',
        caseSensitive: false,
      ),
      'Pekerjaan': RegExp(
        r'(?:pekerjaan|profesi|kerja sebagai|bekerja sebagai)\s*(?:adalah|:)?\s*([^,;.\n]+)',
        caseSensitive: false,
      ),
      'Rutinitas': RegExp(
        r'(?:rutinitas|kebiasaan)\s*(?:saya|aku|ku)?\s*(?:adalah|:)?\s*([^;.\n]+)',
        caseSensitive: false,
      ),
      'Tujuan': RegExp(
        r'(?:tujuan|prioritas|target)\s*(?:saya|aku|ku)?\s*(?:adalah|:)?\s*([^;.\n]+)',
        caseSensitive: false,
      ),
    };
    for (final entry in patterns.entries) {
      final value = entry.value.firstMatch(rawText)?.group(1)?.trim();
      if (value != null && value.isNotEmpty) values[entry.key] = value;
    }
    return values;
  }

  Future<FfmAssistantIntent?> _parseActivityMutation(
    String rawText,
    String normalized,
  ) async {
    final archive = RegExp(r'^(?:arsip|arsipkan)\s+aktivitas\s+(.+)$')
        .firstMatch(normalized);
    final delete = RegExp(r'^hapus\s+aktivitas\s+(.+)$').firstMatch(normalized);
    if (archive == null && delete == null) return null;
    final operation = archive != null ? 'archive' : 'delete';
    final targetText = (archive?.group(1) ?? delete!.group(1)!).trim();
    final candidates = await _findActivityCandidates(targetText);
    if (candidates.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: operation == 'archive'
            ? FfmAssistantIntentType.archiveActivity
            : FfmAssistantIntentType.deleteActivity,
        confidence: .8,
        clarification:
            'Aku tidak menemukan satu aktivitas selesai yang cocok dengan “$targetText”. Aktivitas yang masih berjalan harus diselesaikan dari halaman Aktivitas dulu. Belum ada data yang diubah.',
      );
    }
    if (candidates.length > 1) {
      final options = candidates
          .take(3)
          .map(_activityCandidateLabel)
          .join('; ');
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: operation == 'archive'
            ? FfmAssistantIntentType.archiveActivity
            : FfmAssistantIntentType.deleteActivity,
        confidence: .72,
        clarification:
            'Aku menemukan ${candidates.length} aktivitas yang cocok: $options. Sebut judul yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final draft = FfmAssistantDraft(
      kind: operation == 'archive'
          ? FfmAssistantDraftKind.activityArchive
          : FfmAssistantDraftKind.activityDelete,
      createdAt: _clock(),
      title: _activityCandidateLabel(target),
      note: target.notes,
      date: target.startedAt,
      formValues: {
        'entity': 'activity_session',
        'targetId': target.id,
        'operation': operation,
        'targetSummary': _activityCandidateLabel(target),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'archive'
          ? 'Aku menemukan satu aktivitas selesai untuk diarsipkan. Cek preview dulu; belum ada data yang diubah.'
          : 'Aku menemukan satu aktivitas selesai untuk dihapus permanen beserta data turunannya. Cek preview dampaknya dulu; belum ada data yang diubah.',
    );
  }

  Future<List<ActivitySession>> _findActivityCandidates(
    String targetText,
  ) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where(
          (term) =>
              term.length >= 3 &&
              !const {'aktivitas', 'pada', 'tanggal'}.contains(term) &&
              !RegExp(r'^\d+$').hasMatch(term),
        )
        .toSet();
    if (terms.isEmpty) return const [];
    final rows =
        await (_database.select(_database.activitySessions)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isArchived.equals(false) &
                    row.status.isNotValue('active'),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.startedAt)]))
            .get();
    return rows
        .where((row) {
          final haystack = '${row.title} ${row.category} ${row.notes ?? ''}'
              .toLowerCase();
          return terms.every(haystack.contains);
        })
        .take(4)
        .toList(growable: false);
  }

  String _activityCandidateLabel(ActivitySession row) {
    final date = row.startedAt.toIso8601String().substring(0, 10);
    return '${row.title} • ${row.category} • $date';
  }

  Future<FfmAssistantIntent?> _parseDailyNoteMutation(
    String rawText,
    String normalized,
  ) async {
    final archive = RegExp(
      r'^(?:arsip|arsipkan)\s+(?:catatan harian|catatan)\s+(.+)$',
    ).firstMatch(normalized);
    if (archive == null) return null;
    final targetText = archive.group(1)!.trim();
    final candidates = await _findDailyNoteCandidates(targetText);
    if (candidates.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.archiveDailyNote,
        confidence: .8,
        clarification:
            'Aku tidak menemukan satu Catatan Harian aktif yang cocok dengan “$targetText”. Belum ada data yang diubah.',
      );
    }
    if (candidates.length > 1) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.archiveDailyNote,
        confidence: .72,
        clarification:
            'Aku menemukan ${candidates.length} Catatan Harian yang cocok: ${candidates.take(3).map(_dailyNoteCandidateLabel).join('; ')}. Sebut judul atau isi yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.dailyNoteArchive,
      createdAt: _clock(),
      title: _dailyNoteCandidateLabel(target),
      note: target.body,
      date: target.noteDate,
      formValues: {
        'entity': 'daily_note',
        'targetId': target.id,
        'operation': 'archive',
        'targetSummary': _dailyNoteCandidateLabel(target),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: 'Aku menemukan satu Catatan Harian untuk diarsipkan. Cek preview dulu; catatan tidak akan dihapus permanen.',
    );
  }

  Future<List<DailyNote>> _findDailyNoteCandidates(String targetText) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where((term) => term.length >= 3 && !RegExp(r'^\d+$').hasMatch(term))
        .toSet();
    if (terms.isEmpty) return const [];
    final rows =
        await (_database.select(_database.dailyNotes)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.noteDate)]))
            .get();
    return rows
        .where((row) {
          final haystack =
              '${row.title ?? ''} ${row.body} ${row.noteDate.toIso8601String().substring(0, 10)}'
                  .toLowerCase();
          return terms.every(haystack.contains);
        })
        .take(4)
        .toList(growable: false);
  }

  String _dailyNoteCandidateLabel(DailyNote row) {
    final date = row.noteDate.toIso8601String().substring(0, 10);
    return row.title?.trim().isNotEmpty == true
        ? '${row.title} ($date)'
        : 'Catatan $date';
  }

  Future<FfmAssistantIntent?> _parseTaskMutation(
    String rawText,
    String normalized,
  ) async {
    final create = RegExp(
      r'^(?:tambah|buat|catat)(?:kan)?\s+tugas\s*[:\-]?\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    if (create != null) {
      final title = create.group(1)?.trim() ?? '';
      if (title.isEmpty) return null;
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.task,
        createdAt: _clock(),
        title: title,
        formValues: const {'entity': 'task'},
      );
      return _intentForDraft(rawText, normalized, draft).copyWith(
        response: 'Aku siapkan draft Tugas. Cek preview dulu; belum ada data yang disimpan.',
      );
    }

    final update = RegExp(
      r'^(?:ubah|ganti)\s+tugas\s+(.+?)\s+(?:menjadi|jadi)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    final complete = RegExp(
      r'^(?:selesai|selesaikan|tandai selesai)\s+tugas\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    final reopen = RegExp(
      r'^(?:buka kembali|aktifkan kembali)\s+tugas\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    final archive = RegExp(
      r'^(?:arsip|arsipkan)\s+tugas\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    if (update == null &&
        complete == null &&
        reopen == null &&
        archive == null) {
      return null;
    }
    final operation = update != null
        ? 'update'
        : complete != null
        ? 'complete'
        : reopen != null
        ? 'reopen'
        : 'archive';
    final targetText =
        (update?.group(1) ??
                complete?.group(1) ??
                reopen?.group(1) ??
                archive?.group(1) ??
                '')
            .trim();
    final candidates = await _findTaskCandidates(
      targetText,
      operation: operation,
    );
    final type = switch (operation) {
      'update' => FfmAssistantIntentType.updateTask,
      'complete' => FfmAssistantIntentType.completeTask,
      'reopen' => FfmAssistantIntentType.reopenTask,
      _ => FfmAssistantIntentType.archiveTask,
    };
    if (candidates.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: .8,
        clarification:
            'Aku tidak menemukan satu Tugas aktif yang cocok dengan “$targetText”. Belum ada data yang diubah.',
      );
    }
    if (candidates.length > 1) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: .72,
        clarification:
            'Aku menemukan ${candidates.length} Tugas yang cocok: ${candidates.take(3).map(_taskCandidateLabel).join('; ')}. Sebut judul yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final newTitle = update?.group(2)?.trim();
    final kind = switch (operation) {
      'update' => FfmAssistantDraftKind.taskUpdate,
      'complete' => FfmAssistantDraftKind.taskComplete,
      'reopen' => FfmAssistantDraftKind.taskReopen,
      _ => FfmAssistantDraftKind.taskArchive,
    };
    final draft = FfmAssistantDraft(
      kind: kind,
      createdAt: _clock(),
      title: newTitle ?? _taskCandidateLabel(target),
      note: target.note,
      date: target.dueDate,
      formValues: {
        'entity': 'task',
        'targetId': target.id,
        'operation': operation,
        'targetSummary': _taskCandidateLabel(target),
        if (newTitle != null) 'title': newTitle,
      },
    );
    final action = switch (operation) {
      'update' => 'diubah',
      'complete' => 'ditandai selesai',
      'reopen' => 'dibuka kembali',
      _ => 'diarsipkan tanpa dihapus permanen',
    };
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response:
          'Aku menemukan satu Tugas untuk $action. Cek preview dulu; belum ada data yang diubah.',
    );
  }

  Future<List<Task>> _findTaskCandidates(
    String targetText, {
    required String operation,
  }) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where((term) => term.length >= 3 && !RegExp(r'^\d+$').hasMatch(term))
        .toSet();
    if (terms.isEmpty) return const [];
    final rows =
        await (_database.select(_database.tasks)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
            .get();
    return rows
        .where((row) {
          if (operation == 'complete' && row.status != 'open') return false;
          if (operation == 'reopen' && row.status != 'completed') return false;
          final haystack = '${row.title} ${row.note ?? ''}'.toLowerCase();
          return terms.every(haystack.contains);
        })
        .take(4)
        .toList(growable: false);
  }

  Future<FfmAssistantIntent?> _parseRoutineMutation(
    String rawText,
    String normalized,
  ) async {
    final create = RegExp(
      r'^(?:tambah|buat|catat)(?:kan)?\s+rutinitas\s*[:\-]?\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    if (create != null) {
      final title = create.group(1)?.trim() ?? '';
      if (title.isEmpty) return null;
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.routine,
        createdAt: _clock(),
        title: title,
        formValues: const {'entity': 'daily_routine'},
      );
      return _intentForDraft(rawText, normalized, draft).copyWith(
        response: 'Aku siapkan draft Rutinitas. Cek preview dulu; belum ada data yang disimpan atau notifikasi yang dibuat.',
      );
    }

    final update = RegExp(
      r'^(?:ubah|ganti)\s+rutinitas\s+(.+?)\s+(?:menjadi|jadi)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    final mark = RegExp(
      r'^(?:selesai|selesaikan|tandai selesai)\s+rutinitas\s+(.+?)(?:\s+hari ini)?$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    final unmark = RegExp(
      r'^(?:batalkan|batal|hapus)\s+(?:tanda\s+)?(?:selesai\s+)?rutinitas\s+(.+?)(?:\s+hari ini)?$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    final activate = RegExp(
      r'^aktifkan\s+rutinitas\s+(.+$)',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    final deactivate = RegExp(
      r'^(?:nonaktifkan|matikan)\s+rutinitas\s+(.+$)',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    final archive = RegExp(
      r'^(?:arsip|arsipkan)\s+rutinitas\s+(.+$)',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    if (update == null &&
        mark == null &&
        unmark == null &&
        activate == null &&
        deactivate == null &&
        archive == null) {
      return null;
    }
    final operation = update != null
        ? 'update'
        : mark != null
        ? 'mark'
        : unmark != null
        ? 'unmark'
        : activate != null
        ? 'activate'
        : deactivate != null
        ? 'deactivate'
        : 'archive';
    final targetText =
        (update?.group(1) ??
                mark?.group(1) ??
                unmark?.group(1) ??
                activate?.group(1) ??
                deactivate?.group(1) ??
                archive?.group(1) ??
                '')
            .trim();
    final candidates = await _findRoutineCandidates(
      targetText,
      operation: operation,
    );
    final type = switch (operation) {
      'update' => FfmAssistantIntentType.updateRoutine,
      'mark' => FfmAssistantIntentType.markRoutineComplete,
      'unmark' => FfmAssistantIntentType.unmarkRoutineComplete,
      'activate' => FfmAssistantIntentType.activateRoutine,
      'deactivate' => FfmAssistantIntentType.deactivateRoutine,
      _ => FfmAssistantIntentType.archiveRoutine,
    };
    if (candidates.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: .8,
        clarification:
            'Aku tidak menemukan satu Rutinitas aktif yang cocok dengan “$targetText”. Sebut judul yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    if (candidates.length > 1) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: .72,
        clarification:
            'Aku menemukan ${candidates.length} Rutinitas yang cocok: ${candidates.take(3).map(_routineCandidateLabel).join('; ')}. Sebut judul yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final newTitle = update?.group(2)?.trim();
    final kind = switch (operation) {
      'update' => FfmAssistantDraftKind.routineUpdate,
      'mark' => FfmAssistantDraftKind.routineMarkComplete,
      'unmark' => FfmAssistantDraftKind.routineUnmarkComplete,
      'activate' => FfmAssistantDraftKind.routineActivate,
      'deactivate' => FfmAssistantDraftKind.routineDeactivate,
      _ => FfmAssistantDraftKind.routineArchive,
    };
    final now = _clock();
    final day = DateTime(now.year, now.month, now.day);
    final draft = FfmAssistantDraft(
      kind: kind,
      createdAt: _clock(),
      title: newTitle ?? target.title,
      note: target.note,
      date: operation == 'mark' || operation == 'unmark' ? day : null,
      formValues: {
        'entity': 'daily_routine',
        'targetId': target.id,
        'operation': operation,
        'targetSummary': _routineCandidateLabel(target),
        'weekdays': target.weekdaysJson,
        if (newTitle != null) 'title': newTitle,
      },
    );
    final action = switch (operation) {
      'update' => 'diubah',
      'mark' => 'ditandai selesai hari ini',
      'unmark' => 'dibatalkan tandanya untuk hari ini',
      'activate' => 'diaktifkan',
      'deactivate' => 'dinonaktifkan',
      _ => 'diarsipkan tanpa dihapus permanen',
    };
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response:
          'Aku menemukan satu Rutinitas untuk $action. Cek preview dulu; belum ada data yang diubah.',
    );
  }

  Future<List<DailyRoutine>> _findRoutineCandidates(
    String targetText, {
    required String operation,
  }) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where((term) => term.length >= 3 && !RegExp(r'^\d+$').hasMatch(term))
        .toSet();
    if (terms.isEmpty) return const [];
    final rows =
        await (_database.select(_database.dailyRoutines)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
            .get();
    return rows
        .where((row) {
          if (operation == 'mark' && !row.isActive) return false;
          if (operation == 'activate' && row.isActive) return false;
          if (operation == 'deactivate' && !row.isActive) return false;
          final haystack = '${row.title} ${row.note ?? ''}'.toLowerCase();
          return terms.every(haystack.contains);
        })
        .take(4)
        .toList(growable: false);
  }

  String _routineCandidateLabel(DailyRoutine row) {
    final state = row.isActive ? 'aktif' : 'nonaktif';
    return '${row.title} • $state';
  }

  Future<FfmAssistantIntent?> _parseScheduleMutationSafe(
    String rawText,
    String normalized,
  ) async {
    final direct = await _parseScheduleMutationDirect(rawText, normalized);
    return direct ?? _parseScheduleMutation(rawText, normalized);
  }

  Future<FfmAssistantIntent?> _parseScheduleMutationDirect(
    String rawText,
    String normalized,
  ) async {
    final create = RegExp(r'^(?:buat|tambah|jadwalkan)[ ]+jadwal[ ]+(.+)$')
        .firstMatch(normalized);
    if (create != null) {
      return _draftScheduleCreate(rawText, normalized, create.group(1)!);
    }
    final move = RegExp(
      r'^(?:pindah|pindahkan|jadwalkan ulang)[ ]+jadwal[ ]+(.+?)[ ]+ke[ ]+(.+)$',
    ).firstMatch(normalized);
    final rename = RegExp(
      r'^(?:ubah|ganti|koreksi)[ ]+jadwal[ ]+(.+?)[ ]+(?:jadi|menjadi)[ ]+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(r'^(?:arsip|arsipkan)[ ]+jadwal[ ]+(.+)$')
        .firstMatch(normalized);
    if (move == null && rename == null && archive == null) return null;
    return _draftScheduleMutation(
      rawText,
      normalized,
      move: move,
      rename: rename,
      archive: archive,
    );
  }

  Future<FfmAssistantIntent> _draftScheduleCreate(
    String rawText,
    String normalized,
    String source,
  ) async {
    final date = _scheduleDateFromText(source);
    if (date == null) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.createSchedule,
        confidence: .75,
        clarification: 'Sebutkan tanggal Jadwal, misalnya “buat jadwal kontrol dokter besok” atau “buat jadwal kontrol dokter tanggal 28/08/2026”. Belum ada data yang diubah.',
      );
    }
    final title = _scheduleTitleFromText(source);
    if (title.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.createSchedule,
        confidence: .75,
        clarification:
            'Sebutkan judul agenda Jadwal. Belum ada data yang diubah.',
      );
    }
    final startMinutes = _scheduleMinutesFromText(source);
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.schedule,
      createdAt: _clock(),
      title: title,
      date: date,
      formValues: {
        'entity': 'schedule_entry',
        'date': date.toIso8601String(),
        'isAllDay': (startMinutes == null).toString(),
        if (startMinutes != null) 'startMinutes': startMinutes.toString(),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: 'Aku menyiapkan Jadwal lokal tanpa alarm atau notifikasi. Cek preview dan konfirmasi bila sudah benar.',
    );
  }

  Future<FfmAssistantIntent> _draftScheduleMutation(
    String rawText,
    String normalized, {
    RegExpMatch? move,
    RegExpMatch? rename,
    RegExpMatch? archive,
  }) async {
    final operation = move != null || rename != null ? 'update' : 'archive';
    final targetSource =
        move?.group(1) ?? rename?.group(1) ?? archive?.group(1);
    final type = operation == 'archive'
        ? FfmAssistantIntentType.archiveSchedule
        : FfmAssistantIntentType.updateSchedule;
    if (targetSource == null) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: .5,
        clarification: 'Sebutkan Judul Jadwal yang ingin diubah. Belum ada data yang diubah.',
      );
    }
    final targetText = targetSource.trim();
    final candidates = await _findScheduleCandidates(targetText);
    if (candidates.isEmpty || candidates.length > 1) {
      final detail = candidates.isEmpty
          ? 'Aku tidak menemukan satu Jadwal aktif yang cocok dengan “$targetText”.'
          : 'Aku menemukan ${candidates.length} Jadwal yang cocok: ${candidates.take(3).map(_scheduleCandidateLabel).join('; ')}.';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: candidates.isEmpty ? .8 : .72,
        clarification:
            '$detail Sebut judul yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final replacement = move?.group(2)?.trim();
    final date = move == null
        ? target.scheduledDate
        : _scheduleDateFromText(replacement ?? '');
    if (move != null && date == null) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.updateSchedule,
        confidence: .75,
        clarification: 'Tanggal tujuan Jadwal belum dipahami. Gunakan “besok” atau format “tanggal 28/08/2026”. Belum ada data yang diubah.',
      );
    }
    final draft = FfmAssistantDraft(
      kind: operation == 'archive'
          ? FfmAssistantDraftKind.scheduleArchive
          : FfmAssistantDraftKind.scheduleUpdate,
      createdAt: _clock(),
      title: rename?.group(2)?.trim() ?? target.title,
      note: target.note,
      date: date,
      formValues: {
        'entity': 'schedule_entry',
        'targetId': target.id,
        'operation': operation,
        'targetSummary': _scheduleCandidateLabel(target),
        if (operation == 'update') 'date': date!.toIso8601String(),
        if (operation == 'update') 'isAllDay': target.isAllDay.toString(),
        if (operation == 'update' && target.startMinutes != null)
          'startMinutes': target.startMinutes.toString(),
        if (operation == 'update' && target.endMinutes != null)
          'endMinutes': target.endMinutes.toString(),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'archive'
          ? 'Aku menemukan satu Jadwal untuk diarsipkan tanpa hapus permanen. Cek preview dulu; belum ada data yang diubah.'
          : 'Aku menyiapkan perubahan satu Jadwal tanpa alarm atau notifikasi. Cek preview dulu; belum ada data yang diubah.',
    );
  }

  Future<FfmAssistantIntent?> _parseScheduleMutation(
    String rawText,
    String normalized,
  ) async {
    final create = RegExp(r'^(?:buat|tambah|jadwalkan)s+jadwals+(.+)$')
        .firstMatch(normalized);
    if (create != null) {
      final source = create.group(1)!.trim();
      final date = _scheduleDateFromText(source);
      if (date == null) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.createSchedule,
          confidence: .75,
          clarification: 'Sebutkan tanggal Jadwal, misalnya “buat jadwal kontrol dokter besok” atau “buat jadwal kontrol dokter tanggal 28/08/2026”. Belum ada data yang diubah.',
        );
      }
      final title = _scheduleTitleFromText(source);
      if (title.isEmpty) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.createSchedule,
          confidence: .75,
          clarification:
              'Sebutkan judul agenda Jadwal. Belum ada data yang diubah.',
        );
      }
      final startMinutes = _scheduleMinutesFromText(source);
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.schedule,
        createdAt: _clock(),
        title: title,
        date: date,
        formValues: {
          'entity': 'schedule_entry',
          'date': date.toIso8601String(),
          'isAllDay': (startMinutes == null).toString(),
          if (startMinutes != null) 'startMinutes': startMinutes.toString(),
        },
      );
      return _intentForDraft(rawText, normalized, draft).copyWith(
        response: 'Aku menyiapkan Jadwal lokal tanpa alarm atau notifikasi. Cek preview dan konfirmasi bila sudah benar.',
      );
    }

    final move = RegExp(
      r'^(?:pindah|pindahkan|jadwalkan ulang)s+jadwals+(.+?)s+kes+(.+)$',
    ).firstMatch(normalized);
    final rename = RegExp(
      r'^(?:ubah|ganti|koreksi)s+jadwals+(.+?)s+(?:jadi|menjadi)s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(r'^(?:arsip|arsipkan)s+jadwals+(.+)$')
        .firstMatch(normalized);
    if (move == null && rename == null && archive == null) return null;

    final operation = move != null
        ? 'update'
        : rename != null
        ? 'update'
        : 'archive';
    final targetSource =
        move?.group(1) ?? rename?.group(1) ?? archive?.group(1);
    if (targetSource == null) return null;
    final targetText = targetSource.trim();
    final candidates = await _findScheduleCandidates(targetText);
    final type = operation == 'archive'
        ? FfmAssistantIntentType.archiveSchedule
        : FfmAssistantIntentType.updateSchedule;
    if (candidates.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: .8,
        clarification:
            'Aku tidak menemukan satu Jadwal aktif yang cocok dengan “$targetText”. Sebut judul yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    if (candidates.length > 1) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: .72,
        clarification:
            'Aku menemukan ${candidates.length} Jadwal yang cocok: ${candidates.take(3).map(_scheduleCandidateLabel).join('; ')}. Sebut judul yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final replacement = move?.group(2)?.trim();
    final date = move == null
        ? target.scheduledDate
        : _scheduleDateFromText(replacement ?? '');
    if (move != null && date == null) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.updateSchedule,
        confidence: .75,
        clarification: 'Tanggal tujuan Jadwal belum dipahami. Gunakan “besok” atau format “tanggal 28/08/2026”. Belum ada data yang diubah.',
      );
    }
    final newTitle = rename?.group(2)?.trim() ?? target.title;
    final draft = FfmAssistantDraft(
      kind: operation == 'archive'
          ? FfmAssistantDraftKind.scheduleArchive
          : FfmAssistantDraftKind.scheduleUpdate,
      createdAt: _clock(),
      title: newTitle,
      note: target.note,
      date: date,
      formValues: {
        'entity': 'schedule_entry',
        'targetId': target.id,
        'operation': operation,
        'targetSummary': _scheduleCandidateLabel(target),
        if (operation == 'update') 'date': date!.toIso8601String(),
        if (operation == 'update') 'isAllDay': target.isAllDay.toString(),
        if (operation == 'update' && target.startMinutes != null)
          'startMinutes': target.startMinutes.toString(),
        if (operation == 'update' && target.endMinutes != null)
          'endMinutes': target.endMinutes.toString(),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'archive'
          ? 'Aku menemukan satu Jadwal untuk diarsipkan tanpa hapus permanen. Cek preview dulu; belum ada data yang diubah.'
          : 'Aku menyiapkan perubahan satu Jadwal tanpa alarm atau notifikasi. Cek preview dulu; belum ada data yang diubah.',
    );
  }

  Future<List<ScheduleEntry>> _findScheduleCandidates(String targetText) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where(
          (term) =>
              term.length >= 3 &&
              !const {
                'jadwal',
                'pada',
                'tanggal',
                'hari',
                'besok',
              }.contains(term) &&
              !RegExp(r'^\d+$').hasMatch(term),
        )
        .toSet();
    if (terms.isEmpty) return const [];
    final rows =
        await (_database.select(_database.scheduleEntries)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.scheduledDate)]))
            .get();
    return rows
        .where((row) {
          final haystack = '${row.title} ${row.note ?? ''}'.toLowerCase();
          return terms.every(haystack.contains);
        })
        .take(4)
        .toList(growable: false);
  }

  String _scheduleCandidateLabel(ScheduleEntry row) {
    final date = row.scheduledDate.toIso8601String().substring(0, 10);
    final time = row.isAllDay || row.startMinutes == null
        ? 'sepanjang hari'
        : '${(row.startMinutes! ~/ 60).toString().padLeft(2, '0')}:${(row.startMinutes! % 60).toString().padLeft(2, '0')}';
    return '${row.title} • $date • $time';
  }

  DateTime? _scheduleDateFromText(String value) {
    final now = _clock();
    if (RegExp(r'\b(?:besok|esok)\b').hasMatch(value)) {
      return DateTime(now.year, now.month, now.day + 1);
    }
    if (RegExp(r'\b(?:hari ini|sekarang)\b').hasMatch(value)) {
      return DateTime(now.year, now.month, now.day);
    }
    final numeric = RegExp(
      r'\btanggal\s+(\d{1,2})[/-](\d{1,2})(?:[/-](\d{4}))?\b',
    ).firstMatch(value);
    if (numeric == null) return null;
    final day = int.tryParse(numeric.group(1)!);
    final month = int.tryParse(numeric.group(2)!);
    final year = int.tryParse(numeric.group(3) ?? '') ?? now.year;
    if (day == null || month == null || day < 1 || month < 1 || month > 12) {
      return null;
    }
    final date = DateTime(year, month, day);
    return date.day == day && date.month == month ? date : null;
  }

  int? _scheduleMinutesFromText(String value) {
    final match = RegExp(r'\b(?:jam|pukul)\s*(\d{1,2})(?:[.:](\d{2}))?\b')
        .firstMatch(value);
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2) ?? '0');
    if (hour == null || minute == null || hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  String _scheduleTitleFromText(String value) => value
      .replaceAll(RegExp(r'\b(?:hari ini|besok|esok)\b'), '')
      .replaceAll(RegExp(r'\btanggal\s+\d{1,2}[/-]\d{1,2}(?:[/-]\d{4})?\b'), '')
      .replaceAll(RegExp(r'\b(?:jam|pukul)\s*\d{1,2}(?:[.:]\d{2})?\b'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _taskCandidateLabel(Task row) {
    final due = row.dueDate == null
        ? ''
        : ' • target ${row.dueDate!.toIso8601String().substring(0, 10)}';
    return '${row.title}$due';
  }

  Future<FfmAssistantIntent?> _parseReminderMutation(
    String rawText,
    String normalized,
  ) async {
    final update = RegExp(
      r'^(?:ubah|ganti|koreksi|jadwalkan ulang)\s+pengingat\s+(.+?)\s+(?:jadi|menjadi|ke)\s+(.+)$',
    ).firstMatch(normalized);
    if (update != null) {
      final targetText = update.group(1)!.trim();
      final changeText = update.group(2)!.trim();
      final candidates = await _findReminderCandidates(targetText);
      if (candidates.isEmpty || candidates.length > 1) {
        final detail = candidates.isEmpty
            ? 'Aku tidak menemukan satu pengingat aktif yang cocok dengan “$targetText”.'
            : 'Aku menemukan ${candidates.length} pengingat yang cocok: ${candidates.take(3).map(_reminderCandidateLabel).join('; ')}.';
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.updateReminder,
          confidence: candidates.isEmpty ? .8 : .72,
          clarification:
              '$detail Sebut judul pengingat yang lebih spesifik. Belum ada data yang diubah.',
        );
      }
      final target = candidates.single;
      final parsedDate = _scheduleDateFromText(changeText);
      final parsedMinutes = _scheduleMinutesFromText(changeText);
      final day = parsedDate ?? target.scheduledAt;
      final scheduledAt = DateTime(
        day.year,
        day.month,
        day.day,
        parsedMinutes == null ? target.scheduledAt.hour : parsedMinutes ~/ 60,
        parsedMinutes == null ? target.scheduledAt.minute : parsedMinutes % 60,
      );
      final titleCandidate = _scheduleTitleFromText(changeText);
      final title = titleCandidate.isEmpty ? target.title : titleCandidate;
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.reminderUpdate,
        createdAt: _clock(),
        title: title,
        note: target.note,
        date: scheduledAt,
        formValues: {
          'entity': 'reminder',
          'targetId': target.id,
          'operation': 'update',
          'targetSummary': _reminderCandidateLabel(target),
          'scheduledAt': scheduledAt.toIso8601String(),
          'preserveRecurrence': 'true',
          'preserveSound': 'true',
          'preserveNotificationId': 'true',
        },
      );
      return _intentForDraft(rawText, normalized, draft).copyWith(
        response: 'Aku menyiapkan perubahan satu pengingat. Pola berulang, suara, snooze, dan identitas notifikasi akan dipertahankan. Cek preview lalu konfirmasi; belum ada data yang diubah.',
      );
    }
    final archive = RegExp(
      r'^(?:arsip|arsipkan|nonaktifkan|matikan)\s+pengingat\s+(.+)$',
    ).firstMatch(normalized);
    if (archive == null) return null;
    final targetText = archive.group(1)!.trim();
    final candidates = await _findReminderCandidates(targetText);
    if (candidates.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.archiveReminder,
        confidence: .8,
        clarification:
            'Aku tidak menemukan satu pengingat aktif yang cocok dengan “$targetText”. Sebut judul pengingat yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    if (candidates.length > 1) {
      final options = candidates
          .take(3)
          .map(_reminderCandidateLabel)
          .join('; ');
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.archiveReminder,
        confidence: .72,
        clarification:
            'Aku menemukan ${candidates.length} pengingat yang cocok: $options. Sebut judul yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.reminderArchive,
      createdAt: _clock(),
      title: _reminderCandidateLabel(target),
      date: target.scheduledAt,
      formValues: {
        'entity': 'reminder',
        'targetId': target.id,
        'operation': 'archive',
        'targetSummary': _reminderCandidateLabel(target),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: 'Aku menemukan satu pengingat aktif untuk dinonaktifkan. Alarm berikutnya akan dibatalkan, tetapi riwayat tetap tersimpan. Cek preview dulu sebelum mengonfirmasi.',
    );
  }

  Future<List<Reminder>> _findReminderCandidates(String targetText) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where(
          (term) =>
              term.length >= 3 &&
              !const {
                'pengingat',
                'pada',
                'tanggal',
                'hari',
                'besok',
              }.contains(term) &&
              !RegExp(r'^\d+$').hasMatch(term),
        )
        .toSet();
    if (terms.isEmpty) return const [];
    final rows =
        await (_database.select(_database.reminders)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isActive.equals(true),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.scheduledAt)]))
            .get();
    return rows
        .where((row) => terms.every(row.title.toLowerCase().contains))
        .take(4)
        .toList(growable: false);
  }

  String _reminderCandidateLabel(Reminder row) =>
      '${row.title} • ${row.scheduledAt.toIso8601String().substring(0, 16)}';

  Future<FfmAssistantIntent?> _parseAssetMutation(
    String rawText,
    String normalized,
  ) async {
    final update = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+aset\s+(.+?)\s+(?:jadi|menjadi|ke)\s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(r'^(?:arsip|arsipkan)\s+aset\s+(.+)$')
        .firstMatch(normalized);
    if (update == null && archive == null) return null;
    final operation = update == null ? 'archive' : 'update';
    final targetText = (update?.group(1) ?? archive!.group(1)!).trim();
    final candidates = await _findAssetCandidates(targetText);
    final type = operation == 'update'
        ? FfmAssistantIntentType.updateAsset
        : FfmAssistantIntentType.archiveAsset;
    if (candidates.isEmpty || candidates.length > 1) {
      final detail = candidates.isEmpty
          ? 'Aku tidak menemukan satu aset aktif yang cocok dengan “$targetText”.'
          : 'Aku menemukan ${candidates.length} aset yang cocok: ${candidates.take(3).map(_assetCandidateLabel).join('; ')}.';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: candidates.isEmpty ? .8 : .72,
        clarification:
            '$detail Sebut nama aset yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    if (operation == 'archive') {
      final draft = FfmAssistantDraft(
        kind: FfmAssistantDraftKind.assetArchive,
        createdAt: _clock(),
        title: target.name,
        amount: target.value,
        formValues: {
          'entity': 'asset',
          'targetId': target.id,
          'operation': 'archive',
          'targetSummary': _assetCandidateLabel(target),
        },
      );
      return _intentForDraft(rawText, normalized, draft).copyWith(
        response: 'Aku menemukan satu aset untuk diarsipkan tanpa hapus permanen. Tidak ada transaksi atau saldo yang diubah. Cek preview dulu.',
      );
    }
    final replacement = update!.group(2)!.trim();
    final parsedValue = FfmAssistantAmountParser.parse(replacement);
    final title = _assetTitleFromReplacement(
      replacement,
      fallback: target.name,
    );
    final draft = FfmAssistantDraft(
      kind: FfmAssistantDraftKind.assetUpdate,
      createdAt: _clock(),
      title: title,
      amount: parsedValue ?? target.value,
      note: target.note,
      formValues: {
        'entity': 'asset',
        'targetId': target.id,
        'operation': 'update',
        'targetSummary': _assetCandidateLabel(target),
        'assetType': target.assetType,
        'placement': target.placement,
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: 'Aku menyiapkan perubahan satu aset. Tidak ada transaksi atau saldo yang akan dibuat. Cek preview lalu konfirmasi.',
    );
  }

  Future<List<Asset>> _findAssetCandidates(String targetText) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where(
          (term) =>
              term.length >= 3 &&
              term != 'aset' &&
              !RegExp(r'^\d+$').hasMatch(term),
        )
        .toSet();
    if (terms.isEmpty) return const [];
    final rows =
        await (_database.select(_database.assets)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .get();
    return rows
        .where((row) {
          final haystack = '${row.name} ${row.assetType} ${row.placement}'
              .toLowerCase();
          return terms.every(haystack.contains);
        })
        .take(4)
        .toList(growable: false);
  }

  String _assetCandidateLabel(Asset row) =>
      '${row.name} • ${row.assetType} • ${row.value}';

  String _assetTitleFromReplacement(String value, {required String fallback}) {
    final withoutAmount = value
        .replaceAll(
          RegExp(r'\b(?:rp|rupiah|nilai)\b', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\d+(?:[.,]\d+)*(?:\s*(?:rb|ribu|jt|juta|m))?'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return withoutAmount.isEmpty ? fallback : withoutAmount;
  }

  Future<FfmAssistantIntent?> _parseLiabilityMutation(
    String rawText,
    String normalized,
  ) async {
    final update = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+(?:hutang|utang)\s+(.+?)\s+(?:jadi|menjadi)\s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(r'^(?:arsip|arsipkan)\s+(?:hutang|utang)\s+(.+)$')
        .firstMatch(normalized);
    if (update == null && archive == null) return null;
    final operation = update == null ? 'archive' : 'update';
    final targetText = (update?.group(1) ?? archive!.group(1)!).trim();
    final rows =
        await (_database.select(_database.liabilities)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final terms = targetText
        .split(RegExp(r'\s+'))
        .where((term) => term.length >= 3)
        .toList();
    final candidates = rows
        .where((row) => terms.every(row.name.toLowerCase().contains))
        .take(4)
        .toList(growable: false);
    final type = operation == 'update'
        ? FfmAssistantIntentType.updateLiability
        : FfmAssistantIntentType.archiveLiability;
    if (candidates.length != 1) {
      final detail = candidates.isEmpty
          ? 'Aku tidak menemukan satu Hutang aktif yang cocok dengan “$targetText”.'
          : 'Aku menemukan ${candidates.length} Hutang yang cocok: ${candidates.map((row) => row.name).join('; ')}.';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: candidates.isEmpty ? .8 : .72,
        clarification:
            '$detail Sebut nama Hutang yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final draft = FfmAssistantDraft(
      kind: operation == 'update'
          ? FfmAssistantDraftKind.liabilityUpdate
          : FfmAssistantDraftKind.liabilityArchive,
      createdAt: _clock(),
      title: operation == 'update' ? update!.group(2)!.trim() : target.name,
      note: target.note,
      date: target.dueDate ?? target.startDate,
      formValues: {
        'entity': 'liability',
        'targetId': target.id,
        'operation': operation,
        'targetSummary': '${target.name} • sisa ${target.remainingBalance}',
        'originalAmount': target.originalAmount.toString(),
        'remainingBalance': target.remainingBalance.toString(),
        'monthlyInstallment': target.monthlyInstallment.toString(),
        'interestRate': target.interestRate.toString(),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'update'
          ? 'Aku menyiapkan perubahan metadata satu Hutang. Nilai pokok dan sisa Hutang tidak akan diubah. Cek preview dulu.'
          : 'Aku menyiapkan arsip lunak satu Hutang tanpa hapus permanen, pembayaran, atau transaksi. Cek preview dulu.',
    );
  }

  Future<FfmAssistantIntent?> _parseReceivableMutation(
    String rawText,
    String normalized,
  ) async {
    final update = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+piutang\s+(.+?)\s+(?:jadi|menjadi)\s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(r'^(?:arsip|arsipkan)\s+piutang\s+(.+)$')
        .firstMatch(normalized);
    if (update == null && archive == null) return null;
    final operation = update == null ? 'archive' : 'update';
    final targetText = (update?.group(1) ?? archive!.group(1)!).trim();
    final rows =
        await (_database.select(_database.receivables)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final terms = targetText
        .split(RegExp(r'\s+'))
        .where((term) => term.length >= 3)
        .toList();
    final candidates = rows
        .where((row) => terms.every(row.name.toLowerCase().contains))
        .take(4)
        .toList(growable: false);
    final type = operation == 'update'
        ? FfmAssistantIntentType.updateReceivable
        : FfmAssistantIntentType.archiveReceivable;
    if (candidates.length != 1)
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: candidates.isEmpty ? .8 : .72,
        clarification: candidates.isEmpty
            ? 'Aku tidak menemukan satu Piutang aktif yang cocok dengan “$targetText”. Belum ada data yang diubah.'
            : 'Aku menemukan ${candidates.length} Piutang yang cocok. Sebut nama yang lebih spesifik. Belum ada data yang diubah.',
      );
    final target = candidates.single;
    final draft = FfmAssistantDraft(
      kind: operation == 'update'
          ? FfmAssistantDraftKind.receivableUpdate
          : FfmAssistantDraftKind.receivableArchive,
      createdAt: _clock(),
      title: operation == 'update' ? update!.group(2)!.trim() : target.name,
      note: target.note,
      date: target.dueDate ?? target.startDate,
      formValues: {
        'entity': 'receivable',
        'targetId': target.id,
        'operation': operation,
        'originalAmount': target.originalAmount.toString(),
        'remainingBalance': target.remainingBalance.toString(),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'update'
          ? 'Aku menyiapkan perubahan metadata Piutang. Nilai pokok dan sisa Piutang tidak akan diubah. Cek preview dulu.'
          : 'Aku menyiapkan arsip lunak Piutang tanpa hapus permanen, penagihan, atau transaksi. Cek preview dulu.',
    );
  }

  Future<FfmAssistantIntent?> _parseRecurringTransactionMutation(
    String rawText,
    String normalized,
  ) async {
    final updateName = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+(?:jadwal\s+)?(?:transaksi\s+)?berkala\s+(.+?)\s+(?:jadi|menjadi)\s+(.+)$',
    ).firstMatch(normalized);
    final updateNote = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+catatan\s+(?:jadwal\s+)?(?:transaksi\s+)?berkala\s+(.+?)\s+(?:jadi|menjadi)\s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(
      r'^(?:arsip|arsipkan|nonaktifkan)\s+(?:jadwal\s+)?(?:transaksi\s+)?berkala\s+(.+)$',
    ).firstMatch(normalized);
    if (updateName == null && updateNote == null && archive == null) {
      return null;
    }

    final operation = updateName == null && updateNote == null
        ? 'archive'
        : 'update';
    final metadataField = updateNote == null ? 'name' : 'note';
    final targetText =
        (updateName?.group(1) ?? updateNote?.group(1) ?? archive!.group(1)!)
            .trim();
    final rows =
        await (_database.select(_database.recurringTransactions)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final terms = targetText
        .split(RegExp(r'\s+'))
        .where((term) => term.length >= 3)
        .toList();
    final candidates = rows
        .where((row) => terms.every(row.name.toLowerCase().contains))
        .take(4)
        .toList(growable: false);
    final type = operation == 'update'
        ? FfmAssistantIntentType.updateRecurringTransaction
        : FfmAssistantIntentType.archiveRecurringTransaction;
    if (candidates.length != 1) {
      final detail = candidates.isEmpty
          ? 'Aku tidak menemukan satu jadwal Transaksi Berkala aktif yang cocok dengan “$targetText”.'
          : 'Aku menemukan ${candidates.length} jadwal Transaksi Berkala yang cocok: ${candidates.map((row) => row.name).join('; ')}.';
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: type,
        confidence: candidates.isEmpty ? .8 : .72,
        clarification:
            '$detail Sebut nama jadwal yang lebih spesifik. Belum ada aturan, transaksi, atau run yang diubah.',
      );
    }

    final target = candidates.single;
    final draft = FfmAssistantDraft(
      kind: operation == 'update'
          ? FfmAssistantDraftKind.recurringTransactionUpdate
          : FfmAssistantDraftKind.recurringTransactionArchive,
      createdAt: _clock(),
      title: metadataField == 'name' && operation == 'update'
          ? updateName!.group(2)!.trim()
          : target.name,
      note: metadataField == 'note' && operation == 'update'
          ? updateNote!.group(2)!.trim()
          : target.note,
      date: target.startDate,
      formValues: {
        'entity': 'recurring_transaction',
        'targetId': target.id,
        'operation': operation,
        'metadataField': metadataField,
        'targetSummary': '${target.name} • ${target.periodType}',
        'amount': target.amount.toString(),
        'type': target.type,
        'periodType': target.periodType,
        'calcMode': target.calcMode,
        'ratePercent': target.ratePercent?.toString() ?? '',
        'accountId': target.accountId ?? '',
        'categoryId': target.categoryId ?? '',
        'sourceId': target.sourceId ?? '',
        'startDate': target.startDate.toIso8601String(),
        'endDate': target.endDate?.toIso8601String() ?? '',
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'update'
          ? 'Aku menyiapkan perubahan ${metadataField == 'note' ? 'catatan' : 'nama'} satu Transaksi Berkala. Jadwal tidak akan dijalankan dan tidak ada transaksi baru dibuat. Cek preview dulu.'
          : 'Aku menyiapkan penonaktifan satu Transaksi Berkala tanpa mengubah riwayat, transaksi, atau run. Cek preview dulu.',
    );
  }

  Future<FfmAssistantIntent?> _parseGoalMutation(
    String rawText,
    String normalized,
  ) async {
    final update = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+(?:target|goal)(?:\s+keuangan)?\s+(.+?)\s+(?:jadi|menjadi|ke)\s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(
      r'^(?:arsip|arsipkan)\s+(?:target|goal)(?:\s+keuangan)?\s+(.+)$',
    ).firstMatch(normalized);
    if (update == null && archive == null) return null;

    final operation = update == null ? 'archive' : 'update';
    final targetText = (update?.group(1) ?? archive!.group(1)!).trim();
    final amount = update == null
        ? null
        : FfmAssistantAmountParser.parse(update.group(2)!);
    if (operation == 'update' && (amount == null || amount <= 0)) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.updateGoal,
        confidence: .7,
        clarification: 'Sebut nominal target baru setelah kata “jadi”, misalnya: “ubah target dana darurat jadi 5000000”. Belum ada data yang diubah.',
      );
    }
    final candidates = await _findGoalCandidates(targetText);
    if (candidates.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: operation == 'update'
            ? FfmAssistantIntentType.updateGoal
            : FfmAssistantIntentType.archiveGoal,
        confidence: .8,
        clarification:
            'Aku tidak menemukan satu target keuangan aktif yang cocok dengan “$targetText”. Sebut nama target yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    if (candidates.length > 1) {
      final options = candidates.take(3).map(_goalCandidateLabel).join('; ');
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: operation == 'update'
            ? FfmAssistantIntentType.updateGoal
            : FfmAssistantIntentType.archiveGoal,
        confidence: .72,
        clarification:
            'Aku menemukan ${candidates.length} target yang cocok: $options. Sebut nama target yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final draft = FfmAssistantDraft(
      kind: operation == 'update'
          ? FfmAssistantDraftKind.goalUpdate
          : FfmAssistantDraftKind.goalArchive,
      createdAt: _clock(),
      amount: amount,
      title: _goalCandidateLabel(target),
      date: target.targetDate,
      formValues: {
        'entity': 'goal',
        'targetId': target.id,
        'operation': operation,
        'oldTargetAmount': target.targetAmount.toString(),
        'currentAmount': target.currentAmount.toString(),
        'targetSummary': _goalCandidateLabel(target),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'update'
          ? 'Aku menemukan satu target dan menyiapkan perubahan dari ${_money(target.targetAmount)} menjadi ${_money(amount!)}. Cek preview dulu; belum ada data yang diubah.'
          : 'Aku menemukan satu target untuk diarsipkan. Progresnya tetap tersimpan; cek preview dulu sebelum mengonfirmasi.',
    );
  }

  Future<List<Goal>> _findGoalCandidates(String targetText) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where(
          (term) =>
              term.length >= 3 &&
              !const {
                'target',
                'goal',
                'keuangan',
                'pada',
                'tanggal',
                'ribu',
                'rupiah',
              }.contains(term) &&
              !RegExp(r'^\d+$').hasMatch(term),
        )
        .toSet();
    if (terms.isEmpty) return const [];
    final rows =
        await (_database.select(_database.goals)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isActive.equals(true),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.targetDate)]))
            .get();
    return rows
        .where((row) => terms.every(row.name.toLowerCase().contains))
        .take(4)
        .toList(growable: false);
  }

  String _goalCandidateLabel(Goal row) =>
      '${row.name} • ${_money(row.currentAmount)} dari ${_money(row.targetAmount)}';

  Future<FfmAssistantIntent?> _parseTransactionMutation(
    String rawText,
    String normalized,
  ) async {
    final update = RegExp(
      r'^(?:ubah|ganti|koreksi)\s+transaksi\s+(.+?)\s+(?:jadi|menjadi|ke)\s+(.+)$',
    ).firstMatch(normalized);
    final archive = RegExp(r'^(?:arsip|arsipkan)\s+transaksi\s+(.+)$')
        .firstMatch(normalized);
    final delete = RegExp(r'^hapus\s+transaksi\s+(.+)$').firstMatch(normalized);
    if (update == null && archive == null && delete == null) return null;

    final operation = update != null
        ? 'update'
        : archive != null
        ? 'archive'
        : 'delete';
    final targetText =
        (update?.group(1) ?? archive?.group(1) ?? delete!.group(1)!).trim();
    final amount = update == null
        ? null
        : FfmAssistantAmountParser.parse(update.group(2)!);
    if (operation == 'update' && (amount == null || amount <= 0)) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.updateTransaction,
        confidence: .7,
        clarification: 'Sebut nominal baru setelah kata “jadi”, misalnya: “ubah transaksi kopi jadi 25000”. Belum ada data yang diubah.',
      );
    }
    final candidates = await _findTransactionCandidates(targetText);
    if (candidates.isEmpty) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: _mutationIntentType(operation),
        confidence: .8,
        clarification:
            'Aku tidak menemukan satu transaksi aktif yang cocok dengan “$targetText”. Sebut kata pada catatan atau pihak transaksi. Belum ada data yang diubah.',
      );
    }
    if (candidates.length > 1) {
      final options = candidates
          .take(3)
          .map(_transactionCandidateLabel)
          .join('; ');
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: _mutationIntentType(operation),
        confidence: .72,
        clarification:
            'Aku menemukan ${candidates.length} transaksi yang cocok: $options. Sebut kata catatan yang lebih spesifik. Belum ada data yang diubah.',
      );
    }
    final target = candidates.single;
    final kind = switch (operation) {
      'update' => FfmAssistantDraftKind.transactionUpdate,
      'archive' => FfmAssistantDraftKind.transactionArchive,
      _ => FfmAssistantDraftKind.transactionDelete,
    };
    final draft = FfmAssistantDraft(
      kind: kind,
      createdAt: _clock(),
      amount: amount,
      title: _transactionCandidateLabel(target),
      note: target.note,
      date: target.date,
      formValues: {
        'targetId': target.id,
        'operation': operation,
        'oldAmount': target.amount.abs().toString(),
        'targetSummary': _transactionCandidateLabel(target),
      },
    );
    return _intentForDraft(rawText, normalized, draft).copyWith(
      response: operation == 'update'
          ? 'Aku menemukan satu transaksi dan menyiapkan perubahan dari ${_money(target.amount.abs())} menjadi ${_money(amount!)}. Cek preview dulu; belum ada data yang diubah.'
          : operation == 'archive'
          ? 'Aku menemukan satu transaksi untuk diarsipkan. Cek preview dulu; transaksi belum dipindahkan dari daftar aktif.'
          : 'Aku menemukan satu transaksi untuk dihapus dari daftar aktif. Cek preview dulu; jejak audit lokal tetap dipertahankan.',
    );
  }

  FfmAssistantIntentType _mutationIntentType(String operation) =>
      switch (operation) {
        'update' => FfmAssistantIntentType.updateTransaction,
        'archive' => FfmAssistantIntentType.archiveTransaction,
        _ => FfmAssistantIntentType.deleteTransaction,
      };

  Future<List<Transaction>> _findTransactionCandidates(
    String targetText,
  ) async {
    final terms = targetText
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((term) => term.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where(
          (term) =>
              term.length >= 3 &&
              !const {
                'transaksi',
                'pada',
                'tanggal',
                'ribu',
                'rupiah',
              }.contains(term) &&
              !RegExp(r'^\d+$').hasMatch(term),
        )
        .toSet();
    if (terms.isEmpty) return const [];
    final rows =
        await (_database.select(_database.transactions)
              ..where(
                (row) =>
                    row.householdId.equals(AppContext.householdId) &
                    row.isArchived.equals(false) &
                    row.isDeleted.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.date)]))
            .get();
    return rows
        .where((row) {
          final haystack = '${row.note ?? ''} ${row.partyName ?? ''}'
              .toLowerCase();
          return terms.every(haystack.contains);
        })
        .take(4)
        .toList(growable: false);
  }

  String _transactionCandidateLabel(Transaction row) {
    final kind = row.type == 'income' ? 'pemasukan' : 'pengeluaran';
    final detail = (row.note ?? row.partyName ?? 'tanpa catatan').trim();
    final date = row.date.toIso8601String().substring(0, 10);
    return '$kind ${_money(row.amount.abs())} • $detail • $date';
  }

  String _money(int amount) =>
      'Rp${amount.toString().replaceAllMapped(RegExp(r'(?=(\d{3})+(?!\d))'), (_) => '.')}';

  FfmAssistantDraft? _parseFinancialDraft(
    String rawText,
    String normalized,
    List<Account> accounts,
    List<Category> categories,
  ) {
    final now = DateTime.now();
    final amount = FfmAssistantAmountParser.parse(normalized);
    final adminFee = _parseAdminFee(normalized);
    final createBudget = _containsAny(normalized, const [
      'atur anggaran',
      'buat anggaran',
      'tambah anggaran',
      'set anggaran',
    ]);
    if (createBudget) {
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.budget,
        createdAt: now,
        amount: amount,
        title: _draftTitle(normalized, const [
          'atur anggaran',
          'buat anggaran',
          'tambah anggaran',
          'set anggaran',
        ]),
        note: rawText.trim(),
        date: now,
      );
    }
    final masterData = _masterDataRequest(normalized);
    if (masterData != null) {
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.masterData,
        createdAt: now,
        title: _draftTitle(normalized, masterData.$2),
        categoryName: masterData.$1,
        note: rawText.trim(),
        date: now,
      );
    }
    final createProfile = _containsAny(normalized, const [
      'buat profil',
      'isi profil',
      'ubah profil',
      'perbarui profil',
      'kenalan',
    ]);
    if (createProfile) {
      final profileValues = _extractProfileValues(rawText);
      final profileNote = profileValues.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.profile,
        createdAt: now,
        title: 'Perkenalan Diri',
        note: profileNote.isEmpty ? rawText.trim() : profileNote,
        formValues: profileValues,
        date: now,
      );
    }
    final dailyNote = RegExp(
      r'^(?:catat|tulis|buat)(?:kan)?\s+(?:catatan harian|catatan)\s*[:\-]?\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(rawText.trim());
    if (dailyNote != null) {
      final body = dailyNote.group(1)?.trim() ?? '';
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.dailyNote,
        createdAt: now,
        note: body,
        date: now,
        formValues: {'body': body},
      );
    }
    final createActivity = _containsAny(normalized, const [
      'mulai aktivitas',
      'mulai kegiatan',
      'catat aktivitas',
      'buat aktivitas',
    ]);
    if (createActivity) {
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.activity,
        createdAt: now,
        title: _draftTitle(normalized, const [
          'mulai aktivitas',
          'mulai kegiatan',
          'catat aktivitas',
          'buat aktivitas',
        ]),
        note: rawText.trim(),
        date: now,
      );
    }
    final createReminder = _containsAny(normalized, const [
      'buat pengingat',
      'tambah pengingat',
      'ingatkan saya',
      'pasang pengingat',
    ]);
    if (createReminder) {
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.reminder,
        createdAt: now,
        title: _draftTitle(normalized, const [
          'buat pengingat',
          'tambah pengingat',
          'ingatkan saya',
          'pasang pengingat',
        ]),
        note: rawText.trim(),
        date: now.add(const Duration(hours: 1)),
      );
    }
    final asset = _containsAny(normalized, const [
      'tambah aset',
      'buat aset',
      'catat aset',
    ]);
    if (asset) {
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.asset,
        createdAt: now,
        amount: amount,
        title: _draftTitle(normalized, const [
          'tambah aset',
          'buat aset',
          'catat aset',
        ]),
        note: rawText.trim(),
        date: now,
      );
    }
    final createGoal = _containsAny(normalized, const [
      'target baru',
      'buat target',
      'buatkan target',
    ]);
    if (createGoal) {
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.goal,
        createdAt: now,
        amount: amount,
        title: _draftTitle(normalized, const [
          'target baru',
          'buatkan target',
          'buat target',
        ]),
        note: rawText.trim(),
        date: now.add(const Duration(days: 30)),
      );
    }
    final transfer = _containsAny(normalized, const [
      'pindahkan',
      'pindah uang',
      'transfer',
      'kirim uang',
      'geser uang',
      'cairkan',
    ]);
    if (transfer) {
      final fromTo = _parseTransferAccounts(normalized, accounts);
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.transfer,
        createdAt: now,
        amount: amount,
        fromAccountName: fromTo.$1?.name,
        toAccountName: fromTo.$2?.name,
        adminFee: adminFee,
        note: rawText.trim(),
        date: now,
      );
    }

    final goalUsage = _containsAny(normalized, const [
      'pakai target',
      'pakai dana target',
      'ambil dari target',
    ]);
    if (goalUsage) {
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.goalUsage,
        createdAt: now,
        amount: amount,
        goalName: _extractAfter(normalized, const ['target', 'dana target']),
        note: rawText.trim(),
        date: now,
      );
    }
    final goalDeposit = _containsAny(normalized, const [
      'setor target',
      'isi target',
      'masukkan ke target',
      'tambah target',
    ]);
    if (goalDeposit) {
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.goalDeposit,
        createdAt: now,
        amount: amount,
        goalName: _extractAfter(normalized, const ['target']),
        note: rawText.trim(),
        date: now,
      );
    }

    final isReceivable = _containsAny(normalized, const [
      'piutang',
      'pinjam uang dari saya',
      'minjam uang dari saya',
      'meminjam dari saya',
    ]);
    if (isReceivable) {
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.receivable,
        createdAt: now,
        amount: amount,
        partyName: _extractParty(normalized, const [
          'piutang ke',
          'pinjam uang',
        ]),
        note: rawText.trim(),
        date: now,
      );
    }
    final isLiability = _containsAny(normalized, const [
      'hutang',
      'utang',
      'saya pinjam dari',
      'saya meminjam dari',
    ]);
    if (isLiability) {
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.liability,
        createdAt: now,
        amount: amount,
        partyName: _extractParty(normalized, const [
          'hutang ke',
          'utang ke',
          'pinjam dari',
        ]),
        note: rawText.trim(),
        date: now,
      );
    }

    final income = _containsAny(normalized, const [
      'pemasukan',
      'uang masuk',
      'terima',
      'menerima',
      'gaji',
      'pendapatan',
      'hasil panen',
      'terjual',
      'dapat uang',
      'dapet uang',
      'dikasih uang',
    ]);
    final expense = _containsAny(normalized, const [
      'pengeluaran',
      'uang keluar',
      'beli',
      'belanja',
      'bayar',
      'jajan',
      'dibeli',
      'keluar uang',
      'bayarin',
    ]);
    if (!income && !expense) return null;
    final transactionType = income && !expense ? 'income' : 'expense';
    final category = _matchCategory(normalized, categories, transactionType);
    final selectedAccount = _matchAccount(normalized, accounts);
    final slmFieldValues = <String, String>{
      if (category != null) 'category': category.name,
      if (selectedAccount != null) 'account': selectedAccount.name,
    };
    return FfmAssistantDraft(
      kind: income && !expense
          ? FfmAssistantDraftKind.income
          : FfmAssistantDraftKind.expense,
      createdAt: now,
      amount: amount,
      categoryName: category?.name,
      toAccountName: income ? selectedAccount?.name : null,
      fromAccountName: expense ? selectedAccount?.name : null,
      note: rawText.trim(),
      merchantName: _extractMerchant(normalized),
      slmFieldValues: slmFieldValues,
      date: now,
    );
  }

  FfmAssistantIntent? _parseCorrection(String rawText, String normalized) {
    final match = RegExp(
      r'^(?:ganti|ubah|koreksi)\s+(.+?)\s+(?:jadi|menjadi|ke)\s+(.+)$',
    ).firstMatch(normalized);
    if (match == null) return null;
    final oldText = match.group(1)!.trim();
    final newText = match.group(2)!.trim();
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.replaceDraftText,
      confidence: .95,
      response:
          'Siap, aku akan mengganti “$oldText” menjadi “$newText” di draft yang sedang aktif. Cek hasilnya sebelum disimpan, ya.',
    );
  }

  FfmAssistantIntent? _parseUserProfileMemory(
    String rawText,
    String normalized,
  ) {
    final match = RegExp(
      r'^(?:nama saya|panggil saya|panggil aku|ingat nama saya)\s+(.+)$',
    ).firstMatch(normalized);
    final displayName = match
        ?.group(1)
        ?.trim()
        .replaceAll(RegExp(r'[.!?]+$'), '');
    if (displayName == null || displayName.isEmpty || displayName.length > 80) {
      return null;
    }
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.teachMemory,
      confidence: .98,
      response:
          'Aku bisa mengingat bahwa kamu ingin dipanggil “$displayName”. Cek dulu lalu pilih Simpan ajaran jika sudah pas, ya.',
      teachingProposal: FfmAssistantTeachingProposal(
        kind: 'user_profile',
        triggerText: 'nama_panggilan',
        valueText: displayName,
      ),
    );
  }

  FfmAssistantIntent? _parseAliasMemory(String rawText, String normalized) {
    final match = RegExp(
      r'^(?:ingat|simpan)\s+(?:alias\s+)?(.+?)\s+(?:itu|=|sebagai)\s+(.+)$',
    ).firstMatch(normalized);
    if (match == null) return null;
    final alias = match.group(1)?.trim();
    final canonical = match.group(2)?.trim();
    if (alias == null ||
        canonical == null ||
        alias.isEmpty ||
        canonical.isEmpty) {
      return null;
    }
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.teachMemory,
      confidence: .95,
      response:
          'Aku menangkap ajaran ini: “$alias” berarti “$canonical”. Cek dulu lalu pilih Simpan ajaran kalau sudah pas, ya.',
      teachingProposal: FfmAssistantTeachingProposal(
        kind: 'alias',
        triggerText: alias,
        valueText: canonical,
      ),
    );
  }

  (Account?, Account?) _parseTransferAccounts(
    String normalized,
    List<Account> accounts,
  ) {
    final match = RegExp(r'\bdari\s+(.+?)\s+ke\s+(.+?)(?:\s+admin\b|$)')
        .firstMatch(normalized);
    if (match == null) return (null, null);
    return (
      _matchAccount(match.group(1)!, accounts),
      _matchAccount(match.group(2)!, accounts),
    );
  }

  Account? _matchAccount(String text, List<Account> accounts) {
    final matches = accounts.where(
      (account) => text.contains(account.name.toLowerCase()),
    );
    if (matches.isNotEmpty) return matches.first;
    final normalizedText = text.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final typoMatches = accounts.where(
      (account) => FfmAssistantTypoNormalizer.isSafeNearMatch(
        normalizedText,
        account.name.toLowerCase(),
      ),
    );
    if (typoMatches.length == 1) return typoMatches.single;
    final trigramMatches =
        accounts
            .map((account) {
              final score = FfmAssistantTypoNormalizer.trigramSimilarity(
                normalizedText,
                account.name.toLowerCase(),
              );
              return (account, score);
            })
            .where((entry) => entry.$2 >= 0.5)
            .toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));
    if (trigramMatches.length == 1) return trigramMatches.single.$1;
    return null;
  }

  Category? _matchCategory(
    String text,
    List<Category> categories,
    String type,
  ) {
    final candidates = categories
        .where((item) => item.type == type)
        .where((item) {
          final name = item.name.toLowerCase().trim();
          return name.length > 2 && text.contains(name);
        })
        .toList(growable: false);
    if (candidates.length == 1) return candidates.single;
    if (candidates.length > 1) return null;
    final normalizedText = text.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final trigramMatches =
        categories
            .where((item) => item.type == type)
            .map((item) {
              final score = FfmAssistantTypoNormalizer.trigramSimilarity(
                normalizedText,
                item.name.toLowerCase(),
              );
              return (item, score);
            })
            .where((entry) => entry.$2 >= 0.5)
            .toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));
    if (trigramMatches.length == 1) return trigramMatches.single.$1;
    return null;
  }

  int? _parseAdminFee(String text) {
    final match = RegExp(r'(?:admin|biaya admin|fee)\s+(?:rp\s*)?([\w. ,]+)')
        .firstMatch(text);
    return match == null
        ? null
        : FfmAssistantAmountParser.parse(match.group(1)!);
  }

  FfmAssistantPage? _parseDestination(String normalized) =>
      FfmAssistantCatalog.findByText(normalized);

  bool _isAmbiguousLoan(String text) =>
      _containsAny(text, const ['pinjam', 'minjam', 'meminjam']) &&
      !_containsAny(text, const [
        'hutang',
        'utang',
        'piutang',
        'dari saya',
        'saya pinjam',
        'saya meminjam',
      ]);

  bool _isTransactionStats(String text) => _containsAny(text, const [
    'berapa transaksi',
    'jumlah transaksi',
    'total transaksi',
    'transaksi ada berapa',
    'ada berapa catatan',
  ]);

  bool _isWeeklyAnalysisRequest(String text) => _containsAny(text, const [
    'data minggu',
    'analisa minggu',
    'analisis minggu',
    'pengeluaran minggu',
    'pemasukan minggu',
    'minggu lalu gimana',
    'minggu ini gimana',
  ]);

  bool _isSetupRequest(String text) => _containsAny(text, const [
    'harus mulai dari mana',
    'mulai dari mana',
    'sekarang saya harus apa',
    'sekarang harus apa',
    'sekarang harus ngapain',
    'selanjutnya apa',
    'langkah selanjutnya apa',
    'pertamakali saya harus apa',
    'pertama kali saya harus apa',
    'pertama kali harus apa',
    'harus apa pertama kali',
    'baru buka aplikasi',
    'awal pakai',
    'cara pakai ffm',
    'cara menggunakan ffm',
    'setup awal',
    'pengaturan awal',
    'pertama kali pakai',
    'data utama kosong',
    'data saya kosong',
    'data kosong',
    'data utama belum ada',
    'apa yang harus diisi dulu',
    'isi data utama dulu',
    'cek data utama',
  ]);
  bool _isKnownFfmFeatureGap(String text) => _containsAny(text, const [
    'rekonsiliasi',
    'cadangan',
    'backup',
    'pemulihan',
    'export',
    'ekspor',
    'lampiran',
    'nota',
    'json',
    'ocr',
    'model lokal',
    'slm',
    'notifikasi',
    'nada dering',
    'widget',
    'pelatihan',
    'pengetahuan asisten',
  ]);

  /// Membangun konteks keuangan personal berdasarkan data aktual pengguna.
  /// Digunakan untuk memberikan respons yang lebih kontekstual dan personal.
  Future<String> _buildPersonalFinancialContext() async {
    try {
      final evidence = await _financialSnapshot.readCurrentMonth(
        householdId: AppContext.householdId,
        now: _clock(),
      );
      final income = evidence.income;
      final expenses = evidence.expenses;
      if (income == 0 && expenses == 0) {
        return 'Data keuangan bulan ini belum cukup untuk analisis personal.';
      }
      final parts = <String>[];
      if (income > 0) {
        final savingsRate = income > expenses
            ? ((income - expenses) / income * 100).round()
            : 0;
        parts.add(
          'Pemasukan bulan ini ${_formatRupiah(income)}, pengeluaran ${_formatRupiah(expenses)}.',
        );
        if (savingsRate > 0) {
          parts.add('Saving rate kamu $savingsRate%.');
          if (savingsRate < 20) {
            parts.add('(Idealnya minimal 20% untuk tabungan jangka panjang.)');
          } else {
            parts.add('(Lumayan bagus! Di atas target 20%.)');
          }
        } else {
          parts.add(
            'Cashflow bulan ini negatif — pengeluaran melebihi pemasukan.',
          );
        }
      }
      if (evidence.currentInstallments > 0) {
        final dti = income > 0
            ? (evidence.currentInstallments / income * 100).round()
            : 0;
        parts.add(
          'Cicilan aktif ${_formatRupiah(evidence.currentInstallments)}/bulan.',
        );
        if (dti > 35) {
          parts.add(
            '(Rasio cicilan $dti% dari pemasukan — cukup tinggi, idealnya di bawah 35%.)',
          );
        } else if (dti > 0) {
          parts.add('(Rasio cicilan $dti% dari pemasukan — masih aman.)');
        }
      }
      return parts.isEmpty ? '' : parts.join(' ');
    } on Object {
      return '';
    }
  }

  bool _isDraftHelpRequest(String text) => _containsAny(text, const [
    'fungsi draft',
    'draft buat apa',
    'rancangan buat apa',
    'apa itu draft',
    'apa itu rancangan',
    'kenapa ada draft',
    'kenapa ada rancangan',
  ]);

  bool _isFinancialWarningRequest(String text) => _containsAny(text, const [
    'cek anggaran',
    'cek budget',
    'anggaran hampir habis',
    'anggaran yang hampir habis',
    'apakah ada anggaran',
    'budget hampir habis',
    'mendekati batas',
    'pemakaian cepat',
    'kondisi keuangan',
    'peringatan keuangan',
    'ada peringatan',
    'ada warning',
    'anggaran aman',
    'anggaran saya',
    'budget saya',
    'arus kas saya',
  ]);

  bool _isReadRequest(String text) =>
      _containsAny(text, const ['baca', 'ulang']);

  bool _isHijriDateRequest(String text) => _containsAny(text, const [
    'hijriah',
    'hijriyah',
    'hijri',
    'hijrah',
    'islam',
    'tanggal hijri',
    'tanggal islam',
    'kalender islam',
  ]);

  String _formatHijriDate(HijriDisplayDate date) {
    const months = <String>[
      'Muharam',
      'Safar',
      'Rabiulawal',
      'Rabiulakhir',
      'Jumadilawal',
      'Jumadilakhir',
      'Rajab',
      'Syakban',
      'Ramadan',
      'Syawal',
      'Zulkaidah',
      'Zulhijah',
    ];
    final month = date.hijri.month.clamp(1, months.length);
    return '${date.hijri.day} ${months[month - 1]} ${date.hijri.year} H';
  }

  String? _extractAfter(String text, List<String> markers) {
    for (final marker in markers) {
      final index = text.indexOf(marker);
      if (index >= 0) {
        final rest = text.substring(index + marker.length).trim();
        if (rest.isNotEmpty) return rest;
      }
    }
    return null;
  }

  String? _draftTitle(String text, List<String> markers) {
    final extracted = _extractAfter(text, markers);
    if (extracted == null) return null;
    final title = extracted
        .replaceFirst(RegExp(r'\b(?:senilai|sebesar|harga|nilai|rp)\b.*$'), '')
        .replaceFirst(RegExp(r'\b\d[\d.,]*(?:\s*(?:ribu|juta|jt))?.*$'), '')
        .trim();
    return title.isEmpty ? null : title.split(' ').map(_capitalize).join(' ');
  }

  (String, List<String>)? _masterDataRequest(String text) {
    const candidates = <(String, List<String>)>[
      (
        'profil',
        ['atur keluarga', 'atur profil keluarga', 'ubah nama keluarga'],
      ),
      ('rekening', ['tambah rekening', 'buat rekening']),
      ('kategori', ['tambah kategori', 'buat kategori']),
      ('toko', ['tambah toko', 'buat toko', 'tambah tempat']),
      ('tag', ['tambah tag', 'buat tag']),
      (
        'sumber_pemasukan',
        ['tambah sumber pemasukan', 'buat sumber pemasukan'],
      ),
    ];
    for (final candidate in candidates) {
      if (_containsAny(text, candidate.$2)) return candidate;
    }
    return null;
  }

  String _masterDataTargetName(String? target) => switch (target) {
    'profil' => 'Profil keluarga',
    'rekening' => 'Tambah rekening',
    'toko' => 'Tambah toko atau tempat',
    'tag' => 'Tambah tag',
    'sumber_pemasukan' => 'Tambah sumber pemasukan',
    _ => 'Tambah kategori',
  };

  String? _extractMerchant(String text) {
    final match = RegExp(
      r'\b(?:di|pada)\s+([a-z0-9][a-z0-9 .&-]{1,80}?)(?=\s+(?:sebesar|senilai|rp|harga|untuk|dengan|hari ini|kemarin|besok)\b|\s+[0-9]|$)',
    ).firstMatch(text);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty
        ? null
        : value.split(' ').map(_capitalize).join(' ');
  }

  String? _extractParty(String text, List<String> markers) {
    for (final marker in markers) {
      final match = RegExp(
        '$marker\\s+([a-z ]+?)(?=\\s+(?:sebesar|senilai|rp|[0-9]|nol|satu|dua|tiga|empat|lima|enam|tujuh|delapan|sembilan|sepuluh|sebelas|seratus|seribu)|\$)',
      ).firstMatch(text);
      if (match != null && match.group(1)!.trim().isNotEmpty) {
        return match.group(1)!.trim().split(' ').map(_capitalize).join(' ');
      }
    }
    return null;
  }

  String _capitalize(String word) =>
      word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}';

  String _formatRupiah(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    return 'Rp$buffer';
  }

  FfmAssistantIntent _unknown(
    String raw,
    String normalized,
    String response, {
    FfmAssistantResponseOrigin responseOrigin =
        FfmAssistantResponseOrigin.agentOrchestrator,
    FfmAssistantVisionFailure? visionFailure,
  }) {
    _maybeSaveUnansweredQuestion(raw, normalized);
    final enriched = _enrichUnknownResponse(normalized, response);
    return FfmAssistantIntent(
      rawText: raw,
      normalizedText: normalized,
      type: FfmAssistantIntentType.unknown,
      confidence: 0,
      response: enriched,
      clarification: enriched,
      responseOrigin: responseOrigin,
      visionFailure: visionFailure,
    );
  }

  Future<void> _maybeSaveUnansweredQuestion(
    String raw,
    String normalized,
  ) async {
    final trimmed = normalized.trim();
    if (trimmed.length < 5) return;
    if (_containsAny(trimmed, const [
      'tes',
      'test',
      'ping',
      'halo',
      'hai',
      'hello',
      'hi',
      'hei',
    ]))
      return;
    if (_unsupportedQuestionHelp(trimmed) != null) return;
    if (_isKnownFfmFeatureGap(trimmed)) return;
    final existing = await _taughtMemory.findFuzzyAnswer(trimmed);
    if (existing != null) return;
    try {
      await _taughtMemory.save(
        kind: 'answer',
        triggerText: trimmed,
        valueText: 'Belum terjawab: $raw',
        metadata: {'status': 'unanswered', 'source': 'assistant_observation'},
      );
    } on Object {
      // Memory write is best-effort; never block the response.
    }
  }

  String _enrichUnknownResponse(String normalized, String base) {
    final suggestions = <String>[
      '• **Catat transaksi** — contoh: *"catat beli makan 25rb"*',
      '• **Cek ringkasan** — contoh: *"berapa saldo sekarang"*',
      '• **Buka halaman** — contoh: *"buka Anggaran"*',
    ];
    final isOutOfDomain =
        _unsupportedQuestionHelp(normalized) != null ||
        _containsAny(normalized, const [
          'cuaca',
          'harga pasar',
          'berita',
          'google',
          'internet',
          'resep',
          'olahraga',
          'film',
          'musik',
          'jodoh',
          'zodiak',
          'shio',
          'saham',
          'emas',
          'kurs',
          'bitcoin',
          'crypto',
          'trading',
          'forex',
        ]);
    if (isOutOfDomain) {
      return '$base\n\nAku khusus untuk keuangan keluarga FFM. Coba salah satu:\n${suggestions.join('\n')}';
    }
    final hasAmount = FfmAssistantAmountParser.parse(normalized) != null;
    final mentionsAccount = _containsAny(normalized, const [
      'rekening',
      'akun',
      'bank',
    ]);
    if (hasAmount && mentionsAccount) {
      return '$base\n\nKetik seperti *"catat beli sayur 50rb dari BCA"* agar aku bisa siapkan draft transaksi untuk kamu konfirmasi.';
    }
    return '$base\n\nCoba salah satu:\n${suggestions.join('\n')}';
  }

  String? _unsupportedQuestionHelp(String normalized) {
    // ── Kategori 1: Benar-benar di luar domain (butuh internet/data real-time)
    if (_containsAny(normalized, const [
      'cuaca',
      'harga pasar',
      'harga cabai',
      'berita terbaru',
      'cari di google',
      'internet',
      'resep masakan',
      'cara memasak',
      'olahraga',
      'skor bola',
      'jadwal pertandingan',
      'film',
      'musik',
      'lagu',
      'gadget terbaru',
      'hp terbaru',
      'jodoh',
      'ramalan bintang',
      'zodiak',
      'shio',
    ])) {
      return 'Untuk itu aku belum punya akses internet atau data real-time. Aku cuma bisa membaca data yang sudah tersimpan di FFM. Kalau mau, kamu bisa catat harga atau transaksi tersebut dulu sebagai draft.';
    }
    // ── Kategori 2: Terkait keuangan tapi di luar cakupan FFM
    if (_containsAny(normalized, const [
      'saham naik',
      'harga emas hari ini',
      'kurs dollar',
      'kurs rupiah',
      'bitcoin',
      'crypto',
      'trading',
      'forex',
    ])) {
      return 'Aku belum punya akses data pasar real-time. Yang bisa aku bantu adalah mencatat transaksi investasi yang sudah kamu lakukan di FFM. Kamu bisa catat pembelian emas, saham, atau aset lain sebagai aset di menu Aset.';
    }
    // ── Kategori 3: Pertanyaan personal non-keuangan
    if (_containsAny(normalized, const [
      'kabar',
      'kamu sehat',
      'kamu baik',
      'kamu sedih',
      'kamu senang',
      'umur kamu',
      'berapa umur',
      'tanggal lahir',
      'agama',
      'pacar',
      'menikah',
    ])) {
      return 'Terima kasih atas perhatiannya! Aku baik-baik saja. Aku adalah asisten keuangan lokal yang siap membantu pencatatan dan analisis keuangan keluarga. Ada yang bisa kubantu soal keuangan?';
    }
    // ── Kategori 4: Saldo bank asli
    if (_containsAny(normalized, const [
      'saldo bank asli',
      'cek saldo bank',
      'saldo rekening sekarang',
    ])) {
      return 'Aku belum terhubung langsung ke bank. Yang bisa aku baca hanya saldo dan transaksi yang sudah kamu catat atau impor ke FFM.';
    }
    // ── Kategori 5: Prediksi/Ramalan
    if (_containsAny(normalized, const [
      'ramal',
      'tebak',
      'prediksi pemasukan',
      'prediksi pengeluaran',
      'besok gajian',
    ])) {
      return 'Aku nggak mau nebak soal uang. Aku bisa bantu lihat pola dan data nyata yang sudah tercatat, tapi keputusan tetap kamu yang pegang.';
    }
    return null;
  }

  String _normalize(String text) {
    final cleaned = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9.,\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return FfmAssistantTypoNormalizer.correct(cleaned);
  }

  bool _containsAny(String value, List<String> targets) =>
      targets.any(value.contains);
}

abstract final class FfmAssistantAmountParser {
  static int? parse(String text) {
    final numeric = RegExp(
      r'(?:rp\s*)?(\d[\d.,]*)(?:\s*(ribu|jt|juta|m|miliar))?',
    ).allMatches(text);
    if (numeric.isNotEmpty) {
      final match = numeric.first;
      final rawNumber = match.group(1)!;
      final unit = match.group(2);
      final decimal =
          unit != null &&
          rawNumber.contains(',') &&
          !rawNumber.contains('.') &&
          rawNumber.split(',').last.length <= 2;
      final base = decimal
          ? double.tryParse(rawNumber.replaceAll(',', '.'))
          : double.tryParse(rawNumber.replaceAll(RegExp(r'[^0-9]'), ''));
      if (base != null) {
        return switch (match.group(2)) {
          'ribu' => (base * 1000).round(),
          'jt' || 'juta' => (base * 1000000).round(),
          'm' || 'miliar' => (base * 1000000000).round(),
          _ => base.round(),
        };
      }
    }
    final tokens = text
        .replaceAll(RegExp(r'[^a-z\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    const words = <String, int>{
      'nol': 0,
      'satu': 1,
      'dua': 2,
      'tiga': 3,
      'empat': 4,
      'lima': 5,
      'enam': 6,
      'tujuh': 7,
      'delapan': 8,
      'sembilan': 9,
      'sepuluh': 10,
      'sebelas': 11,
      'seratus': 100,
      'seribu': 1000,
      'sejuta': 1000000,
      'semiliar': 1000000000,
    };
    var total = 0;
    var current = 0;
    var found = false;
    for (var index = 0; index < tokens.length; index++) {
      final token = tokens[index];
      if (token == 'seribu') {
        final amount = current == 0 ? 1000 : current * 1000;
        return total + amount;
      } else if (token == 'sejuta') {
        final amount = current == 0 ? 1000000 : current * 1000000;
        return total + amount;
      } else if (token == 'semiliar') {
        final amount = current == 0 ? 1000000000 : current * 1000000000;
        return total + amount;
      } else if (words.containsKey(token)) {
        current += words[token]!;
        found = true;
      } else if (token == 'setengah' &&
          index + 1 < tokens.length &&
          const ['ribu', 'juta', 'miliar'].contains(tokens[index + 1])) {
        final multiplier = switch (tokens[index + 1]) {
          'ribu' => 1000,
          'juta' => 1000000,
          'miliar' => 1000000000,
          _ => 1,
        };
        return total + ((current + .5) * multiplier).round();
      } else if (token == 'belas') {
        current += 10;
      } else if (token == 'puluh') {
        final lastDigit = current % 10;
        current = current - lastDigit + (lastDigit == 0 ? 10 : lastDigit * 10);
      } else if (token == 'ratus') {
        current = (current == 0 ? 1 : current) * 100;
      } else if (token == 'ribu') {
        return total + (current == 0 ? 1 : current) * 1000;
      } else if (token == 'juta') {
        return total + (current == 0 ? 1 : current) * 1000000;
      } else if (token == 'miliar') {
        return total + (current == 0 ? 1 : current) * 1000000000;
      }
    }
    return found ? total + current : null;
  }
}

// ── PILAR 2: Coreference Memory ─────────────────────────────────────────────
/// Memori entitas sesi dalam satu sesi percakapan (tidak dipersistensikan).
///
/// Menyimpan entitas keuangan yang paling terakhir dirujuk pengguna sehingga
/// asisten bisa memahami kata ganti seperti *"dari situ"*, *"ke sana"*,
/// *"rekening tadi"*, *"nominal yang sama"* tanpa meminta klarifikasi ulang.
class _FfmSessionEntityMemory {
  String? lastAccountName;
  String? lastCategoryName;
  int? lastAmount;
  String? lastTransactionType; // 'income' | 'expense' | 'transfer'

  /// Perbarui memori berdasarkan draft yang baru diproses.
  void updateFromDraft({
    String? accountName,
    String? categoryName,
    int? amount,
    String? transactionType,
  }) {
    if (accountName != null && accountName.isNotEmpty) {
      lastAccountName = accountName;
    }
    if (categoryName != null && categoryName.isNotEmpty) {
      lastCategoryName = categoryName;
    }
    if (amount != null && amount > 0) lastAmount = amount;
    if (transactionType != null) lastTransactionType = transactionType;
  }

  /// Selesaikan kata rujukan dalam teks yang sudah dinormalisasi.
  ///
  /// Kata *"dari situ"*, *"ke situ"*, *"rekening tadi"* diganti dengan
  /// nama entitas yang terakhir diingat.
  String resolveCoref(String normalized) {
    var resolved = normalized;
    if (lastAccountName != null) {
      for (final ref in const [
        'dari situ',
        'ke situ',
        'ke sana',
        'dari sana',
        'rekening tadi',
        'rekening tersebut',
        'rekening itu',
        'dompet tadi',
        'dompet itu',
        'akun tadi',
        'akun itu',
      ]) {
        resolved = resolved.replaceAll(ref, lastAccountName!.toLowerCase());
      }
    }
    if (lastAmount != null) {
      for (final ref in const [
        'nominal yang sama',
        'jumlah yang sama',
        'nominal tadi',
        'jumlah tadi',
      ]) {
        resolved = resolved.replaceAll(ref, lastAmount.toString());
      }
    }
    return resolved;
  }

  bool get hasAnyEntity =>
      lastAccountName != null || lastCategoryName != null || lastAmount != null;
}
