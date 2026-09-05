import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

/// Pilihan strategi pelunasan hutang.
enum DebtPayoffStrategy {
  /// Debt Snowball: Melunasi hutang dengan saldo terkecil terlebih dahulu
  /// untuk memicu kemenangan psikologis cepat.
  snowball,

  /// Debt Avalanche: Melunasi hutang dengan suku bunga tertinggi terlebih dahulu
  /// untuk meminimalkan total beban bunga finansial.
  avalanche,
}

/// Asal-usul penentuan nominal cicilan bulanan.
enum AdaptiveInstallmentOrigin {
  /// Diisi manual oleh pengguna di form hutang.
  explicitInput,

  /// Dihitung dari rata-rata riwayat transaksi pembayaran kas (liability_payment).
  historicalPaymentAverage,

  /// Dihitung dari sisa pokok dibagi sisa bulan hingga tanggal jatuh tempo (dueDate).
  dueDateAmortization,

  /// Nilai batas minimum aman (floor, e.g. 5% dari saldo atau Rp 50.000).
  minimumFloor,
}

/// Representasi hutang dengan informasi cicilan yang sudah diadaptasi.
class AdaptiveLiability {
  const AdaptiveLiability({
    required this.id,
    required this.householdId,
    required this.name,
    required this.originalAmount,
    required this.remainingBalance,
    required this.monthlyInstallment,
    required this.interestRate,
    required this.startDate,
    required this.dueDate,
    required this.isExplicitInstallment,
    required this.installmentOrigin,
  });

  final String id;
  final String householdId;
  final String name;
  final int originalAmount;
  final int remainingBalance;
  final int monthlyInstallment;
  final double interestRate;
  final DateTime startDate;
  final DateTime dueDate;
  final bool isExplicitInstallment;
  final AdaptiveInstallmentOrigin installmentOrigin;

  AdaptiveLiability copyWith({
    String? id,
    String? householdId,
    String? name,
    int? originalAmount,
    int? remainingBalance,
    int? monthlyInstallment,
    double? interestRate,
    DateTime? startDate,
    DateTime? dueDate,
    bool? isExplicitInstallment,
    AdaptiveInstallmentOrigin? installmentOrigin,
  }) {
    return AdaptiveLiability(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      name: name ?? this.name,
      originalAmount: originalAmount ?? this.originalAmount,
      remainingBalance: remainingBalance ?? this.remainingBalance,
      monthlyInstallment: monthlyInstallment ?? this.monthlyInstallment,
      interestRate: interestRate ?? this.interestRate,
      startDate: startDate ?? this.startDate,
      dueDate: dueDate ?? this.dueDate,
      isExplicitInstallment:
          isExplicitInstallment ?? this.isExplicitInstallment,
      installmentOrigin: installmentOrigin ?? this.installmentOrigin,
    );
  }
}

/// Tonggak pelunasan sebuah hutang dalam rangkaian simulasi.
class DebtPayoffMilestone {
  const DebtPayoffMilestone({
    required this.debtId,
    required this.debtName,
    required this.orderIndex,
    required this.paidOffMonth,
    required this.paidOffDate,
    required this.totalInterestPaid,
    required this.totalPrincipalPaid,
  });

  final String debtId;
  final String debtName;
  final int orderIndex;
  final int paidOffMonth;
  final DateTime paidOffDate;
  final int totalInterestPaid;
  final int totalPrincipalPaid;
}

/// Hasil simulasi proyeksi pelunasan hutang.
class DebtPayoffSimulationResult {
  const DebtPayoffSimulationResult({
    required this.strategy,
    required this.extraMonthlyPayment,
    required this.totalMonths,
    required this.debtFreeDate,
    required this.totalInterestPaid,
    required this.totalPrincipalPaid,
    required this.totalPaid,
    required this.monthlyBaseBudget,
    required this.monthlyTotalBudget,
    required this.milestones,
  });

  final DebtPayoffStrategy strategy;
  final int extraMonthlyPayment;
  final int totalMonths;
  final DateTime debtFreeDate;
  final int totalInterestPaid;
  final int totalPrincipalPaid;
  final int totalPaid;
  final int monthlyBaseBudget;
  final int monthlyTotalBudget;
  final List<DebtPayoffMilestone> milestones;
}

