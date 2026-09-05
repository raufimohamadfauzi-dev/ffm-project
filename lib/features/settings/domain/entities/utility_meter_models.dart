
/// Model entitas untuk Buku Saku Meteran Listrik & Token (Pillar 3).
///
/// Menyimpan nomor meteran PLN / ID Pelanggan untuk berbagai properti
/// (misal: Rumah Utama, Ladang/Pompa Air Sawah, Ruko Usaha, Kontrakan),
/// serta riwayat nomor token 20-digit terakhir yang siap disalin dengan 1 ketukan.
class UtilityMeter {
  const UtilityMeter({
    required this.id,
    required this.householdId,
    required this.name,
    required this.meterNumber,
    this.customerName = '',
    this.tariffPower = '',
    this.location = '',
    this.notes = '',
    required this.createdAt,
    this.lastTokenNumber,
    this.lastPurchasedAt,
    this.lastAmount,
  });

  /// ID unik meteran (misal: `meter_uuid`).
  final String id;

  /// ID household pemilik data.
  final String householdId;

  /// Nama pengenal ramah pengguna (contoh: "Rumah Utama", "Pompa Sawah Ladang", "Ruko Blok A").
  final String name;

  /// Nomor meteran PLN atau ID Pelanggan (11–12 digit angka).
  final String meterNumber;

  /// Nama pelanggan terdaftar di PLN (contoh: "Bpk Raufi", "H. Ahmad").
  final String customerName;

  /// Daya dan golongan tarif (contoh: "R1/900VA", "R1M/1300VA", "B1/2200VA").
  final String tariffPower;

  /// Lokasi fisik meteran (contoh: "Dusun Karanganyar RT 02", "Sawah Blok 4").
  final String location;

  /// Catatan khusus pengguna (contoh: "Pompa sibel air sawah musim tanam").
  final String notes;

  /// Waktu meteran pertama kali didaftarkan.
  final DateTime createdAt;

  /// Kode strum/token listrik 20 digit terakhir (bisa diformat `xxxx-xxxx-xxxx-xxxx-xxxx`).
  final String? lastTokenNumber;

  /// Tanggal pembelian token terakhir.
  final DateTime? lastPurchasedAt;

  /// Nominal pembelian token terakhir (dalam Rupiah).
  final double? lastAmount;

  /// Memformat nomor meteran menjadi blok 4-digit agar mudah dibaca manusia.
  String get formattedMeterNumber {
    final clean = meterNumber.replaceAll(RegExp(r'\D'), '');
    if (clean.length < 5) return clean;
    final buffer = StringBuffer();
    for (var i = 0; i < clean.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(clean[i]);
    }
    return buffer.toString();
  }

  /// Memformat kode token 20 digit menjadi 5 blok 4-digit (`xxxx-xxxx-xxxx-xxxx-xxxx`).
  String? get formattedTokenNumber {
    if (lastTokenNumber == null) return null;
    final clean = lastTokenNumber!.replaceAll(RegExp(r'\D'), '');
    if (clean.length != 20) return lastTokenNumber;
    return '${clean.substring(0, 4)}-${clean.substring(4, 8)}-${clean.substring(8, 12)}-${clean.substring(12, 16)}-${clean.substring(16, 20)}';
  }

  UtilityMeter copyWith({
    String? id,
    String? householdId,
    String? name,
    String? meterNumber,
    String? customerName,
    String? tariffPower,
    String? location,
    String? notes,
    DateTime? createdAt,
    String? lastTokenNumber,
    DateTime? lastPurchasedAt,
    double? lastAmount,
  }) {
    return UtilityMeter(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      name: name ?? this.name,
      meterNumber: meterNumber ?? this.meterNumber,
      customerName: customerName ?? this.customerName,
      tariffPower: tariffPower ?? this.tariffPower,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      lastTokenNumber: lastTokenNumber ?? this.lastTokenNumber,
      lastPurchasedAt: lastPurchasedAt ?? this.lastPurchasedAt,
      lastAmount: lastAmount ?? this.lastAmount,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'householdId': householdId,
    'name': name,
    'meterNumber': meterNumber,
    'customerName': customerName,
    'tariffPower': tariffPower,
    'location': location,
    'notes': notes,
    'createdAt': createdAt.toIso8601String(),
    'lastTokenNumber': lastTokenNumber,
    'lastPurchasedAt': lastPurchasedAt?.toIso8601String(),
    'lastAmount': lastAmount,
  };

  factory UtilityMeter.fromJson(Map<String, dynamic> json) {
    return UtilityMeter(
      id: json['id'] as String,
      householdId: json['householdId'] as String,
      name: json['name'] as String,
      meterNumber: json['meterNumber'] as String,
      customerName: (json['customerName'] as String?) ?? '',
      tariffPower: (json['tariffPower'] as String?) ?? '',
      location: (json['location'] as String?) ?? '',
      notes: (json['notes'] as String?) ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      lastTokenNumber: json['lastTokenNumber'] as String?,
      lastPurchasedAt: json['lastPurchasedAt'] != null
          ? DateTime.tryParse(json['lastPurchasedAt'] as String)
          : null,
      lastAmount: (json['lastAmount'] as num?)?.toDouble(),
    );
  }
}
