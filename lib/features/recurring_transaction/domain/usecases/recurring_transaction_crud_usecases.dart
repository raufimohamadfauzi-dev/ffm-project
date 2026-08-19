import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

class GetRecurringTransactions {
  const GetRecurringTransactions(this.database);
  final AppDatabase database;

  Future<List<RecurringTransaction>> call(String householdId) async {
    return (database.select(database.recurringTransactions)
          ..where(
            (row) =>
                row.householdId.equals(householdId) & row.isActive.equals(true),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.startDate)]))
        .get();
  }
}

class CreateRecurringTransaction {
  const CreateRecurringTransaction(this.database);
  final AppDatabase database;

  Future<String> call({
    required String householdId,
    required String name,
    required String type,
    required int amount,
    required DateTime startDate,
    required String periodType,
    String? categoryId,
    String? accountId,
    String? sourceId,
    String? note,
    DateTime? endDate,
    String calcMode = 'fixed',
    double? ratePercent,
  }) async {
    _validateCalculation(calcMode, amount, ratePercent, accountId);
    final id = _newId('rutin');
    await database
        .into(database.recurringTransactions)
        .insert(
          RecurringTransactionsCompanion.insert(
            id: id,
            householdId: householdId,
            name: name.trim(),
            type: type,
            amount: amount.abs(),
            ratePercent: Value(ratePercent),
            calcMode: Value(calcMode),
            categoryId: Value(categoryId),
            accountId: Value(accountId),
            sourceId: Value(sourceId),
            note: Value(note),
            periodType: Value(periodType),
            startDate: startDate,
            endDate: Value(endDate),
            createdAt: DateTime.now(),
          ),
        );
    return id;
  }
}

class UpdateRecurringTransaction {
  const UpdateRecurringTransaction(this.database);
  final AppDatabase database;

  Future<void> call({
    required String id,
    required String householdId,
    required String name,
    required String type,
    required int amount,
    required DateTime startDate,
    required String periodType,
    String? categoryId,
    String? accountId,
    String? sourceId,
    String? note,
    DateTime? endDate,
    String calcMode = 'fixed',
    double? ratePercent,
  }) async {
    _validateCalculation(calcMode, amount, ratePercent, accountId);
    await (database.update(database.recurringTransactions)..where(
          (row) => row.id.equals(id) & row.householdId.equals(householdId),
        ))
        .write(
          RecurringTransactionsCompanion(
            name: Value(name.trim()),
            type: Value(type),
            amount: Value(amount.abs()),
            ratePercent: Value(ratePercent),
            calcMode: Value(calcMode),
            categoryId: Value(categoryId),
            accountId: Value(accountId),
            sourceId: Value(sourceId),
            note: Value(note),
            periodType: Value(periodType),
            startDate: Value(startDate),
            endDate: Value(endDate),
          ),
        );
  }
}

void _validateCalculation(
  String calcMode,
  int amount,
  double? ratePercent,
  String? accountId,
) {
  if (calcMode != 'fixed' && calcMode != 'percent') {
    throw ArgumentError('Mode kalkulasi tidak dikenali.');
  }
  if (calcMode == 'fixed' && amount <= 0) {
    throw ArgumentError('Nominal berkala harus lebih dari nol.');
  }
  if (calcMode == 'percent') {
    if (accountId == null || accountId.isEmpty) {
      throw ArgumentError('Mode persentase wajib memilih rekening.');
    }
    if (ratePercent == null || ratePercent <= 0 || ratePercent > 100) {
      throw ArgumentError('Persentase harus lebih dari 0 dan maksimal 100.');
    }
  }
}

class ArchiveRecurringTransaction {
  const ArchiveRecurringTransaction(this.database);
  final AppDatabase database;

  Future<void> call(String householdId, String id) async {
    await (database.update(database.recurringTransactions)..where(
          (row) => row.id.equals(id) & row.householdId.equals(householdId),
        ))
        .write(const RecurringTransactionsCompanion(isActive: Value(false)));
  }
}

class GetAccountBookBalance {
  const GetAccountBookBalance(this.database);
  final AppDatabase database;

  Future<int> call(
    String householdId,
    String accountId, {
    DateTime? asOf,
  }) async {
    final account =
        await (database.select(database.accounts)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.id.equals(accountId),
            ))
            .getSingleOrNull();
    if (account == null) return 0;

