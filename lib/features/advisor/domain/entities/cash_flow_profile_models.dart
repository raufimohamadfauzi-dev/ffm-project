/// Tipe profil arus kas yang didukung oleh FFM.
enum CashFlowProfileType {
  /// Pertanian, perkebunan, dan musiman (padi, jagung, cabai, sawit, kopi, dll.)
  agriculture,

  /// Pemilik bisnis, pedagang, dan UMKM (perputaran modal kerja harian/mingguan)
  business,

  /// Freelancer, kontraktor, dan profesional independen (berbasis termin invoice)
  freelance,

  /// Karyawan dengan gaji tetap bulanan reguler
  salaried,
}

/// Status kesehatan ketahanan kas siklus (Runway).
enum CycleHealthStatus {
  /// Kas sangat mencukupi hingga panen/inflow berikutnya (Runway >= Hari Panen)
  safe,

  /// Kas mulai menipis, disarankan membatasi belanja non-esensial
  warning,

  /// Kas tidak mencukupi hingga waktu panen tanpa penyesuaian/tambahan modal
  critical,
}

/// Model profil dan siklus arus kas aktif dalam rumah tangga.
class CashFlowProfile {
  const CashFlowProfile({
    required this.id,
    required this.householdId,
    required this.profileType,
    required this.name,
    required this.commodityOrBusinessType,
    required this.startDate,
    required this.targetHarvestDate,
    required this.initialCapital,
    required this.estimatedInflow,
    required this.dailyLivingBudget,
    this.dailyOperationalBudget = 0,
    this.isActive = true,
  });

  final String id;
  final String householdId;
  final CashFlowProfileType profileType;
  final String name;
  final String commodityOrBusinessType;
  final DateTime startDate;
  final DateTime targetHarvestDate;

  /// Modal awal yang dialokasikan khusus untuk siklus ini.
  final int initialCapital;

  /// Estimasi kas masuk saat panen / pencairan invoice.
  final int estimatedInflow;

  /// Anggaran harian untuk kebutuhan dapur / pokok keluarga (Rp/hari).
  final int dailyLivingBudget;

  /// Estimasi biaya operasional harian (pupuk, bahan baku, pekerja, operasional kebun/usaha).
  final int dailyOperationalBudget;

  final bool isActive;

  /// Total durasi siklus dalam hari.
  int get totalDays {
    final diff = targetHarvestDate.difference(startDate).inDays;
    return diff > 0 ? diff : 1;
  }

  /// Jumlah hari yang telah dilalui sejak siklus dimulai.
  int get daysElapsed {
    final now = DateTime.now();
    if (now.isBefore(startDate)) return 0;
    final diff = now.difference(startDate).inDays;
    return diff <= totalDays ? diff : totalDays;
  }

  /// Sisa hari menuju tanggal estimasi panen / pencairan kas.
  int get daysRemaining {
    final now = DateTime.now();
    if (now.isAfter(targetHarvestDate)) return 0;
    final diff = targetHarvestDate.difference(now).inDays;
    return diff >= 0 ? diff : 0;
  }

  /// Progres perjalanan siklus (0.0 sampai 1.0).
  double get progress {
    if (totalDays <= 0) return 1.0;
    final p = daysElapsed / totalDays;
    return p.clamp(0.0, 1.0);
  }

  /// Fase pertumbuhan untuk siklus pertanian (berdasarkan persentase waktu).
  String get phaseLabel {
    if (profileType != CashFlowProfileType.agriculture) {
      if (progress < 0.3) return 'Awal Siklus';
      if (progress < 0.7) return 'Operasional Berjalan';
      if (progress < 0.95) return 'Menjelang Penutupan';
      return 'Pencairan / Penagihan';
    }

    if (progress < 0.25) return 'Olah Lahan & Tanam';
    if (progress < 0.65) return 'Pemupukan & Perawatan';
    if (progress < 0.90) return 'Pembungaan & Pengisian';
    return 'Menjelang Panen';
  }

