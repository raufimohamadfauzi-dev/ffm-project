import 'package:uuid/uuid.dart';

/// Catatan pengisian bahan bakar (BBM) untuk sebuah kendaraan.
class FuelLogEntry {
  const FuelLogEntry({
    required this.id,
    required this.date,
    required this.liters,
    required this.totalAmount,
    this.pricePerLiter,
    this.odometerKm,
    this.fuelType = 'Pertalite',
    this.spbuLocation = '',
    this.notes = '',
  });

  /// ID unik catatan pengisian.
  final String id;

  /// Waktu pengisian BBM.
  final DateTime date;

  /// Jumlah liter BBM yang diisi.
  final double liters;

  /// Total biaya pengisian dalam Rupiah.
  final double totalAmount;

  /// Harga per liter saat pengisian (dihitung otomatis jika null).
  final double? pricePerLiter;

  /// Angka KM pada odometer saat pengisian (opsional).
  final double? odometerKm;

  /// Jenis bahan bakar yang diisi (misal: "Pertalite", "Pertamax", "Solar").
  final String fuelType;

  /// Lokasi atau nama SPBU (misal: "SPBU Pertamina 34-45102").
  final String spbuLocation;

  /// Catatan tambahan.
  final String notes;

  /// Harga per liter efektif.
  double get effectivePricePerLiter {
    if (pricePerLiter != null && pricePerLiter! > 0) return pricePerLiter!;
    if (liters > 0 && totalAmount > 0) return totalAmount / liters;
    return 0.0;
  }