    final cutoff = asOf ?? DateTime.now();
    final transactions =
        await (database.select(database.transactions)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.accountId.equals(accountId) &
                  row.isArchived.equals(false) &
                  row.isDeleted.equals(false) &
                  row.date.isSmallerOrEqualValue(cutoff),
            ))
            .get();
    final transfers =
        await (database.select(database.transfers)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isDeleted.equals(false) &
                  row.date.isSmallerOrEqualValue(cutoff) &
                  (row.fromAccountId.equals(accountId) |
                      row.toAccountId.equals(accountId)),
            ))
            .get();

    var balance = account.openingBalance;
    balance += transactions.fold<int>(0, (sum, row) => sum + row.amount);
    for (final transfer in transfers) {
      if (transfer.toAccountId == accountId) balance += transfer.amount;
      if (transfer.fromAccountId == accountId) {
        // Biaya admin sudah tersimpan sebagai transaksi pengeluaran terpisah.
        balance -= transfer.amount;
      }
    }
    return balance;
  }
}

class RecurringBalanceWarning {
  const RecurringBalanceWarning({
    required this.rule,
    required this.bookBalance,
    required this.estimatedAmount,
    required this.willSkip,
  });

  final RecurringTransaction rule;
  final int bookBalance;
  final int estimatedAmount;
  final bool willSkip;
}

class GetRecurringBalanceWarnings {
  const GetRecurringBalanceWarnings(this.database);
  final AppDatabase database;

  Future<List<RecurringBalanceWarning>> call(String householdId) async {
    final rules = await GetRecurringTransactions(database)(householdId);
    final balanceService = GetAccountBookBalance(database);
    final warnings = <RecurringBalanceWarning>[];
    final today = _dateOnly(DateTime.now());
    for (final rule in rules) {
      if (rule.type != 'expense' || rule.startDate.isAfter(today)) continue;
      final accountId = rule.accountId;
      if (accountId == null || accountId.isEmpty) continue;
      final balance = await balanceService(householdId, accountId);
      final calculated = rule.calcMode == 'percent'
          ? balance <= 0
                ? 0
                : (balance * (rule.ratePercent ?? 0) / 100).round()
          : rule.amount.abs();
      final willSkip = rule.calcMode == 'percent' && balance <= 0;
      if (willSkip || balance < calculated) {
        warnings.add(
          RecurringBalanceWarning(
            rule: rule,
            bookBalance: balance,
            estimatedAmount: calculated,
            willSkip: willSkip,
          ),
        );
      }
    }
    return warnings;
  }
}

class ProcessRecurringTransactions {
  const ProcessRecurringTransactions(this.database);
  final AppDatabase database;

  Future<int> call(String householdId, {DateTime? now}) async {
    final currentTime = now ?? DateTime.now();
    final today = _dateOnly(currentTime);
    final rules =
        await (database.select(database.recurringTransactions)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    var created = 0;

    for (final rule in rules) {
      var occurrence = _dateOnly(rule.startDate);
      final lastDate = rule.endDate == null
          ? today
          : _dateOnly(rule.endDate!.isBefore(today) ? rule.endDate! : today);
      if (occurrence.isAfter(lastDate)) continue;

      var guard = 0;
      while (!occurrence.isAfter(lastDate) && guard < 10000) {
        guard++;
        final occurrenceKey = '${rule.id}:${_keyForDate(occurrence)}';
        final existing =
            await (database.select(database.recurringTransactionRuns)
                  ..where((row) => row.occurrenceKey.equals(occurrenceKey)))
                .getSingleOrNull();
        if (existing == null) {
          final amount = await _amountForOccurrence(
            rule,
            householdId: householdId,
            occurrence: occurrence,
          );
          final transactionId = amount == null
              ? ''
              : 'rutin-${rule.id}-${_keyForDate(occurrence)}';
          await database.transaction(() async {
            if (amount != null && amount > 0) {
              await database
                  .into(database.transactions)
                  .insertOnConflictUpdate(
                    TransactionsCompanion.insert(
                      id: transactionId,
                      householdId: householdId,
                      type: rule.type,
                      categoryId: Value(rule.categoryId),
                      accountId: Value(rule.accountId),
                      amount: rule.type == 'expense' ? -amount : amount,
                      date: occurrence,
                      recordedAt: currentTime,
                      note: Value(rule.note ?? rule.name),
                      owner: const Value('Keluarga'),
                      source: const Value('recurring'),
                      sourceId: Value(rule.sourceId),
                      recurringTransactionId: Value(rule.id),
                      createdAt: currentTime,
                      updatedAt: Value(currentTime),
                    ),
                  );
            }
            // Occurrence yang dilewati karena saldo <= 0 tetap dicatat agar
            // idempotent dan tidak menumpuk saat aplikasi dibuka lagi.
            await database
                .into(database.recurringTransactionRuns)
                .insertOnConflictUpdate(
                  RecurringTransactionRunsCompanion.insert(
                    id: occurrenceKey,
                    recurringTransactionId: rule.id,
                    occurrenceKey: occurrenceKey,
                    occurrenceDate: occurrence,
                    transactionId: transactionId,
                    createdAt: currentTime,
                  ),
                );
          });
          if (amount != null && amount > 0) created++;
        }
        occurrence = _nextOccurrence(occurrence, rule.periodType);
      }
    }
    return created;
  }

  Future<int?> _amountForOccurrence(
    RecurringTransaction rule, {
    required String householdId,
    required DateTime occurrence,
  }) async {
    if (rule.calcMode != 'percent') return rule.amount.abs();
    final rate = rule.ratePercent;
    final accountId = rule.accountId;
    if (rate == null || rate <= 0 || accountId == null || accountId.isEmpty) {
      return null;
    }
    final bookBalance = await GetAccountBookBalance(database)(
      householdId,
      accountId,
      asOf: occurrence,
    );
    if (bookBalance <= 0) return null;
    final calculated = (bookBalance * rate / 100).round();
    return calculated <= 0 ? null : calculated;
  }
}

class CreateReconciliationLog {
  const CreateReconciliationLog(this.database);
  final AppDatabase database;

