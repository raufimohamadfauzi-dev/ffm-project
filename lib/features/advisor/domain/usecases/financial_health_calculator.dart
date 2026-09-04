enum FinancialHealthStatus { excellent, good, fair, warning, critical }

class FinancialHealthPillar {
  const FinancialHealthPillar({
    required this.id,
    required this.title,
    required this.score,
    required this.maxScore,
    required this.status,
    required this.factDescription,
    required this.suggestion,
  });

  final String id;
  final String title;
  final int score;
  final int maxScore;
  final FinancialHealthStatus status;
  final String factDescription;
  final String suggestion;

  double get percentage => maxScore > 0 ? (score / maxScore).clamp(0.0, 1.0) : 0.0;
}

class FinancialHealthInput {
  const FinancialHealthInput({
    required this.totalIncome,
    required this.totalExpenses,
    required this.totalMonthlyInstallments,
    required this.emergencyFundAmount,
    required this.averageMonthlyExpenses,
    this.totalAssets = 0,
    this.totalLiabilities = 0,
  });

  final int totalIncome;
  final int totalExpenses;
  final int totalMonthlyInstallments;
  final int emergencyFundAmount;
  final int averageMonthlyExpenses;
  final int totalAssets;
  final int totalLiabilities;
}

class FinancialHealthScore {
  const FinancialHealthScore({
    required this.totalScore,
    required this.status,
    required this.cashflow,
    required this.expenseRatio,
    this.pillars = const [],
    this.headline = '',
    this.strengths = const [],
    this.warnings = const [],
    this.recommendations = const [],
    this.savingsRate = 0.0,
    this.debtToIncomeRatio = 0.0,
    this.emergencyMonths = 0.0,
    this.netWorth = 0,
  });

  final int totalScore;
  final FinancialHealthStatus status;
  final int cashflow;
  final double expenseRatio;
  final List<FinancialHealthPillar> pillars;
  final String headline;
  final List<String> strengths;
  final List<String> warnings;
  final List<String> recommendations;
  final double savingsRate;
  final double debtToIncomeRatio;
  final double emergencyMonths;
  final int netWorth;

  String get statusLabel => switch (status) {
    FinancialHealthStatus.excellent => 'Prima',
    FinancialHealthStatus.good => 'Sehat',
    FinancialHealthStatus.fair => 'Cukup',
    FinancialHealthStatus.warning => 'Perlu Dijaga',
    FinancialHealthStatus.critical => 'Perlu Dibenahi',
  };
}

class FinancialHealthCalculator {
  const FinancialHealthCalculator();

