/// Tipe aktivitas otonom yang dapat dilakukan oleh Asisten / Agent FFM.
enum AutonomousActivityType {
  /// Pencatatan meteran atau token listrik PLN secara otomatis.
  utilityMeter,

  /// Pencatatan log konsumsi bahan bakar minyak (BBM) kendaraan.
  fuelLog,

  /// Pergeseran plafon anggaran (penyeimbangan zero-sum) otomatis.
  envelopeRebalance,

  /// Penyesuaian tanggal atau siklus panen pertanian otomatis.
  harvestShift,

  /// Pendaftaran kebiasaan rutin pengguna langsung dari percakapan.
  habitDeclaration,
}

/// Status dari aktivitas otonom yang telah tercatat.
enum AutonomousActivityStatus {
  /// Aktivitas aktif dan belum diubah.
  active,

  /// Aktivitas telah dikoreksi oleh pengguna.
  corrected,

  /// Aktivitas telah dibatalkan / di-revert oleh pengguna.
  reverted,
}

/// Rekaman audit tindakan otonom yang dijalankan oleh Asisten.
class AutonomousActivityRecord {
  const AutonomousActivityRecord({
    required this.id,
    required this.householdId,
    required this.title,
    required this.description,
    required this.activityType,
    required this.occurredAt,
    this.status = AutonomousActivityStatus.active,
    this.payload = const <String, dynamic>{},
  });

  final String id;
  final String householdId;
  final String title;
  final String description;
  final AutonomousActivityType activityType;
  final DateTime occurredAt;
  final AutonomousActivityStatus status;
  final Map<String, dynamic> payload;

  AutonomousActivityRecord copyWith({
    String? id,
    String? householdId,
    String? title,
    String? description,
    AutonomousActivityType? activityType,
    DateTime? occurredAt,
    AutonomousActivityStatus? status,
    Map<String, dynamic>? payload,
  }) {
    return AutonomousActivityRecord(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      title: title ?? this.title,
      description: description ?? this.description,
      activityType: activityType ?? this.activityType,
      occurredAt: occurredAt ?? this.occurredAt,
      status: status ?? this.status,
      payload: payload ?? this.payload,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'householdId': householdId,
      'title': title,
      'description': description,
      'activityType': activityType.name,
      'occurredAt': occurredAt.toIso8601String(),
      'status': status.name,
      'payload': payload,
    };
  }

  factory AutonomousActivityRecord.fromJson(Map<String, dynamic> json) {
    return AutonomousActivityRecord(
      id: json['id'] as String,
      householdId: json['householdId'] as String? ?? 'local-household',
      title: json['title'] as String,
      description: json['description'] as String,
      activityType: AutonomousActivityType.values.firstWhere(
        (e) => e.name == json['activityType'],
        orElse: () => AutonomousActivityType.envelopeRebalance,
      ),
      occurredAt: DateTime.parse(json['occurredAt'] as String),
      status: AutonomousActivityStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => AutonomousActivityStatus.active,
      ),
      payload: (json['payload'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }
}