  Future<AccountReconciliationLog> call({
    required String householdId,
    required String accountId,
    required int actualBalance,
    DateTime? checkedAt,
    String? note,
  }) async {
    if (actualBalance < 0) {
      throw ArgumentError('Saldo nyata tidak boleh negatif.');
    }
    final checked = checkedAt ?? DateTime.now();
    final bookBalance = await GetAccountBookBalance(database)(
      householdId,
      accountId,
      asOf: checked,
    );
    final difference = actualBalance - bookBalance;
    final logId = _newId('rekon');
    final adjustmentId = difference == 0 ? null : _newId('penyesuaian');

    await database.transaction(() async {
      if (adjustmentId != null) {
        await database
            .into(database.transactions)
            .insert(
              TransactionsCompanion.insert(
                id: adjustmentId,
                householdId: householdId,
                type: difference > 0 ? 'income' : 'expense',
                accountId: Value(accountId),
                amount: difference,
                date: _dateOnly(checked),
                recordedAt: checked,
                note: Value(
                  note?.trim().isNotEmpty == true
                      ? note!.trim()
                      : 'Penyesuaian saldo',
                ),
                owner: const Value('Keluarga'),
                source: const Value('balance_adjustment'),
                createdAt: checked,
                updatedAt: Value(checked),
              ),
            );
      }
      await database
          .into(database.accountReconciliationLogs)
          .insert(
            AccountReconciliationLogsCompanion.insert(
              id: logId,
              householdId: householdId,
              accountId: accountId,
              bookBalance: bookBalance,
              actualBalance: actualBalance,
              difference: difference,
              checkedAt: checked,
              note: Value(note?.trim().isEmpty == true ? null : note?.trim()),
              adjustmentTransactionId: Value(adjustmentId),
              createdAt: checked,
            ),
          );
    });

    return (database.select(
      database.accountReconciliationLogs,
    )..where((row) => row.id.equals(logId))).getSingle();
  }
}

class GetReconciliationHistory {
  const GetReconciliationHistory(this.database);
  final AppDatabase database;

  Future<List<AccountReconciliationLog>> call({
    required String householdId,
    String? accountId,
    int limit = 30,
  }) {
    final query = database.select(database.accountReconciliationLogs)
      ..where(
        (row) =>
            row.householdId.equals(householdId) &
            (accountId == null
                ? const Constant(true)
                : row.accountId.equals(accountId)),
      )
      ..orderBy([(row) => OrderingTerm.desc(row.checkedAt)])
      ..limit(limit);
    return query.get();
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _keyForDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

DateTime _nextOccurrence(DateTime current, String periodType) {
  switch (periodType) {
    case 'daily':
    case 'harian':
      return current.add(const Duration(days: 1));
    case 'weekly':
    case 'mingguan':
      return current.add(const Duration(days: 7));
    case 'biweekly':
    case 'dua_mingguan':
      return current.add(const Duration(days: 14));
    case 'monthly':
    case 'bulanan':
    default:
      final nextMonth = current.month == 12
          ? DateTime(current.year + 1, 1, 1)
          : DateTime(current.year, current.month + 1, 1);
      final lastDay = DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
      return DateTime(
        nextMonth.year,
        nextMonth.month,
        current.day > lastDay ? lastDay : current.day,
      );
  }
}

String _newId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';