  FinancialHealthScore calculate(FinancialHealthInput input) {
    final income = input.totalIncome;
    final expenses = input.totalExpenses;
    final cashflow = income - expenses;
    final installments = input.totalMonthlyInstallments;
    final emergencyFund = input.emergencyFundAmount;
    final avgExpenses = input.averageMonthlyExpenses > 0
        ? input.averageMonthlyExpenses
        : (expenses > 0 ? expenses : 1);
    final assets = input.totalAssets;
    final liabilities = input.totalLiabilities;
    final netWorth = assets - liabilities;

    final expenseRatio = income <= 0
        ? (expenses > 0 ? 1.0 : 0.0)
        : (expenses / income).clamp(0.0, 10.0);

    final savingsRate = income > 0
        ? ((income - expenses) / income).clamp(-1.0, 1.0)
        : (expenses > 0 ? -1.0 : 0.0);

    final debtToIncomeRatio = income > 0
        ? (installments / income).clamp(0.0, 5.0)
        : (installments > 0 ? 1.0 : 0.0);

    final emergencyMonths = avgExpenses > 0
        ? (emergencyFund / avgExpenses).clamp(0.0, 60.0)
        : 0.0;

    final strengths = <String>[];
    final warnings = <String>[];
    final recommendations = <String>[];

    // -------------------------------------------------------------
    // 1. PILAR 1: Arus Kas / Cashflow (Bobot 25 Poin)
    // -------------------------------------------------------------
    int p1Score;
    FinancialHealthStatus p1Status;
    String p1Fact;
    String p1Sugg;

    if (income <= 0 && expenses <= 0) {
      p1Score = 15;
      p1Status = FinancialHealthStatus.fair;
      p1Fact = 'Belum ada transaksi pemasukan & pengeluaran bulan ini.';
      p1Sugg = 'Catat transaksi rutin keluarga untuk memulai pemantauan arus kas.';
    } else if (income <= 0 && expenses > 0) {
      p1Score = 0;
      p1Status = FinancialHealthStatus.critical;
      p1Fact = 'Pengeluaran berjalan tanpa ada catatan pemasukan.';
      p1Sugg = 'Segera catat sumber pemasukan keluarga agar arus kas terukur.';
      warnings.add('Pemasukan belum tercatat padahal ada pengeluaran.');
      recommendations.add('Catat pemasukan bulan ini untuk melihat surplus riil.');
    } else if (savingsRate >= 0.20) {
      p1Score = 25;
      p1Status = FinancialHealthStatus.excellent;
      final pct = (savingsRate * 100).round();
      p1Fact = 'Surplus sangat sehat: $pct% dari pemasukan berhasil diamankan.';
      p1Sugg = 'Pertahankan surplus ini dan alihkan ke dana darurat atau target tabungan.';
      strengths.add('Arus kas surplus tinggi ($pct% dari pemasukan).');
    } else if (savingsRate >= 0.05) {
      p1Score = 20;
      p1Status = FinancialHealthStatus.good;
      final pct = (savingsRate * 100).round();
      p1Fact = 'Surplus positif: $pct% tersisa setelah kebutuhan belanja.';
      p1Sugg = 'Bagus, pertahankan ritme ini agar terhindar dari defisit.';
      strengths.add('Arus kas surplus positif ($pct%).');
    } else if (savingsRate >= 0.0) {
      p1Score = 15;
      p1Status = FinancialHealthStatus.fair;
      p1Fact = 'Arus kas seimbang tipis (hampir impas / pas-pasan).';
      p1Sugg = 'Cermati pos belanja kecil yang berulang agar sisa dana bertambah.';
      warnings.add('Sisa arus kas sangat tipis mendekati batas pengeluaran.');
      recommendations.add('Sisihkan minimal 5-10% di awal gajian sebelum berbelanja.');
    } else if (savingsRate >= -0.10) {
      p1Score = 8;
      p1Status = FinancialHealthStatus.warning;
      final pct = (savingsRate.abs() * 100).round();
      p1Fact = 'Defisit ringan: pengeluaran melebihi pemasukan sebesar $pct%.';
      p1Sugg = 'Tunda pengeluaran non-primer hingga bulan depan.';
      warnings.add('Arus kas bulan ini mengalami defisit ringan ($pct%).');
      recommendations.add('Evaluasi pengeluaran non-primer untuk menambal defisit.');
    } else {
      p1Score = 0;
      p1Status = FinancialHealthStatus.critical;
      final pct = (savingsRate.abs() * 100).round();
      p1Fact = 'Defisit berat: pengeluaran melampaui pemasukan sebesar $pct%.';
      p1Sugg = 'Perlu rem belanja darurat dan evaluasi pos pengeluaran terbesar.';
      warnings.add('Arus kas defisit signifikan melampaui pemasukan ($pct%).');
      recommendations.add('Gunakan Budget Guard / Anggaran untuk membatasi belanja harian.');
    }

    final p1 = FinancialHealthPillar(
      id: 'cashflow',
      title: 'Arus Kas Bulanan',
      score: p1Score,
      maxScore: 25,
      status: p1Status,
      factDescription: p1Fact,
      suggestion: p1Sugg,
    );

    // -------------------------------------------------------------
    // 2. PILAR 2: Rasio Pengeluaran / Living Expense Ratio (Bobot 20 Poin)
    // -------------------------------------------------------------
    int p2Score;
    FinancialHealthStatus p2Status;
    String p2Fact;
    String p2Sugg;

    final expPct = (expenseRatio * 100).round();
    if (income <= 0) {
      p2Score = 10;
      p2Status = FinancialHealthStatus.fair;
      p2Fact = 'Rasio pengeluaran belum dapat dihitung (pemasukan nihil).';
      p2Sugg = 'Lengkapi data pemasukan untuk mengetahui proporsi belanja.';
    } else if (expenseRatio <= 0.50) {
      p2Score = 20;
      p2Status = FinancialHealthStatus.excellent;
      p2Fact = 'Biaya hidup sangat hemat ($expPct% dari pemasukan).';
      p2Sugg = 'Alokasi pengeluaran sangat terkendali, ada ruang besar untuk tabungan.';
      strengths.add('Biaya hidup sangat hemat (hanya $expPct% dari pemasukan).');
    } else if (expenseRatio <= 0.70) {
      p2Score = 17;
      p2Status = FinancialHealthStatus.good;
      p2Fact = 'Biaya hidup ideal & proporsional ($expPct% dari pemasukan).';
      p2Sugg = 'Proporsi belanja berada dalam rentang ideal perencanaan keluarga.';
      strengths.add('Rasio pengeluaran berada di batas ideal ($expPct%).');
    } else if (expenseRatio <= 0.85) {
      p2Score = 12;
      p2Status = FinancialHealthStatus.fair;
      p2Fact = 'Biaya hidup agak tinggi ($expPct% dari pemasukan).';
      p2Sugg = 'Waspadai kebocoran belanja kebutuhan tersier/hiburan.';
      recommendations.add('Kunci anggaran pada pos belanja terbesar agar tidak melebihi 70%.');
    } else if (expenseRatio <= 1.0) {
      p2Score = 6;
      p2Status = FinancialHealthStatus.warning;
      p2Fact = 'Biaya hidup sangat ketat ($expPct% dari pemasukan).';
      p2Sugg = 'Pangkas pos keinginan untuk memberi ruang tabungan darurat.';
      warnings.add('Biaya hidup mendekati seluruh pemasukan ($expPct%).');
      recommendations.add('Kurangi pos pengeluaran gaya hidup/keinginan minimal 10%.');
    } else {
      p2Score = 0;
      p2Status = FinancialHealthStatus.critical;
      p2Fact = 'Pengeluaran boros melampaui pemasukan ($expPct%).';
      p2Sugg = 'Hentikan belanja konsumtif sampai arus kas kembali aman.';
      warnings.add('Pengeluaran melebihi pemasukan ($expPct%).');
    }

    final p2 = FinancialHealthPillar(
      id: 'living_expense',
      title: 'Rasio Biaya Hidup',
      score: p2Score,
      maxScore: 20,
      status: p2Status,
      factDescription: p2Fact,
      suggestion: p2Sugg,
    );

    // -------------------------------------------------------------
    // 3. PILAR 3: Beban Utang & Cicilan / Debt Service Ratio (Bobot 20 Poin)
    // -------------------------------------------------------------
    int p3Score;
    FinancialHealthStatus p3Status;
    String p3Fact;
    String p3Sugg;

    final debtPct = (debtToIncomeRatio * 100).round();
    if (installments <= 0) {
      p3Score = 20;
      p3Status = FinancialHealthStatus.excellent;
      p3Fact = 'Bebas dari beban cicilan bulanan.';
      p3Sugg = 'Kondisi bebas utang memberikan ketahanan finansial yang luar biasa.';
      strengths.add('Bebas dari beban cicilan utang bulanan.');
    } else if (income <= 0) {
      p3Score = 5;
      p3Status = FinancialHealthStatus.warning;
      p3Fact = 'Ada cicilan bulanan namun pemasukan belum tercatat.';
      p3Sugg = 'Pastikan ada sumber dana yang cukup untuk membayar cicilan tepat waktu.';
      warnings.add('Ada cicilan utang bulanan aktif tanpa catatan pemasukan.');
    } else if (debtToIncomeRatio <= 0.20) {
      p3Score = 18;
      p3Status = FinancialHealthStatus.excellent;
      p3Fact = 'Beban cicilan sangat ringan & aman ($debtPct% dari pemasukan).';
      p3Sugg = 'Beban utang jauh di bawah batas toleransi perbankan.';
      strengths.add('Porsi cicilan utang sangat ringan ($debtPct%).');
    } else if (debtToIncomeRatio <= 0.30) {
      p3Score = 15;
      p3Status = FinancialHealthStatus.good;
      p3Fact = 'Beban cicilan dalam batas sehat BI ($debtPct% dari pemasukan).';
      p3Sugg = 'Hindari menambah pinjaman baru sebelum cicilan lama berkurang.';
    } else if (debtToIncomeRatio <= 0.40) {
      p3Score = 8;
      p3Status = FinancialHealthStatus.warning;
      p3Fact = 'Beban cicilan mulai berat ($debtPct% dari pemasukan).';
      p3Sugg = 'Prioritaskan pelunasan pinjaman terkecil (metode snowball).';
      warnings.add('Cicilan bulanan sudah memakan $debtPct% dari pemasukan keluarga.');
      recommendations.add('Fokus lunasi salah satu hutang untuk melonggarkan arus kas bulanan.');
    } else {
      p3Score = 0;
      p3Status = FinancialHealthStatus.critical;
      p3Fact = 'Beban cicilan sangat berisiko tinggi ($debtPct% dari pemasukan).';
      p3Sugg = 'Lakukan restrukturisasi utang segera agar tidak gagal bayar.';
      warnings.add('Beban cicilan kritis melebihi 40% pemasukan ($debtPct%).');
      recommendations.add('Hindari pinjaman baru dan konsultasikan strategi pelunasan utang.');
    }

    final p3 = FinancialHealthPillar(
      id: 'debt_service',
      title: 'Beban Utang & Cicilan',
      score: p3Score,
      maxScore: 20,
      status: p3Status,
      factDescription: p3Fact,
      suggestion: p3Sugg,
    );

    // -------------------------------------------------------------
    // 4. PILAR 4: Ketahanan Dana Darurat (Bobot 20 Poin)
    // -------------------------------------------------------------
    int p4Score;
    FinancialHealthStatus p4Status;
    String p4Fact;
    String p4Sugg;

    final mString = emergencyMonths.toStringAsFixed(1);
    if (emergencyMonths >= 6.0) {
      p4Score = 20;
      p4Status = FinancialHealthStatus.excellent;
      p4Fact = 'Dana darurat sangat kokoh ($mString bulan biaya hidup).';
      p4Sugg = 'Ketahanan dana darurat sangat aman untuk menghadapi hal tak terduga.';
      strengths.add('Dana darurat sangat kokoh mencukupi $mString bulan kebutuhan.');
    } else if (emergencyMonths >= 3.0) {
      p4Score = 16;
      p4Status = FinancialHealthStatus.good;
      p4Fact = 'Dana darurat memenuhi standar keluarga ($mString bulan biaya hidup).';
      p4Sugg = 'Tingkatkan bertahap menuju target 6 bulan untuk keamanan ekstra.';
      strengths.add('Dana darurat mencukupi standar 3 bulan ($mString bulan).');
    } else if (emergencyMonths >= 1.0) {
      p4Score = 10;
      p4Status = FinancialHealthStatus.fair;
      p4Fact = 'Dana darurat mencukupi kebutuhan dasar ($mString bulan biaya hidup).';
      p4Sugg = 'Sisihkan sebagian surplus bulanan untuk memperkuat dana cadangan.';
      recommendations.add('Tambahkan alokasi tabungan untuk mencapai minimal 3 bulan dana darurat.');
    } else if (emergencyMonths > 0.0) {
      p4Score = 4;
      p4Status = FinancialHealthStatus.warning;
      p4Fact = 'Dana darurat masih tipis ($mString bulan biaya hidup).';
      p4Sugg = 'Sangat disarankan menambah cadangan kas likuid untuk antisipasi.';
      warnings.add('Dana darurat masih di bawah 1 bulan biaya hidup ($mString bulan).');
      recommendations.add('Sisihkan minimal Rp100-500rb per bulan khusus untuk pos Dana Darurat.');
    } else {
      p4Score = 0;
      p4Status = FinancialHealthStatus.critical;
      p4Fact = 'Belum memiliki cadangan dana darurat likuid.';
      p4Sugg = 'Mulai tabung dana darurat pertama di rekening terpisah.';
      warnings.add('Belum ada dana darurat likuid yang tercatat.');
      recommendations.add('Buat target tabungan Dana Darurat di menu Target (Goals).');
    }

    final p4 = FinancialHealthPillar(
      id: 'emergency_fund',
      title: 'Ketahanan Dana Darurat',
      score: p4Score,
      maxScore: 20,
      status: p4Status,
      factDescription: p4Fact,
      suggestion: p4Sugg,
    );

    // -------------------------------------------------------------
    // 5. PILAR 5: Pertumbuhan Kekayaan Bersih / Net Worth (Bobot 15 Poin)
    // -------------------------------------------------------------
    int p5Score;
    FinancialHealthStatus p5Status;
    String p5Fact;
    String p5Sugg;

    if (assets <= 0 && liabilities <= 0) {
      p5Score = 8;
      p5Status = FinancialHealthStatus.fair;
      p5Fact = 'Belum ada pencatatan data aset maupun kewajiban.';
      p5Sugg = 'Daftarkan aset keluarga (tabungan, emas, tanah, kendaraan) untuk memantau kekayaan bersih.';
    } else if (liabilities <= 0 && assets > 0) {
      p5Score = 15;
      p5Status = FinancialHealthStatus.excellent;
      p5Fact = 'Kekayaan bersih positif tanpa ada tanggungan hutang.';
      p5Sugg = 'Kondisi neraca keuangan keluarga sangat prima.';
      strengths.add('Kekayaan bersih positif penuh tanpa ada beban hutang.');
    } else if (assets >= liabilities * 2 && netWorth > 0) {
      p5Score = 15;
      p5Status = FinancialHealthStatus.excellent;
      p5Fact = 'Total aset melampaui 2x total kewajiban.';
      p5Sugg = 'Neraca keuangan sangat sehat dan memiliki bantalan aset yang kuat.';
      strengths.add('Aset bernilai lebih dari 2x total kewajiban.');
    } else if (netWorth > 0) {
      p5Score = 10;
      p5Status = FinancialHealthStatus.good;
      p5Fact = 'Kekayaan bersih bernilai positif (aset melebihi hutang).';
      p5Sugg = 'Pertahankan pertumbuhan aset dan kurangi porsi hutang konsumtif.';
    } else if (netWorth == 0) {
      p5Score = 5;
      p5Status = FinancialHealthStatus.fair;
      p5Fact = 'Kekayaan bersih seimbang (total aset setara hutang).';
      p5Sugg = 'Tingkatkan akumulasi aset likuid agar neraca menjadi positif.';
      warnings.add('Kekayaan bersih seimbang tipis antara aset dan hutang.');
    } else {
      p5Score = 0;
      p5Status = FinancialHealthStatus.critical;
      p5Fact = 'Kekayaan bersih bernilai negatif (hutang melampaui aset).';
      p5Sugg = 'Fokuskan rencana keuangan untuk mereduksi beban hutang.';
      warnings.add('Total hutang lebih besar dari total aset yang dimiliki.');
      recommendations.add('Buat rencana percepatan pelunasan hutang untuk mengembalikan nilai kekayaan bersih.');
    }

    final p5 = FinancialHealthPillar(
      id: 'net_worth',
      title: 'Kekayaan Bersih (Net Worth)',
      score: p5Score,
      maxScore: 15,
      status: p5Status,
      factDescription: p5Fact,
      suggestion: p5Sugg,
    );

    final pillars = [p1, p2, p3, p4, p5];
    final totalScore = (p1Score + p2Score + p3Score + p4Score + p5Score).clamp(0, 100);

    final status = switch (totalScore) {
      >= 85 => FinancialHealthStatus.excellent,
      >= 70 => FinancialHealthStatus.good,
      >= 55 => FinancialHealthStatus.fair,
      >= 40 => FinancialHealthStatus.warning,
      _ => FinancialHealthStatus.critical,
    };

    // Pembangkit headline naratif ramah bahasa Indonesia
    final headline = switch (status) {
      FinancialHealthStatus.excellent =>
        'Keuangan keluarga berada dalam kondisi prima! Arus kas aman dan fondasi aset sangat kokoh.',
      FinancialHealthStatus.good =>
        'Kondisi keuangan sehat. Pemasukan dan belanja terkendali dengan ruang tabungan yang baik.',
      FinancialHealthStatus.fair =>
        'Kondisi keuangan cukup stabil, namun ada beberapa pilar yang perlu diperkuat agar lebih aman.',
      FinancialHealthStatus.warning =>
        'Perlu kewaspadaan: arus kas atau cicilan mulai menekan ruang tabungan keluarga.',
      FinancialHealthStatus.critical =>
        'Kondisi keuangan butuh perhatian segera. Rapikan pengeluaran dan prioritaskan pemulihan arus kas.',
    };

    return FinancialHealthScore(
      totalScore: totalScore,
      status: status,
      cashflow: cashflow,
      expenseRatio: expenseRatio,
      pillars: pillars,
      headline: headline,
      strengths: strengths.take(3).toList(growable: false),
      warnings: warnings.take(3).toList(growable: false),
      recommendations: recommendations.take(3).toList(growable: false),
      savingsRate: savingsRate,
      debtToIncomeRatio: debtToIncomeRatio,
      emergencyMonths: emergencyMonths,
      netWorth: netWorth,
    );
  }
}
