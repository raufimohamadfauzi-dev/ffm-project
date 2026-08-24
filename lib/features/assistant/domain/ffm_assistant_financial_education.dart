enum FfmAssistantFinancialTopic {
  saving,
  budgeting,
  cashflow,
  debt,
  goal,
  emergencyFund,
  insurance,
  tax,
  investment,
  sideIncome,
}

class FfmAssistantFinancialEducationAnswer {
  const FfmAssistantFinancialEducationAnswer({
    required this.topic,
    required this.title,
    required this.message,
    required this.destination,
  });

  final FfmAssistantFinancialTopic topic;
  final String title;
  final String message;
  final String destination;
}

class FfmAssistantFinancialEducationService {
  const FfmAssistantFinancialEducationService();

  FfmAssistantFinancialEducationAnswer? answer(String normalizedText) {
    final topic = _topicFor(normalizedText);
    if (topic == null) return null;
    return switch (topic) {
      FfmAssistantFinancialTopic.saving =>
        const FfmAssistantFinancialEducationAnswer(
          topic: FfmAssistantFinancialTopic.saving,
          title: 'Edukasi Menabung',
          destination: 'Goals',
          message: 'Mulai dari target yang jelas, tentukan nominal dan tanggalnya, lalu pecah menjadi setoran mingguan atau bulanan. Dahulukan dana darurat sebelum target konsumtif. Di FFM, buat atau cek target di Goals dan catat setoran sebagai transaksi agar progres dan cashflow terlihat. Aku bisa memberi saran yang lebih personal setelah ada data pemasukan dan pengeluaran beberapa periode.',
        ),
      FfmAssistantFinancialTopic.budgeting =>
        const FfmAssistantFinancialEducationAnswer(
          topic: FfmAssistantFinancialTopic.budgeting,
          title: 'Edukasi Budgeting',
          destination: 'Budget',
          message: 'Budget yang baik dimulai dari pemasukan yang realistis, kebutuhan wajib, cicilan, tabungan, lalu pengeluaran fleksibel. Sisakan buffer untuk biaya tidak rutin dan tinjau selisih rencana dengan aktual setiap periode. Di FFM, gunakan Anggaran dan cek transaksi aktual; jangan menaikkan batas belanja hanya karena satu bulan terlihat longgar.',
        ),
      FfmAssistantFinancialTopic.cashflow =>
        const FfmAssistantFinancialEducationAnswer(
          topic: FfmAssistantFinancialTopic.cashflow,
          title: 'Edukasi Cashflow',
          destination: 'Summary',
          message: 'Cashflow adalah pemasukan dikurangi pengeluaran pada periode yang sama. Pisahkan kebutuhan tetap, kebutuhan berubah, cicilan, dan pengeluaran satu kali. Jika cashflow sering negatif, tunda komitmen baru dan cari pos yang dapat dikurangi. Di FFM, mulai dari Ringkasan lalu gunakan Analisis untuk membandingkan periode; hasil yang lebih akurat membutuhkan pencatatan rutin.',
        ),
      FfmAssistantFinancialTopic.debt =>
        const FfmAssistantFinancialEducationAnswer(
          topic: FfmAssistantFinancialTopic.debt,
          title: 'Edukasi Utang dan Piutang',
          destination: 'Liabilities',
          message: 'Untuk utang, catat saldo tersisa, cicilan, bunga, biaya, dan jatuh tempo. Jangan menganggap batas cicilan sebagai izin otomatis mengambil pinjaman. Untuk piutang, gunakan nilai yang realistis karena belum tentu diterima tepat waktu. Di FFM, cek Liabilities dan Receivables; analisis kemampuan cicilan akan lebih berguna jika pemasukan, pengeluaran, dan kewajiban aktif tercatat.',
        ),
      FfmAssistantFinancialTopic.goal =>
        const FfmAssistantFinancialEducationAnswer(
          topic: FfmAssistantFinancialTopic.goal,
          title: 'Edukasi Target Keuangan',
          destination: 'Goals',
          message: 'Tentukan tujuan, nominal, tenggat, dan prioritas. Hitung kebutuhan setoran berkala dari selisih target dengan saldo saat ini, lalu uji apakah setoran tersebut masih menyisakan cashflow untuk kebutuhan wajib. Di FFM, pantau progres melalui Goals dan jangan memakai dana darurat untuk target yang tidak mendesak.',
        ),
      FfmAssistantFinancialTopic.emergencyFund =>
        const FfmAssistantFinancialEducationAnswer(
          topic: FfmAssistantFinancialTopic.emergencyFund,
          title: 'Edukasi Dana Darurat',
          destination: 'Goals',
          message: 'Dana darurat adalah cadangan keuangan untuk situasi tak terduga (kehilangan pekerjaan, sakit, perbaikan mendesak). Idealnya 3-6x pengeluaran bulanan. Jika belum punya, mulai dari nominal kecil secara rutin sebelum menabung untuk tujuan lain. Di FFM, buat target "Dana Darurat" di Goals dan prioritaskan di atas target konsumtif.',
        ),
      FfmAssistantFinancialTopic.insurance =>
        const FfmAssistantFinancialEducationAnswer(
          topic: FfmAssistantFinancialTopic.insurance,
          title: 'Edukasi Asuransi Keluarga',
          destination: 'Summary',
          message: 'Asuransi melindungi keluarga dari risiko finansial besar. Prioritas: asuransi kesehatan (BPJS atau swasta), asuransi jiwa untuk pencari nafkah utama, lalu asuransi properti/kendaraan. Premi idealnya 5-10% dari pemasukan. Di FFM, kamu bisa catat premi asuransi sebagai pengeluaran rutin agar cashflow tetap terpantau.',
        ),
      FfmAssistantFinancialTopic.tax =>
        const FfmAssistantFinancialEducationAnswer(
          topic: FfmAssistantFinancialTopic.tax,
          title: 'Edukasi Pajak Keluarga',
          destination: 'Summary',
          message: 'Pajak penghasilan (PPh 21) dipotong otomatis dari gaji. Untuk penghasilan sampingan atau usaha, kewajiban lapor sendiri. Manfaatkan pengurangan yang sah: BPJS, iuran pensiun, donasi, dan沈 KPP. Di FFM, catat pengeluaran terkait pajak agar kamu tahu total beban fiscal tahunan.',
        ),
      FfmAssistantFinancialTopic.investment =>
        const FfmAssistantFinancialEducationAnswer(
          topic: FfmAssistantFinancialTopic.investment,
          title: 'Edukasi Investasi Dasar',
          destination: 'Goals',
          message: 'Investasi harus didahulukan dana darurat dan lunasi utang konsumtif. Jenis umum: tabungan berbunga, deposito, reksa dana, obligasi, saham, emas. Risiko berbanding lurus dengan potensi hasil. Di FFM, catat nilai investasi di Aset dan pantau perubahannya. Ini bukan rekomendasi investasi—konsultasikan dengan penasihat keuangan untuk keputusan akhir.',
        ),
      FfmAssistantFinancialTopic.sideIncome =>
        const FfmAssistantFinancialEducationAnswer(
          topic: FfmAssistantFinancialTopic.sideIncome,
          title: 'Edukasi Penghasilan Sampingan',
          destination: 'Transactions',
          message: 'Penghasilan sampingan membantu mempercepat pencapaian target keuangan. Catat semua pemasukan tambahan di FFM agar cashflow lebih akurat. Pisahkan rekening usaha dari rekening pribadi jika sudah rutin. Gunakan analisis di FFM untuk melihat apakah penghasilan sampingan ini konsisten atau musiman.',
        ),
    };
  }

