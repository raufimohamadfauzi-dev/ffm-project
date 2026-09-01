import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../hijri/domain/hijri_calendar_service.dart';
import '../domain/ffm_assistant_financial_analysis.dart';

class FfmAssistantFinancialSnapshotService {
  const FfmAssistantFinancialSnapshotService(
    this._database, [
    this._hijriService,
  ]);

  final AppDatabase _database;
  final HijriCalendarService? _hijriService;

  Future<FfmAssistantFinancialEvidence> readCurrentMonth({
    required String householdId,
    required DateTime now,
  }) async {
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    final rows =
        await (_database.select(_database.transactions)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false) &
                  row.isDeleted.equals(false),
            ))
            .get();

    var income = 0;
    var expenses = 0;
    var transactionCount = 0;
    for (final row in rows) {
      if (row.date.isBefore(start) || !row.date.isBefore(end)) continue;
      if (row.type == 'income') {
        income += row.amount.abs();
        transactionCount++;
      } else if (row.type == 'expense') {
        expenses += row.amount.abs();
        transactionCount++;
      }
    }

    final liabilities =
        await (_database.select(_database.liabilities)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final currentInstallments = liabilities.fold<int>(
      0,
      (sum, row) => sum + row.monthlyInstallment,
    );
    final quality = classifyFinancialDataQuality(
      income: income,
      expenses: expenses,
      transactionCount: transactionCount,
      monthsWithIncome: income > 0 ? 1 : 0,
      monthsWithExpense: expenses > 0 ? 1 : 0,
    );

    return FfmAssistantFinancialEvidence(
      periodLabel: 'bulan ${_monthLabel(now.month)} ${now.year}',
      transactionCount: transactionCount,
      monthsWithIncome: income > 0 ? 1 : 0,
      monthsWithExpense: expenses > 0 ? 1 : 0,
      income: income,
      expenses: expenses,
      currentInstallments: currentInstallments,
      activeLiabilityCount: liabilities.length,
      quality: quality,
    );
  }

  String buildBoundedPrompt(FfmAssistantFinancialEvidence evidence) {
    final income = evidence.income;
    final expense = evidence.expenses;
    final installments = evidence.currentInstallments;
    final cashflow = evidence.cashflowAfterDebt;
    final quality = switch (evidence.quality) {
      FfmAssistantDataQuality.sufficient => 'sufficient',
      FfmAssistantDataQuality.partial => 'partial',
      FfmAssistantDataQuality.empty => 'empty',
      FfmAssistantDataQuality.insufficientPeriod => 'insufficient_period',
    };
    return 'Financial snapshot lokal bounded: periode=${evidence.periodLabel}; '
        'quality=$quality; income=$income; expenses=$expense; '
        'active_installments=$installments; cashflow_after_debt=$cashflow; '
        'transaction_count=${evidence.transactionCount}; '
        'active_liability_count=${evidence.activeLiabilityCount}. '
        'Gunakan hanya sebagai evidence, jangan mengarang angka lain. '
        'Jika quality bukan sufficient, nyatakan keterbatasan data.';
  }

  /// Digest transaksi untuk capability cloud yang eksplisit. Detail merchant,
  /// catatan, rekening, ID, dan kategori sengaja tidak ikut dikirim; Gemini
  /// hanya menerima maksimal delapan fakta tanggal/jenis/nominal.
  Future<String> buildCurrentMonthTransactionDigest({
    required String householdId,
    required DateTime now,
    int maxItems = 8,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    final rangeStart = startDate ?? start;
    final rangeEndExclusive = endDate == null
        ? end
        : endDate.add(const Duration(days: 1));
    final rows =
        await (_database.select(_database.transactions)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isArchived.equals(false) &
                    row.isDeleted.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.date)]))
            .get();
    final visible = rows
        .where(
          (row) =>
              !row.date.isBefore(rangeStart) &&
              row.date.isBefore(rangeEndExclusive),
        )
        .take(maxItems)
        .map((row) {
          final date = row.date.toIso8601String().substring(0, 10);
          final kind = row.type == 'income' ? 'income' : 'expense';
          return '$date|$kind|amount=${row.amount.abs()}';
        })
        .toList(growable: false);
    if (visible.isEmpty) {
      return 'Transaction digest lokal bounded: periode=${_monthLabel(now.month)} ${now.year}; ${_rangeLabel(startDate, endDate)}; tidak ada transaksi pemasukan/pengeluaran.';
    }
    return 'Transaction digest lokal bounded: periode=${_monthLabel(now.month)} ${now.year}; ${_rangeLabel(startDate, endDate)}; '
        'items=${visible.join('; ')}. Detail merchant, catatan, rekening, kategori, dan ID tidak tersedia.';
  }

  String _rangeLabel(DateTime? startDate, DateTime? endDate) =>
      startDate == null || endDate == null
      ? 'rentang=seluruh_bulan'
      : 'rentang=${startDate.toIso8601String().substring(0, 10)}..${endDate.toIso8601String().substring(0, 10)}';

  /// Daftar nama Data Utama untuk grounding SLM. Nilai saldo, ID, detail
  /// rekening, dan data transaksi sengaja tidak pernah masuk ke prompt.
  Future<String> buildMasterDataContext({
    required String householdId,
    int maxAccounts = 8,
    int maxCategories = 16,
    int maxIncomeSources = 8,
    int maxGoals = 8,
    int maxCharacters = 620,
  }) async {
    final accounts =
        await (_database.select(_database.accounts)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true) &
                  row.isArchived.equals(false),
            ))
            .get();
    final categories =
        await (_database.select(_database.categories)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final incomeSources =
        await (_database.select(_database.transactionParties)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.kind.equals('income_source') &
                  row.isArchived.equals(false),
            ))
            .get();
    final goals =
        await (_database.select(_database.goals)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();

    final accountNames = accounts.map((row) => row.name).toList()..sort();
    final categoryNames = categories.map((row) => row.name).toList()..sort();
    final incomeSourceNames = incomeSources.map((row) => row.name).toList()
      ..sort();
    final goalNames = goals.map((row) => row.name).toList()..sort();
    final context =
        'Data Utama lokal (nama saja; tanpa saldo, ID, atau detail): '
        'rekening_aktif=${_nameList(accountNames, maxAccounts)}; '
        'kategori_aktif=${_nameList(categoryNames, maxCategories)}; '
        'sumber_pemasukan_aktif=${_nameList(incomeSourceNames, maxIncomeSources)}; '
        'target_aktif=${_nameList(goalNames, maxGoals)}. '
        'Gunakan hanya nama yang tercantum sebagai evidence; jangan membuat nama baru.';
    return _clip(context, maxCharacters);
  }

  Future<String> buildHarvestContext({
    required String householdId,
    int limit = 8,
    int maxCharacters = 900,
    bool includeBuyer = false,
  }) async {
    final rows =
        await (_database.select(_database.harvestEvents)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.harvestedAt)])
              ..limit(limit))
            .get();
    if (rows.isEmpty) return 'Fakta panen SQL: belum ada record.';
    final lines = rows
        .map((row) {
          final date = row.harvestedAt.toIso8601String().substring(0, 10);
          final price = row.unitPrice == null ? '-' : row.unitPrice.toString();
          final total = row.totalAmount == null
              ? '-'
              : row.totalAmount.toString();
          final commodity = row.commodity
              .replaceAll(RegExp(r'[\r\n]+'), ' ')
              .trim();
          final unit = row.unit.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
          final base =
              '$date | $commodity | ${row.quantity} $unit | harga_satuan=$price | total=$total';
          if (!includeBuyer) return base;
          final buyer = row.buyerName == null || row.buyerName!.trim().isEmpty
              ? '-'
              : row.buyerName!.trim().replaceAll(RegExp(r'[\r\n]+'), ' ');
          return '$base | pembeli=$buyer';
        })
        .join('; ');
    return _clip('Fakta panen SQL authoritative: $lines', maxCharacters);
  }

  /// Konteks kalender Hijriah untuk LLM. Menyediakan tanggal hijriah hari ini
  /// dan beberapa hari ke depan/ke belakang untuk perhitungan.
  Future<String> buildHijriContext({
    required String householdId,
    required DateTime now,
    int maxCharacters = 300,
  }) async {
    final hijriService = _hijriService ?? HijriCalendarService(_database);
    final hijriToday = await hijriService.convert(householdId, now);
    final hijriTomorrow = await hijriService.convert(
      householdId,
      now.add(const Duration(days: 1)),
    );
    final hijriYesterday = await hijriService.convert(
      householdId,
      now.subtract(const Duration(days: 1)),
    );

    final hToday = _formatHijri(hijriToday.hijri);
    final hTomorrow = _formatHijri(hijriTomorrow.hijri);
    final hYesterday = _formatHijri(hijriYesterday.hijri);

    final offsetInfo = hijriToday.manualOffsetDays != 0
        ? ' (koreksi: ${hijriToday.manualOffsetDays > 0 ? "+" : ""}${hijriToday.manualOffsetDays} hari)'
        : '';

    final context =
        'Kalender Hijriah lokal (Umm al-Qura offline): '
        'hari_ini=$hToday$offsetInfo; '
        'besok=$hTomorrow; '
        'kemarin=$hYesterday. '
        'Gunakan tanggal hijriah ini untuk konteks ibadah dan transaksi terkait Islam.';
    return _clip(context, maxCharacters);
  }

  String _formatHijri(dynamic hijriDate) {
    final year = hijriDate.year.toString();
    final month = _hijriMonthName(hijriDate.month);
    final day = hijriDate.day.toString();
    return '$day $month $year H';
  }

  String _hijriMonthName(int month) {
    const months = [
      'Muharram',
      'Safar',
      'Rabiul Awwal',
      'Rabiul Akhir',
      'Jumadil Awwal',
      'Jumadil Akhir',
      'Rajab',
      'Sya\'ban',
      'Ramadhan',
      'Syawal',
      'Zulqaidah',
      'Zulhijjah',
    ];
    return months[(month - 1) % 12];
  }

  String _nameList(List<String> names, int limit) {
    final cleaned = names
        .map((name) => name.replaceAll(RegExp(r'[\r\n]+'), ' ').trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (cleaned.isEmpty) return '(belum ada)';
    final visible = cleaned.take(limit).join(', ');
    return cleaned.length > limit
        ? '$visible, … (+${cleaned.length - limit})'
        : visible;
  }

  String _clip(String value, int maxCharacters) {
    if (value.length <= maxCharacters) return value;
    return '${value.substring(0, maxCharacters - 1)}…';
  }

  String _monthLabel(int month) {
    const names = <String>[
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
    return month >= 1 && month <= 12 ? names[month - 1] : 'berjalan';
  }

  /// Digest rekening untuk capability cloud.
  ///
  /// Label `opening_balance` secara eksplisit adalah saldo awal, bukan saldo
  /// terkini terhitung. Jangan presentasikan sebagai saldo terkini.
  Future<String> buildAccountsDigest({
    required String householdId,
    int maxItems = 8,
    int maxCharacters = 600,
  }) async {
    final accounts =
        await (_database.select(_database.accounts)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true) &
                  row.isArchived.equals(false),
            ))
            .get();
    if (accounts.isEmpty) {
      return 'Accounts digest: belum ada rekening aktif.';
    }
    accounts.sort((a, b) => a.name.compareTo(b.name));
    final visible = accounts.take(maxItems).toList(growable: false);
    final lines = visible
        .map((row) {
          final name = row.name.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
          return '$name|type=${row.type}|opening_balance=${row.openingBalance}';
        })
        .toList(growable: false);
    final suffix = accounts.length > maxItems
        ? '; … (+${accounts.length - maxItems} lebih)'
        : '';
    return _clip(
      'Accounts digest (opening_balance = saldo awal, bukan saldo terkini terhitung): ${lines.join('; ')}$suffix.',
      maxCharacters,
    );
  }

  /// Digest anggaran untuk capability cloud.
  ///
  /// Hanya `allocated` yang tersedia; pemakaian aktual tidak dihitung di sini.
  Future<String> buildBudgetDigest({
    required String householdId,
    required DateTime now,
    int maxItems = 8,
    int maxCharacters = 700,
  }) async {
    final budgets = await (_database.select(
      _database.envelopeBudgets,
    )..where((row) => row.householdId.equals(householdId))).get();
    if (budgets.isEmpty) {
      return 'Budget digest: belum ada anggaran.';
    }
    budgets.sort((a, b) => a.name.compareTo(b.name));
    final visible = budgets.take(maxItems).toList(growable: false);
    final lines = visible
        .map((row) {
          final name = row.name.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
          return '$name|allocated=${row.allocated}|period=${row.periodType}';
        })
        .toList(growable: false);
    final suffix = budgets.length > maxItems
        ? '; … (+${budgets.length - maxItems} lebih)'
        : '';
    return _clip(
      'Budget digest (allocated = batas alokasi, bukan pemakaian terhitung): ${lines.join('; ')}$suffix.',
      maxCharacters,
    );
  }

  /// Digest kategori untuk capability cloud.
  Future<String> buildCategoriesDigest({
    required String householdId,
    int maxItems = 16,
    int maxCharacters = 600,
  }) async {
    final categories =
        await (_database.select(_database.categories)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    if (categories.isEmpty) {
      return 'Categories digest: belum ada kategori.';
    }
    final names =
        categories
            .map((row) => row.name.replaceAll(RegExp(r'[\r\n]+'), ' ').trim())
            .where((name) => name.isNotEmpty)
            .toList(growable: false)
          ..sort();
    final visible = names.take(maxItems).toList(growable: false);
    final suffix = names.length > maxItems
        ? ', … (+${names.length - maxItems})'
        : '';
    return _clip(
      'Categories digest: ${visible.join(', ')}$suffix.',
      maxCharacters,
    );
  }

  /// Digest target keuangan untuk capability cloud.
  Future<String> buildGoalsDigest({
    required String householdId,
    int maxItems = 8,
    int maxCharacters = 700,
  }) async {
    final goals =
        await (_database.select(_database.goals)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    if (goals.isEmpty) {
      return 'Goals digest: belum ada target keuangan aktif.';
    }
    goals.sort((a, b) => a.name.compareTo(b.name));
    final visible = goals.take(maxItems).toList(growable: false);
    final lines = visible
        .map((row) {
          final name = row.name.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
          return '$name|target=${row.targetAmount}|saved=${row.currentAmount}';
        })
        .toList(growable: false);
    final suffix = goals.length > maxItems
        ? '; … (+${goals.length - maxItems} lebih)'
        : '';
    return _clip(
      'Goals digest (hanya target aktif): ${lines.join('; ')}$suffix.',
      maxCharacters,
    );
  }
}