  FuelLogEntry copyWith({
    String? id,
    DateTime? date,
    double? liters,
    double? totalAmount,
    double? pricePerLiter,
    double? odometerKm,
    String? fuelType,
    String? spbuLocation,
    String? notes,
  }) {
    return FuelLogEntry(
      id: id ?? this.id,
      date: date ?? this.date,
      liters: liters ?? this.liters,
      totalAmount: totalAmount ?? this.totalAmount,
      pricePerLiter: pricePerLiter ?? this.pricePerLiter,
      odometerKm: odometerKm ?? this.odometerKm,
      fuelType: fuelType ?? this.fuelType,
      spbuLocation: spbuLocation ?? this.spbuLocation,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'liters': liters,
    'totalAmount': totalAmount,
    'pricePerLiter': pricePerLiter,
    'odometerKm': odometerKm,
    'fuelType': fuelType,
    'spbuLocation': spbuLocation,
    'notes': notes,
  };

  factory FuelLogEntry.fromJson(Map<String, dynamic> json) {
    return FuelLogEntry(
      id: (json['id'] as String?) ?? const Uuid().v4(),
      date: DateTime.tryParse((json['date'] as String?) ?? '') ?? DateTime.now(),
      liters: (json['liters'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
      pricePerLiter: (json['pricePerLiter'] as num?)?.toDouble(),
      odometerKm: (json['odometerKm'] as num?)?.toDouble(),
      fuelType: (json['fuelType'] as String?) ?? 'Pertalite',
      spbuLocation: (json['spbuLocation'] as String?) ?? '',
      notes: (json['notes'] as String?) ?? '',
    );
  }
}

/// Model entitas untuk Buku Saku Kendaraan & Log BBM.
///
/// Menyimpan data kendaraan (motor, mobil, truk, traktor sawah, mesin tani),
/// nomor polisi/plat, merek/model, jenis BBM, kapasitas tangki, serta riwayat konsumsi BBM.
class Vehicle {
  const Vehicle({
    required this.id,
    required this.householdId,
    required this.name,
    required this.plateNumber,
    this.brandModel = '',
    this.vehicleType = 'motor',
    this.fuelType = 'Pertalite',
    this.tankCapacity = 0.0,
    this.lastOdometer,
    this.notes = '',
    required this.createdAt,
    this.fuelLogs = const [],
  });

  /// ID unik kendaraan.
  final String id;

  /// Household ID pemilik data.
  final String householdId;

  /// Nama pengenal ramah (misal: "Vario Ayah", "Beat Harian", "Avanza Keluarga", "Traktor Sawah").
  final String name;

  /// Nomor polisi / plat nomor (misal: "B 1234 ABC", "D 5678 XY").
  final String plateNumber;

  /// Merek dan tipe kendaraan (misal: "Honda Vario 160", "Toyota Avanza 1.3", "Kubota L3218").
  final String brandModel;

  /// Tipe kendaraan: 'motor', 'mobil', 'truk', 'traktor', 'lainnya'.
  final String vehicleType;

  /// Jenis BBM default: 'Pertalite', 'Pertamax', 'Pertamax Turbo', 'Solar', 'Dexlite', 'Listrik/EV'.
  final String fuelType;

  /// Kapasitas tangki bahan bakar dalam Liter (misal: 5.5, 45.0).
  final double tankCapacity;

  /// Nilai odometer KM terakhir yang tercatat.
  final double? lastOdometer;

  /// Catatan khusus.
  final String notes;

  /// Waktu kendaraan pertama kali didaftarkan.
  final DateTime createdAt;

  /// Riwayat pengisian bahan bakar.
  final List<FuelLogEntry> fuelLogs;

  /// Memformat plat nomor menjadi rapi dan kapital (misal: "B 1234 ABC").
  String get formattedPlateNumber {
    final clean = plateNumber.trim().toUpperCase();
    if (clean.isEmpty) return '-';
    return clean;
  }

  /// Total liter BBM yang diisi pada bulan tertentu (default: bulan ini).
  double totalLitersForMonth(DateTime month) {
    final targetYear = month.year;
    final targetMonth = month.month;
    return fuelLogs
        .where((log) => log.date.year == targetYear && log.date.month == targetMonth)
        .fold(0.0, (sum, log) => sum + log.liters);
  }

  /// Total pengeluaran Rupiah untuk BBM pada bulan tertentu.
  double totalExpenseForMonth(DateTime month) {
    final targetYear = month.year;
    final targetMonth = month.month;
    return fuelLogs
        .where((log) => log.date.year == targetYear && log.date.month == targetMonth)
        .fold(0.0, (sum, log) => sum + log.totalAmount);
  }

  /// Perhitungan efisiensi bahan bakar rata-rata (KM per Liter) jika data odometer tersedia.
  double? get averageKmPerLiter {
    final validLogs = fuelLogs
        .where((l) => l.odometerKm != null && l.odometerKm! > 0 && l.liters > 0)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    if (validLogs.length < 2) return null;

    var totalKm = 0.0;
    var totalLiters = 0.0;

    for (var i = 1; i < validLogs.length; i++) {
      final prev = validLogs[i - 1];
      final curr = validLogs[i];
      final deltaKm = curr.odometerKm! - prev.odometerKm!;
      if (deltaKm > 0) {
        totalKm += deltaKm;
        totalLiters += curr.liters;
      }
    }

    if (totalLiters > 0 && totalKm > 0) {
      return totalKm / totalLiters;
    }
    return null;
  }

  Vehicle copyWith({
    String? id,
    String? householdId,
    String? name,
    String? plateNumber,
    String? brandModel,
    String? vehicleType,
    String? fuelType,
    double? tankCapacity,
    double? lastOdometer,
    String? notes,
    DateTime? createdAt,
    List<FuelLogEntry>? fuelLogs,
  }) {
    return Vehicle(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      name: name ?? this.name,
      plateNumber: plateNumber ?? this.plateNumber,
      brandModel: brandModel ?? this.brandModel,
      vehicleType: vehicleType ?? this.vehicleType,
      fuelType: fuelType ?? this.fuelType,
      tankCapacity: tankCapacity ?? this.tankCapacity,
      lastOdometer: lastOdometer ?? this.lastOdometer,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      fuelLogs: fuelLogs ?? this.fuelLogs,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'householdId': householdId,
    'name': name,
    'plateNumber': plateNumber,
    'brandModel': brandModel,
    'vehicleType': vehicleType,
    'fuelType': fuelType,
    'tankCapacity': tankCapacity,
    'lastOdometer': lastOdometer,
    'notes': notes,
    'createdAt': createdAt.toIso8601String(),
    'fuelLogs': fuelLogs.map((l) => l.toJson()).toList(),
  };

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    final rawLogs = json['fuelLogs'];
    final logs = <FuelLogEntry>[];
    if (rawLogs is List) {
      for (final item in rawLogs) {
        if (item is Map) {
          logs.add(FuelLogEntry.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return Vehicle(
      id: (json['id'] as String?) ?? const Uuid().v4(),
      householdId: (json['householdId'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      plateNumber: (json['plateNumber'] as String?) ?? '',
      brandModel: (json['brandModel'] as String?) ?? '',
      vehicleType: (json['vehicleType'] as String?) ?? 'motor',
      fuelType: (json['fuelType'] as String?) ?? 'Pertalite',
      tankCapacity: (json['tankCapacity'] as num?)?.toDouble() ?? 0.0,
      lastOdometer: (json['lastOdometer'] as num?)?.toDouble(),
      notes: (json['notes'] as String?) ?? '',
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ?? DateTime.now(),
      fuelLogs: logs,
    );
  }
}
