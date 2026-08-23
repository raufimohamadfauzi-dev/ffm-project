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
  late final FfmAssistantFinancialSnapshotService _financialSnapshot;
  late final FfmAssistantQueryRegistry _queryRegistry;
  late final FfmAssistantContextualActionRegistry _actionRegistry;

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
    List<String> capabilityIds = const <String>[],
  }) async {
    final commands = rawText
        .split(
          RegExp(
            r'\s*(?:;|\n|\blalu\b|\bterus\b|\bkemudian\b|\bselanjutnya\b|\bsetelah itu\b)\s*',
            caseSensitive: false,
          ),
        )
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
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
          capabilityIds: capabilityIds,
        ),
      );
    }
    return results;
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
    List<String> capabilityIds = const <String>[],
  }) async {
    var normalized = _normalize(rawText);

    // Semua guard deterministik berjalan lebih dahulu. Jika tidak menangani
    // permintaan, barulah SLM lokal dicoba sebagai classifier/proposal maker.
    // Dengan urutan ini, PIN, diagnostik, konfirmasi, dan query lokal tidak
    // pernah diserahkan kepada teks bebas dari model.

    // Fallback rule-based
    if (normalized.isEmpty) {
      return _unknown(
        rawText,
        normalized,
        'Tulis atau ucapkan dulu yang mau kamu lakukan, ya.',
      );
    }

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

    if (_containsAny(normalized, const [
      'kamu siapa',
      'anda siapa',
      'asisten ffm itu apa',
      'siapa pembuat aplikasi',
      'pembuat aplikasi ini siapa',
      'dibuat oleh siapa',
      'kamu bisa apa',
      'anda bisa apa',
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

    final financialEducation = _financialEducation.answer(normalized);
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
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: 1,
        response: '${financialEducation.title}\n${financialEducation.message}',
      );
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

    final modelIntent = await _tryModelFirst(
      rawText,
      normalized,
      imagePath: imagePath,
      pageContext: pageContext,
      capabilityIds: capabilityIds,
      currentDestination: currentDestination,
    );
    if (modelIntent != null) {
      if (modelIntent.type == FfmAssistantIntentType.outOfDomain) {
        return FfmAssistantIntent(
          rawText: rawText,
          normalizedText: normalized,
          type: FfmAssistantIntentType.outOfDomain,
          confidence: 1,
          response: 'Maaf, aku dirancang khusus sebagai asisten keuangan keluarga untuk FFM. Aku belum bisa menjawab atau membahas topik di luar fitur dan catatan aplikasi ini.',
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
    if (draft != null) return _intentForDraft(rawText, normalized, draft);

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
      _unsupportedQuestionHelp(normalized) ?? 'Aku belum punya jawaban yang pas untuk itu. Kalau ada typo, tekan “Benarkan & kirim ulang”. Kalau pertanyaannya memang belum terjawab, aku simpan di Pengetahuan Asisten pada menu Lainnya. Di sana kamu bisa salin atau ekspor pertanyaannya untuk bahan update aplikasi.',
    );
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
    List<String> capabilityIds = const <String>[],
    FfmAssistantDestination? currentDestination,
  }) async {
    final gateway = _modelGateway;
    if (gateway == null) return null;
    FfmAssistantModelProposal? proposal;
    try {
      final userContext = await FfmAssistantUserModelService(_taughtMemory)
          .buildContext(query: normalized);
      final evidence = await _financialSnapshot.readCurrentMonth(
        householdId: AppContext.householdId,
        now: _clock(),
      );
      final financialContext = _financialSnapshot.buildBoundedPrompt(evidence);
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
        ].join('\\n'),
        capabilityIds: capabilityIds,
        approvedUserContext: userContext,
        personalizationContext: personalizationContext,
        modelReady: true,
      );
      final modelContext = reasoningContext.toBoundedPrompt();
      proposal = await gateway.proposeWithContext(
        input: rawText,
        imagePath: imagePath,
        pageContext: modelContext.isEmpty ? null : modelContext,
        capabilityIds: capabilityIds,
      );
    } catch (error) {
      if (error is FfmInferenceCancelledException) rethrow;
      // Native/model failure is not an assistant failure; continue with the
      // deterministic local interpreter below.
      return null;
    }
    if (proposal == null || !proposal.isUsable) return null;

    if (proposal.intent == FfmAssistantIntentType.help) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.help,
        confidence: proposal.confidence,
        responseMode: FfmAssistantResponseMode.localModel,
      );
    }

    if (proposal.intent == FfmAssistantIntentType.outOfDomain) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.outOfDomain,
        confidence: proposal.confidence,
        responseMode: FfmAssistantResponseMode.localModel,
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
        response:
            validated.response ??
            'Draf dari AI lokal siap ditinjau. Belum ada data yang disimpan.',
      );
    }

    // Help/unknown and malformed/ambiguous actions fall back to the existing
    // deterministic interpreter rather than displaying model-authored prose.
    return null;
  }

  Future<List<Account>> _activeAccounts() =>
      (_database.select(_database.accounts)..where(
            (row) =>
                row.householdId.equals(AppContext.householdId) &
                row.isArchived.equals(false),
          ))
          .get();

  Future<List<Category>> _activeCategories() =>
      (_database.select(_database.categories)..where(
            (row) =>
                row.householdId.equals(AppContext.householdId) &
                row.isActive.equals(true),
          ))
          .get();

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
    final asksAboutPage =
        isQuestion ||
        _containsAny(normalized, const [
          'apa saja',
          'ada apa',
          'isinya',
          'isi ',
          'fitur ',
          'menu ',
        ]);
    final destination =
        page?.destination ?? (asksAboutPage ? currentDestination : null);
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
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.financialWarnings,
      destination: isBudgetQuestion
          ? FfmAssistantDestination.budget
          : FfmAssistantDestination.summary,
      confidence: 1,
      response: service.responseForAssistant(suggestions),
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
      FfmAssistantDraftKind.receivable => (
        type: FfmAssistantIntentType.createReceivable,
        destination: FfmAssistantDestination.liabilities,
        action: 'piutang',
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
      FfmAssistantDraftKind.activity => (
        type: FfmAssistantIntentType.createActivity,
        destination: FfmAssistantDestination.activity,
        action: 'aktivitas',
      ),
      FfmAssistantDraftKind.profile => (
        type: FfmAssistantIntentType.createProfile,
        destination: FfmAssistantDestination.assistantProfile,
        action: 'profil',
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
      return FfmAssistantDraft(
        kind: FfmAssistantDraftKind.profile,
        createdAt: now,
        title: 'Perkenalan Diri',
        note: rawText.trim(),
        date: now,
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
    return typoMatches.length == 1 ? typoMatches.single : null;
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

  FfmAssistantIntent _unknown(String raw, String normalized, String response) =>
      FfmAssistantIntent(
        rawText: raw,
        normalizedText: normalized,
        type: FfmAssistantIntentType.unknown,
        confidence: 0,
        response: response,
        clarification: response,
      );

  String? _unsupportedQuestionHelp(String normalized) {
    if (_containsAny(normalized, const [
      'cuaca',
      'harga pasar',
      'harga cabai',
      'berita terbaru',
      'cari di google',
      'internet',
    ])) {
      return 'Untuk itu aku belum punya akses internet atau data harga terbaru. Aku cuma bisa membaca data yang sudah tersimpan di FFM. Kalau mau, kamu bisa catat harga atau transaksi tersebut dulu sebagai draft.';
    }
    if (_containsAny(normalized, const [
      'saldo bank asli',
      'cek saldo bank',
      'saldo rekening sekarang',
    ])) {
      return 'Aku belum terhubung langsung ke bank. Yang bisa aku baca hanya saldo dan transaksi yang sudah kamu catat atau impor ke FFM.';
    }
    if (_containsAny(normalized, const [
      'ramal',
      'tebak',
      'prediksi pemasukan',
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