/// Komparasi hasil simulasi antara Snowball vs Avalanche vs Baseline.
class DebtPayoffComparison {
  const DebtPayoffComparison({
    required this.baselineResult,
    required this.snowballResult,
    required this.avalancheResult,
    required this.extraMonthlyPayment,
    required this.monthsSavedSnowball,
    required this.interestSavedSnowball,
    required this.monthsSavedAvalanche,
    required this.interestSavedAvalanche,
    required this.recommendationText,
  });

  final DebtPayoffSimulationResult baselineResult;
  final DebtPayoffSimulationResult snowballResult;
  final DebtPayoffSimulationResult avalancheResult;
  final int extraMonthlyPayment;
  final int monthsSavedSnowball;
  final int interestSavedSnowball;
  final int monthsSavedAvalanche;
  final int interestSavedAvalanche;
  final String recommendationText;
}

/// Layanan strategis percepatan pelunasan hutang otonom FFM.
class DebtPayoffStrategistService {
  const DebtPayoffStrategistService(this._db);

  final AppDatabase _db;

  /// Membaca hutang aktif rumah tangga dan menginferensi cicilan bulanan adaptif.
  Future<List<AdaptiveLiability>> getAdaptiveLiabilities(
    String householdId, {
    DateTime? now,
  }) async {
    final effectiveNow = now ?? DateTime.now();

    final activeLiabilities = await (_db.select(_db.liabilities)
          ..where(
            (row) =>
                row.householdId.equals(householdId) & row.isActive.equals(true),
          ))
        .get();

    if (activeLiabilities.isEmpty) return [];

    final result = <AdaptiveLiability>[];

    for (final l in activeLiabilities) {
      if (l.remainingBalance <= 0) continue;

      final dueDate = l.dueDate ?? l.startDate.add(const Duration(days: 365));
      final interest = l.interestRate;

      // 1. Jika pengguna telah mengisi kolom monthlyInstallment secara eksplisit (> 0)
      if (l.monthlyInstallment > 0) {
        result.add(
          AdaptiveLiability(
            id: l.id,
            householdId: l.householdId,
            name: l.name,
            originalAmount: l.originalAmount,
            remainingBalance: l.remainingBalance,
            monthlyInstallment: l.monthlyInstallment,
            interestRate: interest,
            startDate: l.startDate,
            dueDate: dueDate,
            isExplicitInstallment: true,
            installmentOrigin: AdaptiveInstallmentOrigin.explicitInput,
          ),
        );
        continue;
      }

      // 2. Jika tidak diisi (0): cek riwayat pembayaran kas aktual (liability_payment)
      final payments = await (_db.select(_db.transactions)
            ..where(
              (t) =>
                  t.householdId.equals(householdId) &
                  t.source.equals('liability_payment') &
                  t.sourceId.equals(l.id) &
                  t.isDeleted.equals(false) &
                  t.isArchived.equals(false),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .get();

      if (payments.isNotEmpty) {
        final totalPaid =
            payments.fold<int>(0, (sum, tx) => sum + tx.amount.abs());
        final avgPayment = (totalPaid / payments.length).round();

        if (avgPayment > 0) {
          result.add(
            AdaptiveLiability(
              id: l.id,
              householdId: l.householdId,
              name: l.name,
              originalAmount: l.originalAmount,
              remainingBalance: l.remainingBalance,
              monthlyInstallment: avgPayment,
              interestRate: interest,
              startDate: l.startDate,
              dueDate: dueDate,
              isExplicitInstallment: false,
              installmentOrigin:
                  AdaptiveInstallmentOrigin.historicalPaymentAverage,
            ),
          );
          continue;
        }
      }

      // 3. Jika belum pernah ada pembayaran: gunakan amortisasi sisa bulan ke dueDate
      final diffDays = dueDate.difference(effectiveNow).inDays;
      final remainingMonths = (diffDays / 30).ceil();

      if (remainingMonths > 0) {
        final amortizedInstallment = (l.remainingBalance / remainingMonths).ceil();
        if (amortizedInstallment > 0) {
          result.add(
            AdaptiveLiability(
              id: l.id,
              householdId: l.householdId,
              name: l.name,
              originalAmount: l.originalAmount,
              remainingBalance: l.remainingBalance,
              monthlyInstallment: amortizedInstallment,
              interestRate: interest,
              startDate: l.startDate,
              dueDate: dueDate,
              isExplicitInstallment: false,
              installmentOrigin:
                  AdaptiveInstallmentOrigin.dueDateAmortization,
            ),
          );
          continue;
        }
      }

      // 4. Fallback minimum floor: 5% dari sisa saldo atau minimal Rp 50.000
      final floorVal = (l.remainingBalance * 0.05).round();
      final finalFloor = floorVal > 50000 ? floorVal : 50000;
      final safeInstallment =
          finalFloor > l.remainingBalance ? l.remainingBalance : finalFloor;

      result.add(
        AdaptiveLiability(
          id: l.id,
          householdId: l.householdId,
          name: l.name,
          originalAmount: l.originalAmount,
          remainingBalance: l.remainingBalance,
          monthlyInstallment: safeInstallment > 0 ? safeInstallment : 10000,
          interestRate: interest,
          startDate: l.startDate,
          dueDate: dueDate,
          isExplicitInstallment: false,
          installmentOrigin: AdaptiveInstallmentOrigin.minimumFloor,
        ),
      );
    }

    return result;
  }

  /// Menjalankan simulasi amortisasi percepatan pelunasan hutang secara deterministik.
  DebtPayoffSimulationResult simulate({
    required List<AdaptiveLiability> liabilities,
    required DebtPayoffStrategy strategy,
    int extraMonthlyPayment = 0,
    DateTime? startDate,
  }) {
    final effectiveStart = startDate ?? DateTime.now();

    final activeLiabilities =
        liabilities.where((l) => l.remainingBalance > 0).toList();

    if (activeLiabilities.isEmpty) {
      return DebtPayoffSimulationResult(
        strategy: strategy,
        extraMonthlyPayment: extraMonthlyPayment,
        totalMonths: 0,
        debtFreeDate: effectiveStart,
        totalInterestPaid: 0,
        totalPrincipalPaid: 0,
        totalPaid: 0,
        monthlyBaseBudget: 0,
        monthlyTotalBudget: extraMonthlyPayment,
        milestones: const [],
      );
    }

    final totalBaseMonthly = activeLiabilities.fold<int>(
      0,
      (sum, l) => sum + l.monthlyInstallment,
    );

    // Saldo kerja tiap hutang (dalam double untuk presisi perhitungan bunga)
    final balances = <String, double>{
      for (final l in activeLiabilities) l.id: l.remainingBalance.toDouble(),
    };

    final interestPaid = <String, double>{
      for (final l in activeLiabilities) l.id: 0.0,
    };

    final principalPaid = <String, double>{
      for (final l in activeLiabilities) l.id: 0.0,
    };

    final milestones = <DebtPayoffMilestone>[];
    var currentMonth = 0;
    const maxMonthsCap = 360; // 30 tahun batas maksimal

    while (currentMonth < maxMonthsCap) {
      currentMonth++;

      // 1. Akrualkan bunga bulanan untuk semua hutang yang masih bersaldo
      for (final l in activeLiabilities) {
        final bal = balances[l.id]!;
        if (bal > 0 && l.interestRate > 0) {
          final monthlyInterestRate = (l.interestRate / 100.0) / 12.0;
          final interestThisMonth = bal * monthlyInterestRate;
          balances[l.id] = bal + interestThisMonth;
          interestPaid[l.id] = interestPaid[l.id]! + interestThisMonth;
        }
      }

      // 2. Hitung total dana cicilan yang tersedia bulan ini
      // Seluruh base cicilan awal + dana ekstra dialokasikan secara penuh!
      var availableBudget = (totalBaseMonthly + extraMonthlyPayment).toDouble();

      // 3. Tentukan urutan prioritas target pelunasan
      final unpaid =
          activeLiabilities.where((l) => balances[l.id]! > 0.01).toList();

      if (unpaid.isEmpty) {
        currentMonth--;
        break;
      }

      // Urutkan unpaid sesuai strategi
      if (strategy == DebtPayoffStrategy.snowball) {
        unpaid.sort((a, b) => balances[a.id]!.compareTo(balances[b.id]!));
      } else {
        // Avalanche: bunga tertinggi ke terendah, tie-breaker saldo terkecil
        unpaid.sort((a, b) {
          final rateComp = b.interestRate.compareTo(a.interestRate);
          if (rateComp != 0) return rateComp;
          return balances[a.id]!.compareTo(balances[b.id]!);
        });
      }

      // 4. Bayar cicilan minimum untuk hutang NON-target terlebih dahulu
      for (var i = 1; i < unpaid.length; i++) {
        final d = unpaid[i];
        final minPay = d.monthlyInstallment.toDouble();
        final currentBal = balances[d.id]!;
        final actualPay = minPay > currentBal ? currentBal : minPay;

        balances[d.id] = currentBal - actualPay;
        principalPaid[d.id] = principalPaid[d.id]! + actualPay;
        availableBudget -= actualPay;

        if (balances[d.id]! <= 0.01) {
          balances[d.id] = 0.0;
          milestones.add(
            DebtPayoffMilestone(
              debtId: d.id,
              debtName: d.name,
              orderIndex: milestones.length + 1,
              paidOffMonth: currentMonth,
              paidOffDate: DateTime(
                effectiveStart.year,
                effectiveStart.month + currentMonth,
                effectiveStart.day,
              ),
              totalInterestPaid: interestPaid[d.id]!.round(),
              totalPrincipalPaid: principalPaid[d.id]!.round(),
            ),
          );
        }
      }

      // 5. Alokasikan SELURUH sisa dana yang terkumpul ke target debt utama (Snowball Roll-Over)
      while (availableBudget > 0 && unpaid.any((d) => balances[d.id]! > 0.01)) {
        // Cari target aktif berikutnya
        final currentActive =
            unpaid.where((d) => balances[d.id]! > 0.01).toList();
        if (currentActive.isEmpty) break;

        final currentTarget = currentActive.first;
        final targetBal = balances[currentTarget.id]!;

        if (availableBudget >= targetBal) {
          // Lunas penuh!
          availableBudget -= targetBal;
          principalPaid[currentTarget.id] =
              principalPaid[currentTarget.id]! + targetBal;
          balances[currentTarget.id] = 0.0;

          milestones.add(
            DebtPayoffMilestone(
              debtId: currentTarget.id,
              debtName: currentTarget.name,
              orderIndex: milestones.length + 1,
              paidOffMonth: currentMonth,
              paidOffDate: DateTime(
                effectiveStart.year,
                effectiveStart.month + currentMonth,
                effectiveStart.day,
              ),
              totalInterestPaid: interestPaid[currentTarget.id]!.round(),
              totalPrincipalPaid: principalPaid[currentTarget.id]!.round(),
            ),
          );
        } else {
          // Dibayar sebagian dengan seluruh sisa dana
          balances[currentTarget.id] = targetBal - availableBudget;
          principalPaid[currentTarget.id] =
              principalPaid[currentTarget.id]! + availableBudget;
          availableBudget = 0.0;
        }
      }

      // Cek apakah semua sudah tuntas
      if (activeLiabilities.every((l) => balances[l.id]! <= 0.01)) {
        break;
      }
    }

    final totalInterest =
        interestPaid.values.fold<double>(0.0, (sum, v) => sum + v).round();
    final totalPrincipal =
        principalPaid.values.fold<double>(0.0, (sum, v) => sum + v).round();

    final debtFreeDate = DateTime(
      effectiveStart.year,
      effectiveStart.month + currentMonth,
      effectiveStart.day,
    );

    return DebtPayoffSimulationResult(
      strategy: strategy,
      extraMonthlyPayment: extraMonthlyPayment,
      totalMonths: currentMonth,
      debtFreeDate: debtFreeDate,
      totalInterestPaid: totalInterest,
      totalPrincipalPaid: totalPrincipal,
      totalPaid: totalPrincipal + totalInterest,
      monthlyBaseBudget: totalBaseMonthly,
      monthlyTotalBudget: totalBaseMonthly + extraMonthlyPayment,
      milestones: milestones,
    );
  }

  /// Membandingkan performa Snowball vs Avalanche dengan skenario dana ekstra.
  DebtPayoffComparison compareStrategies({
    required List<AdaptiveLiability> liabilities,
    int extraMonthlyPayment = 0,
    DateTime? startDate,
  }) {
    final effectiveStart = startDate ?? DateTime.now();

    // Baseline: tanpa dana ekstra menggunakan snowball
    final baseline = simulate(
      liabilities: liabilities,
      strategy: DebtPayoffStrategy.snowball,
      extraMonthlyPayment: 0,
      startDate: effectiveStart,
    );

    // Snowball dengan dana ekstra
    final snowball = simulate(
      liabilities: liabilities,
      strategy: DebtPayoffStrategy.snowball,
      extraMonthlyPayment: extraMonthlyPayment,
      startDate: effectiveStart,
    );

    // Avalanche dengan dana ekstra
    final avalanche = simulate(
      liabilities: liabilities,
      strategy: DebtPayoffStrategy.avalanche,
      extraMonthlyPayment: extraMonthlyPayment,
      startDate: effectiveStart,
    );

    final monthsSavedSnowball = (baseline.totalMonths - snowball.totalMonths)
        .clamp(0, baseline.totalMonths);
    final interestSavedSnowball =
        (baseline.totalInterestPaid - snowball.totalInterestPaid)
            .clamp(0, baseline.totalInterestPaid);

    final monthsSavedAvalanche = (baseline.totalMonths - avalanche.totalMonths)
        .clamp(0, baseline.totalMonths);
    final interestSavedAvalanche =
        (baseline.totalInterestPaid - avalanche.totalInterestPaid)
            .clamp(0, baseline.totalInterestPaid);

    // Buat kalimat rekomendasi otonom natural bahasa Indonesia
    final String recommendation;
    if (liabilities.isEmpty || liabilities.every((l) => l.remainingBalance <= 0)) {
      recommendation =
          'Keluarga Anda saat ini bebas hutang. Pertahankan kondisi ini dan fokus perbesar pos tabungan & investasi.';
    } else {
      final highestInterestDebt = List.of(liabilities)
        ..sort((a, b) => b.interestRate.compareTo(a.interestRate));
      final topDebt = highestInterestDebt.first;

      final extraFormatted = _rupiahFormat(extraMonthlyPayment);
      final interestSavedFormatted = _rupiahFormat(interestSavedAvalanche);

      if (extraMonthlyPayment > 0) {
        recommendation =
            'Jika sisa uang belanja bulan ini $extraFormatted dialokasikan untuk melunasi '
            'hutang "${topDebt.name}" (bunga ${topDebt.interestRate}%) lebih dulu via metode Avalanche, '
            'Anda akan menghemat total bunga $interestSavedFormatted dan lunas $monthsSavedAvalanche bulan lebih cepat!';
      } else {
        recommendation =
            'Prioritaskan pelunasan hutang "${topDebt.name}" (bunga tertinggi ${topDebt.interestRate}%) '
            'untuk menghemat biaya bunga, atau pilih metode Snowball untuk menyelesaikan hutang ber-saldo terkecil terlebih dahulu.';
      }
    }

    return DebtPayoffComparison(
      baselineResult: baseline,
      snowballResult: snowball,
      avalancheResult: avalanche,
      extraMonthlyPayment: extraMonthlyPayment,
      monthsSavedSnowball: monthsSavedSnowball,
      interestSavedSnowball: interestSavedSnowball,
      monthsSavedAvalanche: monthsSavedAvalanche,
      interestSavedAvalanche: interestSavedAvalanche,
      recommendationText: recommendation,
    );
  }

  /// Mendeteksi estimasi kelebihan anggaran/surplus belanja yang bisa dialokasikan.
  Future<int> estimateSuggestedExtraPayment(String householdId) async {
    try {
      final budgets = await (_db.select(_db.envelopeBudgets)
            ..where((row) => row.householdId.equals(householdId)))
          .get();

      // Cek surplus dari amplop belanja non-pokok jika ada
      if (budgets.isNotEmpty) {
        final totalBudget = budgets.fold<int>(0, (sum, b) => sum + b.allocated);
        final candidate = (totalBudget * 0.10).round(); // 10% dari alokasi
        if (candidate >= 100000) {
          // Bulatkan ke kelipatan 50rb
          return (candidate / 50000).round() * 50000;
        }
      }
    } catch (_) {}

    return 250000; // Default nominal ekstra wajar Rp 250.000
  }

  static String _rupiahFormat(int amount) {
    final digits = amount.abs().toString();
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      final start = (end - 3).clamp(0, end);
      groups.insert(0, digits.substring(start, end));
    }
    return 'Rp ${groups.join('.')}';
  }
}
