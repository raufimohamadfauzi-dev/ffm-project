import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/liability/domain/debt_receivable_validation.dart';

void main() {
  final today = DateTime(2026, 9, 3);

  test('mengklasifikasikan status jatuh tempo secara deterministik', () {
    expect(
      classifyDebtReceivableDue(
        remainingBalance: 100,
        dueDate: DateTime(2026, 9, 2),
        today: today,
      ),
      DebtReceivableDueStatus.overdue,
    );
    expect(
      classifyDebtReceivableDue(
        remainingBalance: 100,
        dueDate: DateTime(2026, 9, 10),
        today: today,
      ),
      DebtReceivableDueStatus.dueWithinWeek,
    );
    expect(
      classifyDebtReceivableDue(
        remainingBalance: 100,
        dueDate: DateTime(2026, 9, 20),
        today: today,
      ),
      DebtReceivableDueStatus.dueWithinMonth,
    );
    expect(
      classifyDebtReceivableDue(
        remainingBalance: 100,
        dueDate: DateTime(2026, 10, 10),
        today: today,
      ),
      DebtReceivableDueStatus.dueBeyondMonth,
    );
    expect(
      classifyDebtReceivableDue(
        remainingBalance: 0,
        dueDate: DateTime(2026, 9, 2),
        today: today,
      ),
      DebtReceivableDueStatus.paid,
    );
    expect(
      debtReceivableDueStatusLabel(DebtReceivableDueStatus.overdue),
      'Terlambat',
    );
    expect(
      debtReceivableDueStatusLabel(DebtReceivableDueStatus.dueBeyondMonth),
      'Lebih dari 30 hari',
    );
  });

  test('menolak sisa saldo yang melebihi nominal awal', () {
    expect(
      validateDebtReceivableAmounts(
        originalAmount: 1000000,
        remainingBalance: 1200000,
        monthlyInstallment: 100000,
      ),
      'Sisa saldo tidak boleh melebihi nominal awal.',
    );
  });

  test('menerima saldo nol sebagai kondisi lunas dan cicilan nol untuk sekali bayar', () {
    expect(
      validateDebtReceivableAmounts(
        originalAmount: 1000000,
        remainingBalance: 0,
        monthlyInstallment: 0,
      ),
      isNull,
    );
  });

  test('menolak bunga negatif', () {
    expect(
      validateDebtReceivableAmounts(
        originalAmount: 1000000,
        remainingBalance: 500000,
        monthlyInstallment: 100000,
        interestRate: -1,
      ),
      'Bunga tidak boleh negatif.',
    );
  });

  test('memvalidasi tanggal jatuh tempo tidak boleh mendahului tanggal mulai', () {
    expect(
      validateDebtReceivableDates(
        startDate: DateTime(2026, 9, 10),
        dueDate: DateTime(2026, 9, 5),
      ),
      'Tanggal jatuh tempo tidak boleh sebelum tanggal mulai.',
    );
    expect(
      validateDebtReceivableDates(
        startDate: DateTime(2026, 9, 10),
        dueDate: DateTime(2026, 9, 15),
      ),
      isNull,
    );
  });

  test('memvalidasi nominal pembayaran hutang/piutang', () {
    expect(
      validateDebtPaymentAmount(paymentAmount: 0, remainingBalance: 500000),
      'Nominal pembayaran harus lebih besar dari nol.',
    );
    expect(
      validateDebtPaymentAmount(paymentAmount: 600000, remainingBalance: 500000),
      'Nominal pembayaran tidak boleh melebihi sisa saldo (500000).',
    );
    expect(
      validateDebtPaymentAmount(paymentAmount: 300000, remainingBalance: 500000),
      isNull,
    );
    expect(
      validateDebtPaymentAmount(paymentAmount: 500000, remainingBalance: 500000),
      isNull,
    );
  });
}
