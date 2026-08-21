import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

enum FinancialGuardSeverity { critical, warning, info }

enum FinancialGuardKind {
  budgetExceeded,
  budgetNearLimit,
  budgetLargeRemaining,
  monthlyCashDeficit,
  liabilityDue,
}

/// Saran ini hanya membaca data lokal. Tidak ada transaksi, anggaran, atau
/// kewajiban yang dibuat maupun diubah otomatis oleh layanan ini.
class FinancialGuardSuggestion {
  const FinancialGuardSuggestion({
    required this.id,
    required this.kind,
    required this.severity,
    required this.title,
    required this.message,
    required this.trace,
    this.currentAmount,
    this.limitAmount,
    this.date,
  });

  final String id;
  final FinancialGuardKind kind;
  final FinancialGuardSeverity severity;
  final String title;
  final String message;

  /// Menjelaskan data yang dipakai agar saran dapat diperiksa pengguna.
  final String trace;
  final int? currentAmount;
  final int? limitAmount;
  final DateTime? date;
}

class BudgetGuardService {
  const BudgetGuardService(this._database);

  final AppDatabase _database;

  Future<List<FinancialGuardSuggestion>> check(
    String householdId, {
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    final localNow = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    );
    final results = <FinancialGuardSuggestion>[];

    final budgets =
        await (_database.select(_database.envelopeBudgets)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final categories =
        await (_database.select(_database.categories)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final transactions = await (_database.select(
      _database.transactions,
    )..where((row) => row.householdId.equals(householdId))).get();
    final envelopeTransfers = await (_database.select(
      _database.envelopeTransfers,
    )..where((row) => row.householdId.equals(householdId))).get();
    final liabilities =
        await (_database.select(_database.liabilities)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();

    final activeTransactions = transactions
        .where(
          (item) =>
              !item.isArchived &&
              !item.isDeleted &&
              item.source != 'transfer' &&
              !item.date.isAfter(localNow),
        )
        .toList(growable: false);
    final categoryParents = <String, String?>{
      for (final category in categories) category.id: category.parentId,
    };

    for (final budget in budgets) {
      if (!_isInPeriod(localNow, budget.startDate, budget.endDate)) continue;
      if (budget.allocated <= 0) continue;

      final categoryIds = _budgetCategoryIds(budget);
      final isOverall = budget.id.startsWith('overall-');
      final spent = activeTransactions
          .where(
            (item) =>
                item.amount < 0 &&
                _isInPeriod(item.date, budget.startDate, budget.endDate) &&
                (isOverall ||
                    _categoryMatches(
                      item.categoryId,
                      categoryIds,
                      categoryParents,
                    )),
          )
          .fold<int>(0, (total, item) => total + item.amount.abs());
      final transferredIn = envelopeTransfers
          .where(
            (item) =>
                item.toEnvelopeId == budget.id &&
                _isInPeriod(item.createdAt, budget.startDate, budget.endDate),
          )
          .fold<int>(0, (total, item) => total + item.amount);
      final transferredOut = envelopeTransfers
          .where(
            (item) =>
                item.fromEnvelopeId == budget.id &&
                _isInPeriod(item.createdAt, budget.startDate, budget.endDate),
          )
          .fold<int>(0, (total, item) => total + item.amount);
      final limit = budget.allocated + budget.rollover + transferredIn;
      if (limit <= 0) continue;

      final remaining = limit - transferredOut - spent;
      final spentPercent = ((spent / limit) * 100).floor();
      final trace =
          '${_periodLabel(budget.periodType)} ${_dateRange(budget.startDate, budget.endDate)} · ${_money(spent)} terpakai dari ${_money(limit)}';

      if (remaining < 0) {
        results.add(
          FinancialGuardSuggestion(
            id: 'budget-exceeded-${budget.id}',
            kind: FinancialGuardKind.budgetExceeded,
            severity: FinancialGuardSeverity.critical,
            title: 'Anggaran ${budget.name} sudah jebol',
            message:
                'Pengeluaran sudah ${_money(spent)} dari batas ${_money(limit)}. Lewat ${_money(remaining.abs())}.',
            trace: trace,
            currentAmount: spent,
            limitAmount: limit,
            date: budget.endDate,
          ),
        );
        continue;
      }

      if (spentPercent >= budget.alertPercent) {
        results.add(
          FinancialGuardSuggestion(
            id: 'budget-near-${budget.id}',
            kind: FinancialGuardKind.budgetNearLimit,
            severity: FinancialGuardSeverity.warning,
            title: 'Anggaran ${budget.name} mulai mepet',
            message:
                'Sudah $spentPercent% terpakai. Sisa ${_money(remaining)} sampai ${_shortDate(budget.endDate)}.',
            trace: trace,
            currentAmount: spent,
            limitAmount: limit,
            date: budget.endDate,
          ),
        );
        continue;
      }

      if (_isAlmostOver(localNow, budget.startDate, budget.endDate) &&
          spent > 0 &&
          remaining * 2 >= limit) {
        results.add(
          FinancialGuardSuggestion(
            id: 'budget-remaining-${budget.id}',
            kind: FinancialGuardKind.budgetLargeRemaining,
            severity: FinancialGuardSeverity.info,
            title: 'Masih ada sisa di ${budget.name}',
            message:
                'Masih ada ${_money(remaining)} sebelum ${_shortDate(budget.endDate)}. Cek lagi kalau ada belanja yang belum dicatat.',
            trace: trace,
            currentAmount: spent,
            limitAmount: limit,
            date: budget.endDate,
          ),
        );
      }
    }

    final monthStart = DateTime(localNow.year, localNow.month);
    final monthTransactions = activeTransactions
        .where((item) => !item.date.isBefore(monthStart))
        .toList(growable: false);
    final income = monthTransactions
        .where((item) => item.amount > 0)
        .fold<int>(0, (total, item) => total + item.amount);
    final expense = monthTransactions
        .where((item) => item.amount < 0)
        .fold<int>(0, (total, item) => total + item.amount.abs());
    if (expense > income) {
      final deficit = expense - income;
      results.add(
        FinancialGuardSuggestion(
          id: 'cash-deficit-${monthStart.year}-${monthStart.month}',
          kind: FinancialGuardKind.monthlyCashDeficit,
          severity: FinancialGuardSeverity.critical,
          title: 'Arus kas bulan ini minus',
          message:
              'Pengeluaran ${_money(expense)} lebih besar dari pemasukan ${_money(income)}. Selisihnya ${_money(deficit)}.',
          trace:
              'Transaksi ${_monthName(monthStart.month)} ${monthStart.year} sampai ${_shortDate(localNow)} · transfer antar rekening tidak dihitung.',
          currentAmount: expense,
          limitAmount: income,
          date: localNow,
        ),
      );
    }

    final dueLimit = _dateOnly(localNow).add(const Duration(days: 7));
    for (final liability in liabilities) {
      if (liability.remainingBalance <= 0) continue;
      final dueDate = _dateOnly(liability.dueDate ?? liability.startDate);
      if (dueDate.isBefore(_dateOnly(localNow)) || dueDate.isAfter(dueLimit)) {
        continue;
      }
      final daysLeft = dueDate.difference(_dateOnly(localNow)).inDays;
      results.add(
        FinancialGuardSuggestion(
          id: 'liability-due-${liability.id}',
          kind: FinancialGuardKind.liabilityDue,
          severity: daysLeft <= 2
              ? FinancialGuardSeverity.critical
              : FinancialGuardSeverity.warning,
          title: 'Cicilan ${liability.name} jatuh tempo',
          message: daysLeft == 0
              ? 'Jatuh tempo hari ini. Sisa hutangnya ${_money(liability.remainingBalance)}.'
              : 'Jatuh tempo ${_shortDate(dueDate)}. Sisa hutangnya ${_money(liability.remainingBalance)}.',
          trace:
              'Tanggal jatuh tempo ${_shortDate(dueDate)} · cicilan per bulan ${_money(liability.monthlyInstallment)}.',
          currentAmount: liability.remainingBalance,
          limitAmount: liability.monthlyInstallment,
          date: dueDate,
        ),
      );
    }

    results.sort(_compareSuggestions);
    return results;
  }

  String responseForAssistant(List<FinancialGuardSuggestion> suggestions) {
    if (suggestions.isEmpty) {
      return 'Belum ada peringatan dari anggaran, arus kas, atau jatuh tempo yang datanya cukup untuk dicek sekarang.';
    }
    final visible = suggestions.take(3).toList(growable: false);
    final lines = visible
        .map((item) => '• ${item.title}: ${item.message}\n  ${item.trace}')
        .join('\n');
    final more = suggestions.length > visible.length
        ? '\nMasih ada ${suggestions.length - visible.length} peringatan lain di Ringkasan.'
        : '';
    return 'Ini yang perlu dicek:\n$lines$more';
  }

  static int _compareSuggestions(
    FinancialGuardSuggestion a,
    FinancialGuardSuggestion b,
  ) {
    final severity = _severityRank(a.severity)
        .compareTo(_severityRank(b.severity));
    if (severity != 0) return severity;
    final current = (b.currentAmount ?? 0).compareTo(a.currentAmount ?? 0);
    if (current != 0) return current;
    return a.title.compareTo(b.title);
  }

  static int _severityRank(FinancialGuardSeverity severity) {
    switch (severity) {
      case FinancialGuardSeverity.critical:
        return 0;
      case FinancialGuardSeverity.warning:
        return 1;
      case FinancialGuardSeverity.info:
        return 2;
    }
  }

  static bool _isInPeriod(DateTime date, DateTime start, DateTime end) {
    final localDate = date.toLocal();
    final periodStart = DateTime(start.year, start.month, start.day);
    final periodEnd = DateTime(end.year, end.month, end.day, 23, 59, 59);
    return !localDate.isBefore(periodStart) && !localDate.isAfter(periodEnd);
  }

  static bool _categoryMatches(
    String? categoryId,
    Set<String> budgetCategoryIds,
    Map<String, String?> parentByCategoryId,
  ) {
    var currentId = categoryId;
    while (currentId != null) {
      if (budgetCategoryIds.contains(currentId)) return true;
      currentId = parentByCategoryId[currentId];
    }
    return false;
  }

  static Set<String> _budgetCategoryIds(EnvelopeBudget budget) {
    final ids = <String>{};
    if (budget.categoryId != null && budget.categoryId!.isNotEmpty) {
      ids.add(budget.categoryId!);
    }
    try {
      final decoded = jsonDecode(budget.categoryIdsJson);
      if (decoded is List) {
        ids.addAll(
          decoded.whereType<String>().where((item) => item.isNotEmpty),
        );
      }
    } catch (_) {
      // Anggaran lama dengan JSON kategori rusak tidak boleh membuat seluruh
      // halaman Ringkasan gagal. Pos tersebut hanya tidak dipasangkan kategori.
    }
    return ids;
  }

  static bool _isAlmostOver(DateTime now, DateTime start, DateTime end) {
    final startDate = _dateOnly(start);
    final endDate = _dateOnly(end);
    final totalDays = endDate.difference(startDate).inDays + 1;
    final daysLeft = endDate.difference(_dateOnly(now)).inDays;
    final lastQuarterDays = (totalDays / 4).ceil().clamp(1, 7);
    return daysLeft >= 0 && daysLeft <= lastQuarterDays;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _periodLabel(String periodType) {
    switch (periodType) {
      case 'weekly':
        return 'Anggaran mingguan';
      case 'biweekly':
        return 'Anggaran dua mingguan';
      default:
        return 'Anggaran bulanan';
    }
  }

  static String _dateRange(DateTime start, DateTime end) =>
      '${_shortDate(start)}–${_shortDate(end)}';

  static String _shortDate(DateTime value) =>
      '${value.day} ${_monthName(value.month)} ${value.year}';

  static String _monthName(int month) => const [
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
  ][month - 1];

  static String _money(int amount) {
    final digits = amount.abs().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      final start = (end - 3).clamp(0, end);
      groups.insert(0, digits.substring(start, end));
    }
    return '${amount < 0 ? '-' : ''}Rp${groups.join('.')}';
  }
}
