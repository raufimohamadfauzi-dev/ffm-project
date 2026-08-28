import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/ffm_assistant_financial_analysis.dart';

class FfmAssistantFinancialSnapshotService {
  const FfmAssistantFinancialSnapshotService(this._database);

  final AppDatabase _database;

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
    int maxCharacters = 520,
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

    final accountNames = accounts.map((row) => row.name).toList()..sort();
    final categoryNames = categories.map((row) => row.name).toList()..sort();
    final context =
        'Data Utama lokal (nama saja; tanpa saldo, ID, atau detail): '
        'rekening_aktif=${_nameList(accountNames, maxAccounts)}; '
        'kategori_aktif=${_nameList(categoryNames, maxCategories)}. '
        'Gunakan hanya nama yang tercantum sebagai evidence; jangan membuat nama baru.';
    return _clip(context, maxCharacters);
  }

  Future<String> buildHarvestContext({
    required String householdId,
    int limit = 8,
    int maxCharacters = 900,
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
          final buyer = row.buyerName == null || row.buyerName!.trim().isEmpty
              ? '-'
              : row.buyerName!.trim();
          return '$date | ${row.commodity} | ${row.quantity} ${row.unit} | '
              'harga_satuan=$price | total=$total | pembeli=$buyer';
        })
        .join('; ');
    return _clip('Fakta panen SQL authoritative: $lines', maxCharacters);
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
}