  CashFlowProfile copyWith({
    String? id,
    String? householdId,
    CashFlowProfileType? profileType,
    String? name,
    String? commodityOrBusinessType,
    DateTime? startDate,
    DateTime? targetHarvestDate,
    int? initialCapital,
    int? estimatedInflow,
    int? dailyLivingBudget,
    int? dailyOperationalBudget,
    bool? isActive,
  }) {
    return CashFlowProfile(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      profileType: profileType ?? this.profileType,
      name: name ?? this.name,
      commodityOrBusinessType:
          commodityOrBusinessType ?? this.commodityOrBusinessType,
      startDate: startDate ?? this.startDate,
      targetHarvestDate: targetHarvestDate ?? this.targetHarvestDate,
      initialCapital: initialCapital ?? this.initialCapital,
      estimatedInflow: estimatedInflow ?? this.estimatedInflow,
      dailyLivingBudget: dailyLivingBudget ?? this.dailyLivingBudget,
      dailyOperationalBudget:
          dailyOperationalBudget ?? this.dailyOperationalBudget,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'householdId': householdId,
        'profileType': profileType.name,
        'name': name,
        'commodityOrBusinessType': commodityOrBusinessType,
        'startDate': startDate.toIso8601String(),
        'targetHarvestDate': targetHarvestDate.toIso8601String(),
        'initialCapital': initialCapital,
        'estimatedInflow': estimatedInflow,
        'dailyLivingBudget': dailyLivingBudget,
        'dailyOperationalBudget': dailyOperationalBudget,
        'isActive': isActive,
      };

  factory CashFlowProfile.fromJson(Map<String, dynamic> json) =>
      CashFlowProfile(
        id: json['id'] as String,
        householdId: json['householdId'] as String,
        profileType: CashFlowProfileType.values.firstWhere(
          (e) => e.name == json['profileType'],
          orElse: () => CashFlowProfileType.agriculture,
        ),
        name: json['name'] as String,
        commodityOrBusinessType:
            json['commodityOrBusinessType'] as String? ?? 'Umum',
        startDate: DateTime.parse(json['startDate'] as String),
        targetHarvestDate: DateTime.parse(json['targetHarvestDate'] as String),
        initialCapital: (json['initialCapital'] as num).toInt(),
        estimatedInflow: (json['estimatedInflow'] as num).toInt(),
        dailyLivingBudget: (json['dailyLivingBudget'] as num).toInt(),
        dailyOperationalBudget:
            (json['dailyOperationalBudget'] as num?)?.toInt() ?? 0,
        isActive: json['isActive'] as bool? ?? true,
      );
}

/// Hasil kalkulasi deterministik ketahanan kas (Runway & Safe-to-Spend).
class CashFlowRunwayResult {
  const CashFlowRunwayResult({
    required this.runwayDays,
    required this.safeToSpendDaily,
    required this.healthStatus,
    required this.totalDailyBurnRate,
    required this.effectiveLiquidCash,
    required this.deficitDays,
    required this.message,
    required this.recommendation,
  });

  /// Berapa hari kas likuid saat ini mampu bertahan.
  final int runwayDays;

  /// Batas maksimal belanja konsumtif keluarga hari ini yang aman (Rp/hari).
  final int safeToSpendDaily;

  /// Kategori kesehatan kas saat ini.
  final CycleHealthStatus healthStatus;

  /// Total pengeluaran harian gabungan (dapur + operasional).
  final int totalDailyBurnRate;

  /// Saldo kas likuid riil yang dihitung.
  final int effectiveLiquidCash;

  /// Defisit hari jika runway lebih pendek dari sisa hari ke panen (0 jika aman).
  final int deficitDays;

  /// Ringkasan status untuk antarmuka.
  final String message;

  /// Rekomendasi praktis untuk pengguna.
  final String recommendation;
}
