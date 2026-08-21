import 'package:drift/drift.dart' hide Column;

import '../../../core/database/app_context.dart';
import '../../../core/database/app_database.dart';
import '../../advisor/domain/usecases/budget_guard_service.dart';
import 'ffm_assistant_local_memory.dart';
import 'ffm_assistant_typo_normalizer.dart';
import '../domain/ffm_assistant_models.dart';

/// Interpreter lokal berbasis aturan. Ia tidak pernah menulis database; semua
/// perubahan dikembalikan sebagai draft untuk dipreview dan dikonfirmasi user.
class FfmAssistantInterpreter {
  FfmAssistantInterpreter(this._database, [FfmAssistantLocalMemory? memory])
    : _memory = memory ?? FfmAssistantLocalMemory();

  final AppDatabase _database;
  final FfmAssistantLocalMemory _memory;

  Future<List<FfmAssistantIntent>> interpretMany(
    String rawText, {
    FfmAssistantDestination? currentDestination,
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
    if (commands.length <= 1) {
      return [await interpret(rawText, currentDestination: currentDestination)];
    }
    return Future.wait(
      commands.map(
        (command) => interpret(command, currentDestination: currentDestination),
      ),
    );
  }

  Future<FfmAssistantIntent> interpret(
    String rawText, {
    FfmAssistantDestination? currentDestination,
  }) async {
    var normalized = _normalize(rawText);
    if (normalized.isEmpty) {
      return _unknown(
        rawText,
        normalized,
        'Tulis atau ucapkan dulu yang mau kamu lakukan, ya.',
      );
    }

    final aliasIntent = _parseAliasMemory(rawText, normalized);
    if (aliasIntent != null) return aliasIntent;
    normalized = await _memory.applyAliases(normalized);

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

    if (_isTransactionStats(normalized)) {
      return _transactionStats(rawText, normalized);
    }

    if (_isFinancialWarningRequest(normalized)) {
      return _financialWarnings(rawText, normalized);
    }

    if (_isCurrentPageRequest(normalized) && currentDestination != null) {
      return _currentPageContext(rawText, normalized, currentDestination);
    }

    if (_containsAny(normalized, const [
      'buat json',
      'bikin json',
      'template json',
    ])) {
      return FfmAssistantIntent(
        rawText: rawText,
        normalizedText: normalized,
        type: FfmAssistantIntentType.createJsonTemplate,
        destination: FfmAssistantDestination.backup,
        confidence: .9,
        response: 'Aku buka Ekspor & cadangan. Di sana kamu bisa salin template JSON, lalu tempel balik hasil yang sudah kamu cek sebagai draft.',
      );
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
          'masuk',
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

    final accounts = await _activeAccounts();
    final draft = _parseFinancialDraft(rawText, normalized, accounts);
    if (draft != null) return _intentForDraft(rawText, normalized, draft);

    return _unknown(
      rawText,
      normalized,
      _unsupportedQuestionHelp(normalized) ?? 'Aku belum nangkep maksudnya nih. Aku bisa bantu cek data FFM, buka halaman, atau siapkan draft yang kamu konfirmasi sendiri. Coba: “Ada berapa transaksi minggu ini?”, “Cek anggaran”, atau “Pindahkan 500 ribu dari SeaBank ke Tunai, admin 3 ribu”.',
    );
  }

  Future<List<Account>> _activeAccounts() =>
      (_database.select(_database.accounts)..where(
            (row) =>
                row.householdId.equals(AppContext.householdId) &
                row.isArchived.equals(false),
          ))
          .get();

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

  bool _isCurrentPageRequest(String text) => _containsAny(text, const [
    'halaman ini',
    'di sini ada apa',
    'di sini ada data apa',
    'kondisi halaman ini',
    'baca halaman ini',
  ]);

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
    };
    final missing = <String>[];
    if (!draft.hasAmount) missing.add('nominal');
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
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: config.type,
      destination: config.destination,
      draft: draft,
      confidence: missing.isEmpty ? .9 : .55,
      clarification: clarification,
      response: missing.isEmpty
          ? 'Draft ${config.action} sudah siap. Cek dulu, lalu konfirmasi di halaman terkait.'
          : null,
    );
  }

  FfmAssistantDraft? _parseFinancialDraft(
    String rawText,
    String normalized,
    List<Account> accounts,
  ) {
    final now = DateTime.now();
    final amount = FfmAssistantAmountParser.parse(normalized);
    final adminFee = _parseAdminFee(normalized);
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
    return FfmAssistantDraft(
      kind: income && !expense
          ? FfmAssistantDraftKind.income
          : FfmAssistantDraftKind.expense,
      createdAt: now,
      amount: amount,
      toAccountName: income ? _matchAccount(normalized, accounts)?.name : null,
      fromAccountName: expense
          ? _matchAccount(normalized, accounts)?.name
          : null,
      note: rawText.trim(),
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
    _memory.saveAlias(alias, canonical);
    return FfmAssistantIntent(
      rawText: rawText,
      normalizedText: normalized,
      type: FfmAssistantIntentType.help,
      confidence: .95,
      response:
          'Siap. Di perangkat ini, “$alias” akan aku pahami sebagai “$canonical”. Kamu bisa mengubahnya kapan saja.',
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

  FfmAssistantIntent _unknown(String raw, String normalized, String response) =>
      FfmAssistantIntent(
        rawText: raw,
        normalizedText: normalized,
        type: FfmAssistantIntentType.unknown,
        confidence: 0,
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