  FfmAssistantFinancialTopic? _topicFor(String text) {
    if (_containsAny(text, const [
      'nabung',
      'menabung',
      'tabungan',
      'dana darurat',
      'simpan uang',
      'hemat uang',
    ])) {
      return FfmAssistantFinancialTopic.saving;
    }
    if (_containsAny(text, const [
      'budget',
      'budgeting',
      'anggaran',
      'atur pengeluaran',
      'mengatur uang',
    ])) {
      return FfmAssistantFinancialTopic.budgeting;
    }
    if (_containsAny(text, const [
      'cashflow',
      'arus kas',
      'arus uang',
      'uang masuk dan keluar',
    ])) {
      return FfmAssistantFinancialTopic.cashflow;
    }
    if (_containsAny(text, const [
      'utang',
      'hutang',
      'piutang',
      'cicilan',
      'pinjaman',
      'kredit',
    ])) {
      return FfmAssistantFinancialTopic.debt;
    }
    if (_containsAny(text, const [
      'target keuangan',
      'tujuan keuangan',
      'target tabungan',
      'rencana keuangan',
    ])) {
      return FfmAssistantFinancialTopic.goal;
    }
    if (_containsAny(text, const [
      'dana darurat',
      'uang darurat',
      'cadangan darurat',
      'tabungan darurat',
      'emergency fund',
      'siaga keuangan',
    ])) {
      return FfmAssistantFinancialTopic.emergencyFund;
    }
    if (_containsAny(text, const [
      'asuransi',
      'perlindungan jiwa',
      'bpjs',
      'premi asuransi',
      'jaminan kesehatan',
      'asuransi keluarga',
    ])) {
      return FfmAssistantFinancialTopic.insurance;
    }
    if (_containsAny(text, const [
      'pajak',
      'pph 21',
      'pajak penghasilan',
      'lapor pajak',
      'npwp',
      'kewajiban pajak',
      'beban pajak',
    ])) {
      return FfmAssistantFinancialTopic.tax;
    }
    if (_containsAny(text, const [
      'investasi',
      'reksa dana',
      'saham',
      'deposito',
      'obligasi',
      'emas',
      'return investasi',
      'hasil investasi',
    ])) {
      return FfmAssistantFinancialTopic.investment;
    }
    if (_containsAny(text, const [
      'penghasilan sampingan',
      'usaha sampingan',
      'kerja sampingan',
      'side income',
      'tambahan penghasilan',
      'penghasilan tambahan',
    ])) {
      return FfmAssistantFinancialTopic.sideIncome;
    }
    return null;
  }

  bool _containsAny(String text, List<String> values) =>
      values.any(text.contains);
}
