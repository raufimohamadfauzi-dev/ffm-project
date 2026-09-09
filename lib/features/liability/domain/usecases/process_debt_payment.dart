import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/audit_logger.dart';
import '../debt_receivable_validation.dart';

class ProcessDebtPayment {
  const ProcessDebtPayment(this.database);
  final AppDatabase database;

  /// Memproses pembayaran sebagian atau pelunasan hutang / piutang secara atomik
  /// dengan validasi nominal dan opsional pencatatan transaksi kas terkait.
  Future<int> call({
    required String householdId,
    required String targetId,
    required String targetName,
    required bool isLiability,
    required int amount,
    required DateTime date,
    String? accountId,
    String? note,
    bool recordCashTransaction = true,
  }) async {
    return database.transaction<int>(() async {
      int newRemaining;

      if (isLiability) {
        final existing = await (database.select(database.liabilities)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.id.equals(targetId),
              ))
            .getSingleOrNull();

        if (existing == null) {
          throw StateError('Data hutang tidak ditemukan.');
        }

        final error = validateDebtPaymentAmount(
          paymentAmount: amount,
          remainingBalance: existing.remainingBalance,
        );
        if (error != null) throw ArgumentError(error);

        newRemaining = (existing.remainingBalance - amount).clamp(0, existing.remainingBalance);

        await (database.update(database.liabilities)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.id.equals(targetId),
              ))
            .write(LiabilitiesCompanion(
              remainingBalance: Value(newRemaining),
            ));
      } else {
        final existing = await (database.select(database.receivables)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.id.equals(targetId),
              ))
            .getSingleOrNull();

        if (existing == null) {
          throw StateError('Data piutang tidak ditemukan.');
        }

        final error = validateDebtPaymentAmount(
          paymentAmount: amount,
          remainingBalance: existing.remainingBalance,
        );
        if (error != null) throw ArgumentError(error);

        newRemaining = (existing.remainingBalance - amount).clamp(0, existing.remainingBalance);

        await (database.update(database.receivables)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.id.equals(targetId),
              ))
            .write(ReceivablesCompanion(
              remainingBalance: Value(newRemaining),
            ));
      }

      // Catat mutasi kas bila dipilih dan rekening tersedia
      if (recordCashTransaction && accountId != null && accountId.isNotEmpty) {
        final now = DateTime.now();
        final txId = const Uuid().v4();
        final defaultNote = isLiability
            ? 'Pembayaran hutang: $targetName'
            : 'Penerimaan piutang: $targetName';

        await database.into(database.transactions).insert(
              TransactionsCompanion.insert(
                id: txId,
                householdId: householdId,
                type: isLiability ? 'expense' : 'income',
                amount: isLiability ? -amount : amount,
                date: date,
                recordedAt: now,
                createdAt: now,
                accountId: Value(accountId),
                partyName: Value(targetName),
                note: Value(note?.trim().isNotEmpty == true ? note!.trim() : defaultNote),
                source: Value(isLiability ? 'liability_payment' : 'receivable_payment'),
                sourceId: Value(targetId),
              ),
            );
      }

      await AuditLogger(database).record(
        action: isLiability ? 'bayar hutang' : 'terima piutang',
        entity: isLiability ? 'liability' : 'receivable',
        householdId: householdId,
        newValue: {
          'id': targetId,
          'amountPaid': amount,
          'newRemaining': newRemaining,
          'accountId': accountId,
          'date': date.toIso8601String(),
        },
      );

      return newRemaining;
    });
  }
}

/// Membatalkan pembayaran hutang/piutang dan merekonsiliasi sisa saldo kembali
/// Use case ini digunakan saat transaksi pembayaran dihapus atau dibatalkan
class RollbackDebtPayment {
  const RollbackDebtPayment(this.database);
  final AppDatabase database;

  Future<void> call({
    required String householdId,
    required String transactionId,
  }) async {
    return database.transaction(() async {
      // Cari transaksi yang akan dihapus
      final tx = await (database.select(database.transactions)
            ..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.id.equals(transactionId),
            ))
          .getSingleOrNull();

      if (tx == null) {
        throw StateError('Transaksi tidak ditemukan.');
      }

      // Cek apakah ini adalah transaksi pembayaran hutang/piutang
      final isLiabilityPayment = tx.source == 'liability_payment';
      final isReceivablePayment = tx.source == 'receivable_payment';

      if (!isLiabilityPayment && !isReceivablePayment) {
        // Bukan pembayaran hutang/piutang, tidak perlu rekonsiliasi
        return;
      }

      final targetId = tx.sourceId;
      if (targetId == null) {
        throw StateError('Transaksi pembayaran tidak memiliki targetId.');
      }

      final amount = tx.amount.abs(); // Gunakan nilai absolut untuk rekonsiliasi

      if (isLiabilityPayment) {
        final existing = await (database.select(database.liabilities)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.id.equals(targetId),
              ))
            .getSingleOrNull();

        if (existing != null) {
          // Kembalikan sisa hutang
          final newRemaining = existing.remainingBalance + amount;
          await (database.update(database.liabilities)
                ..where(
                  (row) =>
                      row.householdId.equals(householdId) &
                      row.id.equals(targetId),
                ))
              .write(LiabilitiesCompanion(
                remainingBalance: Value(newRemaining),
              ));

          await AuditLogger(database).record(
            action: 'batal bayar hutang',
            entity: 'liability',
            householdId: householdId,
            newValue: {
              'id': targetId,
              'amountRollback': amount,
              'newRemaining': newRemaining,
              'transactionId': transactionId,
            },
          );
        }
      } else if (isReceivablePayment) {
        final existing = await (database.select(database.receivables)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.id.equals(targetId),
              ))
            .getSingleOrNull();

        if (existing != null) {
          // Kembalikan sisa piutang
          final newRemaining = existing.remainingBalance + amount;
          await (database.update(database.receivables)
                ..where(
                  (row) =>
                      row.householdId.equals(householdId) &
                      row.id.equals(targetId),
                ))
              .write(ReceivablesCompanion(
                remainingBalance: Value(newRemaining),
              ));

          await AuditLogger(database).record(
            action: 'batal terima piutang',
            entity: 'receivable',
            householdId: householdId,
            newValue: {
              'id': targetId,
              'amountRollback': amount,
              'newRemaining': newRemaining,
              'transactionId': transactionId,
            },
          );
        }
      }
    });
  }
}
